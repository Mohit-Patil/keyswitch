#!/usr/bin/env python3

"""Render one KeySwitch changelog release as a small HTML fragment."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


SECTION_PATTERN = re.compile(r"^## \[(?P<version>[^]]+)](?:\s+-\s+.*)?$")


def inline_markup(value: str) -> str:
    parts = re.split(r"(`[^`]+`)", value)
    rendered: list[str] = []
    for part in parts:
        if part.startswith("`") and part.endswith("`"):
            rendered.append(f"<code>{html.escape(part[1:-1])}</code>")
        else:
            rendered.append(html.escape(part))
    return "".join(rendered)


def release_lines(changelog: Path, version: str) -> list[str]:
    lines = changelog.read_text(encoding="utf-8").splitlines()
    start: int | None = None

    for index, line in enumerate(lines):
        match = SECTION_PATTERN.match(line)
        if match and match.group("version") == version:
            start = index + 1
            break

    if start is None:
        raise SystemExit(f"error: CHANGELOG has no [{version}] release section")

    end = len(lines)
    for index in range(start, len(lines)):
        if SECTION_PATTERN.match(lines[index]):
            end = index
            break

    return lines[start:end]


def render_release(lines: list[str], version: str) -> str:
    output = [f"<h2>KeySwitch {html.escape(version)}</h2>"]
    list_items: list[str] = []
    paragraph: list[str] = []

    def flush_list() -> None:
        if not list_items:
            return
        output.append("<ul>")
        output.extend(f"<li>{inline_markup(item)}</li>" for item in list_items)
        output.append("</ul>")
        list_items.clear()

    def flush_paragraph() -> None:
        if not paragraph:
            return
        output.append(f"<p>{inline_markup(' '.join(paragraph))}</p>")
        paragraph.clear()

    for raw_line in lines:
        stripped = raw_line.strip()
        if not stripped:
            flush_paragraph()
            flush_list()
            continue

        if stripped.startswith("### "):
            flush_paragraph()
            flush_list()
            output.append(f"<h3>{inline_markup(stripped[4:])}</h3>")
            continue

        if stripped.startswith("- "):
            flush_paragraph()
            list_items.append(stripped[2:])
            continue

        if list_items and raw_line[:1].isspace():
            list_items[-1] = f"{list_items[-1]} {stripped}"
            continue

        flush_list()
        paragraph.append(stripped)

    flush_paragraph()
    flush_list()
    return "\n".join(output) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("changelog", type=Path)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()

    lines = release_lines(arguments.changelog, arguments.version)
    rendered = render_release(lines, arguments.version)
    arguments.output.write_text(rendered, encoding="utf-8")


if __name__ == "__main__":
    main()
