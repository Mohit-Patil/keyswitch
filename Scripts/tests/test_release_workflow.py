from __future__ import annotations

import unittest
from pathlib import Path


class ReleaseWorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = (
            Path(__file__).resolve().parents[2]
            / ".github"
            / "workflows"
            / "release.yml"
        ).read_text(encoding="utf-8")

    def test_main_release_is_triggered_by_completed_ci_not_direct_push(self) -> None:
        trigger = self.workflow.split("permissions:", maxsplit=1)[0]
        self.assertIn('workflow_run:\n    workflows: ["CI"]', trigger)
        self.assertIn("types: [completed]", trigger)
        self.assertIn("branches:\n      - main", trigger)
        self.assertIn('push:\n    tags:\n      - "v*"', trigger)
        self.assertNotIn("push:\n    branches:", trigger)

    def test_privileged_ci_trigger_is_restricted_to_successful_main_push(self) -> None:
        self.assertIn(
            "github.event.workflow_run.conclusion == 'success'",
            self.workflow,
        )
        self.assertIn(
            "github.event.workflow_run.event == 'push'",
            self.workflow,
        )
        self.assertIn(
            "github.event.workflow_run.head_repository.full_name == github.repository",
            self.workflow,
        )
        self.assertIn('test "$TESTED_BRANCH" = "main"', self.workflow)
        self.assertIn('test "$TESTED_REPOSITORY" = "$GITHUB_REPOSITORY"', self.workflow)

    def test_release_checks_out_and_verifies_the_ci_tested_sha(self) -> None:
        self.assertIn("github.event.workflow_run.head_sha", self.workflow)
        self.assertIn('test "$(git rev-parse HEAD)" = "$TESTED_SHA"', self.workflow)
        self.assertIn(
            'git merge-base --is-ancestor "$TESTED_SHA" origin/main',
            self.workflow,
        )

    def test_release_resigns_nested_sparkle_components(self) -> None:
        self.assertIn("Scripts/sign_release_app.sh", self.workflow)
        self.assertIn('"$DEVELOPER_IDENTITY"', self.workflow)
        self.assertIn('"$DEVELOPER_TEAM_ID"', self.workflow)

    def test_notarization_uses_diagnostic_wrapper_for_app_and_dmg(self) -> None:
        self.assertEqual(
            self.workflow.count("Scripts/notarize_artifact.sh"),
            2,
        )
        self.assertNotIn("xcrun notarytool submit", self.workflow)


if __name__ == "__main__":
    unittest.main()
