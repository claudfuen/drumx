#!/usr/bin/env python3
"""Sign and notarize a completed macOS app using an explicitly approved identity.

No subprocess command, credential, or raw subprocess output is printed. This
helper is a strict signing path; the packager owns the separate ad-hoc path.
"""
import argparse
import base64
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import sys
import tempfile
import uuid


class SigningError(RuntimeError):
    pass


@dataclass(frozen=True, repr=False)
class Configuration:
    certificate: bytes
    certificate_password: str
    identity: str
    team: str
    apple_id: str
    apple_password: str

    @classmethod
    def from_environment(cls, environment):
        if environment.get("MACOS_SIGNING_ENABLED") != "true":
            raise SigningError("Developer ID signing requires MACOS_SIGNING_ENABLED=true.")
        names = ["MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD", "MACOS_SIGNING_IDENTITY",
                 "APPLE_TEAM_ID", "APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD"]
        missing = [name for name in names if not environment.get(name)]
        if missing:
            raise SigningError("Signing configuration is missing: " + ", ".join(missing))
        identity = environment["MACOS_SIGNING_IDENTITY"]
        match = re.fullmatch(r"Developer ID Application: [^\r\n]+ \(([A-Z0-9]{10})\)", identity)
        if not match or match[1] != environment["APPLE_TEAM_ID"]:
            raise SigningError("The approved identity must be Developer ID Application and match APPLE_TEAM_ID.")
        try:
            certificate = base64.b64decode("".join(environment[names[0]].split()), validate=True)
        except (ValueError, UnicodeError):
            raise SigningError("The certificate secret is not valid base64.") from None
        if not certificate or len(certificate) > 10 * 1024 * 1024:
            raise SigningError("The certificate secret has an invalid size.")
        return cls(certificate, environment[names[1]], identity, match[1], environment["APPLE_ID"],
                   environment["APPLE_APP_SPECIFIC_PASSWORD"])


def run(command, phase, timeout=120):
    """Capture tool diagnostics privately; never let CalledProcessError echo args."""
    child_environment = dict(os.environ)
    for name in ("MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD", "APPLE_APP_SPECIFIC_PASSWORD"):
        child_environment.pop(name, None)
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False, env=child_environment)
    except subprocess.TimeoutExpired:
        raise SigningError(f"{phase} timed out. No signed release was approved.") from None
    except OSError:
        raise SigningError(f"{phase} could not start. Check the macOS runner toolchain.") from None
    if result.returncode:
        raise SigningError(f"{phase} failed (exit {result.returncode}). Tool output is withheld to protect credentials.")
    return result.stdout + result.stderr


def private_file(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(data)


def identity_hash(output, identity):
    matches = re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"\r\n]+)"\s*$', output, re.MULTILINE)
    approved = [fingerprint for fingerprint, name in matches if name == identity]
    if len(approved) != 1:
        raise SigningError("The temporary keychain must contain exactly one valid certificate matching the approved Developer ID identity.")
    return approved[0]


MACHO_MAGIC = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
               b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def sign_targets(app):
    """Explicit current-layout inventory, deepest native images before app seal."""
    app = app.resolve()
    if app.suffix != ".app" or not (app / "Contents/Info.plist").is_file():
        raise SigningError("Expected an exported .app bundle with Contents/Info.plist.")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    executable_name = info.get("CFBundleExecutable", "")
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name or not executable_name:
        raise SigningError("The app has an invalid executable declaration.")
    executable = app / "Contents/MacOS" / executable_name
    binaries = []
    for path in app.rglob("*"):
        if path.is_symlink():
            # New framework/helper layouts need explicit signing rules and review.
            raise SigningError("The exported app contains an unsupported symlink; review its signing layout.")
        if path.is_dir() and path.suffix in {".app", ".framework", ".xpc", ".bundle", ".appex", ".plugin"}:
            raise SigningError("The exported app contains a new nested code bundle; add explicit signing rules before release.")
        if path.is_file():
            with path.open("rb") as handle:
                native = handle.read(4) in MACHO_MAGIC
            if native:
                binaries.append(path)
    if executable not in binaries:
        raise SigningError("The declared app executable is not a Mach-O image.")
    return sorted([path for path in binaries if path != executable], key=lambda path: (-len(path.parts), str(path))) + [app]


def verify_identity(output, config):
    if f"Authority={config.identity}\n" not in output or f"TeamIdentifier={config.team}\n" not in output:
        raise SigningError("The signed app identity read-back does not match the approved Developer ID team.")
    if not re.search(r"flags=0x[0-9a-fA-F]+\([^\n]*runtime", output) or "Timestamp=" not in output:
        raise SigningError("The signed app is missing hardened runtime or a secure timestamp.")


def accepted_submission(output):
    try:
        payload = json.loads(output)
        identifier = str(uuid.UUID(payload["id"]))
    except (ValueError, KeyError, TypeError):
        raise SigningError("Apple returned an invalid notarization receipt.") from None
    if payload.get("status") != "Accepted":
        raise SigningError("Apple did not accept the notarization submission. No signed release was approved.")
    return identifier


def sign_app(app, config, runner=run):
    app = app.resolve()
    targets = sign_targets(app)
    with tempfile.TemporaryDirectory(prefix="drumx-signing-") as temporary:
        directory = Path(temporary)
        keychain = directory / "release.keychain-db"
        certificate = directory / "certificate.p12"
        entitlements = directory / "release-entitlements.plist"
        archive = directory / "notarization.zip"
        keychain_password = secrets.token_urlsafe(32)
        private_file(certificate, config.certificate)
        # Godot's bundled GDExtension is signed by this same team below. No JIT,
        # unsigned code, debugging, microphone capture or foreign plug-ins exist.
        # Keep hardened runtime library validation enabled for this release.
        private_file(entitlements, plistlib.dumps({}))
        created = False
        try:
            runner(["security", "create-keychain", "-p", keychain_password, str(keychain)], "Create temporary signing keychain")
            created = True
            runner(["security", "set-keychain-settings", "-lut", "3600", str(keychain)], "Configure temporary signing keychain")
            runner(["security", "unlock-keychain", "-p", keychain_password, str(keychain)], "Unlock temporary signing keychain")
            runner(["security", "import", str(certificate), "-k", str(keychain), "-P", config.certificate_password,
                    "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], "Import approved signing certificate")
            certificate.unlink()
            runner(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k",
                    keychain_password, str(keychain)], "Authorize codesign for temporary key")
            listing = runner(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], "Inspect imported certificate identity")
            fingerprint = identity_hash(listing, config.identity)
            for target in targets:
                command = ["codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
                           "--options", "runtime", "--timestamp"]
                if target == app: command += ["--entitlements", str(entitlements)]
                runner(command + [str(target)], "Sign native image" if target != app else "Seal app bundle")
                runner(["codesign", "--verify", "--strict", str(target)], "Verify signed native code")
            runner(["codesign", "--verify", "--deep", "--strict", str(app)], "Verify complete app signature")
            verify_identity(runner(["codesign", "--display", "--verbose=4", str(app)], "Read signed identity"), config)
            runner(["xcrun", "notarytool", "store-credentials", "drumx-release", "--keychain", str(keychain),
                    "--apple-id", config.apple_id, "--team-id", config.team, "--password", config.apple_password],
                   "Validate temporary notarization credentials")
            runner(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], "Create notarization archive")
            receipt = runner(["xcrun", "notarytool", "submit", str(archive), "--keychain-profile", "drumx-release",
                              "--keychain", str(keychain), "--wait", "--timeout", "20m", "--output-format", "json"],
                             "Submit app for Apple notarization", timeout=1260)
            identifier = accepted_submission(receipt)
            log = runner(["xcrun", "notarytool", "log", identifier, "--keychain-profile", "drumx-release",
                          "--keychain", str(keychain)], "Review Apple notarization log")
            try:
                details = json.loads(log)
            except (ValueError, TypeError):
                raise SigningError("Apple returned an invalid notarization log.") from None
            if details.get("status") != "Accepted" or details.get("issues"):
                raise SigningError("The notarization log has issues requiring review before release.")
            runner(["xcrun", "stapler", "staple", str(app)], "Staple Apple notarization ticket")
            runner(["xcrun", "stapler", "validate", str(app)], "Validate stapled notarization ticket")
            assessment = runner(["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)], "Verify Gatekeeper assessment")
            if "source=Notarized Developer ID" not in assessment:
                raise SigningError("Gatekeeper did not confirm a notarized Developer ID app.")
            runner(["codesign", "--verify", "--deep", "--strict", str(app)], "Verify final stapled app")
            return {"signed": True, "notarized": True, "signature_type": "developer-id",
                    "signing_identity": config.identity, "team_id": config.team, "notarization_id": identifier,
                    "notarization_status": "Accepted", "stapled": True, "gatekeeper_verified": True}
        finally:
            if created:
                runner(["security", "delete-keychain", str(keychain)], "Delete temporary signing keychain")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.metadata.resolve().is_relative_to(args.app.resolve()):
            raise SigningError("Signing metadata must be outside the sealed app bundle.")
        # A stale receipt must never survive a failed retry, including missing secrets.
        if args.metadata.exists(): args.metadata.unlink()
        config = Configuration.from_environment(os.environ)
        if sys.platform != "darwin": raise SigningError("Developer ID signing requires a macOS runner.")
        result = sign_app(args.app, config)
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(result, indent=2) + "\n")
    except (SigningError, OSError, ValueError, plistlib.InvalidFileException) as error:
        # Validation errors are authored safe messages. Raw OS/plist exceptions
        # may contain paths or input bytes, so those get a fixed diagnostic.
        print(str(error) if isinstance(error, SigningError) else "Signing could not complete; no release receipt was written.", file=sys.stderr)
        return 1
    print("Developer ID signature, Apple notarization, stapled ticket and Gatekeeper assessment verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
