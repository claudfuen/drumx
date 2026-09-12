#!/usr/bin/env python3
"""Publish only a matching, checksum-verified pair produced by the app workflow."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".build/preview"
TARGETS = ["macos-arm64", "windows-x86_64"]


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def gh(*args: str, data=None, allow_missing=False):
    command = ["gh", *args]
    if data is not None:
        command.extend(["--input", "-"])
    result = subprocess.run(command, cwd=ROOT, text=True, input=json.dumps(data) if data else None,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        if allow_missing and "404" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip().startswith(("{", "[")) else result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise RuntimeError("A full commit SHA is required.")
    manifests = []
    files = []
    for target in TARGETS:
        value = json.loads((OUTPUT / f"{target}.json").read_text())
        filename = f"Drumx-{target}.zip"
        if (value.get("commit") != args.commit or value.get("dirty") is not False
                or value.get("target") != target or value.get("archive") != filename
                or "packaged headless smoke" not in value.get("verified", [])):
            raise RuntimeError(f"Unverified or mismatched package: {target}")
        path = OUTPUT / filename
        if digest(path) != value.get("sha256"):
            raise RuntimeError(f"Package checksum mismatch: {target}")
        manifests.append(value)
        files.append(path)
    if len({m["godot"] for m in manifests}) != 1 or len({m["sample_manifest_sha256"] for m in manifests}) != 1:
        raise RuntimeError("The pair does not share the same engine and sample manifest.")
    run_url = (f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
               if os.environ.get("GITHUB_RUN_ID") else None)
    manifest_path = OUTPUT / "build-manifest.json"
    manifest_path.write_text(json.dumps({"schema": 1, "commit": args.commit, "workflow_run": run_url,
                                         "packages": manifests}, indent=2) + "\n")
    files.append(manifest_path)
    checksums = OUTPUT / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{digest(path)}  {path.name}\n" for path in files))
    files.append(checksums)
    print(f"Verified both packaged apps at {args.commit}.")
    if args.verify_only:
        return
    repository = os.environ.get("GITHUB_REPOSITORY")
    if repository != "claudfuen/drumx" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise RuntimeError("Publication is restricted to the Drumx main-branch workflow.")
    notes = OUTPUT / "release-notes.md"
    notes.write_text(
        f"Paired desktop preview from commit `{args.commit}`.\n\n"
        "Download **Drumx-macos-arm64.zip** for Apple Silicon Mac, or **Drumx-windows-x86_64.zip** for 64-bit Windows. "
        "Extract the whole archive before opening the app. Both use the same shared frontend, course data, and native backend source.\n\n"
        f"Both native builds, content contracts, and exported-app headless smoke checks passed in [this workflow run]({run_url}). "
        "This is not a physical-kit, audible-latency, or physical-Windows graphics result.\n\n"
        "The Mac app is ad-hoc signed and not notarized. The Windows app is unsigned. "
        "Preview saves are separate from the AppKit reference lab. "
        "See the [preview guide and feature boundaries](https://github.com/claudfuen/drumx/blob/main/docs/desktop-preview.md).\n\n"
        "The attached build manifest identifies both packages and their SHA-256 checksums. "
        "Source licensing and production distribution remain separate decisions.\n")
    endpoint = f"repos/{repository}"
    existing = gh("api", f"{endpoint}/releases/tags/preview", allow_missing=True)
    if existing is None:
        existing = next((item for item in gh("api", f"{endpoint}/releases?per_page=100")
                         if item["tag_name"] == "preview"), None)
    current_ref = gh("api", f"{endpoint}/git/ref/tags/preview", allow_missing=True)
    if current_ref:
        current_commit = gh("api", f"{endpoint}/commits/preview")["sha"]
        comparison = gh("api", f"{endpoint}/compare/{current_commit}...{args.commit}")
        if comparison["status"] not in ("ahead", "identical"):
            raise RuntimeError("Refusing to move the rolling preview backward or onto diverged history.")
    release_data = {"tag_name": "preview", "target_commitish": args.commit, "draft": True, "prerelease": True,
                    "name": f"Drumx paired preview · {args.commit[:7]}", "body": notes.read_text()}
    if existing:
        # Hide the rolling release during replacement so a partial pair is never published.
        release = gh("api", "--method", "PATCH", f"{endpoint}/releases/{existing['id']}", data=release_data)
    if current_ref:
        gh("api", "--method", "PATCH", f"{endpoint}/git/refs/tags/preview", data={"sha": args.commit, "force": True})
    else:
        gh("api", "--method", "POST", f"{endpoint}/git/refs", data={"ref": "refs/tags/preview", "sha": args.commit})
    if existing is None:
        release = gh("api", "--method", "POST", f"{endpoint}/releases", data=release_data)
    gh("release", "upload", "preview", *(str(path) for path in files), "--clobber", "--repo", repository)
    uploaded = gh("api", f"{endpoint}/releases/{release['id']}")
    assets = {asset["name"]: asset for asset in uploaded["assets"] if asset["state"] == "uploaded"}
    for path in files:
        asset = assets.get(path.name)
        if not asset or asset.get("digest") != f"sha256:{digest(path)}":
            raise RuntimeError("Release upload or digest verification incomplete; draft remains unpublished.")
    gh("api", "--method", "PATCH", f"{endpoint}/releases/{release['id']}", data={"draft": False, "prerelease": True})
    print(f"Published https://github.com/{repository}/releases/tag/preview at {args.commit}.")


if __name__ == "__main__":
    main()
