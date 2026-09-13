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

    def test_project_terms_ship_beside_apps_and_inside_movable_mac_bundle(self):
        source = self.directory / "source"
        source.mkdir()
        for name in packager.PROJECT_NOTICES:
            (source / name).write_text(f"Original project terms: {name}\n")
        package = self.directory / "Drumx-fixture"
        package.mkdir()
        app = package / "Drumx.app"
        with patch.object(packager, "ROOT", source):
            hashes = packager.write_project_notices(package, app)
        for name in packager.PROJECT_NOTICES:
            self.assertEqual((package / name).read_bytes(), (source / name).read_bytes())
            self.assertEqual((app / "Contents/Resources/Drumx licensing" / name).read_bytes(), (source / name).read_bytes())
            self.assertEqual(hashes[name], packager.fetch.sha256(source / name))

    def test_packaging_refuses_missing_or_empty_project_terms(self):
        source = self.directory / "source"
        source.mkdir()
        package = self.directory / "package"
        package.mkdir()
        with patch.object(packager, "ROOT", source):
            with self.assertRaisesRegex(RuntimeError, "missing or empty"):
                packager.write_project_notices(package)
            (source / "LICENSE").write_text("")
            with self.assertRaisesRegex(RuntimeError, "missing or empty"):
                packager.write_project_notices(package)

    def build_identity(self):
        return {"schema": 1, "base_version": "0.1.0", "version": "0.1.0-preview.42",
                "build_number": 42, "channel": "preview", "commit": "a" * 40,
                "short_commit": "a" * 12, "dirty": False,
                "workflow_run": "https://github.com/claudfuen/drumx/actions/runs/123",
                "release_tag": "v0.1.0-preview.42"}

    def test_export_staging_keeps_checkout_unchanged_and_preserves_runtime_content(self):
        source = self.directory / "source"
        source.mkdir()
        for name in ["project.godot", "export_presets.cfg"]:
            shutil.copy2(ROOT / "apps/game" / name, source / name)
        for name, data in {"bin/drumx_engine.dylib": b"native extension",
                           "assets/BigRusty/snare.flac": b"drum sample",
                           "scripts/player.gd": b"extends Node\n",
                           ".godot/editor/cache": b"stale editor cache"}.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        original = {path.relative_to(source): path.read_bytes() for path in source.rglob("*") if path.is_file()}
        identity = self.build_identity()
        destination = packager.stage_project(source, self.directory / "staged", identity)
        self.assertEqual(original, {path.relative_to(source): path.read_bytes() for path in source.rglob("*") if path.is_file()})
        self.assertFalse((destination / ".godot").exists())
        self.assertEqual((destination / "bin/drumx_engine.dylib").read_bytes(), b"native extension")
        self.assertEqual((destination / "assets/BigRusty/snare.flac").read_bytes(), b"drum sample")
        self.assertEqual((destination / "scripts/player.gd").read_bytes(), b"extends Node\n")
        self.assertEqual(json.loads((destination / "build-info.json").read_text()), identity)
        self.assertIn('config/version="0.1.0-preview.42"', (destination / "project.godot").read_text())

    def test_build_identity_is_readable_beside_both_apps_and_inside_mac_bundle(self):
        identity = self.build_identity()
        for target in ["macos-arm64", "windows-x86_64"]:
            with self.subTest(target=target):
                package = self.directory / target
                package.mkdir()
                app = package / "Drumx.app" if target == "macos-arm64" else None
                packager.write_build_info(package, identity, app)
                self.assertEqual(json.loads((package / "build-info.json").read_text()), identity)
                if app:
                    self.assertEqual((app / "Contents/Resources/build-info.json").read_bytes(),
                                     (package / "build-info.json").read_bytes())
                else:
                    self.assertFalse((package / "Drumx.app").exists())

    def test_running_app_must_report_the_exact_package_identity_and_pass_smoke(self):
        identity = self.build_identity()
        report = "DRUMX_BUILD_INFO " + json.dumps(identity) + "\n"
        packager.verify_smoke_identity("Engine startup\n" + report + "DRUMX_SMOKE_OK checks=10\n", identity)
        cases = [
            ("DRUMX_SMOKE_OK\n", "exactly one"),
            (report + report + "DRUMX_SMOKE_OK\n", "exactly one"),
            (report, "did not confirm success"),
            ("DRUMX_BUILD_INFO broken JSON\nDRUMX_SMOKE_OK\n", "malformed"),
            ("DRUMX_BUILD_INFO " + json.dumps({**identity, "version": "0.1.0-preview.41"}) + "\nDRUMX_SMOKE_OK\n", "differs"),
            ("DRUMX_BUILD_INFO " + json.dumps({**identity, "commit": "b" * 40}) + "\nDRUMX_SMOKE_OK\n", "differs"),
        ]
        for output, error in cases:
            with self.subTest(error=error, output=output):
                with self.assertRaisesRegex(RuntimeError, error):
                    packager.verify_smoke_identity(output, identity)

    def test_package_manifest_archive_and_running_app_share_one_identity(self):
        source = self.directory / "source"
        project = source / "apps/game"
        (project / "bin").mkdir(parents=True)
        for name in ["project.godot", "export_presets.cfg"]:
            shutil.copy2(ROOT / "apps/game" / name, project / name)
        (project / "bin/drumx_engine.dll").write_bytes(b"native extension")
        for name in packager.PROJECT_NOTICES:
            (source / name).write_text(f"Project terms {name}\n")
        cache = self.directory / "toolchain"
        cache.mkdir()
        editor = cache / "godot.exe"
        (cache / "toolchain.json").write_text(json.dumps({"editor": str(editor)}))
        identity = self.build_identity()
        stages = []

        def execute(command, log, timeout=180):
            if "--path" in command:
                staged = Path(command[command.index("--path") + 1])
                self.assertNotEqual(staged, project)
                self.assertEqual(json.loads((staged / "build-info.json").read_text()), identity)
            stages.append(log.name)
            if "--export-release" in command:
                destination = Path(command[-1])
                destination.write_bytes(b"exported executable")
                (destination.parent / "Drumx.pck").write_bytes(b"exported resources")
                (destination.parent / "drumx_engine.dll").write_bytes(b"native extension")
            if "--smoke-test" in command:
                return "DRUMX_BUILD_INFO " + json.dumps(identity) + "\nDRUMX_SMOKE_OK\n"
            return ""

        with patch.object(packager, "ROOT", source), patch.object(packager, "PROJECT", project), \
             patch.object(packager.fetch, "CACHE", cache), \
             patch.object(packager.platform, "system", return_value="Windows"), \
             patch.object(packager.subprocess, "check_output", return_value=f"{packager.fetch.VERSION}.stable.official.fixture"), \
             patch.object(packager.version, "build_identity", return_value=identity), \
             patch.object(packager, "validate_assets", return_value="a" * 64), \
             patch.object(packager.content, "verify_font_assets", return_value="b" * 64), \
             patch.object(packager, "write_third_party_notices"), \
             patch.object(packager, "run", side_effect=execute), \
             patch.object(sys, "argv", ["package-game.py", "--target", "windows-x86_64"]):
            packager.main()

        self.assertEqual(stages, ["import.log", "source-smoke.log", "export.log", "packaged-smoke.log"])
        self.assertFalse((project / "build-info.json").exists())
        output = source / ".build/preview"
        outer = json.loads((output / "windows-x86_64.json").read_text())
        self.assertEqual(outer["build_identity"], identity)
        self.assertEqual(outer["commit"], identity["commit"])
        with zipfile.ZipFile(output / outer["archive"]) as archive:
            prefix = "Drumx-windows-x86_64/"
            inner = json.loads(archive.read(prefix + "build-manifest.json"))
            self.assertEqual(inner["build_identity"], identity)
            self.assertEqual(json.loads(archive.read(prefix + "build-info.json")), identity)
            self.assertIn("Version: 0.1.0-preview.42", archive.read(prefix + "START-HERE.txt").decode())
        self.assertEqual(outer["sha256"], packager.fetch.sha256(output / outer["archive"]))

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
