#!/usr/bin/env bash
# Verify cross-layer SKILL.md copies match the declared drift contract.
#
# Usage: scripts/check_skill_drift.sh [repo-root] [skill-drift-contract.yml]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
MAP_FILE="${2:-$ROOT_DIR/skill-drift-contract.yml}"
CHECK_PY="$SCRIPT_DIR/check_skill_drift.py"

PYTHON=""
for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "ERROR: python3, python, or py not found in PATH" >&2
    exit 1
fi

if ! "$PYTHON" -c "import yaml" >/dev/null 2>&1; then
    echo "ERROR: missing Python dependency. Install with: pip install pyyaml" >&2
    exit 1
fi

if [ ! -f "$CHECK_PY" ]; then
    echo "ERROR: check_skill_drift.py not found at $CHECK_PY" >&2
    exit 1
fi

exec "$PYTHON" "$CHECK_PY" "$ROOT_DIR" "$MAP_FILE"
