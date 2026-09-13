# Song recordings and live drum sounds

Drumx plays a song's audio files continuously on a shared timeline. A chart
describes which notes to score; it does not contain the recorded sound of each
note. A separate drum stem contains the original drum performance, including
notes omitted from easier charts and passages between targets.

## Choose what you hear

- **Follow my playing** is the default in Songs. Separate `drums` and
  `drums_1` through `drums_4` stems start audible. A missed chart note mutes that
  drum family, and a successful hit restores it. Extra strikes do not change
  the recording's gain. Backing stems keep playing throughout.
- **Always on** keeps the original recorded performance audible regardless of
  your hits. Use it for reference or unrestricted play-along.
- **Off** silences separate drum stems throughout the take. Use it to play your
  own module's sounds or the enabled Drumx live samples against the backing.
- **Drumx drum sounds** in Sound settings controls the acoustic samples triggered
  by your physical MIDI or keyboard strikes. You can use your module's own sound
  instead. Follow my playing and Always on temporarily suppress these samples
  in Songs, so they do not layer over the original recorded performance. Off
  and leaving Songs restore the monitoring preference without overwriting it.
  Drumx cannot mute sound produced by the physical module itself.
- Library previews always use the full recorded mix.

The recorded-drums preference persists, changes live without resetting the
transport, and survives pause/resume and restart. It never alters the chart,
scoring clock, source media, or lesson progress. The importer retains stem
identity even when an Ogg/Opus recording is decoded to a numbered WAV cache.

A successful hit restores a continuous recording rather than triggering or
stretching an isolated sample. Before the first miss, between targets, and
through rests, the current gate remains in effect. An easier chart can therefore
play drum sounds that have no target. A missed part of a chord closes the drum
family when its hit window expires; the next successful hit opens it again.

Gate decisions use captured hit times and the same per-pad miss deadlines as
scoring, including shortened windows between dense notes. Delayed corrections
recompute the latest valid decision. Overhits do not enter this audio gate,
although they still break score combos. Gain changes use short fades and never
reschedule stems or alter the song epoch. Pause/resume retains the gate; restart
begins with the drums audible again.

A single `song` or `guitar` file can contain the complete mix. Drumx cannot
silence its embedded drums independently: the control displays **In mix** and
explains the limitation. Some separate backing stems can also contain drum
bleed. Full mixes also suppress live hit samples, consistently using their
original recording regardless of the previous song's mode. This control does
not perform source separation. A drum-only package
becomes silent with recorded drums off because there is no backing recording.

## What we learned from YARG

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

Drumx follows this continuous-performance model for ordinary song play. Its
short gain fades are a local click-prevention choice. Unlike YARG's optional
freestyle hit effects around chart boundaries, Drumx suppresses hit samples
throughout its recorded-performance modes. It does not add a source-specific
volume floor or imply that a full mix can be separated. The full-kit sampler
remains available for lessons and the Off recording mode. Physical module
behavior and end-to-end latency still need hardware auditioning.
