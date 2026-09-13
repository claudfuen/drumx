# Song recordings and live drum sounds

Drumx plays a song's audio files continuously on a shared timeline. A chart
describes which notes to score; it does not contain the recorded sound of each
note. A separate drum stem contains the original drum performance, including
notes omitted from easier charts and passages between targets.

## Choose what you hear

- **Recorded drums: Off** is the default for song practice. Separate `drums`
  and `drums_1` through `drums_4` stems are silent. Other backing recordings keep
  playing, including during rests and misses.
- **Recorded drums: On** restores the original recorded performance for
  listening or playing along. Its volume does not depend on your hits.
- **Drumx drum sounds** in Sound settings controls the acoustic samples triggered
  by your physical MIDI or keyboard strikes. You can use your module's own sound
  instead. Turning recorded drums off does not enable live monitoring.
- Library previews always use the full recorded mix.

The recorded-drums preference persists, changes live without resetting the
transport, and survives pause/resume and restart. It never alters the chart,
scoring clock, source media, or lesson progress. The importer retains stem
identity even when an Ogg/Opus recording is decoded to a numbered WAV cache.

A single `song` or `guitar` file can contain the complete mix. Drumx cannot
silence its embedded drums independently: the control displays **In mix** and
explains the limitation. Some separate backing stems can also contain drum
bleed. This control does not perform source separation. A drum-only package
becomes silent with recorded drums off because there is no backing recording.

## How YARG differs

YARG also plays continuous recordings. In the source revision checked on
2026-09-12, its default **Mute On Miss** setting is `MultitrackOnly`. A hit
unmutes the player's stem family and a missed chart note mutes it. That can
leave the recorded drums audible before the first miss, between targets, or
during notes omitted from an easier chart. Per-hit drum sound effects are a
separate setting and default to off.

Sources: [hit/miss handling](https://github.com/YARC-Official/YARG/blob/f5bfbe6996b4af35722d4204a93c6cc5c8f52a45/Assets/Script/Gameplay/Player/TrackPlayer.cs#L999-L1045),
[default settings](https://github.com/YARC-Official/YARG/blob/f5bfbe6996b4af35722d4204a93c6cc5c8f52a45/Assets/Script/Settings/SettingsManager.Settings.cs#L277-L300),
[per-hit drum effects](https://github.com/YARC-Official/YARG/blob/f5bfbe6996b4af35722d4204a93c6cc5c8f52a45/Assets/Script/Gameplay/Player/DrumsPlayer.cs#L580-L598).

The checked YARG build's pinned Core also applies a 0.15 volume floor to packages
whose metadata source is `yarg`, so muting can leave that recording faintly
audible. This does not apply to every package. Sources:
[source condition](https://github.com/YARC-Official/YARG.Core/blob/3beb94e526558134145bcd3e409428f759001a40/YARG.Core/Song/Entries/Ini/SongEntry.UnpackedIni.cs#L33-L37),
[gain floor](https://github.com/YARC-Official/YARG.Core/blob/3beb94e526558134145bcd3e409428f759001a40/YARG.Core/Audio/StemChannel.cs#L61-L71).

Drumx's practice control keeps separate recorded drums at zero for the entire
take. It does not implement YARG's hit/miss volume gating. The full-kit sampler
plays your own strikes independently, with recorded velocity layers and alternate
takes. Physical module behavior and end-to-end latency still need hardware
auditioning.
