# Working on drumx

## Ship visible progress

- Commit each coherent, validated milestone and push it to the configured GitHub remote. Keep commits small enough to explain and review. Do not accumulate a whole session of unrelated changes in one commit.
- Maintain README.md as the product's front door whenever behavior, setup, architecture, controls, or development instructions change. Describe what works today separately from planned work. Keep its quick start executable, links valid, and claims supported.
- Keep CHANGELOG.md aligned with committed milestones. Record meaningful product and engineering progression, not every edit or test run.
- Preserve unrelated work and commit only intentional files. Never commit credentials, private user data, generated builds, or local practice history.

## Product invariants

- One musical timeline, one shared NOW line. Equal-time notes have the same screen Y across all lanes. Kick spans that same line; decorative kit references below it are never additional timing destinations.
- Keep instrument positions stable across lessons and guidance modes. Memory practice keeps the quiet highway and own-hit feedback. Click-only checks additionally hide live timing feedback.
- Keep native input timestamps and audio scheduling authoritative. Rendering must not fire the metronome or determine a hit's capture time. State precisely what a latency or frame measurement covers.
- Teach real counts, notation and drum terminology. Sticking hints are suggestions; MIDI does not verify the player's hands or physical technique.
- Build and inspect playable slices before expanding the course or committing the production renderer. A requested display cadence is not a measured frame rate.

## Validation and documentation

Run the native checks appropriate to the change and build the app for UI or integration changes. Inspect meaningful UI changes in the running app. Keep sample provenance and licenses with the assets.

```sh
bash scripts/test-native.sh
bash scripts/build-macos-lab.sh
```

The README is the starting point. Detailed behavior belongs in docs/native-lab.md; rendering experiments belong in docs/rendering-plan.md. A public repository and an intended free product do not imply a source-code license has already been selected.
