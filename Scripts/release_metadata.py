#!/usr/bin/env python3
"""Validate and expose the release metadata shared by local and CI builds."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SEMVER_PATTERN = re.compile(
    r"^(?P<version>0|[1-9]\d*)\."
    r"(0|[1-9]\d*)\."
    r"(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?"
    r"(?:\+[0-9A-Za-z.-]+)?$"
)
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class ReleaseMetadataError(RuntimeError):
    """Raised when committed release metadata is inconsistent."""


def extract_single(pattern: str, text: str, label: str) -> str:
    values = re.findall(pattern, text, flags=re.MULTILINE)
    if len(values) != 1:
        raise ReleaseMetadataError(
            f"expected exactly one {label} in project.yml; found {len(values)}"
        )
    return values[0]


def load_project_metadata(repository_root: Path) -> tuple[str, int]:
    project_text = (repository_root / "project.yml").read_text(encoding="utf-8")
    version = extract_single(
        r'^\s*MARKETING_VERSION:\s*["\']?([^"\'\s#]+)',
        project_text,
        "MARKETING_VERSION",
    )
    build_text = extract_single(
        r'^\s*CURRENT_PROJECT_VERSION:\s*["\']?([^"\'\s#]+)',
        project_text,
        "CURRENT_PROJECT_VERSION",
    )

    if not SEMVER_PATTERN.fullmatch(version):
        raise ReleaseMetadataError(f"invalid MARKETING_VERSION: {version}")
    if not re.fullmatch(r"[1-9]\d*", build_text):
        raise ReleaseMetadataError(
            f"CURRENT_PROJECT_VERSION must be a positive integer: {build_text}"
        )

    project_file = repository_root / "KeySwitch.xcodeproj" / "project.pbxproj"
    generated_text = project_file.read_text(encoding="utf-8")
    generated_versions = set(
        re.findall(r"MARKETING_VERSION = ([^;]+);", generated_text)
    )
    generated_builds = set(
        re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", generated_text)
    )
    if generated_versions != {version}:
        raise ReleaseMetadataError(
            "KeySwitch.xcodeproj is out of sync with project.yml marketing version"
        )
    if generated_builds != {build_text}:
        raise ReleaseMetadataError(
            "KeySwitch.xcodeproj is out of sync with project.yml build version"
        )

    return version, int(build_text)


def validate_changelog(repository_root: Path, version: str) -> None:
    changelog = (repository_root / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = re.compile(
        rf"^## \[{re.escape(version)}\](?: - \d{{4}}-\d{{2}}-\d{{2}})?\s*$",
        flags=re.MULTILINE,
    )
    if not heading.search(changelog):
        raise ReleaseMetadataError(
            f"CHANGELOG.md has no release section for {version}"
        )


def load_appcast_metadata(feed_path: Path) -> tuple[dict[str, int], int]:
    root = ET.parse(feed_path).getroot()
    versions: dict[str, int] = {}

    for item in root.findall("./channel/item"):
        short_version = item.findtext(f"{{{SPARKLE_NAMESPACE}}}shortVersionString")
        build_text = item.findtext(f"{{{SPARKLE_NAMESPACE}}}version")
        if not short_version or not build_text:
            raise ReleaseMetadataError("appcast item is missing Sparkle version metadata")
        if short_version in versions:
            raise ReleaseMetadataError(
                f"appcast contains duplicate version {short_version}"
            )
        if not re.fullmatch(r"[1-9]\d*", build_text):
            raise ReleaseMetadataError(
                f"appcast build must be a positive integer: {build_text}"
            )
        versions[short_version] = int(build_text)

    return versions, max(versions.values(), default=0)


def write_github_output(path: Path, values: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--tag",
        help="Release tag to validate. Defaults to v<MARKETING_VERSION>.",
    )
    parser.add_argument(
        "--github-output",
        type=Path,
        help="Append validated key/value pairs to a GitHub Actions output file.",
    )
    parser.add_argument(
        "--appcast",
        type=Path,
        help="Appcast to validate. Defaults to docs/appcast.xml.",
    )
    arguments = parser.parse_args()

    repository_root = Path(__file__).resolve().parent.parent
    version, build = load_project_metadata(repository_root)
    tag = arguments.tag or f"v{version}"
    if not tag.startswith("v") or not SEMVER_PATTERN.fullmatch(tag[1:]):
        raise ReleaseMetadataError(f"release tag must look like v1.2.3: {tag}")
    if tag[1:] != version:
        raise ReleaseMetadataError(
            f"tag {tag} does not match project version {version}"
        )

    validate_changelog(repository_root, version)
    feed_path = arguments.appcast or repository_root / "docs" / "appcast.xml"
    published_versions, latest_build = load_appcast_metadata(feed_path)
    published_build = published_versions.get(version)
    already_published = published_build is not None

    if published_build is not None and published_build != build:
        raise ReleaseMetadataError(
            f"appcast version {version} uses build {published_build}, not {build}"
        )
    if published_build is None and build <= latest_build:
        raise ReleaseMetadataError(
            f"build {build} must be newer than appcast build {latest_build}"
        )

    values = {
        "tag": tag,
        "version": version,
        "build": str(build),
        "latest_feed_build": str(latest_build),
        "already_published": str(already_published).lower(),
    }
    if arguments.github_output:
        write_github_output(arguments.github_output, values)

    for key, value in values.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ET.ParseError, ReleaseMetadataError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
