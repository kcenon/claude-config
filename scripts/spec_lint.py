#!/usr/bin/env python3
"""Validate Claude Code SKILL.md frontmatter, plugin.json, and settings.json
against canonical 2026 schemas.

Usage:
    spec_lint.py --mode skill    <file> [<file> ...]
    spec_lint.py --mode plugin   <file> [<file> ...]
    spec_lint.py --mode settings <file> [<file> ...]

Options:
    --warn-only   Print violations but exit 0 (advisory mode for soft rollouts).
    --strict      Exit with code 2 (instead of 1) on violations, so CI can
                  distinguish strict-mode failures from regular violations.
    --quiet       Print only violations and the final summary line.

Exit code: 0 on success; 1 on violations (default); 2 on violations with --strict,
or on setup errors (missing PyYAML/jsonschema, missing schema file, missing input file).
"""
from __future__ import annotations

import argparse
import difflib
import json
import sys
from pathlib import Path
from typing import Iterable

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("ERROR: PyYAML not installed. Run: pip install pyyaml\n")
    sys.exit(2)

try:
    import jsonschema  # type: ignore
    from jsonschema import Draft202012Validator
except ImportError:
    sys.stderr.write("ERROR: jsonschema not installed. Run: pip install jsonschema\n")
    sys.exit(2)


SCHEMA_DIR = Path(__file__).resolve().parent / "schemas"
SCHEMA_FILES = {
    "skill":    SCHEMA_DIR / "skill-md.schema.json",
    "plugin":   SCHEMA_DIR / "plugin-json.schema.json",
    "settings": SCHEMA_DIR / "settings-json.schema.json",
}


def load_schema(mode: str) -> dict:
    path = SCHEMA_FILES[mode]
    if not path.is_file():
        raise FileNotFoundError(f"Schema not found: {path}")
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def extract_frontmatter(text: str, file_path: Path) -> tuple[dict, int]:
    """Return (parsed_frontmatter, frontmatter_start_line).

    Raises ValueError if frontmatter is missing, unterminated, or invalid YAML.
    """
    lines = text.splitlines()
    if not lines or lines[0].rstrip() != "---":
        raise ValueError(f"{file_path}:1: missing YAML frontmatter (first line must be '---')")

    end_idx = -1
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            end_idx = i
            break
    if end_idx == -1:
        raise ValueError(f"{file_path}:1: unterminated YAML frontmatter (no closing '---')")

    body = "\n".join(lines[1:end_idx])
    try:
        data = yaml.safe_load(body) or {}
    except yaml.YAMLError as exc:
        raise ValueError(f"{file_path}:1: YAML parse error: {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError(f"{file_path}:1: frontmatter must be a YAML mapping")
    return data, 2  # frontmatter content begins at line 2


def format_path(error: jsonschema.ValidationError) -> str:
    if not error.absolute_path:
        return "<root>"
    return ".".join(str(p) for p in error.absolute_path)


def known_field_names(schema: dict, instance_path: tuple) -> list[str]:
    """Return the list of declared property names for the (sub)schema at instance_path."""
    node = schema
    for key in instance_path:
        if not isinstance(node, dict):
            return []
        if "properties" in node and key in node["properties"]:
            node = node["properties"][key]
        elif "additionalProperties" in node and isinstance(node["additionalProperties"], dict):
            node = node["additionalProperties"]
        else:
            return []
    if isinstance(node, dict) and "properties" in node:
        return sorted(node["properties"].keys())
    return []


def annotate_unknown_field(message: str, schema: dict,
                           instance_path: tuple) -> str:
    """For 'Additional properties are not allowed' errors, suggest the closest known field."""
    if "Additional properties are not allowed" not in message:
        return message
    # Extract offending field names from the jsonschema message form:
    # "Additional properties are not allowed ('foo', 'bar' were unexpected)"
    # or singular "Additional properties are not allowed ('foo' was unexpected)"
    start = message.find("(")
    end = max(message.find(" were unexpected"), message.find(" was unexpected"))
    if start == -1 or end == -1:
        return message
    offenders = [
        s.strip().strip("'\"")
        for s in message[start + 1:end].split(",")
    ]
    known = known_field_names(schema, instance_path)
    if not known:
        return message
    hints = []
    for name in offenders:
        guess = difflib.get_close_matches(name, known, n=1, cutoff=0.6)
        if guess:
            hints.append(f"'{name}' (did you mean '{guess[0]}'?)")
        else:
            hints.append(f"'{name}'")
    return f"unknown field(s): {', '.join(hints)}"


def validate_instance(instance: dict, schema: dict, file_path: Path,
                      base_line: int = 1) -> list[str]:
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.absolute_path))
    messages: list[str] = []
    for err in errors:
        field = format_path(err)
        msg = annotate_unknown_field(err.message, schema, tuple(err.absolute_path))
        messages.append(f"{file_path}:{base_line}:{field}: {msg}")
    return messages


def lint_skill(file_path: Path) -> list[str]:
    try:
        text = file_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"{file_path}:1: cannot read file: {exc}"]
    try:
        data, base_line = extract_frontmatter(text, file_path)
    except ValueError as exc:
        return [str(exc)]
    schema = load_schema("skill")
    return validate_instance(data, schema, file_path, base_line)


def lint_json(file_path: Path, mode: str) -> list[str]:
    try:
        text = file_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"{file_path}:1: cannot read file: {exc}"]
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        return [f"{file_path}:{exc.lineno}: JSON parse error: {exc.msg}"]
    if not isinstance(data, dict):
        return [f"{file_path}:1: top-level value must be a JSON object"]
    schema = load_schema(mode)
    return validate_instance(data, schema, file_path, base_line=1)


def lint_files(files: Iterable[Path], mode: str) -> tuple[int, int, list[str]]:
    total_files = 0
    total_violations = 0
    all_messages: list[str] = []
    for f in files:
        total_files += 1
        if mode == "skill":
            msgs = lint_skill(f)
        else:
            msgs = lint_json(f, mode)
        if msgs:
            total_violations += len(msgs)
            all_messages.extend(msgs)
    return total_files, total_violations, all_messages


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mode", required=True, choices=["skill", "plugin", "settings"],
                        help="Validation mode.")
    parser.add_argument("--warn-only", action="store_true",
                        help="Print violations but exit 0 (advisory mode).")
    parser.add_argument("--strict", action="store_true",
                        help="Exit with code 2 (instead of 1) on violations. "
                             "Lets CI distinguish strict-mode failures from regular violations.")
    parser.add_argument("--quiet", action="store_true",
                        help="Print only violations and the final summary line.")
    parser.add_argument("files", nargs="+", help="One or more files to lint.")
    args = parser.parse_args(argv)

    paths = [Path(p) for p in args.files]
    missing = [p for p in paths if not p.is_file()]
    if missing:
        for p in missing:
            sys.stderr.write(f"ERROR: file not found: {p}\n")
        return 2

    total_files, total_violations, messages = lint_files(paths, args.mode)

    for m in messages:
        print(m)

    if not args.quiet or total_violations:
        print(f"spec_lint: mode={args.mode} files={total_files} violations={total_violations}")

    if total_violations and not args.warn_only:
        return 2 if args.strict else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
