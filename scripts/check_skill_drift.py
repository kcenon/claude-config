#!/usr/bin/env python3
"""Check cross-layer SKILL.md drift against skill-drift-contract.yml.

Exit codes:
  0: all declared pairs match their contract
  1: setup or contract error
  2: drift detected
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("ERROR: PyYAML not installed. Run: pip install pyyaml\n")
    sys.exit(1)


TOOL_FIELDS = {"allowed-tools", "disallowed-tools"}


def fail_setup(message: str) -> int:
    sys.stderr.write(f"ERROR: {message}\n")
    return 1


def normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def extract_skill(path: Path) -> tuple[dict[str, Any], str]:
    text = normalize_newlines(path.read_text(encoding="utf-8"))
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{path}: missing YAML frontmatter")

    end = -1
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end < 0:
        raise ValueError(f"{path}: unterminated YAML frontmatter")

    raw_frontmatter = "\n".join(lines[1:end])
    data = yaml.safe_load(raw_frontmatter) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: frontmatter must be a YAML mapping")

    body = "\n".join(lines[end + 1 :])
    if body.startswith("\n"):
        body = body[1:]
    body = body.rstrip("\n")
    return data, body


def normalize_tool_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, list):
        return sorted(str(item).strip() for item in value)
    if isinstance(value, str) and "," in value:
        return sorted(part.strip() for part in value.split(",") if part.strip())
    return value


def canonical_field_value(field: str, value: Any) -> Any:
    if field in TOOL_FIELDS:
        return normalize_tool_value(value)
    return value


def canonical_repr(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def load_contract(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("contract root must be a YAML mapping")
    if data.get("version") != 1:
        raise ValueError("contract version must be 1")
    if not isinstance(data.get("pairs"), list) or not data["pairs"]:
        raise ValueError("contract must declare at least one pair")
    if not isinstance(data.get("default_watched_fields"), list) or not data["default_watched_fields"]:
        raise ValueError("contract must declare default_watched_fields")
    return data


def exception_key(exception: dict[str, Any]) -> str:
    return str(exception.get("field", ""))


def build_exception_map(pair: dict[str, Any]) -> dict[str, dict[str, Any]]:
    exceptions: dict[str, dict[str, Any]] = {}
    for raw in pair.get("exceptions", []) or []:
        if not isinstance(raw, dict):
            raise ValueError(f"{pair.get('id')}: exception entries must be mappings")
        field = exception_key(raw)
        if not field:
            raise ValueError(f"{pair.get('id')}: exception missing field")
        if not str(raw.get("reason", "")).strip():
            raise ValueError(f"{pair.get('id')}: exception for {field} missing reason")
        exceptions[field] = raw
    return exceptions


def check_exception(
    pair_id: str,
    field: str,
    exception: dict[str, Any],
    source_value: Any,
    target_value: Any,
) -> list[str]:
    failures: list[str] = []
    if "source" in exception:
        expected = canonical_field_value(field, exception["source"])
        if source_value != expected:
            failures.append(
                f"FAIL: {pair_id}: exception for {field} source no longer matches "
                f"(expected {canonical_repr(expected)}, got {canonical_repr(source_value)})"
            )
    if "target" in exception:
        expected = canonical_field_value(field, exception["target"])
        if target_value != expected:
            failures.append(
                f"FAIL: {pair_id}: exception for {field} target no longer matches "
                f"(expected {canonical_repr(expected)}, got {canonical_repr(target_value)})"
            )
    return failures


def check_pair(root: Path, defaults: list[str], pair: dict[str, Any]) -> list[str]:
    pair_id = str(pair.get("id") or "<unnamed>")
    source_rel = pair.get("source")
    target_rel = pair.get("target")
    if not isinstance(source_rel, str) or not isinstance(target_rel, str):
        return [f"FAIL: {pair_id}: source and target must be paths"]

    source = root / source_rel
    target = root / target_rel
    failures: list[str] = []
    if not source.is_file():
        failures.append(f"FAIL: {pair_id}: missing source {source_rel}")
    if not target.is_file():
        failures.append(f"FAIL: {pair_id}: missing target {target_rel}")
    if failures:
        return failures

    try:
        source_fm, source_body = extract_skill(source)
        target_fm, target_body = extract_skill(target)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        return [f"FAIL: {pair_id}: {exc}"]

    fields = pair.get("fields", defaults)
    if not isinstance(fields, list) or not all(isinstance(item, str) for item in fields):
        return [f"FAIL: {pair_id}: fields must be a list of strings"]

    try:
        exceptions = build_exception_map(pair)
    except ValueError as exc:
        return [f"FAIL: {exc}"]
    unwatched_exceptions = sorted(set(exceptions) - set(fields))
    for field in unwatched_exceptions:
        failures.append(f"FAIL: {pair_id}: exception for unwatched field '{field}'")

    for field in fields:
        source_value = canonical_field_value(field, source_fm.get(field))
        target_value = canonical_field_value(field, target_fm.get(field))
        if field in exceptions:
            failures.extend(check_exception(pair_id, field, exceptions[field], source_value, target_value))
            continue
        if source_value != target_value:
            failures.append(
                f"FAIL: {pair_id}: frontmatter '{field}' drift: "
                f"source={canonical_repr(source_value)} target={canonical_repr(target_value)}"
            )

    body = pair.get("body", {"mode": "exact"})
    if body is None:
        body = {"mode": "exact"}
    if not isinstance(body, dict):
        return [f"FAIL: {pair_id}: body must be a mapping"]
    mode = body.get("mode", "exact")
    if mode == "exact":
        if source_body != target_body:
            failures.append(f"FAIL: {pair_id}: body drift: {source_rel} vs {target_rel}")
    elif mode == "ignore":
        if not str(body.get("reason", "")).strip():
            failures.append(f"FAIL: {pair_id}: body ignore mode requires a reason")
    else:
        failures.append(f"FAIL: {pair_id}: unsupported body mode: {mode}")

    return failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("map", nargs="?", default=None)
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    map_path = Path(args.map).resolve() if args.map else root / "skill-drift-contract.yml"
    if not root.is_dir():
        return fail_setup(f"repo root not found: {root}")
    if not map_path.is_file():
        return fail_setup(f"skill drift contract missing: {map_path}")

    try:
        contract = load_contract(map_path)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        return fail_setup(str(exc))

    defaults = contract["default_watched_fields"]
    failures: list[str] = []
    for raw_pair in contract["pairs"]:
        if not isinstance(raw_pair, dict):
            failures.append("FAIL: pair entries must be mappings")
            continue
        failures.extend(check_pair(root, defaults, raw_pair))

    if not failures:
        print(f"check_skill_drift: OK ({len(contract['pairs'])} SKILL.md pairs match contract)")
        return 0

    for failure in failures:
        print(failure, file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "check_skill_drift: drift detected. Update the paired SKILL.md files "
        "or record an intentional exception in skill-drift-contract.yml.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
