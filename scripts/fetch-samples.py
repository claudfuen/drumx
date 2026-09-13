#!/usr/bin/env python3
"""Fetch Drumx's CC0 acoustic kit from pinned, checksum-verified sources."""

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import urllib.request


ROOT = Path(__file__).resolve().parents[1] / "native" / "assets" / "BigRusty"
INSTRUMENTS = (
    "hihat", "snare", "kick", "tom_high", "tom_mid", "tom_floor",
    "crash", "ride", "hihat_open", "hihat_pedal",
)
VELOCITY_RANGES = ((1, 31), (32, 63), (64, 95), (96, 127))
ROUND_ROBINS = (1, 2)


def safe_relative_path(value):
    path = PurePosixPath(value)
    return not path.is_absolute() and ".." not in path.parts and str(path) == value


def validate_metadata(provenance, manifest):
    samples = {item["file"]: item for item in provenance["files"]}
    if len(samples) != len(provenance["files"]):
        raise ValueError("Duplicate provenance file")
    if not re.fullmatch(r"[0-9a-f]{40}", provenance["source_commit"]):
        raise ValueError("Source commit must be a full pinned commit hash")
    expected_prefix = (
        "https://raw.githubusercontent.com/sfzinstruments/"
        "karoryfer.big-rusty-drums/" + provenance["source_commit"] + "/"
    )
    for item in samples.values():
        if not safe_relative_path(item["file"]) or not (ROOT / item["file"]).resolve().is_relative_to(ROOT):
            raise ValueError("Asset path escapes the kit directory")
        if not safe_relative_path(item["source_path"]) or item["source_url"] != expected_prefix + item["source_path"]:
            raise ValueError("Source does not use the pinned upstream commit")
    contract = provenance["kit_contract"]
    if (contract["version"] != 1
            or contract["velocity_ranges"] != [list(x) for x in VELOCITY_RANGES]
            or contract["round_robins"] != list(ROUND_ROBINS)):
        raise ValueError("Unexpected kit velocity or round-robin contract")
    pads = {pad["pad"]: pad for pad in contract["pads"]}
    if len(pads) != len(INSTRUMENTS) or len(pads) != len(contract["pads"]):
        raise ValueError("Expected all ten distinct kit pads")
    for pad, instrument in enumerate(INSTRUMENTS):
        spec = pads.get(pad)
        if spec is None or spec["instrument"] != instrument:
            raise ValueError(f"Unexpected instrument for pad {pad}")
        layers = spec["source_layers"]
        if (len(layers) != len(VELOCITY_RANGES) or layers != sorted(set(layers))
                or min(layers) < 1 or max(layers) > spec["available_source_layers"]
                or spec["available_round_robins"] < len(ROUND_ROBINS)):
            raise ValueError(f"Invalid original recording selection for pad {pad}")
    expected_count = len(INSTRUMENTS) * len(VELOCITY_RANGES) * len(ROUND_ROBINS)
    if len(manifest) != expected_count:
        raise ValueError("Expected four layers and two variations for all ten pads")
    recording_hashes = [item["sha256"] for item in samples.values() if "instrument" in item]
    if len(recording_hashes) != expected_count or len(set(recording_hashes)) != expected_count:
        raise ValueError(f"Expected {expected_count} distinct original recordings")
    referenced_files = set()
    slots = set()
    for entry in manifest:
        if not entry["file"].startswith("BigRusty/"):
            raise ValueError("Sampler path must start with BigRusty/")
        file = entry["file"].removeprefix("BigRusty/")
        if file not in samples or "instrument" not in samples[file]:
            raise ValueError("Sampler manifest references an unknown recording")
        if file in referenced_files:
            raise ValueError("Sampler manifest repeats a recording")
        referenced_files.add(file)
        pad = entry["pad"]
        if pad not in pads:
            raise ValueError(f"Unknown sampler pad {pad}")
        velocity_range = (entry["velocityMin"], entry["velocityMax"])
        if velocity_range not in VELOCITY_RANGES or entry["roundRobin"] not in ROUND_ROBINS:
            raise ValueError("Unexpected velocity range or round robin")
        curated_layer = VELOCITY_RANGES.index(velocity_range) + 1
        slot = (pad, curated_layer, entry["roundRobin"])
        if slot in slots:
            raise ValueError("Duplicate sampler pad/layer/round-robin slot")
        slots.add(slot)
        item = samples[file]
        spec = pads[pad]
        source_layer = spec["source_layers"][curated_layer - 1]
        expected_source = f"{spec['source_path_prefix']}_vl{source_layer}_rr{entry['roundRobin']}.flac"
        expected_file = f"{spec['instrument']}/v{curated_layer}_rr{entry['roundRobin']}.flac"
        if (item["instrument"] != spec["instrument"] or file != expected_file
                or item["curated_layer"] != curated_layer or item["layer"] != source_layer
                or item["round_robin"] != entry["roundRobin"] or item["source_path"] != expected_source):
            raise ValueError(f"Recording identity does not match pad {pad}, layer {curated_layer}")
    for pad in pads:
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
    if "instrument" in item:
        actual = flac_stream_info(data)
        if any(actual[field] != item[field] for field in actual):
            raise ValueError(f"FLAC format metadata mismatch: {item['file']}")
        if (actual["sample_rate"], actual["channels"], actual["bits_per_sample"]) != (44100, 1, 16):
            raise ValueError(f"Expected original mono 44.1 kHz 16-bit recording: {item['file']}")
        if actual["frames"] <= 0 or abs(item["duration_seconds"] - actual["frames"] / actual["sample_rate"]) > 1e-9:
            raise ValueError(f"Invalid recording duration: {item['file']}")


def flac_stream_info(data):
    """Read the original FLAC STREAMINFO without an optional decoder dependency."""
    if (len(data) < 42 or data[:4] != b"fLaC" or data[4] & 0x7f != 0
            or int.from_bytes(data[5:8], "big") != 34):
        raise ValueError("Recording is missing a valid FLAC STREAMINFO block")
    packed = int.from_bytes(data[18:26], "big")
    return {
        "sample_rate": packed >> 44,
        "channels": ((packed >> 41) & 7) + 1,
        "bits_per_sample": ((packed >> 36) & 31) + 1,
        "frames": packed & ((1 << 36) - 1),
    }


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
    print(f"Verified {len(results)} files ({total:,} bytes), {len(manifest)} unique samples, "
          f"complete MIDI velocity coverage for {len(INSTRUMENTS)} pads.")
    if not args.check:
        print(f"Downloaded {sum(results)} missing files. Existing files were checksum-verified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Sample verification failed: {error}", file=sys.stderr)
        sys.exit(1)
