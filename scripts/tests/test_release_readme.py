#!/usr/bin/env python3
"""Only a verified newer release may update the README's download links."""
import base64
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_readme", Path(__file__).resolve().parents[1] / "update-release-readme.py")
readme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(readme)
COMMIT = "a" * 40
TAG = "v0.1.0-preview.42"
INITIAL = "# Drumx\nKeep this introduction.\n" + readme.START + "\nLegacy preview downloads.\n" + readme.END + "\nKeep this curriculum.\n"


class DownloadRegionChecks(unittest.TestCase):
    def test_exact_downloads_are_generated_and_surrounding_prose_is_preserved(self):
        changed = readme.updated_readme(INITIAL, TAG, COMMIT)
        self.assertTrue(changed.startswith(INITIAL.split(readme.START)[0] + readme.START))
        self.assertTrue(changed.endswith(readme.END + INITIAL.split(readme.END)[1]))
        self.assertIn(f"<!-- drumx:release {TAG} {COMMIT} -->", changed)
        self.assertIn(f"/releases/download/{TAG}/Drumx-macos-arm64.zip", changed)
        self.assertIn(f"/releases/download/{TAG}/Drumx-windows-x86_64.zip", changed)
        self.assertIn("experimental shared desktop builds", changed)
        self.assertNotIn("/releases/latest", changed)

    def test_numeric_version_order_prevents_old_reruns_from_reverting_downloads(self):
        current = readme.updated_readme(INITIAL, TAG, COMMIT)
        self.assertEqual(readme.updated_readme(current, "v0.1.0-preview.9", "b" * 40), current)
        self.assertEqual(readme.updated_readme(current, TAG, COMMIT), current)
        later = readme.updated_readme(current, "v0.2.0-preview.1", "c" * 40)
        self.assertIn("v0.2.0-preview.1", later)
        self.assertEqual(readme.updated_readme(later, "v0.1.0-preview.999", "d" * 40), later)

    def test_same_number_cannot_claim_a_different_commit(self):
        current = readme.updated_readme(INITIAL, TAG, COMMIT)
        with self.assertRaisesRegex(RuntimeError, "another immutable commit"):
            readme.updated_readme(current, TAG, "b" * 40)

    def test_missing_repeated_reversed_or_ambiguous_markers_are_rejected(self):
        for value in ["No markers", INITIAL + readme.START, readme.END + readme.START,
                      INITIAL.replace("Legacy preview downloads.", "<!-- drumx:release malformed -->"),
                      INITIAL.replace("Legacy preview downloads.", f"/releases/tag/{TAG}")]:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                readme.updated_readme(value, TAG, COMMIT)

    def test_only_canonical_numbered_previews_are_allowed(self):
        for tag in ["preview-abc", "v1.0.0", "v0.1.0-preview.042", "v0.1.0-preview.0"]:
            with self.subTest(tag=tag), self.assertRaises(RuntimeError):
                readme.updated_readme(INITIAL, tag, COMMIT)


class ReadmeUpdateChecks(unittest.TestCase):
    def setUp(self):
        self.text = INITIAL
        self.blob = "b" * 40
        self.commit = "d" * 40
        self.conflicts = 0
        self.newer_on_conflict = False
        self.bad_readback = False
        self.calls = []
        self.prefix = f"repos/{readme.publisher.REPOSITORY}/contents/README.md"

    def encoded(self, value):
        return base64.b64encode(value.encode()).decode()

    def fake_gh(self, *args, data=None):
        self.calls.append((args, data))
        if args == ("api", self.prefix + "?ref=main"):
            return {"encoding": "base64", "sha": self.blob, "content": self.encoded(self.text)}
        if args == ("api", "--method", "PUT", self.prefix):
            self.assertEqual(data["sha"], self.blob)
            self.assertEqual(data["branch"], "main")
            if self.conflicts:
                self.conflicts -= 1
                self.blob = "c" * 40
                self.text = "Concurrent introduction edit.\n" + self.text
                if self.newer_on_conflict:
                    self.text = readme.updated_readme(self.text, "v0.1.0-preview.43", "f" * 40)
                raise RuntimeError("GitHub conflict (HTTP 409)")
            self.text = base64.b64decode(data["content"]).decode()
            self.blob = "e" * 40
            return {"commit": {"sha": self.commit}, "content": {"sha": self.blob}}
        if args == ("api", self.prefix + f"?ref={self.commit}"):
            return {"encoding": "base64", "sha": self.blob,
                    "content": self.encoded("wrong content" if self.bad_readback else self.text)}
        raise AssertionError(args)

    def update(self):
        with patch.object(readme, "verify_published_pair", return_value=TAG), \
             patch.object(readme.publisher, "gh", side_effect=self.fake_gh):
            return readme.update(COMMIT)

    def writes(self):
        return [call for call in self.calls if "PUT" in call[0]]

    def test_update_has_a_matching_commit_readback(self):
        self.assertEqual(self.update(), self.commit)
        self.assertEqual(len(self.writes()), 1)
        self.assertEqual(self.text, readme.updated_readme(INITIAL, TAG, COMMIT))
        self.assertIn(f"?ref={self.commit}", self.calls[-1][0][1])

    def test_rerun_does_not_write_again(self):
        self.update()
        self.assertIsNone(self.update())
        self.assertEqual(len(self.writes()), 1)

    def test_conflict_rereads_and_preserves_concurrent_prose(self):
        self.conflicts = 1
        self.update()
        self.assertEqual(len(self.writes()), 2)
        self.assertTrue(self.text.startswith("Concurrent introduction edit.\n"))
        self.assertEqual(self.writes()[0][1]["sha"], "b" * 40)
        self.assertEqual(self.writes()[1][1]["sha"], "c" * 40)

    def test_newer_release_on_conflict_stops_stale_pointer_update(self):
        self.conflicts = 1
        self.newer_on_conflict = True
        self.assertIsNone(self.update())
        self.assertEqual(len(self.writes()), 1)
        self.assertIn("v0.1.0-preview.43", self.text)

    def test_repeated_conflicts_are_bounded(self):
        self.conflicts = 3
        with self.assertRaisesRegex(RuntimeError, "409"):
            self.update()
        self.assertEqual(len(self.writes()), 3)

    def test_mismatched_commit_readback_is_reported(self):
        self.bad_readback = True
        with self.assertRaisesRegex(RuntimeError, "read-back"):
            self.update()

    def test_unpublished_pair_never_reads_or_writes_readme(self):
        with patch.object(readme, "verify_published_pair", side_effect=RuntimeError("incomplete prerelease")), \
             patch.object(readme.publisher, "gh", side_effect=AssertionError("No README access allowed")):
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                readme.update(COMMIT)


class PublishedPairChecks(unittest.TestCase):
    def verify(self, *, release=None, missing=None, tag_commit=COMMIT):
        published = {"draft": False, "prerelease": True, "tag_name": TAG}
        with patch.object(readme.publisher, "require_publication_context"), \
             patch.object(readme.publisher, "verify_pair", return_value=[]), \
             patch.object(readme.publisher, "preview_tag", return_value=TAG), \
             patch.object(readme.publisher, "release_for_tag", return_value=published if release is None else release), \
             patch.object(readme.publisher, "missing_assets", return_value=missing or []), \
             patch.object(readme.publisher, "gh", return_value={"object": {"type": "commit", "sha": tag_commit}}):
            return readme.verify_published_pair(COMMIT)

    def test_published_verified_pair_is_eligible(self):
        self.assertEqual(self.verify(), TAG)

    def test_draft_missing_assets_or_wrong_tag_commit_are_rejected(self):
        for kwargs in [{"release": {"draft": True, "prerelease": True, "tag_name": TAG}},
                       {"missing": [Path("missing.zip")]}, {"tag_commit": "b" * 40}]:
            with self.subTest(kwargs=kwargs), self.assertRaises(RuntimeError):
                self.verify(**kwargs)


if __name__ == "__main__":
    unittest.main()
