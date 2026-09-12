# Big Rusty starter kit

Drumx includes a small acoustic starter selection from **Big Rusty Drums by
Karoryfer Samples**, released under **CC0 1.0 Universal**. The publisher explicitly
permits reuse of its free libraries in other sample libraries. The accompanying
`LICENSE` is the unchanged upstream CC0 legal text. Credit is retained here as
provenance even though CC0 does not require attribution.

- Official product: <https://shop.karoryfer.com/pages/free-big-rusty-drums>
- Publisher's license statement: <https://shop.karoryfer.com/pages/free-samples>
- Upstream: <https://github.com/sfzinstruments/karoryfer.big-rusty-drums>
- Pinned commit: `f07ce00df34a46b6b08375be56fe116cf15782bc`
- Pinned license: <https://github.com/sfzinstruments/karoryfer.big-rusty-drums/blob/f07ce00df34a46b6b08375be56fe116cf15782bc/LICENSE>

The 24 included lossless FLAC files total 984,434 bytes. They are original,
unchanged recordings: mono, 44.1 kHz, 16-bit. No normalization, resampling, onset
trimming, or synthetic pitch variation was applied. Each instrument has four
selected recorded dynamic layers and two different recorded takes per layer.
The complete upstream library offers more layers, four round robins, additional
microphones, and a full kit.

| Pad | Articulation / microphone | Original selected velocity layers | Original full coverage |
| --- | --- | --- | --- |
| 0 | Closed hi-hat / close | 1, 3, 4, 6 | 6 layers x 4 takes |
| 1 | Center snare / top | 2, 5, 8, 10 | 10 layers x 4 takes |
| 2 | Damped kick / close | 3, 7, 10, 14 | 14 layers x 4 takes |

`manifest.json` is a flat sampler manifest. Each entry contains `pad`,
`velocityMin`, `velocityMax`, `roundRobin`, and `file`, with paths relative to the
app's asset root. Each pad covers MIDI velocities 1-31, 32-63, 64-95, and 96-127.
Velocity zero is note-off, not a sample trigger. These are the curated subset's
ranges, not an exact reproduction of the full upstream SFZ velocity map. Original
amplitude differences remain intact. Alternate the two takes within each pad's
dynamic layer, without applying artificial timing offsets.

`provenance.json` records every original source path, pinned download URL,
SHA-256, byte count, source layer, round robin, and decoded-format metadata.
Files were downloaded directly from the publisher-linked upstream repository.

From the repository root, restore missing originals with:

```sh
python3 scripts/fetch-samples.py
```

Verify all local hashes, distinct alternates, and complete velocity coverage
without accessing the network:

```sh
python3 scripts/fetch-samples.py --check
```

The fetcher refuses changed files or unexpected checksums. It does not overwrite
edited assets. These sounds establish a working acoustic sample path; the final
kit sound, balance, velocity response, onset behavior, and e-kit feel still need
auditioning and hardware testing.
