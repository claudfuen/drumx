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


def run(command: list[str], log: Path, timeout: int = 180) -> str:
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
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
    if len(sample_paths) != 24:
        raise RuntimeError("Expected exactly 24 original sample files.")
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
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
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
    common = [str(editor), "--headless", "--path", str(PROJECT)]
    run([*common, "--import"], logs / "import.log")
    if "DRUMX_SMOKE_OK" not in run([*common, "--", "--smoke-test"], logs / "source-smoke.log"):
        raise RuntimeError("Source smoke did not confirm success.")

    package = work / f"Drumx-{args.target}"
    package.mkdir()
    mac = args.target == "macos-arm64"
    destination = package / ("Drumx.app" if mac else "Drumx.exe")
    run([*common, "--export-release", "macOS" if mac else "Windows Desktop", str(destination)], logs / "export.log", 300)
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
    if "DRUMX_SMOKE_OK" not in run([str(executable), "--headless", "--", "--smoke-test"], logs / "packaged-smoke.log"):
        raise RuntimeError("Packaged smoke did not confirm success.")

    manifest = {"schema": 1, "application": "Drumx shared preview", "commit": commit, "dirty": dirty,
                "target": args.target, "godot": reported, "built_at": datetime.now(timezone.utc).isoformat(),
                "sample_manifest_sha256": sample_hash, "native_extension_sha256": fetch.sha256(exported_library[0]),
                "font_provenance_sha256": font_hash,
                "verified": ["24 original samples and provenance", "pinned Inter font and OFL license", "source headless smoke", "packaged headless smoke"],
                "not_verified": ["physical MIDI kit", "audible output latency", "Windows graphics on a physical PC"],
                "signing": "ad-hoc, not notarized" if mac else "unsigned"}
    (package / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    write_third_party_notices(package)
    instructions = ("Open Drumx.app. This preview is ad-hoc signed and not notarized.\n"
                    "If macOS blocks it, use System Settings > Privacy & Security > Open Anyway for this app.\n"
                    if mac else "Extract the whole ZIP into one folder, then open Drumx.exe.\n"
                    "Keep Drumx.pck and the native DLL beside it. This preview is unsigned.\n")
    (package / "START-HERE.txt").write_text(
        f"DRUMX SHARED PREVIEW\nCommit: {commit}\n\n{instructions}\n"
        "Keyboard: A hi-hat, S snare, Space kick. Set up your MIDI source before playing.\n"
        "This preview has its own local saves and does not import the AppKit lab's progress.\n"
        "Headless checks pass on the build host. Real kit, audio latency, and physical Windows display testing remain open.\n"
        "Guide and known limits: https://github.com/claudfuen/drumx/blob/main/docs/desktop-preview.md\n"
        "Godot, Inter font, sample and native dependency notices are included. No project-wide source license has been selected.\n")

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
