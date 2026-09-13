"""Reference-library refresh checks using tiny original charts and fake media."""
from contextlib import contextmanager, ExitStack
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("import_song_refresh", Path(__file__).parents[1] / "import_song.py")
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)

CHART = b'''[Song]
{
  Name = "Original refresh fixture"
  Resolution = 192
}
[SyncTrack]
{
  0 = B 120000
}
[EasyDrums]
{
  0 = N 0 0
}
[ExpertDrums]
{
  0 = N 0 0
  192 = N 1 0
}
'''


class ReferenceRefreshChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.collection = self.root / "collection"
        self.library = self.root / "library"
        self.song = self.make_song("first")

    def make_song(self, name):
        song = self.collection / name
        song.mkdir(parents=True)
        (song / "notes.chart").write_bytes(CHART)
        (song / "song.ini").write_text(f"[song]\nname = {name}\n")
        (song / "song.ogg").write_bytes(b"original tiny audio fixture")
        return song

    def load(self, **kwargs):
        return IMPORTER.import_song(self.song, self.library, reference=True, **kwargs)

    @contextmanager
    def no_source_work(self, forbid_full_manifest=False):
        original_open = Path.open

        def guarded_open(path, *args, **kwargs):
            self.assertNotIn(self.collection, path.parents, f"Refresh opened a source asset: {path.name}")
            if forbid_full_manifest:
                self.assertNotEqual(path.name, "song.json", "Current sidecars should avoid decoding all full charts")
            return original_open(path, *args, **kwargs)

        with ExitStack() as stack:
            for name in ("parse_chart", "parse_midi", "read_ini", "build_charts"):
                stack.enter_context(patch.object(IMPORTER, name, side_effect=AssertionError(f"Refresh called {name}")))
            stack.enter_context(patch.object(IMPORTER.hashlib, "sha256", side_effect=AssertionError("Refresh rehashed assets")))
            stack.enter_context(patch.object(Path, "open", guarded_open))
            yield

    def test_unchanged_import_retains_full_chart_without_asset_reads_or_writes(self):
        first = self.load(source_url="https://example.test/original")
        manifest_path = Path(first["manifestPath"])
        info_path = manifest_path.with_name("song-info.json")
        stamps = (manifest_path.stat(), info_path.stat())
        with self.no_source_work():
            second = self.load()
        self.assertEqual(first, second)
        self.assertEqual(stamps, (manifest_path.stat(), info_path.stat()))
        fingerprint = first["referenceFingerprint"]
        self.assertEqual(fingerprint["sourcePath"], str(self.song))
        self.assertEqual(fingerprint["rootPath"], str(self.song))
        self.assertEqual([entry["path"] for entry in fingerprint["files"]], ["notes.chart", "song.ini", "song.ogg"])
        for entry in fingerprint["files"]:
            attributes = (self.song / entry["path"]).stat()
            self.assertEqual((entry["size"], entry["mtime_ns"], entry["ctime_ns"]),
                             (attributes.st_size, attributes.st_mtime_ns, attributes.st_ctime_ns))
        self.assertEqual(sorted(path.name for path in manifest_path.parent.iterdir()), ["song-info.json", "song.json"])

    def test_scan_seeds_once_then_uses_only_sidecars_and_stats(self):
        self.make_song("second")
        with patch.object(IMPORTER.hashlib, "sha256", wraps=IMPORTER.hashlib.sha256) as hashing:
            initial = IMPORTER.scan_directory(self.collection, self.library, reference=True)
        self.assertEqual(hashing.call_count, 2)
        self.assertEqual(len(initial["imported"]), 2)
        self.assertFalse(initial["errors"])
        with self.no_source_work(forbid_full_manifest=True), patch.object(
                IMPORTER, "_reference_cache", wraps=IMPORTER._reference_cache) as cache_reads:
            refreshed = IMPORTER.scan_directory(self.collection, self.library, reference=True)
        self.assertEqual(initial, refreshed)
        self.assertEqual(cache_reads.call_count, 1)

    def test_changed_audio_chart_metadata_or_file_inventory_reimports(self):
        changes = {
            "audio": lambda: (self.song / "song.ogg").write_bytes(b"changed audio"),
            "chart": lambda: (self.song / "notes.chart").write_bytes(CHART.replace(b"192 = N 1", b"192 = N 2")),
            "metadata": lambda: (self.song / "song.ini").write_text("[song]\nname = changed title\n"),
            "new asset": lambda: (self.song / "album.png").write_bytes(b"original art fixture"),
            "renamed asset": lambda: (self.song / "song.ogg").rename(self.song / "drums.ogg"),
        }
        previous = self.load()
        for label, change in changes.items():
            with self.subTest(change=label):
                change()
                with patch.object(IMPORTER.hashlib, "sha256", wraps=IMPORTER.hashlib.sha256) as hashing, patch.object(
                        IMPORTER, "parse_chart", wraps=IMPORTER.parse_chart) as parsing:
                    current = self.load()
                self.assertEqual(hashing.call_count, 1)
                self.assertEqual(parsing.call_count, 1)
                self.assertNotEqual(previous["id"], current["id"])
                self.assertNotEqual(previous["referenceFingerprint"], current["referenceFingerprint"])
                previous = current

    @unittest.skipIf(os.name == "nt", "Windows ctime is creation time, not a change timestamp")
    def test_same_size_audio_edit_with_restored_mtime_is_not_reused(self):
        previous = self.load()
        audio = self.song / "song.ogg"
        attributes = audio.stat()
        audio.write_bytes(b"x" * attributes.st_size)
        os.utime(audio, ns=(attributes.st_atime_ns, attributes.st_mtime_ns))
        with patch.object(IMPORTER.hashlib, "sha256", wraps=IMPORTER.hashlib.sha256) as hashing:
            current = self.load()
        self.assertEqual(hashing.call_count, 1)
        self.assertNotEqual(previous["id"], current["id"])

    def test_old_content_ids_cannot_shadow_the_current_source_fingerprint(self):
        old = self.load()
        (self.song / "song.ini").write_text("[song]\nname = revised source\n")
        current = self.load()
        self.assertNotEqual(old["id"], current["id"])
        cache = IMPORTER._reference_cache(self.library)
        entries = cache[str(self.song)]
        self.assertEqual(len(entries), 2)
        for order in (entries, list(reversed(entries))):
            with self.no_source_work():
                self.assertEqual(current, self.load(_cache={str(self.song): order}))

    def test_missing_audio_or_chart_never_returns_cached_success(self):
        previous = self.load()
        manifest_path = Path(previous["manifestPath"])
        saved = manifest_path.read_bytes()
        (self.song / "song.ogg").unlink()
        report = IMPORTER.scan_directory(self.collection, self.library, reference=True)
        self.assertFalse(report["imported"])
        self.assertEqual(len(report["errors"]), 1)
        self.assertIn("No song audio", report["errors"][0]["error"])
        self.assertEqual(saved, manifest_path.read_bytes())
        (self.song / "notes.chart").unlink()
        with self.assertRaisesRegex(IMPORTER.SongImportError, "No notes"):
            self.load()
        self.assertEqual(saved, manifest_path.read_bytes())

    def test_old_metadata_version_rebuilds_summary_from_cached_manifest(self):
        previous = self.load()
        manifest_path = Path(previous["manifestPath"])
        saved = manifest_path.read_bytes()
        info_path = manifest_path.with_name("song-info.json")
        summary = json.loads(info_path.read_text())
        summary["metadataVersion"] = IMPORTER.SONG_INFO_VERSION - 1
        for chart in summary["charts"]:
            chart.pop("intensity")
        info_path.write_text(json.dumps(summary))
        with self.no_source_work():
            report = IMPORTER.scan_directory(self.collection, self.library, reference=True)
        self.assertFalse(report["errors"])
        repaired = json.loads(info_path.read_text())
        self.assertEqual(repaired, IMPORTER.song_info(previous))
        self.assertEqual(saved, manifest_path.read_bytes())
        with self.no_source_work(forbid_full_manifest=True):
            self.assertEqual(report, IMPORTER.scan_directory(self.collection, self.library, reference=True))

    def test_old_import_without_fingerprint_hashes_once_to_seed(self):
        previous = self.load()
        manifest_path = Path(previous["manifestPath"])
        for path in (manifest_path, manifest_path.with_name("song-info.json")):
            value = json.loads(path.read_text())
            value.pop("referenceFingerprint")
            path.write_text(json.dumps(value))
        with patch.object(IMPORTER.hashlib, "sha256", wraps=IMPORTER.hashlib.sha256) as hashing:
            seeded = self.load()
        self.assertEqual(hashing.call_count, 1)
        self.assertEqual(seeded["id"], previous["id"])
        self.assertEqual(seeded["importedAt"], previous["importedAt"])
        self.assertIn("referenceFingerprint", seeded)
        with self.no_source_work():
            self.assertEqual(seeded, self.load())

    def test_changed_import_options_do_not_reuse_old_selection_or_mapping(self):
        self.load()
        easy = self.load(difficulty="easy")
        self.assertEqual(easy["selectedDifficulty"], "easy")
        self.assertEqual(len(easy["notes"]), 1)
        with self.no_source_work():
            self.assertEqual(easy, self.load(difficulty="easy"))
        expert = self.load(double_kick=True, source_url="https://example.test/updated")
        self.assertEqual(expert["selectedDifficulty"], "expert")
        self.assertTrue(expert["doubleKick"])
        self.assertTrue(expert["referenceFingerprint"]["doubleKick"])
        self.assertEqual(expert["provenance"]["sourceURL"], "https://example.test/updated")
        exported = self.root / "export.json"
        with self.no_source_work():
            result = self.load(double_kick=True, output=exported)
        self.assertEqual(json.loads(exported.read_text()), result)
        self.assertIn("notes", result)

    def test_source_changed_during_import_is_never_blessed_as_cached(self):
        original_discover = IMPORTER.discover_audio

        def changing_source(*args):
            result = original_discover(*args)
            (self.song / "song.ogg").write_bytes(b"changed while importing")
            return result

        with patch.object(IMPORTER, "discover_audio", side_effect=changing_source):
            with self.assertRaisesRegex(IMPORTER.SongImportError, "changed during import"):
                self.load()
        self.assertFalse(list(self.library.rglob("song.json")))
        self.assertFalse(list(self.library.rglob("song-info.json")))
        self.assertEqual(list(self.library.iterdir()), [])

    def test_missing_or_replaced_manifest_cannot_be_reused(self):
        previous = self.load()
        manifest_path = Path(previous["manifestPath"])
        manifest_path.unlink()
        with self.assertRaisesRegex(IMPORTER.SongImportError, "no safe manifest"):
            self.load()
        manifest_path.write_text(json.dumps(previous))
        cache = IMPORTER._reference_cache(self.library)
        manifest_path.write_text(json.dumps({**previous, "referenceFingerprint": None}))
        with patch.object(IMPORTER.hashlib, "sha256", wraps=IMPORTER.hashlib.sha256) as hashing:
            restored = self.load(_cache=cache)
        self.assertEqual(hashing.call_count, 1)
        self.assertEqual(restored["referenceFingerprint"], previous["referenceFingerprint"])

    def test_cached_reference_never_bypasses_symlink_validation(self):
        previous = self.load()
        audio = self.song / "song.ogg"
        moved = self.root / "external.ogg"
        audio.rename(moved)
        audio.symlink_to(moved)
        with self.assertRaisesRegex(IMPORTER.SongImportError, "symbolic links"):
            self.load()
        self.assertEqual(json.loads(Path(previous["manifestPath"]).read_text()), previous)

    def test_managed_import_still_repairs_media_instead_of_reusing_reference(self):
        reference = self.load()
        managed = IMPORTER.import_song(self.song, self.library)
        self.assertEqual(reference["id"], managed["id"])
        self.assertNotIn("referenceFingerprint", managed)
        managed_audio = Path(managed["audio"][0]["path"])
        managed_audio.write_bytes(b"damaged managed audio")
        repaired = IMPORTER.import_song(self.song, self.library)
        self.assertEqual(managed_audio.read_bytes(), (self.song / "song.ogg").read_bytes())
        self.assertEqual(repaired["mediaMode"], "managed")


if __name__ == "__main__":
    unittest.main()
