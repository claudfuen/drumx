# First session with a MIDI kit

This is a first-play checklist for the native macOS lab. No physical Alesis module has been tested in this work. The user's module is approximately an Alesis Turbo; confirm its exact name and available connections on the module before treating a model-specific assumption as established.

## What a successful first session proves

The chosen MIDI input sends strikes; hi-hat, snare and kick reach the intended lesson pads; raw velocity changes with the incoming values; one guided take can complete and save under the selected player. It does not prove physical round-trip latency, hand technique, every kit articulation, or compatibility with other modules.

The setup model records each selected-source Note On as a raw note, velocity, source ID, timestamp and optional mapped pad. An unmapped note remains visible. Three observed pad receipts mean an input check, not mastery. Keyboard checks are a separate input mode and cannot make a selected MIDI kit appear checked.

## Before starting the lesson

1. Choose the intended player. Use a comfortable listening level and connect the module to the Mac using the connection supported by that exact module.
2. Open Settings and select the module that actually appears as a MIDI input. The popup request alone is not a successful connection. Check the selected source and any connection error before proceeding.
3. Strike hi-hat, snare and kick separately. Read the raw MIDI note and velocity for each. No raw receipt means the problem is before pad mapping. A visible raw note marked unmapped means input is working and the pad needs an alias.
4. To add a pad alias, choose the intended pad and strike it once. Existing aliases stay in place, including hi-hat articulation notes. A note belongs to only one lesson pad; if it moves from another pad, check both pads again. Cancel learning when you do not intend the next hit to remap anything.
5. Try the hi-hat articulations the module supports. Check whether they produce distinct notes, controller changes, or the same note. The current lessons group configured hi-hat notes into one target; they do not teach or grade continuous pedal openness.
6. Hit softly and firmly. The displayed raw velocity should report what the module sends. A velocity reading does not establish sound-output latency or calibration accuracy.
7. Choose one monitoring path. If the module is already sounding through headphones, turn off Drumx's strike monitoring to avoid hearing two drum sounds. The click and demonstration are separate from strike monitoring. Confirm that the click is audible before beginning.
8. Play a guided four-bar take at a comfortable tempo. Verify that physical hits reach the expected catchers, stop behaves as shown, and the completed take is saved under the intended player. Then replay the same conditions to inspect comparison and progression.

## Failure cases to test deliberately

| Case | Expected behavior |
| --- | --- |
| Wrong source selected | No fabricated check marks. A keyboard hit must not validate the MIDI kit. |
| Pad sends an unfamiliar note | Show the raw note and velocity with an unmapped state; do not silently discard it from setup feedback. |
| Add a hi-hat note | Preserve all existing hi-hat aliases. Learning is a one-shot addition, not replacement of the entire pad. |
| The note already belongs to snare or kick | Report that ownership moved. Preserve unrelated aliases and clear the former owner's receipt check. |
| Cancel learning, then play | The following hit must not change mappings. |
| Select another source while learning | Cancel learning, unmute the native learn path, and clear old input receipts. |
| Disconnect or reconnect the same endpoint | Invalidate receipts and pending learning, even if the displayed source ID did not change. Check the pads again. |
| Requested source fails to connect | Reflect the actual connected source, not the requested popup choice. End pending learn state and show the failure. |
| Note On with velocity zero / Note Off | No strike receipt, mapping change or readiness check. |
| One pad triggers two notes | Show the arriving notes. Check module settings and aliases before interpreting extras as the learner's rhythm. |
| Rapid simultaneous hits | Each native input remains a distinct event. Setup may show the latest receipt; the scoring path must retain all chord members. |
| Switch to keyboard mode | Clear MIDI receipts. A complete keyboard check must be identified as keyboard readiness. |
| Change a mapping after a completed take | Preserve that take's captured mapping for comparison. Check the changed pads again for subsequent takes. |

## Controller integration boundary

`DrumxKitSetup` is a pure state model. Feed it every valid incoming selected-source MIDI hit **before** the existing mapped-pad early return. A successful learning receipt supplies the updated complete mapping and the pads from which the note was removed. Apply that mapping to both the native sampler and scoring input, then persist it through the existing shared mapping preference. End native MIDI-learn muting whenever the model's pending pad becomes nil.

Pass the native host time to `beginLearning(pad:at:)`. A packet captured before that arm time may still be waiting on the UI queue; it must remain a raw receipt rather than assigning the pad the learner just selected.

On a source operation, invalidate the old input first and select the source actually reported by `DrumxIO` after connection. Also invalidate on loss or failure, including a same-ID reconnection. Keep native IO's source-generation rejection of stale callbacks. Menu navigation must stay off while mapping or playing; its opt-in setting is a separate feature from readiness.

The optional drum-menu helper maps hi-hat to previous, snare to next, and two kick strikes to activation. The confirmation window is 600 ms, with an 80 ms minimum gap to reject a duplicate packet. It ignores velocities below 32, debounces navigation for 200 ms, and applies a 900 ms activation cooldown. Every page/source transition resets its confirmation and ignores the first 750 ms of captured MIDI. The controller must call it only after explicit opt-in, on the supported menu pages, and never during a take, MIDI learning or keyboard input. A single kick must only arm confirmation; moving the selection must cancel that arm.

Use the raw receipt and the connection status together when diagnosing a silent first hit. Do not compensate for a missing raw packet by changing timing offset. Physical latency and audio quality still require a real-module session and a separately described measurement setup.
