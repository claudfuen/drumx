# Menu and library quality gate

This pass improves the existing routes before adding more destinations. It is part of the open [M1 quality gate](premium-quality-gate.md).

## Navigation contract

- Main menu groups Continue and its progress, Learn, and Songs above a quieter Settings utility. Shared desktop builds expose their supported course and Settings routes.
- Learn features one lesson and one play action. Its state reads Your next step, Available to play, Locked, or Checkpoint earned. Inspecting a locked lesson never starts it.
- Contextual exits name the destination: Learn, Lesson, Review, or Songs. Avoid two controls that do the same thing. Escape closes an overlay first, pauses active playing, and otherwise returns to the main menu.
- Settings is organized by Kit, Sound, Controls, and Players on native Mac; the shared app has Progress in place of Players. Changes retain their existing automatic-save behavior.
- Every new page gives a visible control keyboard focus. Return activates it once. Drum menu selection and keyboard focus must agree.

## Acceptance

| Area | Required result |
| --- | --- |
| Main menu and Learn | One clear primary action, supporting progress near that action, inspectable future lessons, and no duplicate exits. |
| Settings | Quiet section navigation, readable rows, consistently aligned controls, and reachable overflow content. |
| Window sizes | Essential content and targets remain usable at the minimum window, normal desktop size, and a large display. Resizing never changes a control's hit geometry independently of its rendering. |
| Large song library | Search, sort, selection, difficulty choice, audio preview, and Play work with the real collection. Scrolling must reuse rows and selection must not block on artwork or full audio decoding. |
| Refresh | A visible index-refresh action reports additions and skipped/failed songs. Keep the current selection if it still exists. An unchanged refresh must not reread the full audio collection. |
| Preview lifecycle | A selected song can be heard before starting a run. Stopping, changing songs, or leaving the browser cancels pending work and prevents stale playback. Audio failures leave the browser usable. |
| Installation | The verified native app launches from `/Applications/Drumx.app` and retains its existing library and progress. Replacing the bundle does not erase saves. |

Native menu and settings controls have automated geometry, focus, and activation coverage. Real-window review and full-library browser verification are required in addition to those checks. Windows visual acceptance, physical MIDI latency, and the full 30-minute beginner session remain separate open gates.

## Local installation

After building and validating the native app, quit an older installed copy and run:

```sh
bash scripts/install-macos-lab.sh
open /Applications/Drumx.app
```

The installer keeps the same application identity, verifies the bundle signature, and retains the previous bundle under ignored `.build/installed-backups`. It will not replace an app that is still running. These local development installations use ad-hoc signing; Apple notarization is a separate distribution step.
