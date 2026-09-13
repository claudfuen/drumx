"""Signing orchestration contracts without keys, devices, network, or codesign."""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("macos_release_signing", ROOT / "scripts/sign-macos-release.py")
signing = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = signing
spec.loader.exec_module(signing)
TEAM = "ABCDEFGHIJ"
IDENTITY = f"Developer ID Application: Fixture Company ({TEAM})"
FINGERPRINT = "A" * 40
SUBMISSION = "11223344-5566-7788-9900-aabbccddeeff"


def environment():
    return {"MACOS_SIGNING_ENABLED": "true", "MACOS_CERTIFICATE_P12_BASE64": base64.b64encode(b"fixture-certificate").decode(),
            "MACOS_CERTIFICATE_PASSWORD": "private-fixture-p12", "MACOS_SIGNING_IDENTITY": IDENTITY,
            "APPLE_TEAM_ID": TEAM, "APPLE_ID": "fixture@example.invalid", "APPLE_APP_SPECIFIC_PASSWORD": "private-fixture-apple"}


class SigningChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.app = self.directory / "Fixture.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/Frameworks").mkdir()
        (self.app / "Contents/Resources").mkdir()
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Fixture"}))
        (self.app / "Contents/MacOS/Fixture").write_bytes(b"\xcf\xfa\xed\xfeexecutable")
        (self.app / "Contents/Frameworks/engine.dylib").write_bytes(b"\xcf\xfa\xed\xfelibrary")
        (self.app / "Contents/Resources/not-code.dat").write_bytes(b"resource")
        self.calls = []
        self.entitlements = None
        self.config = signing.Configuration.from_environment(environment())

    def tearDown(self):
        self.temporary.cleanup()

    def runner(self, command, phase, timeout=120):
        self.calls.append((command, phase, timeout))
        if "--entitlements" in command:
            self.entitlements = plistlib.loads(Path(command[command.index("--entitlements") + 1]).read_bytes())
        if command[:2] == ["security", "find-identity"]: return f'  1) {FINGERPRINT} "{IDENTITY}"\n'
        if command[:2] == ["codesign", "--display"]:
            return f"Authority={IDENTITY}\nTeamIdentifier={TEAM}\nCodeDirectory flags=0x10000(runtime)\nTimestamp=Sep 12, 2026\n"
        if command[:3] == ["xcrun", "notarytool", "submit"]: return json.dumps({"id": SUBMISSION, "status": "Accepted"})
        if command[:3] == ["xcrun", "notarytool", "log"]: return json.dumps({"status": "Accepted", "issues": None})
        if command[0] == "spctl": return "Fixture.app: accepted\nsource=Notarized Developer ID\n"
        return ""

    def test_explicit_approved_developer_id_team_is_required(self):
        for identity in [f"Apple Distribution: Fixture Company ({TEAM})", f"Developer ID Application: Other Team (0123456789)", IDENTITY + "\n"]:
            changed = environment(); changed["MACOS_SIGNING_IDENTITY"] = identity
            with self.subTest(identity=identity), self.assertRaises(signing.SigningError):
                signing.Configuration.from_environment(changed)
        with self.assertRaises(signing.SigningError): signing.Configuration.from_environment({"MACOS_SIGNING_ENABLED": "false"})

    def test_missing_or_invalid_secrets_fail_before_any_external_command(self):
        for name in environment():
            changed = environment(); changed.pop(name)
            with self.subTest(name=name), self.assertRaises(signing.SigningError): signing.Configuration.from_environment(changed)
        changed = environment(); changed["MACOS_CERTIFICATE_P12_BASE64"] = "!not base64!"
        with self.assertRaises(signing.SigningError): signing.Configuration.from_environment(changed)
        self.assertNotIn("private-fixture", repr(self.config))

    def test_exact_imported_identity_is_required(self):
        for listing in ["", f'1) {FINGERPRINT} "Apple Distribution: Fixture Company ({TEAM})"\n', f'1) {FINGERPRINT} "{IDENTITY}"\n2) {"B" * 40} "{IDENTITY}"\n']:
            with self.assertRaises(signing.SigningError): signing.identity_hash(listing, IDENTITY)

    def test_signs_inside_out_then_notarizes_staples_and_verifies(self):
        result = signing.sign_app(self.app, self.config, self.runner)
        sign_calls = [command for command, _, _ in self.calls if command[0] == "codesign" and "--sign" in command]
        self.assertEqual([command[-1] for command in sign_calls], [str((self.app / "Contents/Frameworks/engine.dylib").resolve()), str(self.app.resolve())])
        self.assertTrue(all("--deep" not in command and "--timestamp" in command and "runtime" in command for command in sign_calls))
        self.assertEqual(self.entitlements, {}, "Godot GDScript and same-team extension need no runtime exceptions")
        self.assertEqual(result["notarization_id"], SUBMISSION)
        self.assertTrue(result["signed"] and result["notarized"] and result["stapled"] and result["gatekeeper_verified"])
        self.assertNotIn("private-fixture", json.dumps(result))
        self.assertEqual(self.calls[-1][0][:2], ["security", "delete-keychain"])
        keychain = Path(self.calls[-1][0][-1])
        self.assertFalse(keychain.parent.exists(), "temporary key and credential files removed")
        submission = next(item for item in self.calls if item[0][:3] == ["xcrun", "notarytool", "submit"])
        self.assertEqual(submission[2], 1260)
        self.assertIn("20m", submission[0])
        self.assertNotIn(self.config.apple_password, submission[0], "submit uses temporary keychain profile")

    def test_rejected_notary_receipt_never_staples_or_returns_release_evidence(self):
        def runner(command, phase, timeout=120):
            output = self.runner(command, phase, timeout)
            if command[:3] == ["xcrun", "notarytool", "submit"]: return json.dumps({"id": SUBMISSION, "status": "Invalid"})
            return output
        with self.assertRaises(signing.SigningError): signing.sign_app(self.app, self.config, runner)
        self.assertFalse(any(command[:2] == ["xcrun", "stapler"] for command, _, _ in self.calls))
        self.assertEqual(self.calls[-1][0][:2], ["security", "delete-keychain"])

    def test_notary_warnings_require_review_even_after_acceptance(self):
        def runner(command, phase, timeout=120):
            output = self.runner(command, phase, timeout)
            if command[:3] == ["xcrun", "notarytool", "log"]: return json.dumps({"status": "Accepted", "issues": [{"severity": "warning"}]})
            return output
        with self.assertRaises(signing.SigningError): signing.sign_app(self.app, self.config, runner)
        self.assertFalse(any(command[0] == "spctl" for command, _, _ in self.calls))

    def test_signature_readback_and_gatekeeper_must_match(self):
        for replacement in [f"Authority={IDENTITY}\nTeamIdentifier=0123456789\n", f"Authority={IDENTITY}\nTeamIdentifier={TEAM}\n"]:
            with self.assertRaises(signing.SigningError): signing.verify_identity(replacement, self.config)
        def runner(command, phase, timeout=120):
            output = self.runner(command, phase, timeout)
            return "accepted\nsource=Developer ID" if command[0] == "spctl" else output
        with self.assertRaises(signing.SigningError): signing.sign_app(self.app, self.config, runner)

    def test_secret_output_and_command_arguments_are_never_echoed_on_tool_failure(self):
        buffer = io.StringIO()
        secret = "do-not-echo-this-secret"
        with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
            with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess(["security", secret], 1, secret, secret)):
                with self.assertRaises(signing.SigningError) as caught: signing.run(["security", secret], "Certificate import")
            self.assertNotIn(secret, str(caught.exception))
            with patch.object(signing.subprocess, "run", side_effect=subprocess.TimeoutExpired(["security", secret], 10, output=secret)):
                with self.assertRaises(signing.SigningError) as caught: signing.run(["security", secret], "Certificate import")
            self.assertNotIn(secret, str(caught.exception))
        self.assertNotIn(secret, buffer.getvalue())

    def test_unrelated_child_tools_do_not_inherit_private_signing_environment(self):
        with patch.dict(signing.os.environ, environment()), patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess(["codesign"], 0, "", "")) as invoked:
            signing.run(["codesign", "--verify", "Fixture.app"], "Verify app")
        child = invoked.call_args.kwargs["env"]
        self.assertNotIn("MACOS_CERTIFICATE_P12_BASE64", child)
        self.assertNotIn("MACOS_CERTIFICATE_PASSWORD", child)
        self.assertNotIn("APPLE_APP_SPECIFIC_PASSWORD", child)

    def test_stale_success_receipt_removed_if_signing_configuration_is_missing(self):
        metadata = self.directory / "signing.json"; metadata.write_text('{"signed":true}')
        with patch.dict(signing.os.environ, {}, clear=True), patch.object(sys, "argv", ["sign", "--app", str(self.app), "--metadata", str(metadata)]), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(signing.main(), 1)
        self.assertFalse(metadata.exists())

    def test_unknown_nested_bundle_or_symlink_requires_explicit_signing_support(self):
        nested = self.app / "Contents/Frameworks/Unknown.framework"; nested.mkdir()
        with self.assertRaises(signing.SigningError): signing.sign_targets(self.app)
        nested.rmdir()
        link = self.app / "Contents/Resources/alias"; link.symlink_to("not-code.dat")
        with self.assertRaises(signing.SigningError): signing.sign_targets(self.app)

    def test_notary_receipt_must_be_valid_json_with_accepted_status_and_uuid(self):
        for receipt in ["", "[]", '{"id":"not-a-uuid","status":"Accepted"}', json.dumps({"id": SUBMISSION, "status": "In Progress"})]:
            with self.subTest(receipt=receipt), self.assertRaises(signing.SigningError): signing.accepted_submission(receipt)


if __name__ == "__main__": unittest.main()
