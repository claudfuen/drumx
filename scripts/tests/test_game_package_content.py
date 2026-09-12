#!/usr/bin/env python3
"""Check redistribution notices and native visual geometry without exporting an app."""
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def load_module(name, script):
    spec = importlib.util.spec_from_file_location(name, ROOT / script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


content = load_module("content_checks", "scripts/verify-game-content.py")
packager = load_module("package_checks", "scripts/package-game.py")


class PackageContentChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def staged_fonts(self):
        destination = self.directory / "apps/game/assets/fonts"
        shutil.copytree(ROOT / "apps/game/assets/fonts", destination)
        return destination

    def test_pinned_original_font_and_license_validate(self):
        self.assertRegex(content.verify_font_assets(), r"^[0-9a-f]{64}$")

    def test_modified_font_or_license_is_rejected(self):
        fonts = self.staged_fonts()
        for filename in ["Inter.ttf", "OFL.txt"]:
            with self.subTest(filename=filename):
                path = fonts / filename
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(RuntimeError, "differs from pinned provenance"):
                    content.verify_font_assets(self.directory)
                path.write_bytes(original)

    def test_missing_font_license_is_rejected(self):
        fonts = self.staged_fonts()
        (fonts / "OFL.txt").unlink()
        with self.assertRaises(FileNotFoundError):
            content.verify_font_assets(self.directory)

    def test_provenance_cannot_omit_the_license(self):
        fonts = self.staged_fonts()
        provenance_path = fonts / "provenance.json"
        provenance = json.loads(provenance_path.read_text())
        provenance["files"] = [entry for entry in provenance["files"] if entry["file"] != "OFL.txt"]
        provenance_path.write_text(json.dumps(provenance))
        with self.assertRaisesRegex(RuntimeError, "exactly the original font and OFL"):
            content.verify_font_assets(self.directory)

    def test_outer_zip_keeps_readable_original_notices(self):
        package = self.directory / "Drumx-fixture"
        package.mkdir()
        # A notice-only package exercises the same production copier without
        # starting Godot, opening an audio device, signing, or invoking GitHub.
        with patch.object(packager.subprocess, "run", side_effect=AssertionError("No subprocess expected")):
            notices = packager.write_third_party_notices(package)
        expected = {
            "Inter/OFL.txt": ROOT / "apps/game/assets/fonts/OFL.txt",
            "Inter/provenance.json": ROOT / "apps/game/assets/fonts/provenance.json",
            "Inter/README.md": ROOT / "apps/game/assets/fonts/README.md",
            "BigRusty-LICENSE": ROOT / "apps/game/assets/BigRusty/LICENSE",
            "Godot/Godot-LICENSE.txt": ROOT / "scripts/distribution/Godot-LICENSE.txt",
            "Native dependencies/godot-cpp-LICENSE.md": ROOT / "apps/game/native/licenses/godot-cpp-LICENSE.md",
        }
        archive_path = self.directory / "notices.zip"
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in notices.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(package.parent))
        with zipfile.ZipFile(archive_path) as archive:
            for relative, original in expected.items():
                self.assertEqual(archive.read(f"Drumx-fixture/Third-party notices/{relative}"), original.read_bytes())
        self.assertFalse((notices / "Inter/Inter.ttf").exists(), "The notice folder need not duplicate the bundled font")

    def test_visual_baseline_comparison_ignores_json_formatting(self):
        baseline = json.loads((ROOT / "apps/game/data/visual-baseline.json").read_text())
        generated = self.directory / "regenerated.json"
        generated.write_text(json.dumps(baseline, separators=(",", ":")))
        content.compare_visual_baseline(generated)

    def test_changed_native_projection_is_rejected(self):
        baseline = json.loads((ROOT / "apps/game/data/visual-baseline.json").read_text())
        baseline["cases"][0]["points"][0]["point"][0] += 0.125
        generated = self.directory / "changed.json"
        generated.write_text(json.dumps(baseline))
        with self.assertRaisesRegex(RuntimeError, "differs from the original Swift projection"):
            content.compare_visual_baseline(generated)


if __name__ == "__main__":
    unittest.main()
