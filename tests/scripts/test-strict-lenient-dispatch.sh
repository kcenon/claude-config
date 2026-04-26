#!/bin/bash
# Test suite for P4-a strict/lenient skill schema dispatch (issue #461).
# Verifies select_skill_schema_mode() honors both the Kill Switch toggle
# and the global/skills/_internal/ path marker.
# Run: bash tests/scripts/test-strict-lenient-dispatch.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"

PASS=0
FAIL=0
ERRORS=()

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH" >&2
    exit 0
fi
if ! "$PYTHON" -c "import yaml, jsonschema" >/dev/null 2>&1; then
    echo "SKIP: missing PyYAML or jsonschema" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helper: invoke select_skill_schema_mode with explicit path and strict_enabled
run_select() {
    # $1 = expected mode, $2 = label, $3 = path, $4 = strict_enabled (true/false)
    local expected="$1" label="$2" path="$3" strict="$4"
    local out
    out=$("$PYTHON" -c "
import sys
from pathlib import Path
sys.path.insert(0, r'$ROOT_DIR/scripts')
from spec_lint import select_skill_schema_mode
print(select_skill_schema_mode(Path(r'$path'), $strict))
" 2>&1)
    if [ "$out" = "$expected" ]; then
        PASS=$((PASS+1))
        echo "PASS: $label -> $out"
    else
        FAIL=$((FAIL+1))
        ERRORS+=("FAIL: $label (expected $expected, got $out)")
    fi
}

# Set up a fake repo layout so resolve() produces predictable paths
mkdir -p "$WORK/repo/global/skills/_internal/sample"
mkdir -p "$WORK/repo/global/skills/regular/sample"
mkdir -p "$WORK/repo/plugin/skills/external"
touch "$WORK/repo/global/skills/_internal/sample/SKILL.md"
touch "$WORK/repo/global/skills/regular/sample/SKILL.md"
touch "$WORK/repo/plugin/skills/external/SKILL.md"

# Strict OFF -> always lenient (Kill Switch behavior)
run_select "skill-lenient" "_internal/ path with strict OFF -> lenient" \
    "$WORK/repo/global/skills/_internal/sample/SKILL.md" "False"
run_select "skill-lenient" "regular global skill with strict OFF -> lenient" \
    "$WORK/repo/global/skills/regular/sample/SKILL.md" "False"
run_select "skill-lenient" "plugin skill with strict OFF -> lenient" \
    "$WORK/repo/plugin/skills/external/SKILL.md" "False"

# Strict ON -> path-based dispatch
run_select "skill-strict" "_internal/ path with strict ON -> strict" \
    "$WORK/repo/global/skills/_internal/sample/SKILL.md" "True"
run_select "skill-lenient" "regular global skill with strict ON -> lenient" \
    "$WORK/repo/global/skills/regular/sample/SKILL.md" "True"
run_select "skill-lenient" "plugin skill with strict ON -> lenient" \
    "$WORK/repo/plugin/skills/external/SKILL.md" "True"

# Edge: nested path under _internal
mkdir -p "$WORK/repo/global/skills/_internal/nested/deep/skill"
touch "$WORK/repo/global/skills/_internal/nested/deep/skill/SKILL.md"
run_select "skill-strict" "deeply nested _internal path with strict ON" \
    "$WORK/repo/global/skills/_internal/nested/deep/skill/SKILL.md" "True"

# Edge: path containing the literal substring elsewhere should NOT match
# Test ensures the marker is anchored to the actual directory layout
mkdir -p "$WORK/repo/docs/global/skills/_internal-fake"
touch "$WORK/repo/docs/global/skills/_internal-fake/notes.md"
# This path has "global/skills/_internal-" not "global/skills/_internal/", so lenient
run_select "skill-lenient" "look-alike _internal-fake path with strict ON -> lenient" \
    "$WORK/repo/docs/global/skills/_internal-fake/notes.md" "True"

# Real repo file (should always be lenient until D2 creates _internal/ entries)
run_select "skill-lenient" "real claude-config skill (no _internal/ yet) with strict ON" \
    "$ROOT_DIR/global/skills/preflight/SKILL.md" "True"

# Final report
echo ""
echo "=== Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '%s\n' "${ERRORS[@]}"
    exit 1
fi
exit 0
