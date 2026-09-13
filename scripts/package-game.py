#!/usr/bin/env python3
"""Export and smoke-test the shared app on its target host before making a ZIP."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import zipfile

import importlib.util

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/game"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("fetch_godot", ROOT / "scripts/fetch-godot.py")
fetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch)
content_spec = importlib.util.spec_from_file_location("verify_game_content", ROOT / "scripts/verify-game-content.py")
content = importlib.util.module_from_spec(content_spec)
content_spec.loader.exec_module(content)
version_spec = importlib.util.spec_from_file_location("build_version", ROOT / "scripts/build-version.py")
version = importlib.util.module_from_spec(version_spec)
version_spec.loader.exec_module(version)
PROJECT_NOTICES = ["LICENSE", "NOTICE", "LICENSE-GUIDE.md"]


def run(command: list[str], log: Path, timeout: int = 180) -> str:
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        captured = error.stdout or ""
        log.write_text(captured.decode("utf-8", errors="replace") if isinstance(captured, bytes) else captured)
        raise RuntimeError(f"Command exceeded {timeout} seconds; see {log}") from error
    log.write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="", flush=True)
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
        raise RuntimeError(f"Command failed; see {log}")
    return result.stdout


def validate_assets() -> str:
    originals = ROOT / "native/assets/BigRusty"
    staged = PROJECT / "assets/BigRusty"
    sample_paths = sorted(originals.rglob("*.flac"))
    if len(sample_paths) != 80:
        raise RuntimeError("Expected exactly 80 original sample files for the full kit.")
    for source in [*sample_paths, *(originals / n for n in ["manifest.json", "LICENSE", "provenance.json"])]:
        target = staged / source.relative_to(originals)
        if not target.is_file() or fetch.sha256(source) != fetch.sha256(target):
            raise RuntimeError(f"Missing or changed staged sample/provenance: {target}")
    return fetch.sha256(staged / "manifest.json")


def write_third_party_notices(package: Path) -> Path:
    """Keep readable redistribution notices beside the app, outside its PCK."""
    content.verify_font_assets(ROOT)
    notices = package / "Third-party notices"
    notices.mkdir()
    shutil.copytree(ROOT / "scripts/distribution", notices / "Godot")
    shutil.copytree(PROJECT / "native/licenses", notices / "Native dependencies")
    for name in ["LICENSE", "provenance.json", "README.md"]:
        shutil.copy2(PROJECT / "assets/BigRusty" / name, notices / f"BigRusty-{name}")
    font_notices = notices / "Inter"
    font_notices.mkdir()
    for name in ["OFL.txt", "provenance.json", "README.md"]:
        shutil.copy2(PROJECT / "assets/fonts" / name, font_notices / name)
    return notices


def write_project_notices(package: Path, mac_app: Path | None = None) -> dict[str, str]:
    """Keep project terms beside either app and inside a movable Mac app bundle."""
    hashes = {}
    embedded = mac_app / "Contents/Resources/Drumx licensing" if mac_app else None
    if embedded:
        embedded.mkdir(parents=True, exist_ok=True)
    for name in PROJECT_NOTICES:
        source = ROOT / name
        if not source.is_file() or not source.read_bytes().strip():
            raise RuntimeError(f"Required project notice is missing or empty: {name}")
        shutil.copy2(source, package / name)
        if embedded:
            shutil.copy2(source, embedded / name)
        hashes[name] = fetch.sha256(source)
    return hashes


def stage_project(source: Path, destination: Path, identity: dict) -> Path:
    """Stamp an isolated export tree while keeping the checked-out project intact."""
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".godot"))
    version.stamp_godot_project(destination, identity)
    return destination


def write_build_info(package: Path, identity: dict, mac_app: Path | None = None) -> None:
    """Make the same build identity readable without unpacking the game's PCK."""
    encoded = json.dumps(identity, indent=2) + "\n"
    (package / "build-info.json").write_text(encoded, encoding="utf-8")
    if mac_app:
        resources = mac_app / "Contents/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        (resources / "build-info.json").write_text(encoded, encoding="utf-8")


def verify_smoke_identity(output: str, identity: dict) -> None:
    """Check the running app, not just the adjacent package metadata, identifies itself."""
    if "DRUMX_SMOKE_OK" not in output:
        raise RuntimeError("Smoke did not confirm success.")
    reports = [line.removeprefix("DRUMX_BUILD_INFO ") for line in output.splitlines()
               if line.startswith("DRUMX_BUILD_INFO ")]
    if len(reports) != 1:
        raise RuntimeError("Smoke must report exactly one embedded build identity.")
    try:
        embedded = json.loads(reports[0])
    except json.JSONDecodeError as error:
        raise RuntimeError("Smoke reported malformed embedded build identity.") from error
    if embedded != identity:
        raise RuntimeError("Running app build identity differs from the package build identity.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=["macos-arm64", "windows-x86_64"])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"))
    parser.add_argument("--allow-dirty", action="store_true", help="Local inspection only; such packages cannot be published.")
    args = parser.parse_args()
    expected_host = "Darwin" if args.target == "macos-arm64" else "Windows"
    if platform.system() != expected_host:
        raise RuntimeError("Package on its target OS so the exported app is actually executed.")
    if args.target == "macos-arm64" and platform.machine().lower() not in ("arm64", "aarch64"):
        raise RuntimeError("The initial Mac preview is built and tested on Apple Silicon.")
    toolchain = json.loads((fetch.CACHE / "toolchain.json").read_text())
    editor = Path(args.godot or toolchain["editor"]).resolve()
    reported = subprocess.check_output([str(editor), "--version"], text=True).strip()
    if not reported.startswith(f"{fetch.VERSION}.stable.official."):
        raise RuntimeError(f"Expected pinned Godot {fetch.VERSION}, got {reported}")
    identity = version.build_identity(ROOT)
    commit = identity["commit"]
    dirty = identity["dirty"]
    if dirty and not args.allow_dirty:
        raise RuntimeError("Commit the source before creating a release package, or use --allow-dirty locally.")
    sample_hash = validate_assets()
    font_hash = content.verify_font_assets(ROOT)
    library_name = "drumx_engine.dylib" if args.target == "macos-arm64" else "drumx_engine.dll"
    if not (PROJECT / "bin" / library_name).is_file():
        raise RuntimeError("Build apps/game/native before exporting.")

    work = ROOT / ".build/game-export" / args.target
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    logs = work / "logs"
    logs.mkdir()
    staged_project = stage_project(PROJECT, work / "project", identity)
    common = [str(editor), "--headless", "--path", str(staged_project)]
    run([*common, "--import"], logs / "import.log")
    verify_smoke_identity(run([*common, "--", "--smoke-test"], logs / "source-smoke.log"), identity)

    package = work / f"Drumx-{args.target}"
    package.mkdir()
    mac = args.target == "macos-arm64"
    destination = package / ("Drumx.app" if mac else "Drumx.exe")
    run([*common, "--export-release", "macOS" if mac else "Windows Desktop", str(destination)], logs / "export.log", 300)
    project_license_hashes = write_project_notices(package, destination if mac else None)
    # Embed this before sealing the Mac bundle. Nothing writes inside it after signing.
    write_build_info(package, identity, destination if mac else None)
    signing = "ad-hoc, not notarized" if mac else "unsigned"
    signing_details = {"signed": False, "notarized": False,
                       "signature_type": "ad-hoc" if mac else "unsigned"}
    exported_library = list(package.rglob(library_name))
    if len(exported_library) != 1:
        raise RuntimeError(f"Expected one packaged {library_name}, got {len(exported_library)}")
    if mac:
        executable = destination / "Contents/MacOS/Drumx"
        # Official 4.7.2 templates contain a universal executable. The native preview
        # is arm64, so remove the unsupported Intel slice and restore the ad-hoc seal.
        thinned = executable.with_suffix(".arm64")
        run(["lipo", str(executable), "-thin", "arm64", "-output", str(thinned)], logs / "thin.log")
        thinned.replace(executable)
        if os.environ.get("MACOS_SIGNING_ENABLED") == "true":
            signing_path = work / "macos-signing.json"
            run([sys.executable, str(ROOT / "scripts/sign-macos-release.py"), "--app", str(destination),
                 "--metadata", str(signing_path)], logs / "sign.log", 1500)
            signing_details = json.loads(signing_path.read_text(encoding="utf-8"))
            if (signing_details.get("signed") is not True or signing_details.get("notarized") is not True
                    or signing_details.get("stapled") is not True
                    or signing_details.get("gatekeeper_verified") is not True
                    or signing_details.get("signature_type") != "developer-id"
                    or signing_details.get("notarization_status") != "Accepted"):
                raise RuntimeError("Developer ID signing did not confirm notarization and Gatekeeper verification.")
            signing = "Developer ID signed, notarized and stapled"
        else:
            run(["codesign", "--force", "--deep", "--sign", "-", "--preserve-metadata=entitlements,requirements,flags",
                 str(destination)], logs / "sign.log")
        for binary, log_name in [(executable, "app-architecture.log"), (exported_library[0], "extension-architecture.log")]:
            if run(["lipo", "-archs", str(binary)], logs / log_name).strip() != "arm64":
                raise RuntimeError(f"The Mac preview must contain only arm64: {binary}")
        run(["codesign", "--verify", "--deep", "--strict", str(destination)], logs / "signature.log")
    else:
        executable = destination
        if not (package / "Drumx.pck").is_file():
            raise RuntimeError("The Windows package is missing Drumx.pck.")
    verify_smoke_identity(run([str(executable), "--headless", "--", "--smoke-test"], logs / "packaged-smoke.log"), identity)

    manifest = {"schema": 1, "application": "Drumx shared preview", "commit": commit, "dirty": dirty,
                "build_identity": identity,
                "target": args.target, "godot": reported, "built_at": datetime.now(timezone.utc).isoformat(),
                "sample_manifest_sha256": sample_hash, "native_extension_sha256": fetch.sha256(exported_library[0]),
                "font_provenance_sha256": font_hash,
                "project_license_sha256": project_license_hashes,
                "verified": ["80 original full-kit samples and provenance", "pinned Inter font and OFL license", "source headless smoke", "packaged headless smoke", "source and packaged app build identity"],
                "not_verified": ["full visual parity", "physical MIDI kit", "audible output latency", "Windows graphics on a physical PC"],
                "signing": signing, "signing_details": signing_details}
    (package / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    write_third_party_notices(package)
    if mac and signing_details["notarized"]:
        instructions = "Open Drumx.app. This build is Developer ID signed, notarized, and stapled.\n"
    elif mac:
        instructions = ("Open Drumx.app. This preview is ad-hoc signed and not notarized.\n"
                        "If macOS blocks it, use System Settings > Privacy & Security > Open Anyway for this app.\n")
    else:
        instructions = ("Extract the whole ZIP into one folder, then open Drumx.exe.\n"
                        "Keep Drumx.pck and the native DLL beside it. This preview is unsigned.\n")
    (package / "START-HERE.txt").write_text(
        f"DRUMX SHARED PREVIEW\nVersion: {identity['version']}\nBuild: {identity['build_number']}\n"
        f"Channel: {identity['channel']}\nCommit: {commit}\n\n{instructions}\n"
        "Keyboard: A hi-hat, S snare, Space kick. Set up your MIDI source before playing.\n"
        "This preview has its own local saves and does not import the AppKit lab's progress.\n"
        "Headless checks pass on the build host. Real kit, audio latency, and physical Windows display testing remain open.\n"
        f"Guide and known limits: https://github.com/claudfuen/drumx/blob/{commit}/docs/desktop-preview.md\n"
        "Free noncommercial use is covered by the included project license. Commercial use requires a separate paid license.\n"
        "Read LICENSE, NOTICE and LICENSE-GUIDE.md. Godot, Inter, sample and native dependency notices are also included.\n")

    output = ROOT / ".build/preview"
    output.mkdir(exist_ok=True)
    archive = output / f"Drumx-{args.target}.zip"
    if archive.exists():
        archive.unlink()
    if mac:
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(package), str(archive)], check=True)
    else:
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(package.rglob("*")):
                if path.is_file():
                    bundle.write(path, path.relative_to(package.parent))
    artifact_manifest = {**manifest, "archive": archive.name, "sha256": fetch.sha256(archive)}
    manifest_path = output / f"{args.target}.json"
    manifest_path.write_text(json.dumps(artifact_manifest, indent=2) + "\n")
    print(f"Verified package: {archive}\nSHA-256: {artifact_manifest['sha256']}", flush=True)


if __name__ == "__main__":
    main()
