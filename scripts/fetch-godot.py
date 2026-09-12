#!/usr/bin/env python3
"""Install pinned official Godot editor and desktop export templates for previews."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
CACHE = ROOT / ".build" / f"godot-{VERSION}"
PINS = {
    "macos": (f"Godot_v{VERSION}-stable_macos.universal.zip", "c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e"),
    "windows": (f"Godot_v{VERSION}-stable_win64.exe.zip", "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953"),
    "templates": (f"Godot_v{VERSION}-stable_export_templates.tpz", "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(kind: str, filename: str) -> Path:
    asset, expected = PINS[kind]
    target = CACHE / filename
    if target.exists():
        if sha256(target) != expected:
            raise RuntimeError(f"Checksum mismatch in {target}; cached file preserved.")
        return target
    partial = target.with_suffix(target.suffix + ".part")
    print(f"Downloading pinned {asset}", flush=True)
    request = urllib.request.Request(f"{BASE}/{asset}", headers={"User-Agent": "drumx-preview-builder"})
    with urllib.request.urlopen(request, timeout=120) as source, partial.open("wb") as output:
        shutil.copyfileobj(source, output, 1024 * 1024)
    if sha256(partial) != expected:
        raise RuntimeError(f"Checksum mismatch in {partial}; download will not be used.")
    partial.replace(target)
    return target


def main() -> None:
    host = "macos" if sys.platform == "darwin" else "windows" if sys.platform == "win32" else None
    if not host:
        raise RuntimeError("The paired preview toolchain targets macOS and Windows hosts.")
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = download(host, "editor.zip" if host == "macos" else "editor-windows.zip")
    editor = CACHE / ("Godot.app/Contents/MacOS/Godot" if host == "macos" else f"Godot_v{VERSION}-stable_win64.exe")
    if not editor.exists():
        if host == "macos":
            subprocess.run(["ditto", "-x", "-k", str(archive), str(CACHE)], check=True)
        else:
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(CACHE)
    reported = subprocess.check_output([str(editor), "--version"], text=True).strip()
    if not reported.startswith(f"{VERSION}.stable.official."):
        raise RuntimeError(f"Unexpected Godot version: {reported}")

    # Install only the desktop templates used by our presets, in Godot's official path.
    template_archive = download("templates", "templates.tpz")
    data = (Path.home() / "Library/Application Support/Godot" if host == "macos"
            else Path(os.environ["APPDATA"]) / "Godot")
    templates = data / "export_templates" / f"{VERSION}.stable"
    templates.mkdir(parents=True, exist_ok=True)
    wanted = ["macos.zip", "version.txt", "windows_release_x86_64.exe", "windows_release_x86_64_console.exe",
              "windows_debug_x86_64.exe", "windows_debug_x86_64_console.exe"]
    with zipfile.ZipFile(template_archive) as bundle:
        for name in wanted:
            contents = bundle.read(f"templates/{name}")
            destination = templates / name
            if destination.exists() and destination.read_bytes() != contents:
                raise RuntimeError(f"Existing template differs: {destination}; preserved.")
            if not destination.exists():
                destination.write_bytes(contents)
    metadata = {"version": VERSION, "editor": str(editor), "templates": str(templates), "host": host,
                "template_sha256": PINS["templates"][1], "editor_sha256": PINS[host][1]}
    (CACHE / "toolchain.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Verified Godot {reported}; desktop templates ready.", flush=True)
    print(f"Editor: {editor}", flush=True)
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            output.write(f"GODOT_BIN={editor}\n")


if __name__ == "__main__":
    main()
