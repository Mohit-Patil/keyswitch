from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts import release_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        (self.root / "KeySwitch.xcodeproj").mkdir()
        (self.root / "docs").mkdir()
        (self.root / "project.yml").write_text(
            'MARKETING_VERSION: "1.2.3"\nCURRENT_PROJECT_VERSION: "8"\n',
            encoding="utf-8",
        )
        (self.root / "KeySwitch.xcodeproj" / "project.pbxproj").write_text(
            "MARKETING_VERSION = 1.2.3;\n"
            "CURRENT_PROJECT_VERSION = 8;\n",
            encoding="utf-8",
        )
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\n## [1.2.3] - 2026-08-07\n",
            encoding="utf-8",
        )
        self.write_appcast("1.2.2", 7)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_appcast(self, version: str, build: int) -> None:
        (self.root / "docs" / "appcast.xml").write_text(
            "<?xml version=\"1.0\"?>\n"
            "<rss xmlns:sparkle=\"http://www.andymatuschak.org/"
            "xml-namespaces/sparkle\" version=\"2.0\">\n"
            "  <channel><item>\n"
            f"    <sparkle:version>{build}</sparkle:version>\n"
            f"    <sparkle:shortVersionString>{version}"
            "</sparkle:shortVersionString>\n"
            "  </item></channel>\n"
            "</rss>\n",
            encoding="utf-8",
        )

    def test_valid_release_metadata(self) -> None:
        self.assertEqual(
            release_metadata.load_project_metadata(self.root),
            ("1.2.3", 8),
        )
        release_metadata.validate_changelog(self.root, "1.2.3")
        versions, latest_build = release_metadata.load_appcast_metadata(
            self.root / "docs" / "appcast.xml"
        )
        self.assertEqual(versions, {"1.2.2": 7})
        self.assertEqual(latest_build, 7)

    def test_rejects_generated_project_version_drift(self) -> None:
        (self.root / "KeySwitch.xcodeproj" / "project.pbxproj").write_text(
            "MARKETING_VERSION = 1.2.2;\n"
            "CURRENT_PROJECT_VERSION = 8;\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
            release_metadata.ReleaseMetadataError,
            "out of sync",
        ):
            release_metadata.load_project_metadata(self.root)

    def test_rejects_duplicate_appcast_version(self) -> None:
        feed_path = self.root / "docs" / "appcast.xml"
        duplicate_item = (
            "<item><sparkle:version>6</sparkle:version>"
            "<sparkle:shortVersionString>1.2.2"
            "</sparkle:shortVersionString></item>"
        )
        feed_path.write_text(
            feed_path.read_text(encoding="utf-8").replace(
                "</channel>",
                f"{duplicate_item}</channel>",
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
            release_metadata.ReleaseMetadataError,
            "duplicate version",
        ):
            release_metadata.load_appcast_metadata(feed_path)


if __name__ == "__main__":
    unittest.main()
