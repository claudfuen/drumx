#!/usr/bin/env python3
"""Import Clone Hero / YARG drum songs into Drumx's private, versioned song library.

Uses only Python's standard library. See docs/song-format.md for the JSON contract,
format references, timing semantics, and deliberate gameplay limitations.
"""
from __future__ import annotations

import argparse
import bisect
from collections import defaultdict, deque
import configparser
import filecmp
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import sys
import tempfile
import zipfile

SCHEMA_VERSION = 1
SONG_INFO_VERSION = 1
INTENSITY_VERSION = 1
DIFFICULTIES = ("easy", "medium", "hard", "expert")
LANES = ("hihat", "snare", "kick", "tom1", "tom2", "tom3", "crash", "ride")
MAX_FILES = 10000
MAX_SCAN_ENTRIES = 100000
MAX_TOTAL_BYTES = 2 * 1024**3
MAX_FILE_BYTES = 1024**3
MAX_CHART_BYTES = 64 * 1024**2
MAX_METADATA_BYTES = 8 * 1024**2
MAX_EVENTS = 1000000
MAX_TICK = 2**40
MAX_DURATION = 2 * 60 * 60
MAX_PLAYABLE_NOTES = 200000
AUDIO_EXTENSIONS = (".wav", ".flac", ".aiff", ".aif", ".mp3", ".ogg", ".opus", ".m4a")
STEMS = ("song", "guitar", "bass", "rhythm", "keys", "vocals", "vocals_1", "vocals_2",
         "drums", "drums_1", "drums_2", "drums_3", "drums_4", "crowd")
STREAM_KEYS = {"musicstream": "song", "guitarstream": "guitar", "bassstream": "bass",
               "rhythmstream": "rhythm", "keysstream": "keys", "vocalstream": "vocals",
               "drumstream": "drums", "drum2stream": "drums_2", "drum3stream": "drums_3",
               "drum4stream": "drums_4", "crowdstream": "crowd"}


class SongImportError(ValueError):
    """An unsupported or malformed package, reported without a Python traceback."""


def fail(message):
    raise SongImportError(message)


def read_exact(stream, length):
    if length < 0:
        fail("Negative binary field length")
    data = stream.read(length)
    if len(data) != length:
        fail("Truncated binary file")
    return data


def number(value, default=0.0, label="number"):
    if value is None or value == "":
        return default
    try:
        result = float(value)
    except (ValueError, TypeError):
        fail(f"Invalid {label}: {value!r}")
    if not math.isfinite(result):
        fail(f"Non-finite {label}")
    return result


def decode_text(data):
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


def clean_text(value):
    return re.sub(r"<[^>]*>", "", str(value)).replace("\x00", "").strip().strip('"')


def safe_relative(name):
    # Backslash is a directory separator on some consumers, never a safe literal.
    if not name or "\\" in name or "\x00" in name or any(ord(c) < 32 for c in name):
        fail(f"Unsafe package path: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(p in ("..", "") for p in path.parts) or ":" in name:
        fail(f"Unsafe package path: {name!r}")
    if not path.parts or path.parts[0] == ".":
        fail(f"Unsafe package path: {name!r}")
    return Path(*path.parts)


def check_entries(entries):
    """Validate a full index before any extraction, including macOS case collisions."""
    if len(entries) > MAX_FILES:
        fail(f"Package exceeds {MAX_FILES} files")
    seen = set()
    total = 0
    files = []
    for name, size in entries:
        relative = safe_relative(name)
        key = relative.as_posix().casefold()
        if key in seen:
            fail(f"Duplicate package path: {name}")
        seen.add(key)
        if size < 0 or size > MAX_FILE_BYTES:
            fail(f"Package file exceeds {MAX_FILE_BYTES} bytes: {name}")
        total += size
        if total > MAX_TOTAL_BYTES:
            fail(f"Package exceeds {MAX_TOTAL_BYTES} expanded bytes")
        files.append(relative)
    for key in seen:
        parts = key.split("/")
        if any("/".join(parts[:i]) in seen for i in range(1, len(parts))):
            fail("Package file collides with a directory")
    return files


def extract_zip(source, destination):
    with zipfile.ZipFile(source) as archive:
        entries = []
        for info in archive.infolist():
            # ZipInfo sanitizes names before exposing .filename: on Windows it
            # replaces backslashes, and on every OS it truncates at NUL. Validate
            # the original archive spelling before that information is lost.
            safe_relative(info.orig_filename.rstrip("/"))
            safe_relative(info.filename.rstrip("/"))
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and not
                                      (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
                fail(f"Links and special files are not supported: {info.filename}")
            if info.flag_bits & 1:
                fail("Encrypted ZIP packages are not supported")
            if not info.is_dir():
                entries.append(info)
        relatives = check_entries([(info.filename, info.file_size) for info in entries])
        for info, relative in zip(entries, relatives):
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            remaining = info.file_size
            with archive.open(info) as src, target.open("xb") as out:
                while remaining:
                    chunk = src.read(min(1024 * 1024, remaining))
                    if not chunk:
                        fail(f"Truncated ZIP entry: {info.filename}")
                    out.write(chunk)
                    remaining -= len(chunk)
                if src.read(1):
                    fail(f"ZIP entry exceeds its advertised length: {info.filename}")
    return {}


def extract_sng(source, destination):
    """Read the published SNGPKG version 1 container, with bounded index sections."""
    with source.open("rb") as src:
        total_size = source.stat().st_size
        if total_size > MAX_TOTAL_BYTES + 2 * MAX_METADATA_BYTES:
            fail("SNG package exceeds size limit")
        if read_exact(src, 6) != b"SNGPKG":
            fail("Not an SNGPKG song container")
        if struct.unpack("<I", read_exact(src, 4))[0] != 1:
            fail("Only SNG container version 1 is supported")
        mask = read_exact(src, 16)

        def section():
            length = struct.unpack("<Q", read_exact(src, 8))[0]
            if length < 8 or length > MAX_METADATA_BYTES:
                fail("Invalid or oversized SNG index section")
            end = src.tell() + length
            if end > total_size:
                fail("SNG section exceeds file bounds")
            count = struct.unpack("<Q", read_exact(src, 8))[0]
            if count > MAX_FILES:
                fail("SNG index contains too many entries")
            return end, count

        def text_field(end):
            length = struct.unpack("<i", read_exact(src, 4))[0]
            if length < 0 or src.tell() + length > end:
                fail("SNG metadata field exceeds its section")
            return read_exact(src, length).decode("utf-8")

        metadata = {}
        end, count = section()
        for _ in range(count):
            key, value = text_field(end), text_field(end)
            if not key or any(c in key for c in "\x00\r\n=") or any(c in value for c in "\x00\r\n"):
                fail("Invalid SNG metadata characters")
            metadata[key.lower()] = value
        if src.tell() != end:
            fail("SNG metadata length does not match its contents")
        end, count = section()
        entries = []
        for _ in range(count):
            name_length = read_exact(src, 1)[0]
            if src.tell() + name_length + 16 > end:
                fail("SNG file entry exceeds its index section")
            name = read_exact(src, name_length).decode("utf-8")
            length, offset = struct.unpack("<QQ", read_exact(src, 16))
            entries.append((name, length, offset))
        if src.tell() != end:
            fail("SNG file index length does not match its contents")
        data_length = struct.unpack("<Q", read_exact(src, 8))[0]
        data_start = src.tell()
        data_end = data_start + data_length
        if data_end != total_size:
            fail("SNG payload length does not match the package size")
        relatives = check_entries([(name, length) for name, length, _ in entries])
        previous_end = data_start
        for _, length, offset in sorted(entries, key=lambda entry: entry[2]):
            if offset < previous_end or offset + length > data_end:
                fail("SNG payload contains overlapping or out-of-bounds files")
            previous_end = offset + length
        # Each residue's XOR key is constant; bytes.translate keeps decoding in C.
        tables = [bytes(b ^ mask[i % 16] ^ i for b in range(256)) for i in range(256)]
        for (_, length, offset), relative in zip(entries, relatives):
            src.seek(offset)
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as out:
                position = 0
                while position < length:
                    chunk = bytearray(read_exact(src, min(1024 * 1024, length - position)))
                    for residue in range(min(256, len(chunk))):
                        chunk[residue::256] = chunk[residue::256].translate(tables[(position + residue) % 256])
                    out.write(chunk)
                    position += len(chunk)
        return metadata


def folder_files(root):
    entries = []
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d != "__MACOSX" and not d.startswith("."))
        for name in dirs + names:
            path = Path(directory) / name
            if path.is_symlink():
                fail(f"Song folders must not contain symbolic links: {path.name}")
        for name in sorted(names):
            if name == ".DS_Store":
                continue
            path = Path(directory) / name
            if not path.is_file():
                fail(f"Song folder contains a non-regular file: {name}")
            entries.append((path.relative_to(root).as_posix(), path.stat().st_size))
            if len(entries) > MAX_FILES:
                fail("Song folder contains too many files")
    check_entries(entries)
    return [root / name for name, _ in entries]


def find_song_folders(root):
    found = []
    visited = 0
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "__MACOSX"
                         and not (Path(directory) / d).is_symlink())
        visited += len(dirs) + len(files)
        if visited > MAX_SCAN_ENTRIES:
            fail(f"Directory scan exceeds {MAX_SCAN_ENTRIES} entries; choose a narrower song directory")
        if any(name.casefold() in ("notes.mid", "notes.midi", "notes.chart") for name in files):
            found.append(Path(directory))
            dirs[:] = []
    return found


def read_ini(path):
    if path.stat().st_size > MAX_METADATA_BYTES:
        fail("song.ini exceeds metadata size limit")
    parser = configparser.ConfigParser(interpolation=None, strict=False,
                                       inline_comment_prefixes=(";",), empty_lines_in_values=False)
    try:
        parser.read_string(decode_text(path.read_bytes()))
    except configparser.Error as error:
        fail(f"Invalid song.ini: {error}")
    section = next((s for s in parser.sections() if s.casefold() == "song"), None)
    if section is None:
        fail("song.ini is missing its [song] section")
    return {key.casefold(): value.strip().strip('"') for key, value in parser[section].items()}


def read_vlq(data, position):
    value = 0
    for _ in range(4):
        if position >= len(data):
            fail("Truncated MIDI variable-length quantity")
        byte = data[position]
        position += 1
        value = (value << 7) | (byte & 127)
        if byte < 128:
            return value, position
    fail("MIDI variable-length quantity exceeds four bytes")


def parse_midi(data, warnings):
    import io
    src = io.BytesIO(data)
    if read_exact(src, 4) != b"MThd":
        fail("notes.mid is not a Standard MIDI File")
    header_length = struct.unpack(">I", read_exact(src, 4))[0]
    if header_length < 6 or header_length > 1024:
        fail("Invalid MIDI header length")
    fmt, track_count, resolution = struct.unpack(">HHH", read_exact(src, 6))
    read_exact(src, header_length - 6)
    if fmt not in (0, 1) or track_count == 0 or track_count > 1024:
        fail("Only synchronous MIDI format 0 and 1 songs are supported")
    if not resolution or resolution & 0x8000:
        fail("MIDI needs ticks-per-quarter-note timing; SMPTE timing is unsupported")
    tempos, signatures, tracks, sections = [], [], [], []
    event_count = 0
    end_tick = 0
    for _ in range(track_count):
        if read_exact(src, 4) != b"MTrk":
            fail("Missing MIDI track chunk")
        length = struct.unpack(">I", read_exact(src, 4))[0]
        if length > MAX_CHART_BYTES:
            fail("MIDI track exceeds chart size limit")
        track = read_exact(src, length)
        position = tick = 0
        running = None
        name, notes, text_events = "", [], []
        normalized_releases = 0
        active = defaultdict(deque)
        while position < len(track):
            event_count += 1
            if event_count > MAX_EVENTS:
                fail("MIDI contains too many events")
            delta, position = read_vlq(track, position)
            tick += delta
            if tick > MAX_TICK or position >= len(track):
                fail("Invalid MIDI event position")
            status = track[position]
            if status < 128:
                if running is None:
                    fail("MIDI running status without a channel status")
                status = running
            else:
                position += 1
                if status < 0xF0:
                    running = status
            if status == 0xFF:
                if position >= len(track):
                    fail("Truncated MIDI meta event")
                kind = track[position]
                position += 1
                size, position = read_vlq(track, position)
                if position + size > len(track):
                    fail("MIDI meta event exceeds track bounds")
                payload = track[position:position + size]
                position += size
                if kind == 0x03:
                    name = decode_text(payload).strip().upper()
                elif kind == 0x51:
                    if size != 3 or int.from_bytes(payload, "big") <= 0:
                        fail("Invalid MIDI tempo event")
                    tempos.append((tick, 60000000.0 / int.from_bytes(payload, "big")))
                elif kind == 0x58:
                    if size < 2 or not payload[0] or payload[1] > 7:
                        fail("Invalid MIDI time signature")
                    signatures.append((tick, payload[0], 2**payload[1]))
                elif kind in (0x01, 0x05, 0x06):
                    event = decode_text(payload).strip().strip("[]")
                    text_events.append((tick, event))
                    if event.lower() == "end":
                        end_tick = max(end_tick, tick)
                    if event.lower().startswith(("section ", "section_", "prc_")):
                        sections.append((tick, re.sub(r"^(section[ _]|prc_)", "", event, flags=re.I)))
                elif kind == 0x2F:
                    break
                continue
            if status in (0xF0, 0xF7):
                size, position = read_vlq(track, position)
                position += size
                if position > len(track):
                    fail("MIDI SysEx event exceeds track bounds")
                continue
            if status >= 0xF0:
                fail(f"Unsupported MIDI system event 0x{status:02x}")
            kind, channel = status & 0xF0, status & 15
            size = 1 if kind in (0xC0, 0xD0) else 2
            if position + size > len(track):
                fail("Truncated MIDI channel event")
            payload = track[position:position + size]
            position += size
            # Some Rock Band keyboard-animation tracks use FF for a discarded
            # release velocity. YARG consumes this fixed-size event as written.
            # Tolerate that exact value, keeping pitches and all other data strict.
            if kind == 0x80 and payload[0] < 128 and payload[1] == 0xFF:
                payload = bytes((payload[0], 0))
                normalized_releases += 1
            if any(b >= 128 for b in payload):
                fail("Invalid MIDI channel data byte")
            if kind == 0x90 and payload[1]:
                active[(channel, payload[0])].append((tick, payload[1]))
            elif kind == 0x80 or (kind == 0x90 and not payload[1]):
                queue = active[(channel, payload[0])]
                if queue:
                    start, velocity = queue.popleft()
                    notes.append((start, payload[0], tick - start, velocity))
        dangling = 0
        for (_, pitch), queue in active.items():
            for start, velocity in queue:
                notes.append((start, pitch, 0, velocity))
                dangling += 1
        if dangling:
            warnings.append(f"MIDI track {name or '(unnamed)'} has {dangling} unterminated notes; treated as hits")
        if normalized_releases:
            warnings.append(f"MIDI track {name or '(unnamed)'} has {normalized_releases} Note Off release velocities "
                            "of 255; normalized to zero because release velocity is unused")
        tracks.append((name, notes, text_events))
    drum_track = next((t for t in tracks if t[0] == "PART DRUMS"), None)
    if drum_track is None:
        drum_track = next((t for t in tracks if t[0] == "PART DRUM"), None)
    if drum_track is None:
        fail("No PART DRUMS track in notes.mid; guitar-only charts cannot be played as drums")
    if sum(t[0] == drum_track[0] for t in tracks) > 1:
        warnings.append("Multiple PART DRUMS tracks found; using the first")
    raw = {difficulty: [] for difficulty in DIFFICULTIES}
    markers = defaultdict(list)
    for tick, pitch, length, velocity in drum_track[1]:
        if pitch in (110, 111, 112):
            markers[pitch - 108].append((tick, tick + length))
        for difficulty, base in zip(DIFFICULTIES, (60, 72, 84, 96)):
            if pitch == base - 1:
                raw[difficulty].append((tick, 32, length, velocity))
            if base <= pitch <= base + 5:
                raw[difficulty].append((tick, pitch - base, length, velocity))
    return {"resolution": resolution, "tempos": tempos, "signatures": signatures, "raw": raw,
            "markers": markers, "events": drum_track[2], "sections": sections, "endTick": end_tick,
            "song": {}, "format": "midi"}


def parse_chart(data, warnings):
    sections = defaultdict(list)
    section = None
    in_section = False
    event_count = 0
    for line_number, line in enumerate(decode_text(data).splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        match = re.fullmatch(r"\[([^\]]+)\]\s*(\{)?", line)
        if match:
            if in_section:
                fail(f"Unclosed .chart section at line {line_number}")
            section, brace = match.groups()
            section = section.casefold()
            in_section = bool(brace)
            continue
        if line == "{" and section and not in_section:
            in_section = True
            continue
        if line == "}" and in_section:
            in_section = False
            section = None
            continue
        if not section or not in_section or "=" not in line:
            fail(f"Malformed .chart syntax at line {line_number}")
        key, value = line.split("=", 1)
        sections[section].append((key.strip(), value.strip()))
        event_count += 1
        if event_count > MAX_EVENTS:
            fail(".chart contains too many events")
    if in_section or section:
        fail("Unclosed .chart section")
    song = {key.casefold(): value.strip('"') for key, value in sections.get("song", [])}
    try:
        resolution = int(song.get("resolution", "192"))
    except ValueError:
        fail("Invalid .chart resolution")
    if not 1 <= resolution <= 32767:
        fail(".chart resolution must be between 1 and 32767")
    if "resolution" not in song:
        warnings.append("Missing .chart resolution; assumed 192 ticks per quarter note")
    tempos, signatures, events, song_sections = [], [], [], []
    raw = {difficulty: [] for difficulty in DIFFICULTIES}
    markers = defaultdict(list)
    end_tick = 0
    for section_name, entries in sections.items():
        if section_name == "song":
            continue
        difficulty = next((d for d in DIFFICULTIES if section_name == d + "drums"), None)
        if not difficulty and section_name not in ("synctrack", "events"):
            continue
        for position, value in entries:
            try:
                tick = int(position)
                if not 0 <= tick <= MAX_TICK:
                    fail(".chart event tick outside supported range")
                fields = value.split()
                kind = fields[0]
                if section_name == "synctrack" and kind == "B":
                    tempos.append((tick, int(fields[1]) / 1000.0))
                elif section_name == "synctrack" and kind == "TS":
                    exponent = int(fields[2]) if len(fields) > 2 else 2
                    numerator = int(fields[1])
                    if not 0 <= exponent <= 7 or not 1 <= numerator <= 255:
                        fail("Invalid .chart time signature")
                    signatures.append((tick, numerator, 2**exponent))
                elif difficulty and kind == "N":
                    lane, length = int(fields[1]), int(fields[2])
                    if length < 0 or tick + length > MAX_TICK:
                        fail("Invalid .chart note length")
                    raw[difficulty].append((tick, lane, length, 100))
                    if lane in (66, 67, 68):
                        markers[(difficulty, lane - 64)].append(tick)
                elif kind == "E":
                    event = value[1:].strip().strip('"').strip("[]")
                    events.append((tick, event))
                    if section_name == "events" and event.lower() == "end":
                        end_tick = max(end_tick, tick)
                    if section_name == "events" and event.lower().startswith(("section ", "section_", "prc_")):
                        song_sections.append((tick, re.sub(r"^(section[ _]|prc_)", "", event, flags=re.I)))
            except (ValueError, IndexError):
                fail(f"Malformed .chart event in [{section_name}]: {position} = {value}")
    return {"resolution": resolution, "tempos": tempos, "signatures": signatures, "raw": raw,
            "markers": markers, "events": events, "sections": song_sections, "endTick": end_tick,
            "song": song, "format": "chart"}


class TempoMap:
    def __init__(self, resolution, tempos, offset=0.0):
        self.resolution = resolution
        values = {0: 120.0}
        for tick, bpm in tempos:
            if not math.isfinite(bpm) or not 0 < bpm <= 10000:
                fail("Tempo must be finite and between 0 and 10000 BPM")
            values[tick] = bpm
        self.ticks = sorted(values)
        self.bpms = [values[tick] for tick in self.ticks]
        self.seconds = [offset]
        for i in range(1, len(self.ticks)):
            self.seconds.append(self.seconds[-1] + (self.ticks[i] - self.ticks[i - 1])
                                * 60.0 / (resolution * self.bpms[i - 1]))

    def seconds_at(self, tick):
        i = max(0, bisect.bisect_right(self.ticks, tick) - 1)
        return self.seconds[i] + (tick - self.ticks[i]) * 60.0 / (self.resolution * self.bpms[i])

    def position(self, tick):
        return {"tick": tick, "beat": tick / self.resolution,
                "timeSeconds": round(self.seconds_at(tick), 9)}


def is_true(value):
    return str(value).casefold().strip() in ("true", "1", "yes")


def drum_mode(parsed, metadata, warnings):
    pro, five = is_true(metadata.get("pro_drums")), is_true(metadata.get("five_lane_drums"))
    if pro and five:
        fail("song.ini cannot enable both pro_drums and five_lane_drums")
    if pro:
        return "pro"
    if five:
        return "fiveLane"
    if parsed["markers"]:
        return "pro"
    if any(note[1] == 5 for notes in parsed["raw"].values() for note in notes):
        return "fiveLane"
    warnings.append("Standard four-lane drums do not encode cymbal/tom identity; yellow maps to hi-hat, blue to mid tom, green to crash")
    return "fourLane"


def build_charts(parsed, metadata, warnings, double_kick):
    mode = drum_mode(parsed, metadata, warnings)
    ini_delay = number(metadata.get("delay"), label="song.ini delay") / 1000.0
    offset = ini_delay if ini_delay else number(parsed["song"].get("offset"), label=".chart Offset")
    if abs(offset) > MAX_DURATION:
        fail("Chart offset exceeds two hours")
    clock = TempoMap(parsed["resolution"], parsed["tempos"], offset)
    mix = defaultdict(list)
    dynamics = False
    for tick, event in parsed["events"]:
        if event.upper() == "ENABLE_CHART_DYNAMICS":
            dynamics = True
        match = re.fullmatch(r"mix[ _]([0-3])[ _]drums\d*(\w*)", event, flags=re.I)
        if match:
            difficulty_index, flag = match.groups()
            mix[DIFFICULTIES[int(difficulty_index)]].append((tick, flag.casefold() == "d"))
    for values in mix.values():
        values.sort()
    # Merge overlapping marker intervals for efficient lookup and consistent boundaries.
    toms = {}
    if parsed["format"] == "midi":
        for lane, values in parsed["markers"].items():
            merged = []
            for start, end in sorted(values):
                end = max(end, start + 1)
                if merged and start <= merged[-1][1]:
                    merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
                else:
                    merged.append((start, end))
            toms[lane] = ([start for start, _ in merged], [end for _, end in merged])
    charts = []
    extra_kicks = 0
    for difficulty in DIFFICULTIES:
        notes = []
        modifiers = defaultdict(set)
        for tick, lane, _, _ in parsed["raw"][difficulty]:
            if lane > 5 and lane != 32:
                modifiers[tick].add(lane)
        mix_values = mix[difficulty]
        mix_ticks = [value[0] for value in mix_values]
        seen = set()
        for tick, source_lane, length, velocity in sorted(parsed["raw"][difficulty]):
            if source_lane == 32:
                extra_kicks += 1
                if not double_kick:
                    continue
            elif not 0 <= source_lane <= 5:
                continue
            lane_number = 0 if source_lane == 32 else source_lane
            if mode != "fiveLane" and lane_number == 5:
                warnings.append("Ignored a fifth-lane note in an explicitly four-lane chart")
                continue
            cymbal = False
            if lane_number in (2, 3, 4):
                if parsed["format"] == "midi":
                    starts, ends = toms.get(lane_number, ([], []))
                    marker_index = bisect.bisect_right(starts, tick) - 1
                    cymbal = not (marker_index >= 0 and tick < ends[marker_index])
                else:
                    cymbal = lane_number + 64 in modifiers[tick]
            if mode == "fiveLane":
                lane = ("kick", "snare", "hihat", "tom2", "crash", "tom3")[lane_number]
            elif mode == "fourLane":
                lane = ("kick", "snare", "hihat", "tom2", "crash")[lane_number]
            elif lane_number <= 1:
                lane = ("kick", "snare")[lane_number]
            else:
                lane = ({2: "hihat", 3: "ride", 4: "crash"} if cymbal
                        else {2: "tom1", 3: "tom2", 4: "tom3"})[lane_number]
            mix_index = bisect.bisect_right(mix_ticks, tick) - 1
            if mode == "pro" and mix_index >= 0 and mix_values[mix_index][1]:
                if lane_number == 1:
                    lane = "hihat"
                elif lane_number == 2:
                    lane = "snare"
            if parsed["format"] == "chart":
                if lane_number + 33 in modifiers[tick]:
                    velocity = 127
                elif lane_number + 39 in modifiers[tick]:
                    velocity = 1
            key = (tick, lane)
            if key in seen:
                continue
            seen.add(key)
            note = clock.position(tick)
            note.update({"durationSeconds": round(clock.seconds_at(tick + length) - clock.seconds_at(tick), 9),
                         "lane": lane, "sourceLane": source_lane, "velocity": velocity,
                         "doubleKick": source_lane == 32})
            if (dynamics or mode == "fiveLane" or parsed["format"] == "chart") and velocity in (1, 127):
                note["dynamic"] = "accent" if velocity == 127 else "ghost"
            notes.append(note)
        if len(notes) > MAX_PLAYABLE_NOTES:
            fail(f"The {difficulty} chart exceeds Drumx's {MAX_PLAYABLE_NOTES} playable-note limit")
        if notes:
            charts.append({"difficulty": difficulty, "notes": notes})
    if not charts:
        fail("No playable drum notes in this song")
    if extra_kicks and not double_kick:
        warnings.append(f"{extra_kicks} optional double-kick notes excluded; import with --double-kick to include them")
    # Dedupe repeats caused by malformed notes while retaining meaningful diagnostics.
    warnings[:] = list(dict.fromkeys(warnings))
    signatures = {0: (4, 4)}
    signatures.update({tick: (n, d) for tick, n, d in parsed["signatures"]})
    all_notes = [note for chart in charts for note in chart["notes"]]
    declared_lengths = []
    for value, scale, label in ((metadata.get("song_length"), 1000.0, "song_length"),
                                (parsed["song"].get("length"), 1.0, ".chart Length")):
        declared = number(value, label=label) / scale
        if not 0 <= declared <= MAX_DURATION:
            warnings.append(f"Ignored {label} outside the supported zero-to-two-hour range; using chart duration")
        else:
            declared_lengths.append(declared)
    duration = max(max(n["timeSeconds"] + n["durationSeconds"] for n in all_notes) + 2.0,
                   clock.seconds_at(parsed["endTick"]), *declared_lengths)
    start = min(0.0, min(n["timeSeconds"] for n in all_notes))
    if not 0 < duration <= MAX_DURATION or duration - start > MAX_DURATION:
        fail("Song duration must be positive and no more than two hours")
    for chart in charts:
        chart["intensity"] = chart_intensity(chart, metadata)
    return {"drumMode": mode, "offsetSeconds": offset, "chartStartSeconds": start,
            "durationSeconds": round(duration, 9), "charts": charts,
            "doubleKick": double_kick, "doubleKickNoteCount": extra_kicks,
            "tempos": [dict(clock.position(t), bpm=bpm) for t, bpm in zip(clock.ticks, clock.bpms)],
            "timeSignatures": [dict(clock.position(t), numerator=n, denominator=d)
                               for t, (n, d) in sorted(signatures.items())],
            "sections": [dict(clock.position(t), name=clean_text(name))
                         for t, name in sorted(set(parsed["sections"]))]}


def discover_audio(root, song_metadata, warnings):
    files = {p.name.casefold(): p for p in root.iterdir() if p.is_file()}
    audio = []
    for stem in STEMS:
        matches = [files[stem + extension] for extension in AUDIO_EXTENSIONS if stem + extension in files]
        if matches:
            audio.append({"stem": stem, "path": str(matches[0])})
            if len(matches) > 1:
                warnings.append(f"Multiple {stem} audio formats found; selected {matches[0].name}")
    present = {entry["stem"] for entry in audio}
    for key, stem in STREAM_KEYS.items():
        if stem in present or key not in song_metadata or song_metadata[key].casefold() == "none":
            continue
        relative = safe_relative(song_metadata[key])
        path = root / relative
        if not path.is_file() or path.is_symlink():
            warnings.append(f"Chart references missing audio: {relative}")
        elif path.suffix.casefold() in AUDIO_EXTENSIONS:
            audio.append({"stem": stem, "path": str(path)})
    # Numbered files split the same instrument into stems; mixing the fallback
    # combined recording alongside them would double that instrument's volume.
    for family in ("drums", "vocals"):
        if any(entry["stem"].startswith(family + "_") for entry in audio):
            audio = [entry for entry in audio if entry["stem"] != family]
    if not audio:
        warnings.append("No song audio found; import the complete song folder before playing")
    art = next((files[name] for name in ("album.png", "album.jpg", "album.jpeg", "album.webp") if name in files), None)
    return audio, str(art) if art else None


def preview_times(metadata, chart_metadata, warnings):
    result = {}
    for edge in ("start", "end"):
        ini_key, chart_key = f"preview_{edge}_time", f"preview{edge}"
        if ini_key in metadata:
            value, scale, label = metadata[ini_key], 1000.0, ini_key
        elif chart_key in chart_metadata:
            value, scale, label = chart_metadata[chart_key], 1.0, f"Preview{edge.title()}"
        else:
            continue
        try:
            seconds = number(value, default=-1, label=label) / scale
            if seconds < 0 or (edge == "end" and seconds == 0):
                continue
            if seconds > MAX_DURATION:
                fail("Preview position exceeds supported song duration")
        except SongImportError:
            warnings.append(f"Ignored invalid {label}; using the default song preview")
            continue
        result[f"preview{edge.title()}Seconds"] = seconds
    if ("previewStartSeconds" in result and "previewEndSeconds" in result
            and result["previewEndSeconds"] <= result["previewStartSeconds"]):
        result.pop("previewEndSeconds")
        warnings.append("Ignored preview end at or before its start; using the default preview length")
    return result


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".song-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(value, out, ensure_ascii=False, indent=2, allow_nan=False)
            out.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def chart_intensity(chart, metadata=None):
    """Versioned chart demand estimate, calculated on import rather than browse.

    Authored 0..6 tiers describe Expert only. Other difficulties use the same
    deterministic density, two-second burst and coordination model.
    """
    metadata = metadata or {}
    notes = chart.get("notes", [])
    if not notes:
        fail("Cannot calculate intensity for an empty drum chart")
    ordered = sorted(notes, key=lambda note: note["timeSeconds"])
    if any(not isinstance(note.get("timeSeconds"), (int, float))
           or not math.isfinite(note["timeSeconds"]) or note.get("lane") not in LANES for note in ordered):
        fail("Invalid drum notes in intensity calculation")
    active = max(0.0, ordered[-1]["timeSeconds"] - ordered[0]["timeSeconds"])
    density_window = max(8.0, active + 1.0)
    density = len(ordered) / density_window
    left = peak_count = 0
    for right, note in enumerate(ordered):
        while note["timeSeconds"] - ordered[left]["timeSeconds"] >= 2.0 - 1e-9:
            left += 1
        peak_count = max(peak_count, right - left + 1)
    groups = defaultdict(set)
    for note in ordered:
        groups[round(note["timeSeconds"], 6)].add(note["lane"])
    hand_foot = sum("kick" in lanes and len(lanes) > 1 for lanes in groups.values()) / len(groups)
    multiple_hands = sum(len(lanes - {"kick"}) >= 2 for lanes in groups.values()) / len(groups)
    kick_density = sum(note["lane"] == "kick" for note in ordered) / density_window
    peak = peak_count / 2.0
    demand = 0.50 * density + 0.35 * peak + 1.50 * hand_foot + 1.20 * multiple_hands + 0.50 * min(1, kick_density / 2)
    level = sum(demand >= threshold for threshold in (1.4, 2.6, 3.9, 5.4, 7.2, 9.2))
    result = {"level": level, "source": "estimated", "version": INTENSITY_VERSION,
              "metrics": {"noteCount": len(ordered), "activeSeconds": round(active, 4),
                          "densityWindowSeconds": round(density_window, 4), "averageNPS": round(density, 4),
                          "peakTwoSecondNPS": round(peak, 4), "handFootRatio": round(hand_foot, 4),
                          "multiHandRatio": round(multiple_hands, 4), "kickNPS": round(kick_density, 4),
                          "demandScore": round(demand, 4)}}
    if chart.get("difficulty") == "expert":
        for field in ("diff_drums_real", "diff_drums"):
            try:
                authored = float(metadata[field])
            except (KeyError, TypeError, ValueError, OverflowError):
                continue
            if math.isfinite(authored) and authored.is_integer() and 0 <= authored <= 6:
                result.update(level=int(authored), source="authored", authoredField=field)
                break
    return result


def current_intensity(value):
    metrics = value.get("metrics") if isinstance(value, dict) else None
    return (isinstance(value, dict) and type(value.get("level")) is int and 0 <= value["level"] <= 6
            and value.get("version") == INTENSITY_VERSION and value.get("source") in ("authored", "estimated")
            and isinstance(metrics, dict) and all(key in metrics for key in
                ("noteCount", "activeSeconds", "averageNPS", "peakTwoSecondNPS", "handFootRatio", "demandScore"))
            and all(isinstance(metric, (int, float)) and math.isfinite(metric) for metric in metrics.values()))


def song_info(manifest):
    """Keep browsing independent of the size of every playable note chart."""
    fields = ("schemaVersion", "id", "title", "artist", "album", "charter", "year", "genre",
              "sourceFormat", "sourcePath", "chartPath", "manifestPath", "mediaMode", "importedAt",
              "resolution", "selectedDifficulty", "difficulties", "drumMode", "durationSeconds",
              "chartStartSeconds", "offsetSeconds", "audio", "albumArtPath", "warnings", "provenance",
              "doubleKick", "doubleKickNoteCount", "previewStartSeconds", "previewEndSeconds", "referenceFingerprint")
    summary = {key: manifest[key] for key in fields if key in manifest}
    summary["metadataVersion"] = SONG_INFO_VERSION
    summary["charts"] = []
    for chart in manifest["charts"]:
        rating = chart.get("intensity")
        if not current_intensity(rating):
            rating = chart_intensity(chart, manifest.get("metadata", {}))
        summary["charts"].append({"difficulty": chart["difficulty"], "noteCount": len(chart["notes"]),
                                  "instrumentCount": len({note["lane"] for note in chart["notes"]}),
                                  "intensity": rating})
    return summary


def rebuild_index(library=None):
    """Repair only metadata sidecars. Never hash, decode, copy or rewrite media.

    Full song manifests remain untouched; this works even when referenced song
    directories are temporarily offline because all chart notes are already local.
    """
    library = Path(library or Path.home() / "Library/Application Support/Drumx/Songs").expanduser().resolve()
    report = {"updated": 0, "unchanged": 0, "errors": []}
    if not library.exists():
        return report
    for folder in sorted(library.iterdir()):
        manifest_path, info_path = folder / "song.json", folder / "song-info.json"
        if folder.is_symlink() or not folder.is_dir() or folder.name.startswith(".") or not manifest_path.is_file():
            continue
        try:
            if manifest_path.is_symlink() or info_path.is_symlink():
                fail("Song index files must not be symbolic links")
            try:
                info = json.loads(info_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                info = {}
            if (info.get("schemaVersion") == SCHEMA_VERSION and info.get("metadataVersion") == SONG_INFO_VERSION
                    and info.get("id") == folder.name
                    and info.get("charts") and all(current_intensity(chart.get("intensity")) for chart in info["charts"])
                    and info_path.stat().st_mtime_ns >= manifest_path.stat().st_mtime_ns):
                report["unchanged"] += 1
                continue
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("schemaVersion") != SCHEMA_VERSION or manifest.get("id") != folder.name or not manifest.get("charts"):
                fail("Unsupported, mismatched or empty song manifest")
            atomic_json(info_path, song_info(manifest))
            report["updated"] += 1
        except (OSError, ValueError, KeyError, TypeError) as error:
            report["errors"].append({"path": str(manifest_path), "error": str(error)})
    return report


def _reference_fingerprint(source, root, files, double_kick):
    """Cheap change detection, recorded only after a successful content import.

    ctime catches same-size edits whose mtime was restored. This is a local refresh
    optimization, not a replacement for the content hash that establishes song ID.
    """
    entries = []
    for path in sorted(files, key=lambda item: item.relative_to(root).as_posix()):
        attributes = path.stat()
        entries.append({"path": path.relative_to(root).as_posix(), "size": attributes.st_size,
                        "mtime_ns": attributes.st_mtime_ns, "ctime_ns": attributes.st_ctime_ns})
    return {"schemaVersion": 1, "sourcePath": str(source), "rootPath": str(root),
            "doubleKick": bool(double_kick), "files": entries}


def _manifest_stamp(path):
    attributes = path.stat()
    return attributes.st_size, attributes.st_mtime_ns, attributes.st_ctime_ns


def _remember_reference(cache, manifest_path, summary, stamp=None):
    entries = cache.setdefault(summary["sourcePath"], [])
    # Edited songs retain their older content IDs. Keep all candidates so directory
    # enumeration order cannot let an obsolete fingerprint shadow the current one.
    entries[:] = [entry for entry in entries if entry[0] != manifest_path]
    entries.append((manifest_path, summary, stamp or _manifest_stamp(manifest_path)))


def _reference_cache(library):
    """Read small private sidecars once, never all chart JSON or source media."""
    cache = {}
    if not library.exists():
        return cache
    for folder in library.iterdir():
        manifest_path, info_path = folder / "song.json", folder / "song-info.json"
        if (folder.is_symlink() or not folder.is_dir() or not re.fullmatch(r"[0-9a-f]{24}", folder.name)
                or manifest_path.is_symlink() or info_path.is_symlink()):
            continue
        try:
            if not manifest_path.is_file() or not info_path.is_file() or info_path.stat().st_size > MAX_METADATA_BYTES:
                continue
            summary = json.loads(info_path.read_text(encoding="utf-8"))
            if (not isinstance(summary, dict) or summary.get("schemaVersion") != SCHEMA_VERSION
                    or summary.get("id") != folder.name or summary.get("mediaMode") != "reference"
                    or summary.get("manifestPath") != str(manifest_path)
                    or not isinstance(summary.get("sourcePath"), str)
                    or not isinstance(summary.get("referenceFingerprint"), dict)):
                continue
            _remember_reference(cache, manifest_path, summary)
        except (OSError, ValueError, UnicodeError):
            continue  # An absent or damaged cache must take the normal import path.
    return cache


def _cached_reference(fingerprint, cache, difficulty, source_url, summary_only):
    entry = next((entry for entry in cache.get(fingerprint["sourcePath"], [])
                  if entry[1].get("referenceFingerprint") == fingerprint), None)
    if not entry:
        return None
    manifest_path, summary, manifest_stamp = entry
    info_path = manifest_path.with_name("song-info.json")
    charts = summary.get("charts")
    provenance = summary.get("provenance")
    if (summary.get("referenceFingerprint") != fingerprint or not isinstance(charts, list) or not charts
            or not all(isinstance(chart, dict) for chart in charts)
            or summary.get("selectedDifficulty") != (difficulty or charts[-1].get("difficulty"))
            or (source_url and (not isinstance(provenance, dict) or provenance.get("sourceURL") != source_url))):
        return None
    try:
        if (manifest_path.parent.is_symlink() or manifest_path.is_symlink() or info_path.is_symlink()
                or not manifest_path.is_file() or _manifest_stamp(manifest_path) != manifest_stamp):
            return None
        summary_current = (summary.get("metadataVersion") == SONG_INFO_VERSION
                           and all(current_intensity(chart.get("intensity")) for chart in charts)
                           and info_path.stat().st_mtime_ns >= manifest_stamp[1])
        if summary_only and summary_current:
            return summary
        # Direct imports still return the complete playable chart. A metadata
        # upgrade also uses this cached chart, without reopening the source assets.
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if (not isinstance(manifest, dict) or manifest.get("schemaVersion") != SCHEMA_VERSION
                or manifest.get("id") != summary["id"] or manifest.get("mediaMode") != "reference"
                or manifest.get("manifestPath") != str(manifest_path)
                or manifest.get("sourcePath") != fingerprint["sourcePath"]
                or manifest.get("referenceFingerprint") != fingerprint
                or manifest.get("selectedDifficulty") != summary["selectedDifficulty"]
                or not manifest.get("charts")):
            return None
        if not summary_current:
            summary = song_info(manifest)
            atomic_json(info_path, summary)
            _remember_reference(cache, manifest_path, summary, manifest_stamp)
        return summary if summary_only else manifest
    except (OSError, ValueError, KeyError, TypeError, UnicodeError):
        return None


def import_song(source, library=None, difficulty=None, output=None, source_url=None, double_kick=False,
                reference=False, *, _cache=None, _summary_only=False):
    source = Path(source).expanduser().resolve(strict=True)
    if reference and not source.is_dir():
        fail("Reference imports require an unpacked song folder. Extract archives to a folder first.")
    library = Path(library or Path.home() / "Library/Application Support/Drumx/Songs").expanduser().resolve()
    if source_url and not source_url.startswith(("https://", "http://")):
        fail("Source URL must use http or https")
    if difficulty is not None and difficulty not in DIFFICULTIES:
        fail(f"Unsupported difficulty: {difficulty}")
    library.mkdir(parents=True, exist_ok=True)
    if reference and _cache is None:
        _cache = _reference_cache(library)
    warnings = []
    with tempfile.TemporaryDirectory(prefix=".import-", dir=library) as temporary:
        stage = Path(temporary)
        unpacked = stage / "unpacked"
        unpacked.mkdir()
        package_metadata = {}
        if source.is_dir():
            roots = find_song_folders(source)
        elif source.suffix.casefold() in (".mid", ".midi", ".chart", ".ini"):
            roots = find_song_folders(source.parent)
        elif source.suffix.casefold() in (".sng", ".zip"):
            package_metadata = (extract_sng(source, unpacked) if source.suffix.casefold() == ".sng"
                                else extract_zip(source, unpacked))
            roots = find_song_folders(unpacked)
        else:
            fail("Choose a song folder, song.ini, notes.mid, notes.chart, .zip, or .sng package")
        if len(roots) != 1:
            if not roots:
                fail("No notes.mid or notes.chart found in this package")
            fail("Multiple songs found; use --scan DIRECTORY to import a song collection")
        root = roots[0]
        files = folder_files(root)
        fingerprint = _reference_fingerprint(source, root, files, double_kick) if reference else None
        if reference:
            cached = _cached_reference(fingerprint, _cache, difficulty, source_url, _summary_only and not output)
            if cached is not None:
                if output:
                    atomic_json(Path(output).expanduser().resolve(), cached)
                return cached
        top_level = {p.name.casefold(): p for p in files if p.parent == root}
        metadata = read_ini(top_level["song.ini"]) if "song.ini" in top_level else {}
        metadata.update(package_metadata)
        chart_file = next((top_level[name] for name in ("notes.mid", "notes.midi", "notes.chart")
                           if name in top_level), None)
        if chart_file.stat().st_size > MAX_CHART_BYTES:
            fail("Note chart exceeds 64 MiB size limit")
        chart_data = chart_file.read_bytes()
        parsed = parse_chart(chart_data, warnings) if chart_file.suffix.casefold() == ".chart" else parse_midi(chart_data, warnings)
        timing = build_charts(parsed, metadata, warnings, double_kick)
        if difficulty and difficulty not in [chart["difficulty"] for chart in timing["charts"]]:
            fail(f"This song has no {difficulty} drum chart")
        selected = difficulty or timing["charts"][-1]["difficulty"]
        # Content identity includes author metadata and all assets, independent of wrapper
        # folder/ZIP/SNG names, source paths, and the chosen difficulty.
        digest = hashlib.sha256(b"drumx-song-identity-v1\0")
        encoded_metadata = json.dumps(metadata, sort_keys=True, ensure_ascii=False).encode("utf-8")
        digest.update(struct.pack("<Q", len(encoded_metadata)))
        digest.update(encoded_metadata)
        identity_files = sorted((p for p in files if p.name.casefold() != "song.ini"),
                                key=lambda p: p.relative_to(root).as_posix())
        # SNG moves song.ini values into its header. Length framing makes the
        # concatenation unambiguous even when arbitrary audio bytes contain names.
        digest.update(struct.pack("<Q", len(identity_files)))
        for path in identity_files:
            encoded_path = path.relative_to(root).as_posix().encode("utf-8")
            digest.update(struct.pack("<Q", len(encoded_path)))
            digest.update(encoded_path)
            digest.update(struct.pack("<Q", path.stat().st_size))
            with path.open("rb") as src:
                while chunk := src.read(1024 * 1024):
                    digest.update(chunk)
        song_id = digest.hexdigest()[:24]
        destination = library / song_id
        candidate = stage / "song"
        candidate.mkdir()
        materialized = root if reference else candidate / "source"
        if not reference:
            materialized.mkdir()
            for path in files:
                target = materialized / path.relative_to(root)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
            # SNG metadata remains available after its original download is removed.
            if package_metadata and "song.ini" not in top_level:
                ini = "[song]\n" + "\n".join(f"{key} = {value}" for key, value in sorted(metadata.items())) + "\n"
                (materialized / "song.ini").write_text(ini, encoding="utf-8")
        audio, art = discover_audio(materialized, parsed["song"], warnings)
        if reference and not audio:
            fail("No song audio found in the referenced folder. Restore its audio before importing.")
        if not reference:
            for entry in audio:
                entry["path"] = str(destination / Path(entry["path"]).relative_to(candidate))
            if art:
                art = str(destination / Path(art).relative_to(candidate))
        song = parsed["song"]
        preview = preview_times(metadata, song, warnings)
        manifest = {"schemaVersion": SCHEMA_VERSION, "id": song_id,
                    "title": clean_text(metadata.get("name", song.get("name", source.stem))),
                    "artist": clean_text(metadata.get("artist", song.get("artist", "Unknown artist"))),
                    "album": clean_text(metadata.get("album", song.get("album", ""))),
                    "charter": clean_text(metadata.get("charter", metadata.get("frets", song.get("charter", "")))),
                    "year": clean_text(metadata.get("year", song.get("year", ""))).lstrip(", "),
                    "genre": clean_text(metadata.get("genre", song.get("genre", ""))),
                    "sourceFormat": parsed["format"], "sourcePath": str(source),
                    "mediaMode": "reference" if reference else "managed",
                    "chartPath": str(chart_file if reference else destination / "source" / chart_file.name),
                    "importedAt": datetime.now(timezone.utc).isoformat(),
                    "resolution": parsed["resolution"], "selectedDifficulty": selected,
                    "difficulties": [chart["difficulty"] for chart in timing["charts"]],
                    "audio": audio, "albumArtPath": art, "metadata": metadata,
                    "warnings": list(dict.fromkeys(warnings)), "provenance": {"sourceURL": source_url},
                    **timing, **preview}
        manifest["notes"] = next(chart["notes"] for chart in manifest["charts"] if chart["difficulty"] == selected)
        manifest["manifestPath"] = str(destination / "song.json")
        if reference:
            # Never bless a fingerprint for files that changed during parsing or
            # hashing; the next refresh must retry the complete source import.
            if fingerprint != _reference_fingerprint(source, root, folder_files(root), double_kick):
                fail("Song files changed during import. Wait for file changes to finish, then refresh again.")
            manifest["referenceFingerprint"] = fingerprint
        if destination.is_symlink():
            fail("Song destination must not be a symbolic link")
        if destination.exists():
            existing_path = destination / "song.json"
            if not existing_path.is_file() or existing_path.is_symlink():
                fail("Existing song directory has no safe manifest; refusing to replace it")
            try:
                existing = json.loads(existing_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                fail("Existing song manifest is unreadable; refusing to replace it")
            if existing.get("id") != song_id or existing.get("schemaVersion") != SCHEMA_VERSION:
                fail("Existing song identity does not match; refusing to replace it")
            if not reference:
                # Repair managed imports, including a previous reference import.
                # Referencing a folder never changes existing managed media.
                managed_source = destination / "source"
                if managed_source.is_symlink():
                    fail("Managed song source must not be a symbolic link")
                for staged_file in folder_files(materialized):
                    relative = staged_file.relative_to(materialized)
                    target = managed_source / relative
                    ancestor = target
                    while ancestor != destination:
                        if ancestor.is_symlink():
                            fail("Managed song asset must not be a symbolic link")
                        ancestor = ancestor.parent
                    if target.exists() and not target.is_file():
                        fail("Managed song asset collides with a directory")
                    if not target.exists() or not filecmp.cmp(staged_file, target, shallow=False):
                        target.parent.mkdir(parents=True, exist_ok=True)
                        os.replace(staged_file, target)
            manifest["importedAt"] = existing.get("importedAt", manifest["importedAt"])
            if not source_url:
                manifest["provenance"] = existing.get("provenance", manifest["provenance"])
            summary = song_info(manifest)
            atomic_json(existing_path, manifest)
            atomic_json(destination / "song-info.json", summary)
        else:
            summary = song_info(manifest)
            atomic_json(candidate / "song.json", manifest)
            atomic_json(candidate / "song-info.json", summary)
            candidate.rename(destination)
        if reference:
            manifest_path = destination / "song.json"
            _remember_reference(_cache, manifest_path, summary)
        if output:
            atomic_json(Path(output).expanduser().resolve(), manifest)
        return manifest


def scan_directory(directory, library=None, difficulty=None, double_kick=False, reference=False):
    directory = Path(directory).expanduser().resolve(strict=True)
    if not directory.is_dir():
        fail("--scan requires a directory")
    library_path = Path(library or Path.home() / "Library/Application Support/Drumx/Songs").expanduser().resolve()
    sources = []
    visited = 0
    for folder, dirs, files in os.walk(directory, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "__MACOSX"
                         and not (Path(folder) / d).is_symlink()
                         and (Path(folder) / d).resolve() != library_path)
        visited += len(dirs) + len(files)
        if visited > MAX_SCAN_ENTRIES:
            fail(f"Directory scan exceeds {MAX_SCAN_ENTRIES} entries; choose a narrower song directory")
        if any(name.casefold() in ("notes.mid", "notes.midi", "notes.chart") for name in files):
            sources.append(Path(folder))
            dirs[:] = []
        else:
            sources.extend(Path(folder) / name for name in sorted(files)
                           if Path(name).suffix.casefold() in (".sng", ".zip") and not (Path(folder) / name).is_symlink())
    report = {"imported": [], "errors": [], "skipped": []}
    cache = _reference_cache(library_path) if reference else None
    for source in sources:
        try:
            manifest = import_song(source, library=library, difficulty=difficulty, double_kick=double_kick,
                                   reference=reference, _cache=cache, _summary_only=True)
            if manifest["manifestPath"] not in report["imported"]:
                report["imported"].append(manifest["manifestPath"])
            else:
                report["skipped"].append({"path": str(source), "reason": "Duplicate song content"})
        except (SongImportError, OSError, zipfile.BadZipFile, UnicodeError) as error:
            report["errors"].append({"path": str(source), "error": str(error)})
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", help="Song directory, notes file, .zip, or .sng package")
    parser.add_argument("--scan", nargs="?", const=True, metavar="DIRECTORY",
                        help="Recursively import a collection (DIRECTORY or the positional source)")
    parser.add_argument("--library", type=Path, help="Private library directory (default: ~/Library/Application Support/Drumx/Songs)")
    parser.add_argument("--reference", action="store_true",
                        help="Index unpacked song folders in place without copying media; keep those folders available")
    parser.add_argument("--rebuild-index", action="store_true",
                        help="Repair lightweight library metadata and intensity ratings without rescanning source assets")
    parser.add_argument("--output", type=Path, help="Also write a manifest copy to this path")
    parser.add_argument("--difficulty", choices=DIFFICULTIES, help="Initial difficulty (default: highest chart available)")
    parser.add_argument("--double-kick", action="store_true", help="Include optional Expert+ second-pedal notes")
    parser.add_argument("--source-url", help="Record the chart's source page; no network requests are made")
    args = parser.parse_args(argv)
    if args.rebuild_index:
        if args.source or args.scan or args.output or args.source_url or args.reference or args.difficulty or args.double_kick:
            parser.error("--rebuild-index accepts only --library")
        try:
            result = rebuild_index(args.library)
            json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
            sys.stdout.write("\n")
            return 0 if not result["errors"] or result["updated"] else 1
        except (OSError, ValueError) as error:
            print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
            return 1
    if args.scan is True:
        if not args.source:
            parser.error("--scan requires a directory")
        args.scan, args.source = args.source, None
    if bool(args.source) == bool(args.scan):
        parser.error("provide SOURCE, SOURCE --scan, or --scan DIRECTORY")
    if args.scan and (args.output or args.source_url):
        parser.error("--output and --source-url are only available for a single song")
    try:
        if args.scan:
            result = scan_directory(args.scan, args.library, args.difficulty, args.double_kick, args.reference)
            json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
            sys.stdout.write("\n")
            return 0 if result["imported"] or not result["errors"] else 1
        manifest = import_song(args.source, args.library, args.difficulty, args.output, args.source_url,
                               args.double_kick, args.reference)
        json.dump({"id": manifest["id"], "title": manifest["title"], "artist": manifest["artist"],
                   "manifestPath": manifest["manifestPath"], "difficulties": manifest["difficulties"],
                   "mediaMode": manifest["mediaMode"],
                   "notes": len(manifest["notes"]), "audioStems": len(manifest["audio"]),
                   "warnings": manifest["warnings"]}, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 0
    except (SongImportError, OSError, zipfile.BadZipFile, UnicodeError, RuntimeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
