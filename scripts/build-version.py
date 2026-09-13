#!/usr/bin/env python3
"""Resolve one Drumx version for app UI, OS metadata, packages, and releases."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build_identity(root: Path = ROOT, environ: dict | None = None) -> dict:
    root = Path(root)
    env = os.environ if environ is None else environ
    base = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", base):
        raise RuntimeError("VERSION must contain a numeric major.minor.patch version.")
    if any(int(part) > 65535 for part in base.split(".")):
        raise RuntimeError("VERSION exceeds the Windows resource version range.")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("Build identity requires a full Git commit.")
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip())
    short = commit[:12]
    number = env.get("GITHUB_RUN_NUMBER")
    ci = env.get("GITHUB_ACTIONS") == "true" or number is not None
    workflow = None
    if ci:
        if not number or not re.fullmatch(r"[1-9][0-9]*", number) or int(number) > 65535:
            raise RuntimeError("CI needs a positive GITHUB_RUN_NUMBER within the Windows version range.")
        if env.get("GITHUB_SHA") != commit:
            raise RuntimeError("CI checkout does not match GITHUB_SHA.")
        repository, run_id = env.get("GITHUB_REPOSITORY", ""), env.get("GITHUB_RUN_ID", "")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository) or not run_id.isdigit():
            raise RuntimeError("CI needs a valid repository and workflow run ID.")
        number = int(number)
        version, channel = f"{base}-preview.{number}", "preview"
        workflow = f"https://github.com/{repository}/actions/runs/{run_id}"
    else:
        number = 0
        version, channel = f"{base}-dev+{short}" + (".dirty" if dirty else ""), "dev"
    return {"schema": 1, "base_version": base, "version": version, "build_number": number,
            "channel": channel, "commit": commit, "short_commit": short, "dirty": dirty,
            "workflow_run": workflow, "release_tag": f"v{version}" if ci else None}


def write_identity(path: Path, identity: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")


def macos_build_number(identity: dict) -> str:
    number = identity["build_number"]
    # Apple's first component allows four digits; following components allow two.
    # A fixed encoding stays ordered when the CI sequence crosses digit boundaries.
    return f"{1 + number // 10000}.{(number // 100) % 100}.{number % 100}"


def stamp_macos_plist(path: Path, identity: dict) -> None:
    with path.open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleShortVersionString"] = identity["base_version"]
    info["CFBundleVersion"] = macos_build_number(identity)
    info["DrumxVersion"] = identity["version"]
    info["DrumxCommit"] = identity["commit"]
    with path.open("wb") as output:
        plistlib.dump(info, output)


def _setting(text: str, section: str, key: str, value: str) -> str:
    pattern = re.compile(r"(^\[" + re.escape(section) + r"\][^\n]*\n)(.*?)(?=^\[|\Z)", re.M | re.S)
    match = pattern.search(text)
    if not match:
        raise RuntimeError(f"Missing Godot config section: {section}")
    body = match.group(2)
    setting = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
    replacement = key + "=" + json.dumps(value)
    if len(setting.findall(body)) > 1:
        raise RuntimeError(f"Duplicate Godot setting: {section}/{key}")
    body = setting.sub(lambda _: replacement, body) if setting.search(body) else body.rstrip() + "\n" + replacement + "\n\n"
    return text[:match.start(2)] + body + text[match.end(2):]


def stamp_godot_project(project: Path, identity: dict) -> None:
    """Stamp a disposable export project, never the tracked source presets."""
    project = Path(project)
    config = project / "project.godot"
    config.write_text(_setting(config.read_text(encoding="utf-8"), "application", "config/version",
                               identity["version"]), encoding="utf-8")
    presets = project / "export_presets.cfg"
    text = presets.read_text(encoding="utf-8")
    # Find preset indexes by platform instead of assuming their order.
    platforms = {}
    for match in re.finditer(r'^\[preset\.(\d+)\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S):
        platform = re.search(r'^platform="([^"]+)"$', match.group(2), re.M)
        if platform:
            platforms[platform.group(1)] = f"preset.{match.group(1)}.options"
    if not {"macOS", "Windows Desktop"}.issubset(platforms):
        raise RuntimeError("Both desktop export presets are required for version stamping.")
    text = _setting(text, platforms["macOS"], "application/short_version", identity["base_version"])
    text = _setting(text, platforms["macOS"], "application/version", macos_build_number(identity))
    numeric = identity["base_version"] + "." + str(identity["build_number"])
    for key in ["application/file_version", "application/product_version"]:
        text = _setting(text, platforms["Windows Desktop"], key, numeric)
    presets.write_text(text, encoding="utf-8")
    write_identity(project / "build-info.json", identity)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--identity-file", type=Path, help="Reuse identity captured at the start of a build.")
    parser.add_argument("--stamp-macos-plist", type=Path)
    parser.add_argument("--stamp-godot-project", type=Path)
    args = parser.parse_args()
    identity = json.loads(args.identity_file.read_text(encoding="utf-8")) if args.identity_file else build_identity()
    if args.output:
        write_identity(args.output, identity)
    if args.stamp_macos_plist:
        stamp_macos_plist(args.stamp_macos_plist, identity)
    if args.stamp_godot_project:
        stamp_godot_project(args.stamp_godot_project, identity)
    print(json.dumps(identity, sort_keys=True))


if __name__ == "__main__":
    main()
