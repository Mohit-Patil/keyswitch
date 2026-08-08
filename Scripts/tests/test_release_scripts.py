from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class ReleaseScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def make_executable(self, name: str, contents: str) -> Path:
        path = self.root / name
        path.write_text(contents, encoding="utf-8")
        path.chmod(0o755)
        return path

    def normalize_keychain_path(self, value: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [REPOSITORY_ROOT / "Scripts" / "normalize_keychain_path.sh"],
            input=value,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_keychain_normalizer_handles_github_runner_security_output(self) -> None:
        result = self.normalize_keychain_path(
            '    "/Users/runner/Library/Keychains/login.keychain-db"\n'
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "/Users/runner/Library/Keychains/login.keychain-db\n",
        )

    def test_keychain_normalizer_preserves_spaces_inside_absolute_path(self) -> None:
        result = self.normalize_keychain_path(
            '  "/Users/runner/Library/Keychains/Release Login.keychain-db"  \n'
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "/Users/runner/Library/Keychains/Release Login.keychain-db\n",
        )

    def test_keychain_normalizer_rejects_unsafe_paths(self) -> None:
        for value in ("", "login.keychain-db\n", "/first\n/second\n"):
            with self.subTest(value=value):
                result = self.normalize_keychain_path(value)
                self.assertNotEqual(result.returncode, 0)

    def test_sparkle_private_key_verifier_derives_expected_public_key(self) -> None:
        private_key = self.root / "sparkle-private-key"
        private_key.write_text(
            "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=\n",
            encoding="utf-8",
        )
        expected_public_key = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

        result = subprocess.run(
            [
                "swift",
                REPOSITORY_ROOT / "Scripts" / "verify_sparkle_private_key.swift",
                private_key,
                expected_public_key,
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), expected_public_key)

    def test_sparkle_private_key_verifier_rejects_wrong_public_key(self) -> None:
        private_key = self.root / "sparkle-private-key"
        private_key.write_text(
            "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=",
            encoding="utf-8",
        )

        result = subprocess.run(
            [
                "swift",
                REPOSITORY_ROOT / "Scripts" / "verify_sparkle_private_key.swift",
                private_key,
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            ],
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_signing_script_signs_sparkle_inside_out(self) -> None:
        app = self.root / "KeySwitch.app"
        sparkle = (
            app
            / "Contents"
            / "Frameworks"
            / "Sparkle.framework"
            / "Versions"
            / "Current"
        )
        (sparkle / "XPCServices" / "Downloader.xpc").mkdir(parents=True)
        (sparkle / "XPCServices" / "Installer.xpc").mkdir()
        (sparkle / "Autoupdate").touch()
        (sparkle / "Updater.app").mkdir()
        calls = self.root / "codesign-calls"
        fake_codesign = self.make_executable(
            "codesign",
            textwrap.dedent(
                f"""\
                #!/bin/bash
                echo "$*" >> "{calls}"
                if [[ "$1" == "-dv" ]]; then
                  echo "Authority=Developer ID Application: Example (TEAMID)" >&2
                  echo "TeamIdentifier=TEAMID" >&2
                fi
                """
            ),
        )

        environment = os.environ.copy()
        environment["CODESIGN_BIN"] = str(fake_codesign)
        subprocess.run(
            [
                REPOSITORY_ROOT / "Scripts" / "sign_release_app.sh",
                app,
                "Developer ID Application: Example (TEAMID)",
                "TEAMID",
            ],
            check=True,
            env=environment,
            text=True,
            capture_output=True,
        )

        sign_calls = [
            line
            for line in calls.read_text(encoding="utf-8").splitlines()
            if " --sign " in f" {line} "
        ]
        self.assertEqual(len(sign_calls), 6)
        self.assertIn("Downloader.xpc", sign_calls[0])
        self.assertIn("Installer.xpc", sign_calls[1])
        self.assertIn("Autoupdate", sign_calls[2])
        self.assertIn("Updater.app", sign_calls[3])
        self.assertTrue(sign_calls[4].endswith("Sparkle.framework/Versions/Current"))
        self.assertTrue(sign_calls[5].endswith("KeySwitch.app"))

    def test_notarization_script_prints_rejection_issues(self) -> None:
        artifact = self.root / "KeySwitch.zip"
        api_key = self.root / "AuthKey.p8"
        artifact.touch()
        api_key.touch()
        fake_xcrun = self.make_executable(
            "xcrun",
            textwrap.dedent(
                r"""
                #!/bin/bash
                if [[ "$2" == "submit" ]]; then
                  printf '{"id":"submission-id","status":"Invalid"}\n'
                  exit 0
                fi
                if [[ "$2" == "log" ]]; then
                  cat > "$4" <<'JSON'
                {"statusSummary":"Archive contains critical validation errors",
                 "issues":[{"severity":"error","message":"The signature is invalid",
                 "path":"KeySwitch.app/Updater.app","architecture":"arm64"}]}
                JSON
                  exit 0
                fi
                exit 2
                """
            ).lstrip(),
        )

        environment = os.environ.copy()
        environment["XCRUN_BIN"] = str(fake_xcrun)
        result = subprocess.run(
            [
                REPOSITORY_ROOT / "Scripts" / "notarize_artifact.sh",
                artifact,
                api_key,
                "KEYID",
                "ISSUERID",
            ],
            check=False,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("Archive contains critical validation errors", result.stderr)
        self.assertIn("The signature is invalid", result.stderr)
        self.assertIn("Updater.app, arm64", result.stderr)

    def test_notarization_script_accepts_successful_submission(self) -> None:
        artifact = self.root / "KeySwitch.zip"
        api_key = self.root / "AuthKey.p8"
        artifact.touch()
        api_key.touch()
        fake_xcrun = self.make_executable(
            "xcrun",
            textwrap.dedent(
                r"""
                #!/bin/bash
                printf '{"id":"submission-id","status":"Accepted"}\n'
                """
            ).lstrip(),
        )

        environment = os.environ.copy()
        environment["XCRUN_BIN"] = str(fake_xcrun)
        result = subprocess.run(
            [
                REPOSITORY_ROOT / "Scripts" / "notarize_artifact.sh",
                artifact,
                api_key,
                "KEYID",
                "ISSUERID",
            ],
            check=False,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("finished with status: Accepted", result.stdout)
