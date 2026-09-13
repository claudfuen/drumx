#!/usr/bin/env python3
"""The release gate rejects incomplete, stale, dirty, or altered artifact pairs."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "publish-game-preview.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
COMMIT = "a" * 40


class PairFixture:
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "source"
        self.output = Path(self.temporary.name) / "output"
        self.root.mkdir()
        self.output.mkdir()
        for name in publisher.PROJECT_NOTICES:
            (self.root / name).write_text(f"Original fixture {name}\n")
        self.license_hashes = {name: publisher.digest(self.root / name) for name in publisher.PROJECT_NOTICES}
        for target in publisher.TARGETS:
            archive = self.output / f"Drumx-{target}.zip"
            value = {"commit": COMMIT, "dirty": False, "target": target, "archive": archive.name,
                     "godot": "4.7.2.stable.official.fixture", "sample_manifest_sha256": "same-samples",
                     "font_provenance_sha256": "same-font", "project_license_sha256": self.license_hashes,
                     "signing": "ad-hoc, not notarized" if target == "macos-arm64" else "unsigned",
                     "verified": ["packaged headless smoke"]}
            with zipfile.ZipFile(archive, "w") as bundle:
                prefix = f"Drumx-{target}/"
                bundle.writestr(prefix + "build-manifest.json", json.dumps(value))
                for name in publisher.PROJECT_NOTICES:
                    bundle.writestr(prefix + name, (self.root / name).read_bytes())
                    if target == "macos-arm64":
                        bundle.writestr(prefix + "Drumx.app/Contents/Resources/Drumx licensing/" + name,
                                        (self.root / name).read_bytes())
            value["sha256"] = publisher.digest(archive)
            (self.output / f"{target}.json").write_text(json.dumps(value))

    def tearDown(self):
        self.temporary.cleanup()

    def change(self, **values):
        path = self.output / "windows-x86_64.json"
        original = json.loads(path.read_text())
        path.write_text(json.dumps({**original, **values}))

    def verify(self):
        with patch.object(publisher, "ROOT", self.root), patch.object(publisher, "OUTPUT", self.output), patch.object(sys, "argv", ["publish", "--commit", COMMIT, "--verify-only"]), \
             patch.object(publisher, "gh", side_effect=AssertionError("Verification must not call GitHub")):
            publisher.main()


class PairGateChecks(PairFixture, unittest.TestCase):
    def test_pair_records_both_targets_and_commit_without_network(self):
        self.verify()
        value = json.loads((self.output / "build-manifest.json").read_text())
        self.assertEqual(value["commit"], COMMIT)
        self.assertEqual({entry["target"] for entry in value["packages"]}, set(publisher.TARGETS))
        self.assertEqual(value["release_tag"], f"preview-{COMMIT[:12]}")
        self.assertEqual(len((self.output / "SHA256SUMS.txt").read_text().splitlines()), 6)

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

    def test_missing_project_license_is_rejected(self):
        (self.root / "LICENSE").unlink()
        with self.assertRaisesRegex(RuntimeError, "Required project notice"):
            self.verify()

    def test_package_notice_must_match_source_even_when_archive_hash_matches(self):
        path = self.output / "Drumx-windows-x86_64.zip"
        with zipfile.ZipFile(path) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries["Drumx-windows-x86_64/LICENSE"] = b"altered terms"
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries.items(): archive.writestr(name, data)
        self.change(sha256=publisher.digest(path))
        with self.assertRaisesRegex(RuntimeError, "Packaged project notice mismatch"):
            self.verify()

    def test_mac_app_keeps_license_when_moved_out_of_outer_directory(self):
        path = self.output / "Drumx-macos-arm64.zip"
        with zipfile.ZipFile(path) as archive:
            entries = {name: archive.read(name) for name in archive.namelist() if "Drumx licensing/LICENSE" not in name}
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries.items(): archive.writestr(name, data)
        manifest_path = self.output / "macos-arm64.json"
        value = json.loads(manifest_path.read_text())
        value["sha256"] = publisher.digest(path)
        manifest_path.write_text(json.dumps(value))
        with self.assertRaises(KeyError): self.verify()


class PublicationChecks(PairFixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.environment = {"GITHUB_REPOSITORY": publisher.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                            "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": COMMIT, "GITHUB_RUN_ID": "123"}
        self.tag_commit = None
        self.release = None
        self.calls = []
        self.corrupt_upload = False

    def fake_gh(self, *args, data=None, allow_missing=False):
        self.calls.append((args, data))
        endpoint = f"repos/{publisher.REPOSITORY}"
        tag = publisher.preview_tag(COMMIT)
        if args == ("api", f"{endpoint}/releases/tags/{tag}"):
            return self.release
        if args == ("api", "--paginate", "--slurp", f"{endpoint}/releases?per_page=100"):
            return [[]]
        if args == ("api", f"{endpoint}/git/ref/tags/{tag}"):
            return {"object": {"type": "commit", "sha": self.tag_commit}} if self.tag_commit else None
        if args == ("api", "--method", "POST", f"{endpoint}/git/refs"):
            self.tag_commit = data["sha"]
            return {"object": {"type": "commit", "sha": self.tag_commit}}
        if args == ("api", "--method", "POST", f"{endpoint}/releases"):
            self.release = {**data, "id": 7, "assets": []}
            return self.release
        if args[:3] == ("release", "upload", tag):
            self.assertNotIn("--clobber", args)
            for filename in args[3:-2]:
                path = Path(filename)
                self.release["assets"].append({"name": path.name, "state": "uploaded", "size": path.stat().st_size,
                    "digest": "sha256:" + ("bad" if self.corrupt_upload else publisher.digest(path))})
            return ""
        if args == ("api", f"{endpoint}/releases/7"):
            return self.release
        if args == ("api", "--method", "PATCH", f"{endpoint}/releases/7"):
            self.release.update(data)
            return self.release
        raise AssertionError(f"Unexpected GitHub call: {args}")

    def publish(self):
        with patch.object(publisher, "ROOT", self.root), patch.object(publisher, "OUTPUT", self.output), \
             patch.dict(publisher.os.environ, self.environment, clear=True), patch.object(publisher, "gh", side_effect=self.fake_gh):
            files = publisher.verify_pair(COMMIT)
            return publisher.publish(COMMIT, files)

    def mutations(self):
        return [call for call in self.calls if "--method" in call[0] or call[0][:2] == ("release", "upload")]

    def test_new_pair_publishes_only_after_asset_readback(self):
        url = self.publish()
        self.assertTrue(url.endswith("preview-" + COMMIT[:12]))
        self.assertEqual(self.tag_commit, COMMIT)
        self.assertFalse(self.release["draft"])
        self.assertTrue(self.release["prerelease"])
        self.assertEqual(self.release["make_latest"], "false")
        self.assertEqual(len(self.release["assets"]), 7)
        self.assertIn("Commercial use requires a separate paid license", self.release["body"])

    def test_identical_rerun_has_no_mutations(self):
        self.publish()
        before = len(self.mutations())
        self.publish()
        self.assertEqual(len(self.mutations()), before)

    def test_tag_pointing_elsewhere_is_never_moved(self):
        self.tag_commit = "b" * 40
        with self.assertRaisesRegex(RuntimeError, "will not be moved"):
            self.publish()
        self.assertEqual(self.mutations(), [])

    def test_changed_existing_asset_is_never_replaced(self):
        self.publish()
        self.release["assets"][0]["digest"] = "sha256:changed"
        before = len(self.mutations())
        with self.assertRaisesRegex(RuntimeError, "will not be replaced"):
            self.publish()
        self.assertEqual(len(self.mutations()), before)

    def test_missing_published_asset_does_not_mutate_public_version(self):
        self.publish()
        self.release["assets"].pop()
        before = len(self.mutations())
        with self.assertRaisesRegex(RuntimeError, "Published release is missing assets"):
            self.publish()
        self.assertEqual(len(self.mutations()), before)

    def test_matching_partial_draft_resumes_without_replacing_existing_asset(self):
        self.publish()
        self.release["draft"] = True
        self.release["assets"] = self.release["assets"][:1]
        before = len(self.calls)
        self.publish()
        uploads = [call for call in self.calls[before:] if call[0][:2] == ("release", "upload")]
        self.assertEqual(len(uploads), 1)
        self.assertNotIn(str(self.output / "Drumx-macos-arm64.zip"), uploads[0][0])
        self.assertFalse(self.release["draft"])

    def test_bad_upload_cannot_publish(self):
        self.corrupt_upload = True
        with self.assertRaisesRegex(RuntimeError, "Immutable release asset mismatch"):
            self.publish()
        self.assertTrue(self.release["draft"])
        self.assertFalse(any(call[1] and call[1].get("draft") is False for call in self.calls))

    def test_pull_request_fork_other_branch_or_commit_cannot_publish(self):
        for key, value in [("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_REPOSITORY", "other/drumx"),
                           ("GITHUB_REF", "refs/heads/feature"), ("GITHUB_SHA", "b" * 40)]:
            with self.subTest(key=key):
                old = self.environment[key]
                self.environment[key] = value
                with self.assertRaisesRegex(RuntimeError, "restricted"):
                    self.publish()
                self.environment[key] = old
        self.assertEqual(self.calls, [])

    def test_full_commit_is_required_for_version_tag(self):
        with self.assertRaisesRegex(RuntimeError, "full commit"):
            publisher.preview_tag(COMMIT[:12])


if __name__ == "__main__":
    unittest.main()
