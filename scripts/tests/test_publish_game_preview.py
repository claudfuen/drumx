#!/usr/bin/env python3
"""The release gate rejects incomplete, stale, dirty, or altered artifact pairs."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "publish-game-preview.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
COMMIT = "a" * 40


class PairGateChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.output = Path(self.temporary.name)
        for target in publisher.TARGETS:
            archive = self.output / f"Drumx-{target}.zip"
            archive.write_bytes(f"fixture-{target}".encode())
            value = {"commit": COMMIT, "dirty": False, "target": target, "archive": archive.name,
                     "sha256": publisher.digest(archive), "godot": "4.7.2.stable.official.fixture",
                     "sample_manifest_sha256": "same-samples", "verified": ["packaged headless smoke"]}
            (self.output / f"{target}.json").write_text(json.dumps(value))

    def tearDown(self):
        self.temporary.cleanup()

    def change(self, **values):
        path = self.output / "windows-x86_64.json"
        original = json.loads(path.read_text())
        path.write_text(json.dumps({**original, **values}))

    def verify(self):
        with patch.object(publisher, "OUTPUT", self.output), patch.object(sys, "argv", ["publish", "--commit", COMMIT, "--verify-only"]), \
             patch.object(publisher, "gh", side_effect=AssertionError("Verification must not call GitHub")):
            publisher.main()

    def test_pair_records_both_targets_and_commit_without_network(self):
        self.verify()
        value = json.loads((self.output / "build-manifest.json").read_text())
        self.assertEqual(value["commit"], COMMIT)
        self.assertEqual({entry["target"] for entry in value["packages"]}, set(publisher.TARGETS))
        self.assertEqual(len((self.output / "SHA256SUMS.txt").read_text().splitlines()), 3)

    def test_other_commit_is_rejected(self):
        self.change(commit="b" * 40)
        with self.assertRaises(RuntimeError): self.verify()

    def test_dirty_build_is_rejected(self):
        self.change(dirty=True)
        with self.assertRaises(RuntimeError): self.verify()

    def test_changed_archive_is_rejected(self):
        (self.output / "Drumx-windows-x86_64.zip").write_bytes(b"altered")
        with self.assertRaises(RuntimeError): self.verify()

    def test_missing_partner_is_rejected(self):
        (self.output / "windows-x86_64.json").unlink()
        with self.assertRaises(FileNotFoundError): self.verify()

    def test_missing_smoke_is_rejected(self):
        self.change(verified=[])
        with self.assertRaises(RuntimeError): self.verify()

    def test_different_engine_is_rejected(self):
        self.change(godot="4.5.stable")
        with self.assertRaises(RuntimeError): self.verify()

    def test_different_sample_manifest_is_rejected(self):
        self.change(sample_manifest_sha256="other-samples")
        with self.assertRaises(RuntimeError): self.verify()


if __name__ == "__main__":
    unittest.main()
