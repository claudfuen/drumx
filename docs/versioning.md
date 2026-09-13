# Versions and releases

`VERSION` is the shared product version, initially `0.1.0`. Each desktop CI run produces a numbered experimental release such as `0.1.0-preview.34`, tagged `v0.1.0-preview.34`. The number comes from that workflow's run number, so retrying failed jobs retains the original version. Bump the product version intentionally when the next milestone warrants it.

Both apps show the version and source commit in the main menu. Open **Build details** to copy the complete version, commit, and source state into a bug report. Native builds embed the same identity in their app resources and macOS metadata. Shared builds embed it in the game, macOS/Windows metadata, ZIP-root `build-info.json`, and both package manifests.

Local builds use `0.1.0-dev+<commit>` and append `.dirty` when there are uncommitted changes. An unstamped editor build says version unavailable. Neither case identifies itself as a published version.

## Automated publication

1. Resolve the version from `VERSION`, the workflow run number, and the checked-out commit.
2. Build both platforms. Run the source and exported application checks on their target operating systems, requiring both executables to report their embedded identity.
3. Verify that both packages are clean and share the complete build identity, course, fonts, samples, and licensing. Check the manifests inside the ZIPs as well as their outer manifests.
4. Create the immutable Git tag and publish a numbered experimental GitHub release with both ZIPs, licenses, checksums, and a build manifest. Existing tags and assets are never replaced.
5. Update only the marked README download section to the verified release. Concurrent edits elsewhere in the README are preserved, and an older run cannot move the links backward.

The README badges show workflow status, release version, downloads, and license. GitHub excludes prereleases from its built-in Latest shortcut, so CI writes exact verified download links instead of relying on `/releases/latest/download`. [GitHub release API](https://docs.github.com/en/rest/releases/releases)

These remain **experimental releases** while the [quality gate](premium-quality-gate.md) is open. A release number establishes identity and reproducibility; it does not claim stable quality or Apple notarization. Signing status appears in the release notes and manifest. [Apple signing setup](apple-signing.md)

## Troubleshooting a build

Include the copied build details, operating system, connected kit, and the action that failed. For a downloaded package, retain `build-info.json` and `build-manifest.json`. The version locates its GitHub release; the commit locates the exact source.

The pure build identity helper is `scripts/build-version.py`. Packaging stamps a disposable copy of the Godot project so export metadata cannot dirty the tracked source or make a clean manifest misleading.
