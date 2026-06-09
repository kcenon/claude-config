#!/bin/bash
# Test suite for P4 strict-schema Kill Switch toggle (issue #469).
# Verifies: STRICT_SCHEMA env var > harness_policies.p4_strict_schema in
# settings.json > default false. Run: bash tests/scripts/test-killswitch.sh

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

PY_SCRIPT='
import sys
from pathlib import Path
sys.path.insert(0, r"'"$ROOT_DIR"'/scripts")
import spec_lint
spec_lint.SETTINGS_PATH = Path(r"'"$WORK"'/fakehome/.claude/settings.json")
print(spec_lint.read_p4_strict_schema_toggle())
'

run_toggle() {
    # $1 = expected ("True"/"False"), $2 = label, $3 = STRICT_SCHEMA value or "__UNSET__"
    local expected="$1"
    local label="$2"
    local strict_value="${3:-__UNSET__}"
    local out
    if [ "$strict_value" = "__UNSET__" ]; then
        out=$(env -u STRICT_SCHEMA "$PYTHON" -c "$PY_SCRIPT" 2>&1)
    else
        out=$(STRICT_SCHEMA="$strict_value" "$PYTHON" -c "$PY_SCRIPT" 2>&1)
    fi
    if [ "$out" = "$expected" ]; then
        PASS=$((PASS+1))
        echo "PASS: $label -> $out"
    else
        FAIL=$((FAIL+1))
        ERRORS+=("FAIL: $label (expected $expected, got $out)")
    fi
}

write_settings() {
    # $1 = settings dir, $2 = JSON body
    mkdir -p "$1"
    printf '%s\n' "$2" > "$1/settings.json"
}

# Case 1: no env, no settings → default False
mkdir -p "$WORK/fakehome/.claude"
run_toggle "False" "default (no env, no settings)"

# Case 2: settings true, no env → True
write_settings "$WORK/fakehome/.claude" '{"harness_policies": {"p4_strict_schema": true}}'
run_toggle "True" "settings=true, no env"

# Case 3: settings true, env=0 → False (env wins)
run_toggle "False" "settings=true, env=0 (env overrides)" "0"

# Case 4: settings false, env=1 → True (env wins)
write_settings "$WORK/fakehome/.claude" '{"harness_policies": {"p4_strict_schema": false}}'
run_toggle "True" "settings=false, env=1 (env overrides)" "1"

# Case 5: env=true (case insensitive) → True
run_toggle "True" "env=TRUE (case-insensitive)" "TRUE"

# Case 6: env=on → True
run_toggle "True" "env=on" "on"

# Case 7: env=anything-else → False (only documented truthy values)
run_toggle "False" "env=garbage (not truthy)" "garbage"

# Case 8: malformed settings.json → fall back to default False
write_settings "$WORK/fakehome/.claude" 'this is not json'
run_toggle "False" "malformed settings.json (graceful fallback)"

# Case 9: missing harness_policies key → default False
write_settings "$WORK/fakehome/.claude" '{"other_key": 42}'
run_toggle "False" "settings present but no harness_policies"

# Case 10: harness_policies present but p4_strict_schema missing → default False
write_settings "$WORK/fakehome/.claude" '{"harness_policies": {"other_toggle": true}}'
run_toggle "False" "harness_policies without p4_strict_schema"

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
