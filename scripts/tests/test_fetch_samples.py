"""Keep full-kit recording identity, coverage, and verified restore behavior intact."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("fetch_samples", ROOT / "scripts/fetch-samples.py")
samples = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(samples)
PROVENANCE = json.loads((samples.ROOT / "provenance.json").read_text())
MANIFEST = json.loads((samples.ROOT / "manifest.json").read_text())


class FullKitSampleChecks(unittest.TestCase):
    def setUp(self):
        self.provenance = copy.deepcopy(PROVENANCE)
        self.manifest = copy.deepcopy(MANIFEST)

    def validate(self):
        samples.validate_metadata(self.provenance, self.manifest)

    def test_all_ten_pads_have_verified_distinct_original_recordings(self):
        self.validate()
        self.assertEqual({entry["pad"] for entry in self.manifest}, set(range(10)))
        self.assertEqual(len(self.manifest), 80)
        with patch.object(samples.urllib.request, "urlopen", side_effect=AssertionError("Network forbidden")):
            for item in self.provenance["files"]:
                self.assertFalse(samples.ensure_file(item, check_only=True))

    def test_contract_cannot_silently_shrink_to_incomplete_kit(self):
        self.provenance["kit_contract"]["pads"].pop()
        self.provenance["files"] = [x for x in self.provenance["files"] if x.get("instrument") != "hihat_pedal"]
        self.manifest = [x for x in self.manifest if x["pad"] != 9]
        with self.assertRaisesRegex(ValueError, "ten distinct kit pads"):
            self.validate()

    def test_wrong_instrument_cannot_replace_a_tom(self):
        high = next(x for x in self.manifest if x["pad"] == 3)
        middle = next(x for x in self.manifest if x["pad"] == 4)
        high["file"], middle["file"] = middle["file"], high["file"]
        with self.assertRaisesRegex(ValueError, "identity does not match"):
            self.validate()

    def test_duplicate_take_cannot_masquerade_as_a_round_robin(self):
        self.provenance["files"][1]["sha256"] = self.provenance["files"][0]["sha256"]
        with self.assertRaisesRegex(ValueError, "distinct original recordings"):
            self.validate()

    def test_missing_and_duplicate_manifest_slots_are_rejected(self):
        self.manifest[-1]["roundRobin"] = 1
        with self.assertRaisesRegex(ValueError, "Duplicate sampler"):
            self.validate()

    def test_overlapping_or_note_off_velocity_ranges_are_rejected(self):
        for value in (0, 2, 32):
            with self.subTest(value=value):
                self.manifest = copy.deepcopy(MANIFEST)
                self.manifest[0]["velocityMin"] = value
                with self.assertRaisesRegex(ValueError, "Unexpected velocity range"):
                    self.validate()

    def test_original_layer_and_take_must_match_manifest(self):
        for field, value in (("layer", 2), ("round_robin", 2), ("curated_layer", 4)):
            with self.subTest(field=field):
                self.provenance = copy.deepcopy(PROVENANCE)
                self.provenance["files"][0][field] = value
                with self.assertRaisesRegex(ValueError, "identity does not match"):
                    self.validate()

    def test_duplicate_provenance_entries_are_rejected(self):
        self.provenance["files"].append(copy.deepcopy(self.provenance["files"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate provenance"):
            self.validate()

    def test_unpinned_or_mismatched_source_urls_are_rejected(self):
        item = self.provenance["files"][0]
        item["source_url"] = item["source_url"].replace(self.provenance["source_commit"], "main")
        with self.assertRaisesRegex(ValueError, "pinned upstream commit"):
            self.validate()

    def test_escaping_asset_paths_are_rejected(self):
        self.provenance["files"][0]["file"] = "../outside.flac"
        with self.assertRaisesRegex(ValueError, "escapes the kit directory"):
            self.validate()

    def test_decoded_format_metadata_must_match_flac_header(self):
        item = self.provenance["files"][0]
        data = (samples.ROOT / item["file"]).read_bytes()
        item["channels"] = 2
        with self.assertRaisesRegex(ValueError, "FLAC format metadata mismatch"):
            samples.verify_bytes(data, item)

    def test_check_does_not_fetch_missing_recordings(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(samples, "ROOT", Path(directory)):
            with patch.object(samples.urllib.request, "urlopen") as request:
                with self.assertRaises(FileNotFoundError):
                    samples.ensure_file(self.provenance["files"][0], check_only=True)
                request.assert_not_called()

    def test_restore_downloads_verified_original_and_never_overwrites_changes(self):
        item = self.provenance["files"][0]
        original = (samples.ROOT / item["file"]).read_bytes()
        with tempfile.TemporaryDirectory() as directory, patch.object(samples, "ROOT", Path(directory)):
            path = samples.ROOT / item["file"]
            with patch.object(samples.urllib.request, "urlopen", return_value=io.BytesIO(original)):
                self.assertTrue(samples.ensure_file(item, check_only=False))
            self.assertEqual(path.read_bytes(), original)
            changed = original[:-1] + bytes([original[-1] ^ 1])
            path.write_bytes(changed)
            with patch.object(samples.urllib.request, "urlopen") as request:
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    samples.ensure_file(item, check_only=False)
                request.assert_not_called()
            self.assertEqual(path.read_bytes(), changed)

    def test_corrupt_download_never_becomes_a_local_asset(self):
        item = self.provenance["files"][0]
        with tempfile.TemporaryDirectory() as directory, patch.object(samples, "ROOT", Path(directory)):
            with patch.object(samples.urllib.request, "urlopen", return_value=io.BytesIO(b"not a recording")):
                with self.assertRaisesRegex(ValueError, "Byte count mismatch"):
                    samples.ensure_file(item, check_only=False)
            self.assertFalse((samples.ROOT / item["file"]).exists())


if __name__ == "__main__":
    unittest.main()
