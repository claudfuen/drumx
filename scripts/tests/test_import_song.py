"""Behavioral checks with tiny original charts; no commercial media is committed."""
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
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
        for bad_name in ("../outside", "/absolute", "a/../../outside", "C:/bad", "folder\\bad"):
            with self.subTest(name=bad_name):
                path = self.root / "bad.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("notes.chart", simple_chart())
                    archive.writestr(bad_name, b"bad")
                with self.assertRaises(IMPORTER.SongImportError):
                    IMPORTER.import_song(path, self.library)
        path = self.root / "link.zip"
        with zipfile.ZipFile(path, "w") as archive:
            info = zipfile.ZipInfo("link")
            info.create_system = 3
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

    def test_midi_running_status_survives_meta_and_sysex_like_yarg(self):
        events = [text(0, "PART DRUMS", 3), (0, b"\x99\x60\x64"),
                  text(0, "test"), (240, b"\x61\x64"),
                  (240, b"\xf0\x01\xf7"), (480, b"\x62\x64"),
                  (481, b"\x89\x60\x00"), (481, b"\x61\x00"), (481, b"\x62\x00")]
        parsed = IMPORTER.parse_midi(midi_file(events), [])
        self.assertEqual(len(parsed["raw"]["expert"]), 3)

    def test_different_charters_receive_distinct_library_ids(self):
        first = self.load(ini="[song]\ncharter = First\n")
        second = self.load(ini="[song]\ncharter = Second\n")
        self.assertNotEqual(first["id"], second["id"])


if __name__ == "__main__":
    unittest.main()
