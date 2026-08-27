#!/usr/bin/env python3
"""Run zero-dependency structural checks and regression tests for this skill."""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parent
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TOP_LEVEL_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")


def validate_frontmatter(skill_dir):
    errors = []
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.is_file():
        return ["missing SKILL.md"]

    lines = skill_file.read_text(encoding="utf-8-sig").splitlines()
    if not lines or lines[0].strip() != "---":
        return ["SKILL.md: frontmatter must start with ---"]

    try:
        end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        return ["SKILL.md: frontmatter closing --- not found"]

    keys = {}
    for line in lines[1:end]:
        if not line or line[0].isspace():
            continue
        match = TOP_LEVEL_KEY_RE.match(line)
        if not match:
            errors.append(f"SKILL.md: invalid frontmatter line: {line!r}")
            continue
        key, value = match.groups()
        if key in keys:
            errors.append(f"SKILL.md: duplicate frontmatter key: {key}")
        keys[key] = (value or "").strip()

    expected = {"name", "description"}
    if set(keys) != expected:
        errors.append(
            "SKILL.md: frontmatter keys must be exactly name and description "
            f"(found: {', '.join(sorted(keys)) or 'none'})"
        )

    name = keys.get("name", "")
    if not NAME_RE.fullmatch(name):
        errors.append("SKILL.md: name must use lowercase letters, digits, and hyphens")
    if name and name != skill_dir.name:
        errors.append(f"SKILL.md: name {name!r} must match folder {skill_dir.name!r}")

    description_line = keys.get("description", "")
    description_index = next(
        (i for i, line in enumerate(lines[1:end], 1) if line.startswith("description:")),
        None,
    )
    description_body = []
    if description_index is not None:
        for line in lines[description_index + 1 : end]:
            if line and not line[0].isspace():
                break
            description_body.append(line.strip())
    block_markers = {"", ">", "|", ">-", "|-"}
    if description_line in block_markers and not any(description_body):
        errors.append("SKILL.md: description must not be empty")
    return errors


def validate_markdown_links(skill_dir):
    errors = []
    for markdown in sorted(skill_dir.rglob("*.md")):
        text = markdown.read_text(encoding="utf-8-sig")
        text_without_inline_code = INLINE_CODE_RE.sub("", text)
        for raw_target in MARKDOWN_LINK_RE.findall(text_without_inline_code):
            target = raw_target.strip().strip("<>").split("#", 1)[0]
            if not target or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
                continue
            resolved = (markdown.parent / target).resolve()
            if not resolved.exists():
                errors.append(f"{markdown.relative_to(skill_dir)}: missing link target {target!r}")
    return errors


def validate_regression_cases(skill_dir):
    errors = []
    case_dir = skill_dir / "tests" / "regressions"
    for case_path in sorted(case_dir.glob("*.json")):
        try:
            case = json.loads(case_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{case_path.relative_to(skill_dir)}: invalid JSON: {exc}")
            continue
        for key in ("id", "kind", "assertions"):
            if key not in case:
                errors.append(f"{case_path.relative_to(skill_dir)}: missing key {key!r}")
        if case.get("kind") not in {"build_arg"}:
            errors.append(
                f"{case_path.relative_to(skill_dir)}: unsupported kind {case.get('kind')!r}"
            )
        if not isinstance(case.get("assertions"), list) or not case.get("assertions"):
            errors.append(f"{case_path.relative_to(skill_dir)}: assertions must be a non-empty list")
    return errors


def run_tests(skill_dir):
    command = [
        sys.executable,
        "-m",
        "unittest",
        "discover",
        "-s",
        str(skill_dir / "tests"),
        "-p",
        "test_*.py",
        "-v",
    ]
    return subprocess.run(command, cwd=skill_dir, check=False).returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-tests", action="store_true", help="run structural checks only")
    args = parser.parse_args(argv)

    errors = []
    errors.extend(validate_frontmatter(SKILL_DIR))
    errors.extend(validate_markdown_links(SKILL_DIR))
    errors.extend(validate_regression_cases(SKILL_DIR))

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
    else:
        print("OK: skill structure, links, and regression cases")

    test_rc = 0 if args.skip_tests else run_tests(SKILL_DIR)
    if test_rc:
        print("ERROR: regression tests failed")
    elif not args.skip_tests:
        print("OK: regression tests")
    return 1 if errors or test_rc else 0


if __name__ == "__main__":
    raise SystemExit(main())
