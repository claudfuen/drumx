#!/bin/bash
# Install a validated native build without changing its progress/library identity.
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRUMX_SOURCE="${1:-$DRUMX_ROOT/.build/DrumxLab.app}"
DRUMX_DESTINATION="/Applications/Drumx.app"
test -x "$DRUMX_SOURCE/Contents/MacOS/DrumxLab"
codesign --verify --deep --strict "$DRUMX_SOURCE"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DRUMX_SOURCE/Contents/Info.plist")" != "org.drumx.timing-lab" ]; then
  echo "Expected a native Drumx build with its original application identity." >&2
  exit 1
fi
if pgrep -f '^/Applications/Drumx.app/Contents/MacOS/DrumxLab([[:space:]]|$)' >/dev/null; then
  echo "Quit the installed Drumx app, then run this installer again. Your build is ready." >&2
  exit 1
fi
DRUMX_STAGING="$(mktemp -d /Applications/.drumx-install.XXXXXX)"
trap 'rmdir "$DRUMX_STAGING" 2>/dev/null || true' EXIT
ditto "$DRUMX_SOURCE" "$DRUMX_STAGING/Drumx.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Drumx' "$DRUMX_STAGING/Drumx.app/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$DRUMX_STAGING/Drumx.app/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Drumx' "$DRUMX_STAGING/Drumx.app/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Drumx' "$DRUMX_STAGING/Drumx.app/Contents/Info.plist"
fi
codesign --force --sign - "$DRUMX_STAGING/Drumx.app"
codesign --verify --deep --strict "$DRUMX_STAGING/Drumx.app"
# Retain the previous bundle for a reversible local update. Never touch saves.
if [ -e "$DRUMX_DESTINATION" ]; then
  mkdir -p "$DRUMX_ROOT/.build/installed-backups"
  DRUMX_BACKUP="$(mktemp -d "$DRUMX_ROOT/.build/installed-backups/update.XXXXXX")"
  mv "$DRUMX_DESTINATION" "$DRUMX_BACKUP/Drumx.app"
fi
if ! mv "$DRUMX_STAGING/Drumx.app" "$DRUMX_DESTINATION"; then
  if [ -n "${DRUMX_BACKUP:-}" ]; then mv "$DRUMX_BACKUP/Drumx.app" "$DRUMX_DESTINATION"; fi
  exit 1
fi
codesign --verify --deep --strict "$DRUMX_DESTINATION"
echo "Installed $DRUMX_DESTINATION"
echo "Launch with: open /Applications/Drumx.app"
