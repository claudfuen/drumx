# Big Rusty acoustic kit

Drumx includes an acoustic kit selection from **Big Rusty Drums by
Karoryfer Samples**, released under **CC0 1.0 Universal**. The publisher explicitly
permits reuse of its free libraries in other sample libraries. The accompanying
`LICENSE` is the unchanged upstream CC0 legal text. Credit is retained here as
provenance even though CC0 does not require attribution.

- Official product: <https://shop.karoryfer.com/pages/free-big-rusty-drums>
- Publisher's license statement: <https://shop.karoryfer.com/pages/free-samples>
- Upstream: <https://github.com/sfzinstruments/karoryfer.big-rusty-drums>
- Pinned commit: `f07ce00df34a46b6b08375be56fe116cf15782bc`
- Pinned license: <https://github.com/sfzinstruments/karoryfer.big-rusty-drums/blob/f07ce00df34a46b6b08375be56fe116cf15782bc/LICENSE>

The 80 included lossless FLAC files total 9,296,016 bytes. They are original,
unchanged recordings: mono, 44.1 kHz, 16-bit. No normalization, resampling, onset
trimming, or synthetic pitch variation was applied. Each instrument has four
selected recorded dynamic layers and two different recorded takes per layer.
The original 24 closed-hat, snare, and kick recordings remain unchanged. Three
different recorded toms, crash, ride, open hat, and foot chik complete Drumx's
ten-pad kit. The complete upstream library offers more layers, additional
round robins and microphones, and further instruments and articulations.

| Pad | Articulation / microphone | Original selected velocity layers | Original full coverage |
| --- | --- | --- | --- |
| 0 | Closed hi-hat / close | 1, 3, 4, 6 | 6 layers x 4 takes |
| 1 | Center snare / top | 2, 5, 8, 10 | 10 layers x 4 takes |
| 2 | Damped kick / close | 3, 7, 10, 14 | 14 layers x 4 takes |
| 3 | High tom, 14 inch center hit / close | 1, 3, 4, 6 | 6 layers x 4 takes |
| 4 | Mid tom, 15 inch center hit / close | 1, 3, 5, 7 | 7 layers x 4 takes |
| 5 | Floor tom, 18 inch center hit / close | 2, 4, 6, 8 | 8 layers x 4 takes |
| 6 | Crash, 17 inch edge / close | 1, 2, 4, 5 | 5 layers x 4 takes |
| 7 | Ride, 22 inch bow / close | 2, 5, 8, 10 | 10 layers x 3 takes |
| 8 | Fully open hi-hat, tip / close | 1, 3, 4, 6 | 6 layers x 4 takes |
| 9 | Pedal hi-hat, foot chik / close | 1, 2, 4, 5 | 5 layers x 4 takes |

The high, mid, and floor toms use the source's separate 14, 15, and 18 inch drums;
none is a pitch-shifted copy. High and mid are relative positions within this
oversized acoustic kit. The ride is its bow articulation, and the pedal hat is
an actual foot closure recording. Further source articulations such as ride
bell, hi-hat openness stages, and cymbal choke recordings are not included.

`manifest.json` is a flat sampler manifest. Each entry contains `pad`,
`velocityMin`, `velocityMax`, `roundRobin`, and `file`, with paths relative to the
app's asset root. Each pad covers MIDI velocities 1-31, 32-63, 64-95, and 96-127.
Velocity zero is note-off, not a sample trigger. These are the curated subset's
ranges, not an exact reproduction of the full upstream SFZ velocity map. Original
amplitude differences remain intact. Alternate the two takes within each pad's
dynamic layer, without applying artificial timing offsets.

`provenance.json` includes the pad, instrument, layer, and round-robin contract
and records every original source path, pinned download URL,
SHA-256, byte count, source layer, round robin, and decoded-format metadata.
Files were downloaded directly from the publisher-linked upstream repository.
All sample paths follow `BigRusty/<instrument>/v<layer>_rr<take>.flac`; the
instrument names are `hihat`, `snare`, `kick`, `tom_high`, `tom_mid`, `tom_floor`,
`crash`, `ride`, `hihat_open`, and `hihat_pedal` in pad order.

From the repository root, restore missing originals with:

```sh
python3 scripts/fetch-samples.py
```

Verify all local hashes, FLAC format metadata, distinct alternates, pad identity,
and complete velocity coverage
without accessing the network:

```sh
python3 scripts/fetch-samples.py --check
python3 -m unittest discover -s scripts/tests -p test_fetch_samples.py
```

The fetcher refuses changed files or unexpected checksums. It does not overwrite
edited assets. The long natural cymbal and open-hat tails remain intact. The
kit sound, balance, velocity response, onset behavior, and e-kit feel still need
auditioning and hardware testing.
