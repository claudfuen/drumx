# Song import and format compatibility

Drumx's song library accepts the common Clone Hero / YARG song package: a folder
with `notes.mid` or `notes.chart`, optional `song.ini`, and accompanying audio.
A single-song ZIP or version 1 `.sng` container can be imported directly.
Enchor.us is a chart discovery site; its downloads use these existing formats.
The importer makes no network requests.

Use the Songs section in the native app to add a song or scan a song directory.
The same import is available from the command line with Python 3.10 or newer:

```sh
python3 scripts/import_song.py "$HOME/Downloads/Artist - Song.sng"
python3 scripts/import_song.py "$HOME/Music/Clone Hero Songs" --scan
python3 scripts/import_song.py --scan "$HOME/Music/Clone Hero Songs"
python3 scripts/import_song.py "/path/to/song" --difficulty hard --double-kick
```

The default destination is `~/Library/Application Support/Drumx/Songs`.
`--library DIRECTORY` overrides it. Original charts, metadata, artwork, and
recordings are copied into the library so moving a download does not break a song.
`--source-url URL` records provenance for one song. `--output FILE` writes an
additional manifest for inspection. Neither downloads nor imported media belong
in Git.

A recursive directory scan discovers song folders and `.sng`/`.zip` files, reports
individual failures, and continues importing other songs. Its JSON report has
`imported` manifest paths, `errors` with a source path and reason, and `skipped`
duplicates. A ZIP containing several songs must first be extracted into a song
directory. Hidden directories and symbolic links are not followed during scans.

## Supported drum data

The importer preserves every available Easy, Medium, Hard, and Expert drum chart.
The initial selection defaults to the highest available difficulty. An explicit
missing difficulty is an error. Tracks for guitar, bass, keys, and vocals are not
converted to drum notes; their recordings can still be backing stems.

MIDI support includes format 0/1 files using ticks per quarter note, `PART DRUMS`
(and the `PART DRUM` alias), running status, note-on with zero velocity, tempo
changes, time signatures, drum velocities, and pro-drum tom markers. Running
channel status survives intervening meta/SysEx events, matching YARG's reader.
`.chart` support covers the four `*Drums` sections, tempo and meter changes,
cymbal modifiers, dynamics, and named sections. Tempo anchors are editor metadata
and do not change playback timing.

Pro and five-lane flags in `song.ini` take precedence. Without them, tom/cymbal
markers identify pro drums and a fifth lane identifies five-lane drums. Otherwise,
the song is treated as standard four-lane and receives an ambiguity warning.
Sustain length alone is not used to infer five-lane mode because standard MIDI
hits also have durations. The `five_lane_drums` flag resolves those ambiguous
charts.

| Source part | Pro drums | Standard four-lane | Five-lane |
| --- | --- | --- | --- |
| Kick | kick | kick | kick |
| Red | snare | snare | snare |
| Yellow cymbal | hihat | hihat | hihat |
| Yellow tom | tom1 | hihat | unavailable |
| Blue cymbal | ride | tom2 | unavailable |
| Blue tom | tom2 | tom2 | tom2 |
| Green cymbal / five-lane orange | crash | crash | crash |
| Green tom / five-lane green | tom3 | crash | tom3 |

The eight native lane identifiers are `hihat`, `snare`, `kick`, `tom1`, `tom2`,
`tom3`, `crash`, and `ride`. These preserve the chart's available cymbal/tom
separation; a plastic-instrument chart cannot identify every acoustic kit voice.
Pro disco-flip events restore red hits to hi-hat and yellow hits to snare while
active. `dnoflip` does not swap the notes.

Optional second-pedal notes are excluded unless `--double-kick` is selected.
Their count remains in the manifest. MIDI uses the note immediately below each
difficulty's kick, including Expert note 95; `.chart` uses note type 32. Dynamics
are preserved as velocity and optional `accent`/`ghost` annotations, with MIDI
chart dynamics enabled only by the chart flag or five-lane mode.

Drumx practices the authored hits. It does not reproduce Clone Hero / YARG's star
power, freestyle fills, roll-lane scoring, sustain scoring, flam expansion,
Big Rock Ending rules, leaderboard hashes, or other instrument engines.
`PART REAL_DRUMS_PS`, a separate `PART DRUMS_2X` track, SMPTE MIDI timing, RAR/7z,
and Rock Band console containers are not imported by this parser.

## Audio and timing

Reserved stem names are discovered first, followed by safe relative audio paths
from `.chart` stream metadata. Recognized extensions are WAV, FLAC, AIFF, MP3,
OGG, Opus, and M4A. A numbered drum or vocal stem suppresses the corresponding
combined fallback stem to avoid playing that instrument twice. Preview audio is
not used as a backing recording. Importing audio is separate from the native
player's codec support and conversion.

Notes and tempo/meter entries store absolute seconds relative to the recording's
start. A positive offset means later chart notes. A nonzero `song.ini` `delay`
(milliseconds) takes precedence; otherwise `.chart` `Offset` (seconds) applies.
The offsets are not added together. This follows YARG's metadata and playback
semantics.

Tempo changes are integrated across ticks, using quarter-note resolution. A meter
change does not change a tick's duration. `timeSeconds` already includes the
chosen offset; consumers must not add it a second time. Negative positions are
preserved. `chartStartSeconds` is the earlier of zero and the first playable note,
so a consumer can shift its transport origin and audio scheduling consistently.
The duration is the largest of the final note's end plus two seconds, the chart's
end marker, and declared song duration. Declared duration is a fallback and does
not establish the actual decoded recording's length.

## JSON contract, schema version 1

Each imported song lives at `<library>/<id>/song.json`, with media in its `source`
subdirectory. The ID is a 24-character SHA-256 prefix of length-framed normalized INI metadata
and asset contents and paths. It is independent of download path, archive wrapper,
and selected difficulty, but distinguishes chart authors and changed media.
Equivalent folder, ZIP, and SNG inputs deduplicate. Reimport updates the manifest
and restores missing or damaged managed source files. Existing import timestamps
and recorded provenance survive a duplicate import.

The native consumer may ignore additional fields added within version 1.

| Field | Meaning |
| --- | --- |
| `schemaVersion`, `id` | Integer schema version and stable content identity |
| `title`, `artist`, `album`, `charter`, `year`, `genre` | Display strings; simple formatting tags removed |
| `sourceFormat` | `midi` or `chart` |
| `sourcePath`, `chartPath`, `manifestPath` | Absolute original input, managed chart, and manifest paths |
| `importedAt` | UTC ISO-8601 string |
| `resolution` | Ticks per quarter note |
| `drumMode` | `pro`, `fourLane`, or `fiveLane` |
| `difficulties`, `selectedDifficulty` | Available names in easy-to-expert order and initial selection |
| `charts` | Array of `{difficulty, notes}` for every available drum difficulty |
| `notes` | Duplicate of the selected chart's notes, for simple consumers |
| `offsetSeconds`, `chartStartSeconds`, `durationSeconds` | Timing values described above |
| `tempos` | Array of `{tick, beat, timeSeconds, bpm}` |
| `timeSignatures` | Array of `{tick, beat, timeSeconds, numerator, denominator}` |
| `sections` | Array of `{tick, beat, timeSeconds, name}` |
| `audio` | Array of `{stem, path}` with absolute managed asset paths |
| `albumArtPath` | Absolute managed artwork path, or null |
| `doubleKick`, `doubleKickNoteCount` | Inclusion option and total optional kick count across difficulties |
| `warnings` | Human-readable import caveats |
| `metadata`, `provenance` | Raw string metadata and an optional `sourceURL` |

A note has `tick`, quarter-note `beat`, `timeSeconds`, `durationSeconds`, `lane`,
`sourceLane` (normalized source color 0 through 5, or 32 for second-pedal kicks),
`velocity` (1 through 127), and boolean `doubleKick`. It may also have `dynamic`.
Simultaneous notes remain simultaneous. Duplicate notes for the same tick and
mapped lane are collapsed. Sustain durations are retained as data even though
Drumx scores a drum strike at the note's start.

## Validation and input bounds

```sh
python3 -m unittest discover -s scripts/tests -p test_import_song.py -v
```

The tests generate small original MIDI, `.chart`, ZIP, and SNG fixtures in temporary
directories. They cover integrated tempo changes, meter, all drum difficulties,
pro cymbals/toms, disco flip, dynamics, offsets, second pedals, metadata precedence,
content deduplication, stable media, repair on reimport, malformed input, and safe
archive handling. No commercial recordings or charts are committed.

Archive indices are validated before extraction. Absolute paths, traversal,
backslash paths, links, special files, case-insensitive duplicate names,
file/directory collisions, encrypted ZIP entries, overlapping SNG payloads, and
invalid section boundaries are rejected. Limits are 10,000 files, 1 GiB per file,
2 GiB expanded per package, 64 MiB per chart, 8 MiB per metadata/index section,
and one million parsed events. Playable charts are limited to 200,000 notes per
difficulty and two hours, matching the native engine's bounds. Failed imports do
not publish a new song manifest.

## Primary references

- [Chart format overview](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/chart-format/Format-Overview.md)
- [MIDI drums](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/mid-format/Tracks/Drums.md)
- [.chart drums](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/chart-format/Tracks/Drums.md)
- [Standard song.ini tags](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/song-ini/Standard-Tags.md)
- [Supported audio files](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/Supported-Audio-Files.md)
- [SNG container specification and reference implementation](https://github.com/mdsitton/SngFileFormat)
- [YARG.Core](https://github.com/YARC-Official/YARG.Core): `IO/Midi/YARGMidiTrack.cs`,
  `Song/Entries/Types/SongMetadata.cs`, and `MoonscraperChartParser/IO/Midi/MidReader.ProcessLists.cs`
- [YARG playback clock](https://github.com/YARC-Official/YARG/blob/master/Assets/Script/Playback/SongRunner.cs)
