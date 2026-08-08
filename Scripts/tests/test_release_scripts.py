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
