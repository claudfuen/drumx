"""Behavioral checks with tiny original charts; no commercial media is committed."""
import importlib.util
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location("import_song", Path(__file__).parents[1] / "import_song.py")
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


def vlq(value):
    result = [value & 127]
    value >>= 7
    while value:
        result.insert(0, 128 | (value & 127))
        value >>= 7
    return bytes(result)


def midi_file(track_events, resolution=480, extra_tracks=()):
    tracks = []
    for events in [*extra_tracks, track_events]:
        body = bytearray()
        previous = 0
        for tick, payload in sorted(events, key=lambda event: event[0]):
            body.extend(vlq(tick - previous) + payload)
            previous = tick
        body.extend(b"\x00\xff\x2f\x00")
        tracks.append(b"MTrk" + struct.pack(">I", len(body)) + body)
    return b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), resolution) + b"".join(tracks)


def note(tick, pitch, length=1, velocity=100):
    return [(tick, bytes([0x99, pitch, velocity])), (tick + length, bytes([0x89, pitch, 0]))]


def text(tick, value, kind=1):
    encoded = value.encode()
    return (tick, b"\xff" + bytes([kind]) + vlq(len(encoded)) + encoded)


def simple_chart(extra="", song_extra="", expert="0 = N 0 0\n192 = N 1 0"):
    return (f'[Song]\n{{\nName = "Original Test Song"\nArtist = "Drumx Test"\nResolution = 192\n{song_extra}\n}}\n'
            f'[SyncTrack]\n{{\n0 = B 120000\n{extra}\n}}\n[ExpertDrums]\n{{\n{expert}\n}}\n').encode()


def sng_file(files, metadata=None, mask=bytes(range(16))):
    metadata = metadata or {}
    meta = struct.pack("<Q", len(metadata))
    for key, value in metadata.items():
        for value in (key, value):
            encoded = value.encode()
            meta += struct.pack("<i", len(encoded)) + encoded
    index_len = 8 + sum(1 + len(name.encode()) + 16 for name in files)
    offset = 26 + 8 + len(meta) + 8 + index_len + 8
    index = struct.pack("<Q", len(files))
    payload = bytearray()
    for name, content in files.items():
        encoded = name.encode()
        index += bytes([len(encoded)]) + encoded + struct.pack("<QQ", len(content), offset)
        payload.extend(byte ^ mask[i % 16] ^ (i & 255) for i, byte in enumerate(content))
        offset += len(content)
    return (b"SNGPKG" + struct.pack("<I", 1) + mask + struct.pack("<Q", len(meta)) + meta
            + struct.pack("<Q", len(index)) + index + struct.pack("<Q", len(payload)) + payload)


class ImportSongChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.library = self.root / "library"
        self.song = self.root / "input"
        self.song.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def load(self, data=None, ini="[song]\nname = Original Test Song\n", **kwargs):
        (self.song / "notes.chart").write_bytes(data or simple_chart())
        (self.song / "song.ini").write_text(ini)
        return IMPORTER.import_song(self.song, self.library, **kwargs)

    def test_tempo_changes_are_integrated_and_signatures_not_tempo(self):
        manifest = self.load(simple_chart(extra="192 = B 60000\n192 = TS 6 3",
                                         expert="0 = N 0 0\n192 = N 1 0\n384 = N 2 192"),
                             ini="[song]\npro_drums = true\ndelay = 250\n")
        self.assertEqual([n["timeSeconds"] for n in manifest["notes"]], [.25, .75, 1.75])
        self.assertEqual(manifest["notes"][-1]["durationSeconds"], 1)
        self.assertEqual(manifest["timeSignatures"][-1]["denominator"], 8)
        self.assertEqual(manifest["timeSignatures"][-1]["numerator"], 6)
        self.assertEqual(manifest["durationSeconds"], 4.75)

    def test_out_of_range_declared_length_warns_without_rejecting_valid_notes(self):
        manifest = self.load(ini="[song]\nsong_length = 25500507\n")
        self.assertEqual(manifest["durationSeconds"], 2.5)
        self.assertTrue(any("Ignored song_length" in warning for warning in manifest["warnings"]))
        summary = json.loads(Path(manifest["manifestPath"]).with_name("song-info.json").read_text())
        self.assertEqual(summary["durationSeconds"], 2.5)
        for length in ("-5", "25500"):
            manifest = self.load(simple_chart(song_extra=f"Length = {length}"))
            self.assertEqual(manifest["durationSeconds"], 2.5)
            self.assertTrue(any("Ignored .chart Length" in warning for warning in manifest["warnings"]))
        supported = self.load(ini="[song]\nsong_length = 20000\n")
        self.assertEqual(supported["durationSeconds"], 20)

    def test_real_chart_timing_over_two_hours_is_still_rejected(self):
        after_limit = 384 * (IMPORTER.MAX_DURATION + 1)
        charts = [simple_chart(expert=f"0 = N 0 0\n{after_limit} = N 1 0"),
                  simple_chart(expert=f"0 = N 0 {after_limit}"),
                  simple_chart() + f'[Events]\n{{\n{after_limit} = E "[end]"\n}}\n'.encode()]
        for chart in charts:
            with self.subTest(chart=chart[-80:]):
                with self.assertRaisesRegex(IMPORTER.SongImportError, "no more than two hours"):
                    self.load(chart, ini="[song]\nsong_length = 25500507\n")

    def test_midi_all_difficulties_toms_running_status_and_double_kick(self):
        events = [text(0, "PART DRUMS", 3), text(0, "[ENABLE_CHART_DYNAMICS]")]
        for pitch in (60, 72, 84, 96):
            events += note(0, pitch)
        # Same event tick, explicit note status then legal running status.
        events += [(480, b"\x99\x62\x7f"), (480, b"\x63\x64"), (481, b"\x89\x62\x00"), (481, b"\x63\x00")]
        events += note(960, 98) + note(960, 110, 480) + note(1440, 98)
        events += note(720, 95)
        tempo = [(0, b"\xff\x51\x03\x07\xa1\x20"), (960, b"\xff\x51\x03\x0f\x42\x40"),
                 (0, b"\xff\x58\x04\x06\x03\x18\x08")]
        data = midi_file(events, extra_tracks=[tempo])
        (self.song / "notes.mid").write_bytes(data)
        (self.song / "song.ini").write_text("[song]\npro_drums = true\n")
        manifest = IMPORTER.import_song(self.song, self.library)
        self.assertEqual(manifest["difficulties"], ["easy", "medium", "hard", "expert"])
        self.assertEqual([n["lane"] for n in manifest["notes"]], ["kick", "hihat", "ride", "tom1", "hihat"])
        self.assertEqual([n["timeSeconds"] for n in manifest["notes"]], [0, .5, .5, 1, 2])
        self.assertEqual(manifest["notes"][1]["dynamic"], "accent")
        self.assertEqual(manifest["doubleKickNoteCount"], 1)
        self.assertEqual(manifest["selectedDifficulty"], "expert")
        again = IMPORTER.import_song(self.song, self.library, difficulty="easy", double_kick=True)
        self.assertEqual(again["id"], manifest["id"])
        self.assertEqual(len(again["notes"]), 1)
        self.assertEqual(len(again["charts"][-1]["notes"]), 6)

    def test_chart_cymbal_modifiers_toms_and_dynamics(self):
        manifest = self.load(simple_chart(expert="0 = N 2 0\n192 = N 2 0\n192 = N 66 0\n"
                                                    "384 = N 3 0\n384 = N 67 0\n384 = N 36 0\n"
                                                    "576 = N 4 0\n576 = N 43 0"))
        self.assertEqual(manifest["drumMode"], "pro")
        self.assertEqual([n["lane"] for n in manifest["notes"]], ["tom1", "hihat", "ride", "tom3"])
        self.assertEqual([n["velocity"] for n in manifest["notes"]], [100, 100, 127, 1])

    def test_pro_disco_flip_only_changes_red_and_yellow_while_active(self):
        chart = simple_chart(expert='0 = E "mix_3_drums0d"\n0 = N 1 0\n192 = N 2 0\n'
                                    '384 = E "mix_3_drums0dnoflip"\n384 = N 1 0\n576 = N 2 0')
        manifest = self.load(chart, ini="[song]\npro_drums = true\n")
        self.assertEqual([n["lane"] for n in manifest["notes"]], ["hihat", "snare", "snare", "tom1"])

    def test_negative_offset_is_retained_and_zero_ini_falls_back_to_chart(self):
        manifest = self.load(simple_chart(song_extra="Offset = -0.25"), ini="[song]\ndelay = 0\n")
        self.assertEqual(manifest["offsetSeconds"], -.25)
        self.assertEqual(manifest["chartStartSeconds"], -.25)
        self.assertEqual(manifest["notes"][0]["timeSeconds"], -.25)
        manifest = self.load(simple_chart(song_extra="Offset = -0.25"), ini="[song]\ndelay = 500\n")
        self.assertEqual(manifest["notes"][0]["timeSeconds"], .5)

    def test_five_lane_has_distinct_cymbals_and_toms(self):
        manifest = self.load(simple_chart(expert="\n".join(f"{192*i} = N {i} 0" for i in range(6))))
        self.assertEqual(manifest["drumMode"], "fiveLane")
        self.assertEqual([n["lane"] for n in manifest["notes"]], ["kick", "snare", "hihat", "tom2", "crash", "tom3"])

    def test_library_media_survives_source_removal_and_reserved_stems_win(self):
        (self.song / "song.opus").write_bytes(b"original fixture, not real audio")
        manifest = self.load(simple_chart(song_extra='MusicStream = "missing.ogg"'))
        audio = Path(manifest["audio"][0]["path"])
        self.assertTrue(audio.is_absolute())
        self.assertTrue(audio.is_file())
        self.assertFalse(any("missing.ogg" in warning for warning in manifest["warnings"]))
        (self.song / "song.opus").unlink()
        self.assertEqual(audio.read_bytes(), b"original fixture, not real audio")
        self.assertTrue(Path(manifest["manifestPath"]).is_file())

    def test_zip_wrapper_and_sng_match_folder_identity(self):
        data = simple_chart()
        ini = b"[song]\nname = Original Test Song\nartist = Drumx Test\n"
        files = {"notes.chart": data, "song.ini": ini, "song.opus": b"test audio"}
        for name, content in files.items():
            (self.song / name).write_bytes(content)
        folder = IMPORTER.import_song(self.song, self.library)
        zip_path = self.root / "song.zip"
        with zipfile.ZipFile(zip_path, "w") as archive:
            for name, content in files.items():
                archive.writestr("Artist - Song/" + name, content)
        zipped = IMPORTER.import_song(zip_path, self.library)
        sng_path = self.root / "song.sng"
        sng_path.write_bytes(sng_file({key: value for key, value in files.items() if key != "song.ini"},
                                      {"artist": "Drumx Test", "name": "Original Test Song"}))
        packed = IMPORTER.import_song(sng_path, self.library)
        self.assertEqual(folder["id"], zipped["id"])
        self.assertEqual(folder["id"], packed["id"])
        self.assertEqual(folder["importedAt"], packed["importedAt"])
        self.assertEqual(len(list(self.library.glob("*/song.json"))), 1)

    def test_sng_mask_is_file_relative_and_handles_multiple_chunks(self):
        sample = bytes(range(256)) * 4097 + b"last bytes"
        path = self.root / "large.sng"
        path.write_bytes(sng_file({"notes.chart": simple_chart(), "song.opus": sample}))
        manifest = IMPORTER.import_song(path, self.library)
        self.assertEqual(Path(manifest["audio"][0]["path"]).read_bytes(), sample)

    def test_archive_traversal_links_duplicate_names_and_bad_offsets_are_rejected(self):
        for bad_name in ("../outside", "/absolute", "a/../../outside", "C:/bad", "folder\\bad", "folder\x00bad"):
            with self.subTest(name=bad_name):
                path = self.root / "bad.zip"
                # zipfile sanitizes names while writing on Windows. Replace an
                # equal-length ASCII placeholder in both filename headers so the
                # hostile filename is identical on every test platform.
                raw_name = bad_name.encode("ascii")
                placeholder = b"x" * len(raw_name)
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("notes.chart", simple_chart())
                    archive.writestr(placeholder.decode("ascii"), b"bad")
                raw_archive = path.read_bytes()
                self.assertEqual(raw_archive.count(placeholder), 2)
                path.write_bytes(raw_archive.replace(placeholder, raw_name))
                with zipfile.ZipFile(path) as archive:
                    self.assertEqual(archive.infolist()[-1].orig_filename, bad_name)
                with self.assertRaises(IMPORTER.SongImportError):
                    IMPORTER.import_song(path, self.library)
        for creator_os in (0, 3):
            with self.subTest(link_creator_os=creator_os):
                path = self.root / "link.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    info = zipfile.ZipInfo("link")
                    info.create_system = creator_os
                    info.external_attr = 0o120777 << 16
                    archive.writestr(info, "../outside")
                with self.assertRaises(IMPORTER.SongImportError):
                    IMPORTER.import_song(path, self.library)
        path = self.root / "duplicate.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("notes.chart", simple_chart())
            archive.writestr("NOTES.CHART", simple_chart())
        with self.assertRaises(IMPORTER.SongImportError):
            IMPORTER.import_song(path, self.library)
        path = self.root / "offset.sng"
        raw = bytearray(sng_file({"notes.chart": simple_chart()}))
        # Header26 + metadata length8 + empty count8 + file-index length8 + count8
        offset_position = 26 + 8 + 8 + 8 + 8 + 1 + len("notes.chart") + 8
        raw[offset_position:offset_position+8] = struct.pack("<Q", 0)
        path.write_bytes(raw)
        with self.assertRaises(IMPORTER.SongImportError):
            IMPORTER.import_song(path, self.library)
        self.assertFalse((self.root / "outside").exists())
        self.assertEqual(list(self.library.glob("*/song.json")), [])

    def test_malformed_midi_chart_and_metadata_are_actionable(self):
        for data in (b"MThd", midi_file([text(0, "PART GUITAR", 3)]),
                     midi_file([text(0, "PART DRUMS", 3)], resolution=0x8001)):
            with self.subTest(data=data[:20]):
                with self.assertRaises(IMPORTER.SongImportError):
                    IMPORTER.parse_midi(data, [])
        for data in (b"[Song]\n{\nResolution = 0\n}\n", b"[ExpertDrums]\n{\n0 = N 0\n}",
                     simple_chart(extra="192 = B 0")):
            with self.subTest(data=data[:30]):
                with self.assertRaises(IMPORTER.SongImportError):
                    self.load(data)
        for ini in ("name = Missing section", "[song]\ndelay = nan", "[song]\npro_drums = true\nfive_lane_drums = true"):
            with self.subTest(ini=ini):
                with self.assertRaises(IMPORTER.SongImportError):
                    self.load(ini=ini)

    def test_scan_imports_valid_songs_and_reports_invalid_package_without_aborting(self):
        self.load()
        (self.root / "invalid.sng").write_bytes(b"not a song")
        report = IMPORTER.scan_directory(self.root, self.library)
        self.assertEqual(len(report["imported"]), 1)
        self.assertEqual(len(report["errors"]), 1)
        self.assertIn("SNGPKG", report["errors"][0]["error"])

    def test_missing_difficulty_does_not_publish_a_song(self):
        with self.assertRaisesRegex(IMPORTER.SongImportError, "no easy"):
            self.load(difficulty="easy")
        self.assertEqual(list(self.library.glob("*/song.json")), [])

    def test_numbered_stems_suppress_their_combined_fallbacks(self):
        for stem in ("song", "drums", "drums_1", "drums_2", "vocals", "vocals_1"):
            (self.song / (stem + ".opus")).write_bytes(stem.encode())
        manifest = self.load()
        self.assertEqual({a["stem"] for a in manifest["audio"]},
                         {"song", "drums_1", "drums_2", "vocals_1"})

    def test_reimport_repairs_removed_and_damaged_managed_audio(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        manifest = self.load()
        copied = Path(manifest["audio"][0]["path"])
        copied.unlink()
        repaired = IMPORTER.import_song(self.song, self.library)
        self.assertEqual(repaired["id"], manifest["id"])
        self.assertEqual(copied.read_bytes(), b"original audio")
        copied.write_bytes(b"corrupted")
        IMPORTER.import_song(self.song, self.library)
        self.assertEqual(copied.read_bytes(), b"original audio")

    def test_reference_import_keeps_absolute_media_paths_and_only_stores_json(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        (self.song / "album.jpg").write_bytes(b"original artwork")
        with patch.object(IMPORTER.shutil, "copyfile", side_effect=AssertionError("unexpected media copy")):
            manifest = self.load(reference=True)
        destination = Path(manifest["manifestPath"]).parent
        self.assertEqual(manifest["mediaMode"], "reference")
        self.assertEqual(sorted(p.name for p in destination.iterdir()), ["song-info.json", "song.json"])
        self.assertEqual(Path(manifest["chartPath"]), (self.song / "notes.chart").resolve())
        self.assertEqual(Path(manifest["audio"][0]["path"]), (self.song / "song.opus").resolve())
        self.assertEqual(Path(manifest["albumArtPath"]), (self.song / "album.jpg").resolve())
        for key in ("chartPath", "albumArtPath"):
            self.assertTrue(Path(manifest[key]).is_absolute())
            self.assertTrue(Path(manifest[key]).is_file())

    def test_reference_and_managed_modes_share_identity_without_deleting_media(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        referenced = self.load(reference=True, source_url="https://example.com/chart")
        managed = IMPORTER.import_song(self.song, self.library)
        self.assertEqual(managed["id"], referenced["id"])
        self.assertEqual(managed["mediaMode"], "managed")
        copied = Path(managed["audio"][0]["path"])
        self.assertTrue(copied.is_relative_to(self.library.resolve()))
        self.assertEqual(copied.read_bytes(), b"original audio")
        copied.write_bytes(b"damaged managed copy")
        with patch.object(IMPORTER.shutil, "copyfile", side_effect=AssertionError("unexpected media copy")):
            referenced_again = IMPORTER.import_song(self.song, self.library, reference=True)
        self.assertEqual(referenced_again["id"], managed["id"])
        self.assertEqual(referenced_again["importedAt"], referenced["importedAt"])
        self.assertEqual(referenced_again["provenance"], referenced["provenance"])
        self.assertEqual(Path(referenced_again["audio"][0]["path"]), (self.song / "song.opus").resolve())
        self.assertEqual(copied.read_bytes(), b"damaged managed copy")
        IMPORTER.import_song(self.song, self.library)
        self.assertEqual(copied.read_bytes(), b"original audio")

    def test_reference_scan_deduplicates_and_cli_indexes_folders_in_place(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        initial = self.load(reference=True)
        shutil.copytree(self.song, self.root / "duplicate")
        for arguments in (["--scan", str(self.root)], [str(self.root), "--scan"]):
            output = io.StringIO()
            with redirect_stdout(output):
                result = IMPORTER.main([*arguments, "--reference", "--library", str(self.library)])
            report = json.loads(output.getvalue())
            self.assertEqual(result, 0)
            self.assertEqual(report["imported"], [initial["manifestPath"]])
            self.assertEqual(len(report["skipped"]), 1)
            self.assertEqual(report["errors"], [])
        self.assertEqual(sorted(p.name for p in Path(initial["manifestPath"]).parent.iterdir()),
                         ["song-info.json", "song.json"])
        current = json.loads(Path(initial["manifestPath"]).read_text())
        self.assertTrue(Path(current["audio"][0]["path"]).is_file())
        self.assertEqual(current["mediaMode"], "reference")

    def test_reference_archives_fail_with_extract_first_message_and_scan_continues(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        manifest = self.load(reference=True)
        for extension in ("zip", "sng"):
            archive = self.root / ("song." + extension)
            archive.write_bytes(b"archive placeholder")
            with self.assertRaisesRegex(IMPORTER.SongImportError, "Extract archives to a folder first"):
                IMPORTER.import_song(archive, self.library, reference=True)
        report = IMPORTER.scan_directory(self.root, self.library, reference=True)
        self.assertEqual(report["imported"], [manifest["manifestPath"]])
        self.assertEqual(len(report["errors"]), 2)
        self.assertTrue(all("Extract archives" in error["error"] for error in report["errors"]))

    def test_reference_missing_source_or_audio_does_not_publish_false_success(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        manifest = self.load(reference=True)
        saved = Path(manifest["manifestPath"]).read_bytes()
        (self.song / "song.opus").unlink()
        self.assertFalse(Path(manifest["audio"][0]["path"]).exists())
        with self.assertRaisesRegex(IMPORTER.SongImportError, "Restore its audio"):
            IMPORTER.import_song(self.song, self.library, reference=True)
        with self.assertRaises(FileNotFoundError):
            IMPORTER.import_song(self.root / "missing", self.library, reference=True)
        self.assertEqual(Path(manifest["manifestPath"]).read_bytes(), saved)
        self.assertEqual(len(list(self.library.glob("*/song.json"))), 1)

    def test_directory_scan_bound_is_independent_of_per_song_file_bound(self):
        for index in range(3):
            song = self.root / f"song-{index}"
            song.mkdir()
            (song / "notes.chart").write_bytes(simple_chart().replace(b"Original Test Song", f"Song {index}".encode()))
            (song / "song.opus").write_bytes(b"original audio")
        with patch.object(IMPORTER, "MAX_FILES", 2):
            report = IMPORTER.scan_directory(self.root, self.library, reference=True)
        self.assertEqual(len(report["imported"]), 3)
        self.assertEqual(report["errors"], [])

    def test_browse_sidecar_remains_small_and_reports_all_chart_counts(self):
        expert = "\n".join(f"{tick * 24} = N {tick % 5} 0" for tick in range(4000))
        chart = simple_chart(expert=expert) + b"[EasyDrums]\n{\n0 = N 0 0\n192 = N 1 0\n}\n"
        (self.song / "song.opus").write_bytes(b"original audio")
        (self.song / "album.jpg").write_bytes(b"original artwork")
        manifest = self.load(chart, reference=True)
        info_path = Path(manifest["manifestPath"]).with_name("song-info.json")
        summary = json.loads(info_path.read_text())
        self.assertEqual([{key: value for key, value in chart.items() if key != "intensity"}
                          for chart in summary["charts"]], [
            {"difficulty": "easy", "noteCount": 2, "instrumentCount": 2},
            {"difficulty": "expert", "noteCount": 4000, "instrumentCount": 5}])
        for key, value in summary.items():
            if key not in ("charts", "metadataVersion"):
                self.assertEqual(value, manifest[key])
        self.assertEqual(summary["metadataVersion"], IMPORTER.SONG_INFO_VERSION)
        self.assertTrue(all(IMPORTER.current_intensity(chart["intensity"]) for chart in summary["charts"]))
        for key in ("notes", "tempos", "timeSignatures", "sections", "metadata"):
            self.assertNotIn(key, summary)
        self.assertNotIn('"notes"', info_path.read_text())
        self.assertLess(info_path.stat().st_size, 6000)
        self.assertGreater(Path(manifest["manifestPath"]).stat().st_size, info_path.stat().st_size * 100)

    def test_browse_sidecar_refreshes_for_managed_and_reference_reimports(self):
        (self.song / "song.opus").write_bytes(b"original audio")
        manifest = self.load(source_url="https://example.com/chart")
        info_path = Path(manifest["manifestPath"]).with_name("song-info.json")
        initial = json.loads(info_path.read_text())
        self.assertEqual(initial["mediaMode"], "managed")
        for reference in (True, True, False):
            info_path.write_text('{"stale": true}')
            with patch.object(IMPORTER.os, "replace", wraps=IMPORTER.os.replace) as replace:
                manifest = IMPORTER.import_song(self.song, self.library, reference=reference)
            summary = json.loads(info_path.read_text())
            self.assertEqual(summary, IMPORTER.song_info(manifest))
            self.assertEqual(summary["id"], initial["id"])
            self.assertEqual(summary["importedAt"], initial["importedAt"])
            self.assertEqual(summary["provenance"], initial["provenance"])
            self.assertTrue(Path(summary["audio"][0]["path"]).is_file())
            self.assertTrue(any(Path(call.args[1]) == info_path for call in replace.call_args_list))
            self.assertEqual(list(info_path.parent.glob(".song-*.json")), [])

    def test_preview_positions_use_ini_milliseconds_before_chart_seconds_and_ignore_offset(self):
        chart = simple_chart(song_extra="PreviewStart = 42.5\nPreviewEnd = 62.5\nOffset = 2")
        manifest = self.load(chart, ini="[song]\npreview_start_time = 0\npreview_end_time = 12500\ndelay = 1000\n")
        self.assertEqual(manifest["previewStartSeconds"], 0)
        self.assertEqual(manifest["previewEndSeconds"], 12.5)
        info = json.loads(Path(manifest["manifestPath"]).with_name("song-info.json").read_text())
        self.assertEqual(info["previewStartSeconds"], 0)
        self.assertEqual(info["previewEndSeconds"], 12.5)
        fallback = self.load(chart)
        self.assertEqual(fallback["previewStartSeconds"], 42.5)
        self.assertEqual(fallback["previewEndSeconds"], 62.5)

    def test_preview_invalid_values_and_missing_sentinels_do_not_break_import(self):
        for value in ("nan", "inf", "unavailable", "9999999999999999999999999999"):
            with self.subTest(value=value):
                manifest = self.load(ini=f"[song]\npreview_start_time = {value}\n")
                self.assertNotIn("previewStartSeconds", manifest)
                self.assertTrue(any("Ignored invalid preview_start_time" in warning for warning in manifest["warnings"]))
        missing = self.load(ini="[song]\npreview_start_time = -1\npreview_end_time = 0\n")
        self.assertNotIn("previewStartSeconds", missing)
        self.assertNotIn("previewEndSeconds", missing)
        reversed_times = self.load(ini="[song]\npreview_start_time = 30000\npreview_end_time = 20000\n")
        self.assertEqual(reversed_times["previewStartSeconds"], 30)
        self.assertNotIn("previewEndSeconds", reversed_times)

    def test_midi_running_status_survives_meta_and_sysex_like_yarg(self):
        events = [text(0, "PART DRUMS", 3), (0, b"\x99\x60\x64"),
                  text(0, "test"), (240, b"\x61\x64"),
                  (240, b"\xf0\x01\xf7"), (480, b"\x62\x64"),
                  (481, b"\x89\x60\x00"), (481, b"\x61\x00"), (481, b"\x62\x00")]
        parsed = IMPORTER.parse_midi(midi_file(events), [])
        self.assertEqual(len(parsed["raw"]["expert"]), 3)

    def test_midi_note_off_release_255_does_not_change_note_time_or_velocity(self):
        events = [text(0, "PART DRUMS", 3), (0, b"\x99\x60\x64"), (120, b"\x61\x50"),
                  (240, b"\x89\x60\xff"), (360, b"\x61\xff"),
                  (480, b"\x99\x62\x64"), (481, b"\x89\x62\x00")]
        animation = [text(0, "PART KEYS_ANIM_RH", 3), (0, b"\x90\x36\x40"),
                     (60, b"\x80\x36\xff")]
        warnings = []
        parsed = IMPORTER.parse_midi(midi_file(events, extra_tracks=[animation]), warnings)
        self.assertEqual(parsed["raw"]["expert"], [(0, 0, 240, 100), (120, 1, 240, 80), (480, 2, 1, 100)])
        release_warnings = [warning for warning in warnings if "release velocities" in warning]
        self.assertEqual(len(release_warnings), 2)
        self.assertIn("PART DRUMS has 2", release_warnings[1])

    def test_midi_release_compatibility_keeps_other_channel_data_and_bounds_strict(self):
        for payload in (b"\x90\x60\xff", b"\x80\xff\x00", b"\x80\x60\x80",
                        b"\xb0\x01\xff", b"\xc0\xff", b"\xe0\x00\xff"):
            with self.subTest(payload=payload):
                with self.assertRaisesRegex(IMPORTER.SongImportError, "Invalid MIDI channel data byte"):
                    IMPORTER.parse_midi(midi_file([text(0, "PART DRUMS", 3), (0, payload)]), [])
        for body, message in ((b"\x00\x80\x60", "Truncated MIDI channel event"),
                              (b"\x00\xff\x01\x05a", "MIDI meta event exceeds track bounds"),
                              (b"\x00\xf0\x03\xf7", "MIDI SysEx event exceeds track bounds")):
            data = b"MThd" + struct.pack(">IHHH", 6, 1, 1, 480) + b"MTrk" + struct.pack(">I", len(body)) + body
            with self.subTest(body=body):
                with self.assertRaisesRegex(IMPORTER.SongImportError, message):
                    IMPORTER.parse_midi(data, [])

    def test_different_charters_receive_distinct_library_ids(self):
        first = self.load(ini="[song]\ncharter = First\n")
        second = self.load(ini="[song]\ncharter = Second\n")
        self.assertNotEqual(first["id"], second["id"])

    def test_authored_expert_intensity_prefers_pro_drums_and_preserves_all_tiers(self):
        chart = simple_chart() + b"[EasyDrums]\n{\n0 = N 0 0\n192 = N 1 0\n}\n"
        manifest = self.load(chart, ini="[song]\ndiff_drums_real = 4\ndiff_drums = 1\n")
        easy, expert = manifest["charts"]
        self.assertEqual(expert["intensity"]["level"], 4)
        self.assertEqual(expert["intensity"]["authoredField"], "diff_drums_real")
        self.assertEqual(expert["intensity"]["source"], "authored")
        self.assertEqual(easy["intensity"]["source"], "estimated")
        for tier in range(7):
            rating = IMPORTER.chart_intensity(expert, {"diff_drums_real": "-1", "diff_drums": str(tier)})
            self.assertEqual((rating["level"], rating["source"]), (tier, "authored"))

    def test_invalid_authored_intensity_falls_back_to_versioned_estimate(self):
        chart = {"difficulty": "expert", "notes": [{"timeSeconds": 0, "lane": "hihat"}]}
        for invalid in ("-1", "7", "3.1", "nan", "inf", "not a rating"):
            rating = IMPORTER.chart_intensity(chart, {"diff_drums_real": invalid, "diff_drums": invalid})
            self.assertEqual(rating["source"], "estimated")
            self.assertEqual(rating["version"], 1)
            self.assertTrue(IMPORTER.current_intensity(rating))
            self.assertIn(rating["level"], range(7))

    def test_estimated_intensity_tracks_density_bursts_and_coordination(self):
        sparse = {"difficulty": "easy", "notes": [{"timeSeconds": i * 2, "lane": "hihat"} for i in range(20)]}
        dense = {"difficulty": "expert", "notes": [{"timeSeconds": i / 8, "lane": lane}
                 for i in range(160) for lane in ("hihat", "kick")]}
        a, b = IMPORTER.chart_intensity(sparse), IMPORTER.chart_intensity(dense)
        self.assertEqual(a["level"], 0)
        self.assertEqual(b["level"], 6)
        self.assertGreater(b["metrics"]["averageNPS"], a["metrics"]["averageNPS"])
        self.assertGreater(b["metrics"]["peakTwoSecondNPS"], a["metrics"]["peakTwoSecondNPS"])
        self.assertEqual(b["metrics"]["handFootRatio"], 1)
        alternating = {"difficulty": "hard", "notes": [{"timeSeconds": i / 2, "lane": "kick" if i % 2 else "hihat"}
                       for i in range(40)]}
        together = {"difficulty": "hard", "notes": [{"timeSeconds": i, "lane": lane}
                    for i in range(20) for lane in ("hihat", "kick")]}
        self.assertGreater(IMPORTER.chart_intensity(together)["metrics"]["demandScore"],
                           IMPORTER.chart_intensity(alternating)["metrics"]["demandScore"])

    def test_intensity_is_independent_of_chart_offset_and_input_order(self):
        notes = [{"timeSeconds": i / 4 - 0.25, "lane": "snare" if i % 4 == 2 else "hihat"}
                 for i in range(100)]
        rating = IMPORTER.chart_intensity({"difficulty": "hard", "notes": notes})
        shifted = [dict(note, timeSeconds=note["timeSeconds"] + 19.5) for note in reversed(notes)]
        self.assertEqual(rating, IMPORTER.chart_intensity({"difficulty": "hard", "notes": shifted}))

    def test_rebuild_index_repairs_only_sidecars_without_hashing_or_reading_media(self):
        manifest = self.load(ini="[song]\ndiff_drums_real = 5\n")
        manifest_path = Path(manifest["manifestPath"])
        full_before = manifest_path.read_bytes()
        info_path = manifest_path.with_name("song-info.json")
        old = json.loads(info_path.read_text())
        old["metadataVersion"] = 0
        for chart in old["charts"]:
            chart["intensity"]["version"] = 0
        info_path.write_text(json.dumps(old))
        shutil.rmtree(manifest_path.parent / "source")
        with patch.object(IMPORTER.hashlib, "sha256", side_effect=AssertionError("Index repair must not hash assets")):
            report = IMPORTER.rebuild_index(self.library)
        self.assertEqual(report, {"updated": 1, "unchanged": 0, "errors": []})
        self.assertEqual(manifest_path.read_bytes(), full_before)
        repaired = json.loads(info_path.read_text())
        self.assertEqual(repaired["charts"][0]["intensity"]["level"], 5)
        self.assertEqual(repaired["metadataVersion"], IMPORTER.SONG_INFO_VERSION)
        self.assertEqual(IMPORTER.rebuild_index(self.library), {"updated": 0, "unchanged": 1, "errors": []})

    def test_rebuild_index_isolates_bad_manifests_and_has_a_standalone_cli(self):
        manifest = self.load()
        Path(manifest["manifestPath"]).with_name("song-info.json").unlink()
        bad = self.library / "bad-chart"
        bad.mkdir(); (bad / "song.json").write_text("{broken")
        out = io.StringIO()
        with redirect_stdout(out):
            status = IMPORTER.main(["--rebuild-index", "--library", str(self.library)])
        report = json.loads(out.getvalue())
        self.assertEqual(status, 0)
        self.assertEqual(report["updated"], 1)
        self.assertEqual(len(report["errors"]), 1)
        self.assertTrue(Path(manifest["manifestPath"]).with_name("song-info.json").exists())


if __name__ == "__main__":
    unittest.main()
