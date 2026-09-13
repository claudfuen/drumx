"""Keep release, app, and OS version identity consistent without touching source."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_version_test", ROOT / "scripts/build-version.py")
versioning = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(versioning)
COMMIT = "a" * 40


class BuildVersionChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "VERSION").write_text("0.1.0\n")
        self.env = {"GITHUB_ACTIONS": "true", "GITHUB_RUN_NUMBER": "34", "GITHUB_RUN_ID": "12345",
                    "GITHUB_REPOSITORY": "claudfuen/drumx", "GITHUB_SHA": COMMIT}

    def identity(self, env=None, dirty=""):
        with patch.object(versioning.subprocess, "check_output", side_effect=[COMMIT + "\n", dirty]):
            return versioning.build_identity(self.root, self.env if env is None else env)

    def test_ci_identity_stays_equal_on_partial_reruns(self):
        first = self.identity()
        retry = self.identity({**self.env, "GITHUB_RUN_ATTEMPT": "2"})
        self.assertEqual(first, retry)
        self.assertEqual(first["version"], "0.1.0-preview.34")
        self.assertEqual(first["release_tag"], "v0.1.0-preview.34")
        self.assertEqual(first["commit"], COMMIT)
        self.assertFalse(first["dirty"])

    def test_next_run_gets_a_new_version(self):
        self.assertEqual(self.identity({**self.env, "GITHUB_RUN_NUMBER": "35"})["version"], "0.1.0-preview.35")

    def test_local_builds_are_explicit_development_versions(self):
        clean = self.identity({})
        changed = self.identity({}, " M native/macos/DrumxMainMenuView.swift\n")
        self.assertEqual(clean["version"], "0.1.0-dev+" + COMMIT[:12])
        self.assertEqual(changed["version"], clean["version"] + ".dirty")
        self.assertIsNone(changed["release_tag"])
        self.assertIsNone(changed["workflow_run"])
        self.assertEqual(changed["channel"], "dev")

    def test_invalid_or_incomplete_ci_identity_never_falls_back_to_dev(self):
        for env in [{**self.env, "GITHUB_RUN_NUMBER": n} for n in ["0", "-1", "01", "1.2", "65536", ""]] + [
            {**self.env, "GITHUB_SHA": "b" * 40}, {"GITHUB_ACTIONS": "true"},
            {**self.env, "GITHUB_RUN_ID": ""}, {**self.env, "GITHUB_REPOSITORY": "../bad"}]:
            with self.subTest(env=env), self.assertRaises(RuntimeError):
                self.identity(env)

    def test_invalid_base_versions_are_rejected(self):
        for value in ["v0.1.0", "0.1", "0.1.0-beta", "00.1.0", "1.2.65536"]:
            (self.root / "VERSION").write_text(value)
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                versioning.build_identity(self.root, {})

    def test_mac_bundle_preserves_identity_and_existing_settings(self):
        identity = self.identity()
        plist = self.root / "Info.plist"
        plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.drumx.timing-lab", "NSHighResolutionCapable": True}))
        versioning.stamp_macos_plist(plist, identity)
        info = plistlib.loads(plist.read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "0.1.0")
        self.assertEqual(info["CFBundleVersion"], "1.0.34")
        self.assertEqual(info["DrumxVersion"], identity["version"])
        self.assertEqual(info["DrumxCommit"], COMMIT)
        self.assertTrue(info["NSHighResolutionCapable"])

    def test_godot_stamping_preserves_export_settings_and_shares_identity(self):
        identity = self.identity()
        for name in ["project.godot", "export_presets.cfg"]:
            shutil.copy2(ROOT / "apps/game" / name, self.root / name)
        versioning.stamp_godot_project(self.root, identity)
        first = (self.root / "export_presets.cfg").read_text()
        self.assertIn('application/short_version="0.1.0"', first)
        self.assertIn('application/version="1.0.34"', first)
        self.assertIn('application/file_version="0.1.0.34"', first)
        self.assertIn('application/product_version="0.1.0.34"', first)
        self.assertIn('application/bundle_identifier="org.drumx.preview"', first)
        self.assertIn('config/version="0.1.0-preview.34"', (self.root / "project.godot").read_text())
        self.assertEqual(json.loads((self.root / "build-info.json").read_text()), identity)
        versioning.stamp_godot_project(self.root, identity)
        self.assertEqual((self.root / "export_presets.cfg").read_text(), first)

    def test_mac_build_encoding_remains_ordered_at_digit_boundaries(self):
        numbers = [0, 1, 99, 100, 9999, 10000, 65535]
        encoded = [tuple(map(int, versioning.macos_build_number({"build_number": n}).split("."))) for n in numbers]
        self.assertEqual(sorted(set(encoded)), encoded)
        self.assertTrue(all(0 < a <= 9999 and 0 <= b <= 99 and 0 <= c <= 99 for a, b, c in encoded))


if __name__ == "__main__":
    unittest.main()
