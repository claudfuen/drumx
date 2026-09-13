# Apple signing and notarization

The release pipeline has a Developer ID signing path. **It is not yet verified with a real signing certificate or Apple notarization receipt.** Automated tests exercise the command ordering, identity boundary, credential cleanup and rejection paths without using private keys or contacting Apple.

Claudio selected the **LeapLabs Apple Developer team, `SBDQQVGXVD`**. The locally discovered Apple Distribution identity does not qualify for direct macOS distribution. A **Developer ID Application** certificate with its private key is required; this pipeline does not export or repurpose the existing company certificate. Apple distinguishes these certificate types in its [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## GitHub configuration

Configure the repository or a protected release environment with the following values. Keep signing credentials restricted to trusted release code. Pull requests must not receive them.

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `MACOS_SIGNING_ENABLED` | Exactly `true` enables the required signing path; otherwise builds remain experimental and ad-hoc signed. |
| Variable | `APPLE_TEAM_ID` | `SBDQQVGXVD` for the selected LeapLabs account. |
| Variable | `MACOS_SIGNING_IDENTITY` | The exact common name of the approved certificate, beginning `Developer ID Application:` and ending `(SBDQQVGXVD)`. Use the certificate’s actual legal name. |
| Secret | `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the approved Developer ID Application certificate **and private key**, exported as an encrypted `.p12`. |
| Secret | `MACOS_CERTIFICATE_PASSWORD` | That `.p12` export password. |
| Secret | `APPLE_ID` | Apple account authorized to notarize for the selected team. |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for that Apple account. |

The account holder or a team member with certificate permissions must obtain the correct certificate. Never paste private keys, certificate exports, or passwords into issues, tracked files, chat messages, workflow source, or release notes. Set secrets through GitHub’s protected secret interface. The repository variable `APPLE_TEAM_ID` is configured as `SBDQQVGXVD`. The certificate and notarization secrets are not configured; Developer ID signing remains disabled until they are supplied.

Apple’s supported workflow uses `notarytool`, with credentials held in a keychain profile. An app-specific password is the currently implemented authentication option. Supporting an App Store Connect API key later requires a separate explicit configuration path; the script does not infer credentials from the operator’s personal keychain. See Apple’s [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Pipeline contract

After the complete app has been exported, thinned to its target architecture, and supplied with its notices, the packager invokes:

```sh
python3 scripts/sign-macos-release.py --app /path/to/Drumx.app --metadata /path/to/signing.json
```

The helper requires macOS and `MACOS_SIGNING_ENABLED=true`. Missing credentials, an unexpected identity/team, an invalid certificate, rejected notarization, a warning in Apple’s notarization log, or failed signature/ticket/Gatekeeper verification fails the build. There is no automatic fallback from requested Developer ID signing to an experimental ad-hoc build.

The helper:

1. Creates a randomly password-protected temporary keychain and private certificate file. It does not modify the operator’s normal keychain search list.
2. Imports the supplied `.p12`, verifies the exact approved identity, and uses that certificate’s fingerprint for signing.
3. Signs each bundled Mach-O library explicitly before sealing the app. Signing never uses recursive `codesign --deep`. Unexpected nested bundles or symlink layouts fail until explicit signing support is reviewed.
4. Enables hardened runtime and secure timestamps. The release entitlement file grants no runtime exceptions: Drumx uses GDScript without JIT, and its bundled GDExtension is signed by the same team. Library validation therefore remains enabled. Apple permits loading libraries signed by the [same Team ID](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation). The experimental ad-hoc export has different requirements. Any future third-party plug-ins, microphone capture or managed runtime need an explicit entitlement review; [Godot documents those options](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html).
5. Reads back the app’s Developer ID authority, Team ID, hardened runtime flag and timestamp, then verifies the complete signature.
6. Stores notarization credentials only in the temporary keychain, submits a temporary ZIP, and waits for up to 20 minutes. A timeout fails this build; Apple may still finish processing the submitted job afterward.
7. Requires an `Accepted` response and an issue-free notarization log, staples the ticket to the app, validates it, and requires Gatekeeper to report `Notarized Developer ID`.
8. Deletes the temporary keychain and files, then emits a metadata receipt. Failed retries remove an existing receipt rather than leaving stale success evidence.

The packager executes its smoke checks on the resulting app and creates the downloadable ZIP **after stapling**. Editing app resources after signing invalidates its seal. The final paired manifest must identify whether the actual Mac artifact is ad-hoc or Developer ID signed and notarized; Windows signing is a separate platform concern.

A successful receipt contains `signed`, `notarized`, `signature_type`, `signing_identity`, `team_id`, `notarization_id`, `notarization_status`, `stapled`, and `gatekeeper_verified`. It contains no passwords or private-key material. Subprocess commands and raw tool diagnostics are withheld from logs because they can contain credentials. A real failed Apple submission may require the authorized operator to retrieve and review its notarization log in a trusted environment.

## Acceptance still required

Before describing the Mac download as a verified signed release, require all of the following on the same candidate: real Developer ID identity read-back for the selected team, Apple’s `Accepted` receipt, successful stapler and Gatekeeper verification, packaged smoke success, and first launch of the downloaded ZIP on a Mac with quarantine metadata intact. Automated command-contract tests cannot establish that a certificate is valid, that Apple accepted the app, or that a physical first launch succeeds.

Sources checked September 12, 2026.
