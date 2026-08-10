from __future__ import annotations

import unittest
from pathlib import Path


class ReleaseWorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[2]
        cls.workflow = (
            cls.repository_root / ".github" / "workflows" / "release.yml"
        ).read_text(encoding="utf-8")
        cls.feed_workflow = (
            cls.repository_root / ".github" / "workflows" / "publish-feed.yml"
        ).read_text(encoding="utf-8")
        cls.generate_script = (
            cls.repository_root / "Scripts" / "generate_update_appcast.sh"
        ).read_text(encoding="utf-8")
        cls.publish_script = (
            cls.repository_root / "Scripts" / "publish_update_feed.sh"
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

    def test_every_release_entry_point_requires_successful_main_ci(self) -> None:
        self.assertIn("actions: read", self.workflow)
        self.assertIn(
            "Require successful main CI for the exact source",
            self.workflow,
        )
        self.assertIn(
            '"repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs"',
            self.workflow,
        )
        self.assertIn('-f head_sha="$source_sha"', self.workflow)
        self.assertIn('.head_branch == \\"main\\"', self.workflow)
        self.assertIn('.conclusion == \\"success\\"', self.workflow)
        self.assertIn("for ci_lookup_attempt in {1..6}", self.workflow)

    def test_release_resigns_nested_sparkle_components(self) -> None:
        self.assertIn("Scripts/sign_release_app.sh", self.workflow)
        self.assertIn('"$DEVELOPER_IDENTITY"', self.workflow)
        self.assertIn('"$DEVELOPER_TEAM_ID"', self.workflow)

    def test_runner_default_keychain_path_is_normalized_before_export(self) -> None:
        self.assertIn(
            "security default-keychain -d user |\n"
            "              Scripts/normalize_keychain_path.sh",
            self.workflow,
        )
        self.assertIn(
            'echo "ORIGINAL_DEFAULT_KEYCHAIN_PATH=$original_default_keychain"',
            self.workflow,
        )

    def test_notarization_uses_diagnostic_wrapper_for_app_and_dmg(self) -> None:
        self.assertEqual(
            self.workflow.count("Scripts/notarize_artifact.sh"),
            2,
        )
        self.assertNotIn("xcrun notarytool submit", self.workflow)

    def test_sparkle_feed_signing_never_imports_the_key_into_keychain(self) -> None:
        signing_sources = "\n".join(
            (
                self.workflow,
                self.feed_workflow,
                self.generate_script,
                self.publish_script,
            )
        )
        self.assertNotIn("generate_keys", signing_sources)
        self.assertNotIn("delete-generic-password", signing_sources)
        self.assertNotIn("--account", self.generate_script)
        self.assertNotIn("--account", self.publish_script)
        self.assertIn('--ed-key-file "$sparkle_private_key_path"', self.generate_script)
        self.assertIn('--ed-key-file "$sparkle_private_key_path"', self.publish_script)

    def test_existing_release_can_be_published_through_feed_only_workflow(self) -> None:
        self.assertIn("workflow_dispatch:", self.feed_workflow)
        self.assertIn("version:", self.feed_workflow)
        self.assertIn('ref: main', self.feed_workflow)
        self.assertIn('gh release download "$release_tag"', self.feed_workflow)
        self.assertIn("Scripts/publish_update_feed.sh", self.feed_workflow)
        self.assertIn("gh workflow run pages.yml --ref main", self.feed_workflow)

    def test_feed_merge_waits_for_the_pr_attached_protected_check(self) -> None:
        self.assertIn("--json statusCheckRollup", self.publish_script)
        self.assertIn(
            'select(.__typename == "CheckRun" and .name == "Test")',
            self.publish_script,
        )
        self.assertIn("ascii_downcase", self.publish_script)
        self.assertIn('conclusion == \\"action_required\\"', self.publish_script)
        self.assertNotIn("gh workflow run ci.yml", self.publish_script)

    def test_release_treats_protected_feed_approval_as_a_handoff(self) -> None:
        self.assertIn("return 75", self.publish_script)
        self.assertIn('if [[ "$feed_status" -eq 75 ]]', self.workflow)
        self.assertIn("Sparkle feed approval required", self.workflow)
        self.assertNotIn('if [[ "$feed_status" -eq 75 ]]', self.feed_workflow)

    def test_sparkle_secret_is_only_written_to_an_ephemeral_file(self) -> None:
        for workflow in (self.workflow, self.feed_workflow):
            self.assertIn('umask 077', workflow)
            self.assertIn('printf \'%s\' "$SPARKLE_PRIVATE_KEY"', workflow)
            self.assertIn('export SPARKLE_PRIVATE_KEY_PATH="$sparkle_key_path"', workflow)
            self.assertIn('/bin/unlink "$sparkle_key_path"', workflow)


if __name__ == "__main__":
    unittest.main()
