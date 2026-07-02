#!/usr/bin/env bash
# Validate generated doc-index manifest entries against the working tree.
#
# Checks intentionally stay narrow:
#   - every manifest document path exists
#   - every recorded `size` equals the checked-in entry's byte length
#   - every checked-in docs/.index/*.yaml file has the same generated date
#
# Usage:
#   scripts/validate-doc-index.sh [repo-root] [manifest-path]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
MANIFEST="${2:-$ROOT_DIR/docs/.index/manifest.yaml}"

PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "validate-doc-index: python3/python not found" >&2
    exit 2
fi

"$PYTHON" - "$ROOT_DIR" "$MANIFEST" <<'PY'
from pathlib import Path
import sys

try:
    import yaml
except ImportError:
    print("validate-doc-index: missing PyYAML module", file=sys.stderr)
    sys.exit(2)

root = Path(sys.argv[1]).resolve()
manifest = Path(sys.argv[2]).resolve()

if not manifest.is_file():
    print(f"validate-doc-index: manifest not found: {manifest}", file=sys.stderr)
    sys.exit(2)

errors = []


def rel(path):
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def load_yaml(path):
    try:
        with path.open("r", encoding="utf-8") as fh:
            loaded = yaml.safe_load(fh) or {}
    except yaml.YAMLError as exc:
        errors.append(f"{rel(path)}: invalid YAML: {exc}")
        return {}
    return loaded


def generated_value(path, loaded):
    meta = loaded.get("_meta")
    if not isinstance(meta, dict):
        errors.append(f"{rel(path)}: missing _meta mapping")
        return None

    generated = meta.get("generated")
    if not isinstance(generated, str) or not generated:
        errors.append(f"{rel(path)}: missing _meta.generated")
        return None

    return generated


data = load_yaml(manifest)

manifest_generated = generated_value(manifest, data)
for index_file in sorted(manifest.parent.glob("*.yaml")):
    index_data = data if index_file == manifest else load_yaml(index_file)
    index_generated = generated_value(index_file, index_data)
    if (
        manifest_generated
        and index_generated
        and index_generated != manifest_generated
    ):
        errors.append(
            f"{rel(index_file)}: generated mismatch "
            f"manifest={manifest_generated} actual={index_generated}"
        )

documents = data.get("documents")
if not isinstance(documents, list):
    print("validate-doc-index: manifest has no documents list", file=sys.stderr)
    sys.exit(1)

seen = set()

for idx, entry in enumerate(documents, 1):
    if not isinstance(entry, dict):
        errors.append(f"entry {idx}: expected mapping")
        continue

    rel = entry.get("path")
    if not isinstance(rel, str) or not rel:
        errors.append(f"entry {idx}: missing path")
        continue

    if rel in seen:
        errors.append(f"{rel}: duplicate manifest entry")
    seen.add(rel)

    target = root / rel
    resolved_target = target.resolve()
    try:
        resolved_target.relative_to(root)
    except ValueError:
        errors.append(f"{rel}: path escapes repository root")
        continue

    if not target.exists() and not target.is_symlink():
        errors.append(f"{rel}: missing file")
        continue

    expected_size = entry.get("size")
    if not isinstance(expected_size, int):
        errors.append(f"{rel}: size is not an integer")
        continue

    actual_size = target.lstat().st_size
    if actual_size != expected_size:
        errors.append(
            f"{rel}: size mismatch manifest={expected_size} actual={actual_size}"
        )

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    print(f"validate-doc-index: {len(errors)} error(s)", file=sys.stderr)
    sys.exit(1)

print(f"validate-doc-index: OK ({len(documents)} documents)")
PY
