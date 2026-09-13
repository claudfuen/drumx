#!/usr/bin/env python3
"""Point the README's generated download region at a verified numbered prerelease."""
from __future__ import annotations

import argparse
import base64
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("publisher", ROOT / "scripts/publish-game-preview.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
START = "<!-- drumx:downloads:start -->"
END = "<!-- drumx:downloads:end -->"
TAG = r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-preview\.([1-9][0-9]*)"
RECORD = re.compile(r"<!-- drumx:release (" + TAG + r") ([0-9a-f]{40}) -->")


def sequence(tag: str) -> tuple[int, ...]:
    match = re.fullmatch(TAG, tag)
    if not match:
        raise RuntimeError("README downloads require a numbered experimental version.")
    return tuple(int(value) for value in match.groups())


def updated_readme(text: str, tag: str, commit: str) -> str:
    version_order = sequence(tag)
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("README release metadata requires the full verified commit.")
    if text.count(START) != 1 or text.count(END) != 1:
        raise RuntimeError("README must have exactly one generated downloads region.")
    start, end = text.index(START) + len(START), text.index(END)
    if end < start:
        raise RuntimeError("README download region markers are reversed.")
    region = text[start:end]
    records = list(RECORD.finditer(region))
    if len(records) > 1 or region.count("<!-- drumx:release") != len(records):
        raise RuntimeError("README has ambiguous or malformed release metadata.")
    if records:
        previous_tag, *_, previous_commit = records[0].groups()
        previous_order = sequence(previous_tag)
        if previous_order > version_order:
            return text
        if previous_order == version_order:
            if previous_commit != commit:
                raise RuntimeError("README version already identifies another immutable commit.")
            return text
    elif re.search(r"/releases/(?:tag|download)/v[0-9]", region):
        raise RuntimeError("Existing numbered download links need explicit release metadata before automatic updates.")
    release = f"https://github.com/{publisher.REPOSITORY}/releases"
    downloads = f"{release}/download/{tag}"
    content = (
        f"\n<!-- drumx:release {tag} {commit} -->\n"
        f"Current experimental release: **[{tag[1:]}]({release}/tag/{tag})** · "
        f"[`{commit[:12]}`](https://github.com/{publisher.REPOSITORY}/commit/{commit})\n\n"
        "| Platform | Download |\n| --- | --- |\n"
        f"| macOS · Apple Silicon | [Download Mac]({downloads}/Drumx-macos-arm64.zip) |\n"
        f"| Windows · x64 | [Download Windows]({downloads}/Drumx-windows-x86_64.zip) |\n\n"
        f"[Build manifest]({downloads}/build-manifest.json) · "
        f"[Checksums]({downloads}/SHA256SUMS.txt) · [All releases]({release})\n\n"
        "These are experimental shared desktop builds. Extract the complete archive before opening the app. "
        "The release notes record signing status and open quality gates.\n"
    )
    return text[:start] + content + text[end:]


def verify_published_pair(commit: str) -> str:
    publisher.require_publication_context(commit)
    files = publisher.verify_pair(commit)
    tag = publisher.preview_tag(commit)
    release = publisher.release_for_tag(tag)
    if (release is None or release.get("draft") is not False
            or release.get("prerelease") is not True or release.get("tag_name") != tag
            or publisher.missing_assets(release, files)):
        raise RuntimeError("README cannot link an incomplete or unpublished prerelease.")
    reference = publisher.gh("api", f"repos/{publisher.REPOSITORY}/git/ref/tags/{tag}")
    obj = reference.get("object", {})
    resolved = obj.get("sha") if obj.get("type") == "commit" else publisher.gh(
        "api", f"repos/{publisher.REPOSITORY}/commits/{tag}").get("sha")
    if resolved != commit:
        raise RuntimeError("README release tag does not identify the verified commit.")
    return tag


def read_main_readme() -> tuple[dict, str]:
    value = publisher.gh("api", f"repos/{publisher.REPOSITORY}/contents/README.md?ref=main")
    if value.get("encoding") != "base64" or not value.get("sha"):
        raise RuntimeError("GitHub did not return a versioned README file.")
    text = base64.b64decode(value["content"], validate=False).decode("utf-8")
    return value, text


def update(commit: str) -> str | None:
    tag = verify_published_pair(commit)
    for attempt in range(3):
        current, text = read_main_readme()
        replacement = updated_readme(text, tag, commit)
        if replacement == text:
            print(f"README already points at {tag} or a newer verified version.")
            return None
        try:
            result = publisher.gh("api", "--method", "PUT", f"repos/{publisher.REPOSITORY}/contents/README.md", data={
                "message": f"docs: update downloads for {tag}", "branch": "main", "sha": current["sha"],
                "content": base64.b64encode(replacement.encode("utf-8")).decode("ascii")})
        except RuntimeError as error:
            # GitHub rejects stale blob SHAs. Reload current prose and compare
            # version precedence again rather than replacing a concurrent edit.
            if "409" in str(error) and attempt < 2:
                continue
            raise
        new_sha = result.get("commit", {}).get("sha")
        content_sha = result.get("content", {}).get("sha")
        if not re.fullmatch(r"[0-9a-f]{40}", new_sha or "") or not content_sha:
            raise RuntimeError("README update did not return its new commit and content identity.")
        confirmed = publisher.gh("api", f"repos/{publisher.REPOSITORY}/contents/README.md?ref={new_sha}")
        if (confirmed.get("sha") != content_sha
                or base64.b64decode(confirmed.get("content", "")).decode("utf-8") != replacement):
            raise RuntimeError("README commit read-back did not match the generated download links.")
        print(f"Updated README downloads to {tag} in commit {new_sha}.")
        return new_sha
    raise RuntimeError("README kept changing; retry after concurrent updates finish.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    update(args.commit)


if __name__ == "__main__":
    main()
