#!/usr/bin/env python3
"""Fetch Drumx's small CC0 starter kit from pinned, checksum-verified sources."""

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sys
import urllib.request


ROOT = Path(__file__).resolve().parents[1] / "native" / "assets" / "BigRusty"


def validate_metadata(provenance, manifest):
    samples = {item["file"]: item for item in provenance["files"]}
    expected_prefix = (
        "https://raw.githubusercontent.com/sfzinstruments/"
        "karoryfer.big-rusty-drums/" + provenance["source_commit"] + "/"
    )
    for item in samples.values():
        if not (ROOT / item["file"]).resolve().is_relative_to(ROOT):
            raise ValueError("Asset path escapes the kit directory")
        if not item["source_url"].startswith(expected_prefix):
            raise ValueError("Source does not use the pinned upstream commit")
    if len(manifest) != 24:
        raise ValueError("Expected four layers and two variations for three pads")
    recording_hashes = [item["sha256"] for item in samples.values() if "instrument" in item]
    if len(recording_hashes) != 24 or len(set(recording_hashes)) != 24:
        raise ValueError("Expected 24 distinct original recordings")
    for entry in manifest:
        file = entry["file"].removeprefix("BigRusty/")
        if file not in samples or "instrument" not in samples[file]:
            raise ValueError("Sampler manifest references an unknown recording")
    for pad in range(3):
        for velocity in range(1, 128):
            choices = [
                entry for entry in manifest
                if entry["pad"] == pad
                and entry["velocityMin"] <= velocity <= entry["velocityMax"]
            ]
            if len(choices) != 2 or {x["roundRobin"] for x in choices} != {1, 2}:
                raise ValueError(f"Invalid layer coverage at pad {pad}, velocity {velocity}")
            hashes = {
                samples[x["file"].removeprefix("BigRusty/")]["sha256"]
                for x in choices
            }
            if len(hashes) != 2:
                raise ValueError("Round robins must be distinct recorded samples")


def verify_bytes(data, item):
    if len(data) != item["bytes"]:
        raise ValueError(f"Byte count mismatch: {item['file']}")
    if hashlib.sha256(data).hexdigest() != item["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {item['file']}")


def ensure_file(item, check_only):
    path = ROOT / item["file"]
    if path.exists():
        verify_bytes(path.read_bytes(), item)
        return False
    if check_only:
        raise FileNotFoundError(path)
    request = urllib.request.Request(item["source_url"], headers={"User-Agent": "Drumx-sample-fetch/1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read()
    verify_bytes(data, item)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".download")
    try:
        temporary.write_bytes(data)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify local assets without network access")
    args = parser.parse_args()
    provenance = json.loads((ROOT / "provenance.json").read_text())
    manifest = json.loads((ROOT / "manifest.json").read_text())
    validate_metadata(provenance, manifest)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda item: ensure_file(item, args.check), provenance["files"]))
    total = sum(item["bytes"] for item in provenance["files"])
    print(f"Verified {len(results)} files ({total:,} bytes), 24 unique samples, complete MIDI velocity coverage.")
    if not args.check:
        print(f"Downloaded {sum(results)} missing files. Existing files were checksum-verified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Sample verification failed: {error}", file=sys.stderr)
        sys.exit(1)
