#!/usr/bin/env python3
"""Verify a desktop pair, then publish an immutable experimental prerelease."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".build/preview"
TARGETS = ["macos-arm64", "windows-x86_64"]
PROJECT_NOTICES = ["LICENSE", "NOTICE", "LICENSE-GUIDE.md"]
REPOSITORY = "claudfuen/drumx"


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
    result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                            input=json.dumps(data) if data is not None else None,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        if allow_missing and "404" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip().startswith(("{", "[")) else result.stdout.strip()


def preview_tag(commit: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("A full commit SHA is required.")
    return f"preview-{commit[:12]}"


def verify_pair(commit: str) -> list[Path]:
    tag = preview_tag(commit)
    license_hashes = {}
    for name in PROJECT_NOTICES:
        path = ROOT / name
        if not path.is_file() or not path.read_bytes().strip():
            raise RuntimeError(f"Required project notice is missing or empty: {name}")
        license_hashes[name] = digest(path)
    manifests, files = [], []
    for target in TARGETS:
        value = json.loads((OUTPUT / f"{target}.json").read_text(encoding="utf-8"))
        filename = f"Drumx-{target}.zip"
        if (value.get("commit") != commit or value.get("dirty") is not False
                or value.get("target") != target or value.get("archive") != filename
                or "packaged headless smoke" not in value.get("verified", [])
                or value.get("project_license_sha256") != license_hashes):
            raise RuntimeError(f"Unverified or mismatched package: {target}")
        path = OUTPUT / filename
        if digest(path) != value.get("sha256"):
            raise RuntimeError(f"Package checksum mismatch: {target}")
        with zipfile.ZipFile(path) as archive:
            prefix = f"Drumx-{target}/"
            inner = json.loads(archive.read(prefix + "build-manifest.json"))
            for key in ["commit", "dirty", "target", "godot", "sample_manifest_sha256",
                        "font_provenance_sha256", "project_license_sha256", "verified", "signing", "signing_details"]:
                if inner.get(key) != value.get(key):
                    raise RuntimeError(f"Packaged manifest disagrees about {key}: {target}")
            for name, expected in license_hashes.items():
                if hashlib.sha256(archive.read(prefix + name)).hexdigest() != expected:
                    raise RuntimeError(f"Packaged project notice mismatch: {target}/{name}")
                if target == "macos-arm64":
                    embedded = prefix + "Drumx.app/Contents/Resources/Drumx licensing/" + name
                    if hashlib.sha256(archive.read(embedded)).hexdigest() != expected:
                        raise RuntimeError(f"Mac app project notice mismatch: {name}")
        manifests.append(value)
        files.append(path)
    for key in ["godot", "sample_manifest_sha256", "font_provenance_sha256"]:
        if not manifests[0].get(key) or len({m.get(key) for m in manifests}) != 1:
            raise RuntimeError(f"The pair does not share the same {key}.")
    run_url = workflow_run_url()
    manifest_path = OUTPUT / "build-manifest.json"
    manifest_path.write_text(json.dumps({"schema": 1, "commit": commit, "release_tag": tag,
        "workflow_run": run_url, "project_license_sha256": license_hashes,
        "packages": manifests}, indent=2) + "\n", encoding="utf-8")
    files.append(manifest_path)
    for name in PROJECT_NOTICES:
        path = OUTPUT / name
        shutil.copy2(ROOT / name, path)
        files.append(path)
    checksums = OUTPUT / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{digest(path)}  {path.name}\n" for path in files), encoding="utf-8")
    files.append(checksums)
    print(f"Verified both packaged apps at {commit}.")
    return files


def workflow_run_url() -> str | None:
    repository, run_id = os.environ.get("GITHUB_REPOSITORY"), os.environ.get("GITHUB_RUN_ID")
    return f"https://github.com/{repository}/actions/runs/{run_id}" if repository and run_id else None


def require_publication_context(commit: str) -> None:
    if (os.environ.get("GITHUB_REPOSITORY") != REPOSITORY
            or os.environ.get("GITHUB_REF") != "refs/heads/main"
            or os.environ.get("GITHUB_EVENT_NAME") not in ("push", "workflow_dispatch")
            or os.environ.get("GITHUB_SHA") != commit
            or not os.environ.get("GITHUB_RUN_ID")):
        raise RuntimeError("Publication is restricted to this commit's Drumx main-branch workflow.")


def ensure_tag(commit: str) -> str:
    tag = preview_tag(commit)
    endpoint = f"repos/{REPOSITORY}"
    reference = gh("api", f"{endpoint}/git/ref/tags/{tag}", allow_missing=True)
    if reference is None:
        gh("api", "--method", "POST", f"{endpoint}/git/refs",
           data={"ref": f"refs/tags/{tag}", "sha": commit})
        reference = gh("api", f"{endpoint}/git/ref/tags/{tag}")
    obj = reference.get("object", {})
    resolved = obj.get("sha") if obj.get("type") == "commit" else gh("api", f"{endpoint}/commits/{tag}").get("sha")
    if resolved != commit:
        raise RuntimeError(f"Immutable tag {tag} does not point to {commit}; it will not be moved.")
    return tag


def release_for_tag(tag: str):
    endpoint = f"repos/{REPOSITORY}"
    release = gh("api", f"{endpoint}/releases/tags/{tag}", allow_missing=True)
    if release is not None:
        return release
    # A staged draft is not necessarily returned by the public tag endpoint.
    pages = gh("api", "--paginate", "--slurp", f"{endpoint}/releases?per_page=100")
    matches = [item for page in pages for item in page if item.get("tag_name") == tag]
    if len(matches) > 1:
        raise RuntimeError(f"More than one release claims {tag}.")
    return matches[0] if matches else None


def missing_assets(release: dict, files: list[Path]) -> list[Path]:
    assets = {}
    for asset in release.get("assets", []):
        name = asset.get("name")
        if name in assets:
            raise RuntimeError(f"Duplicate release asset: {name}")
        assets[name] = asset
    expected_names = {path.name for path in files}
    if set(assets) - expected_names:
        raise RuntimeError("Existing release contains unexpected assets; refusing to mutate it.")
    missing = []
    for path in files:
        asset = assets.get(path.name)
        if asset is None:
            missing.append(path)
        elif (asset.get("state") != "uploaded" or asset.get("size") != path.stat().st_size
              or asset.get("digest") != f"sha256:{digest(path)}"):
            raise RuntimeError(f"Immutable release asset mismatch: {path.name}; it will not be replaced.")
    return missing


def release_body(commit: str) -> str:
    manifest = json.loads((OUTPUT / "build-manifest.json").read_text(encoding="utf-8"))
    signing = {item["target"]: item.get("signing", "unverified") for item in manifest["packages"]}
    source = f"https://github.com/{REPOSITORY}/blob/{commit}"
    return (
        f"Experimental paired desktop preview from commit [`{commit[:12]}`](https://github.com/{REPOSITORY}/commit/{commit}).\n\n"
        "Download **Drumx-macos-arm64.zip** for Apple Silicon Mac or **Drumx-windows-x86_64.zip** for 64-bit Windows. "
        "Extract the whole archive before opening the app. Both packages use the same source revision.\n\n"
        f"Native builds, content contracts, and actual exported-app headless checks passed in [the build workflow]({manifest['workflow_run']}). "
        "Interactive visual acceptance, real-kit play, audible latency, and measured frame pacing remain open quality gates.\n\n"
        f"Signing: Mac **{signing['macos-arm64']}**; Windows **{signing['windows-x86_64']}**. "
        "These experimental builds are not a stable release.\n\n"
        f"Drumx project code and original content are free for noncommercial use under the included license. "
        f"Commercial use requires a separate paid license. Read [LICENSE-GUIDE.md]({source}/LICENSE-GUIDE.md); "
        "third-party components retain their own included licenses.\n\n"
        f"See the [preview guide and known limits]({source}/docs/desktop-preview.md). "
        "The build manifest and SHA256SUMS.txt identify this exact pair. Tags and existing assets are never replaced by the publisher.\n"
    )


def publish(commit: str, files: list[Path]) -> str:
    require_publication_context(commit)
    tag = preview_tag(commit)
    endpoint = f"repos/{REPOSITORY}"
    existing = release_for_tag(tag)
    if existing is not None:
        if existing.get("tag_name") != tag or existing.get("prerelease") is not True:
            raise RuntimeError("Existing release is not the expected experimental prerelease.")
        missing = missing_assets(existing, files)
        if not existing.get("draft") and missing:
            raise RuntimeError("Published release is missing assets; refusing to change a published version.")
    # This never updates an existing tag, including abbreviated-SHA collisions.
    ensure_tag(commit)
    if existing is None:
        existing = gh("api", "--method", "POST", f"{endpoint}/releases", data={
            "tag_name": tag, "target_commitish": commit, "draft": True, "prerelease": True,
            "make_latest": "false", "name": f"Experimental desktop preview {tag}",
            "body": release_body(commit)})
        missing = files
    if missing:
        gh("release", "upload", tag, *(str(path) for path in missing), "--repo", REPOSITORY)
    uploaded = gh("api", f"{endpoint}/releases/{existing['id']}")
    if missing_assets(uploaded, files):
        raise RuntimeError("Release upload incomplete; the staged draft remains unpublished.")
    ensure_tag(commit)
    if uploaded.get("draft"):
        gh("api", "--method", "PATCH", f"{endpoint}/releases/{existing['id']}",
           data={"draft": False, "prerelease": True, "make_latest": "false"})
    verified = gh("api", f"{endpoint}/releases/{existing['id']}")
    if verified.get("draft") is not False or verified.get("prerelease") is not True or missing_assets(verified, files):
        raise RuntimeError("Published prerelease read-back did not match the verified pair.")
    url = f"https://github.com/{REPOSITORY}/releases/tag/{tag}"
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as output:
            output.write(f"### Experimental desktop preview\n\n[{tag}]({url})\n\n")
            for target in TARGETS:
                output.write(f"- [{target}]({url.replace('/tag/', '/download/')}/Drumx-{target}.zip)\n")
    print(f"Published {url} at {commit}.")
    return url


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    files = verify_pair(args.commit)
    if not args.verify_only:
        publish(args.commit, files)


if __name__ == "__main__":
    main()
