#!/bin/bash
# Test suite for scripts/check_workspace_prefix.sh
# Run: bash tests/scripts/test-workspace-prefix.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
LINTER="$ROOT_DIR/scripts/check_workspace_prefix.sh"

PASS=0
FAIL=0
ERRORS=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_contains() {
    local needle="$1" output="$2" label="$3"
    if echo "$output" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output did not contain '$needle'")
        echo "  FAIL: $label"
    fi
}

assert_not_contains() {
    local needle="$1" output="$2" label="$3"
    if echo "$output" | grep -Fq -- "$needle"; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output unexpectedly contained '$needle'")
        echo "  FAIL: $label"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    fi
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $actual)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected exit $expected, got $actual")
        echo "  FAIL: $label"
    fi
}

echo "=== check_workspace_prefix.sh tests ==="
echo ""

# ── Fixture: only conforming files ───────────────────────────
FIX_GOOD="$WORK/good"
mkdir -p "$FIX_GOOD/_workspace/2026-04-26-1"
: > "$FIX_GOOD/_workspace/2026-04-26-1/00_discovery.md"
: > "$FIX_GOOD/_workspace/2026-04-26-1/01_plan.md"
: > "$FIX_GOOD/_workspace/2026-04-26-1/02_implement.log"

echo "[case 1: all conforming files -> 0 warnings]"
out=$(bash "$LINTER" "$FIX_GOOD" 2>&1); rc=$?
assert_exit 0 "$rc" "exit code 0 (warn-only)"
assert_contains "scanned=3" "$out" "scanned 3 files"
assert_contains "warnings=0" "$out" "no warnings"

# ── Fixture: mix of conforming and non-conforming ────────────
FIX_MIX="$WORK/mix"
mkdir -p "$FIX_MIX/_workspace/2026-04-26-1"
: > "$FIX_MIX/_workspace/2026-04-26-1/00_discovery.md"
: > "$FIX_MIX/_workspace/2026-04-26-1/notes.md"
: > "$FIX_MIX/_workspace/2026-04-26-1/1_oneDigit.md"
: > "$FIX_MIX/_workspace/2026-04-26-1/02_PascalCase.md"

echo ""
echo "[case 2: mixed files -> 3 warnings, exit still 0]"
out=$(bash "$LINTER" "$FIX_MIX" 2>&1); rc=$?
assert_exit 0 "$rc" "exit code 0 even with warnings"
assert_contains "warnings=3" "$out" "3 non-conforming files reported"
assert_contains "notes.md" "$out" "warns on missing prefix"
assert_contains "1_oneDigit.md" "$out" "warns on single-digit prefix"
assert_contains "02_PascalCase.md" "$out" "warns on non-snake_case phase"
assert_not_contains "00_discovery.md" "$out" "no warning for conforming file"

# ── Fixture: no _workspace directory at all ──────────────────
FIX_EMPTY="$WORK/empty"
mkdir -p "$FIX_EMPTY/src"
: > "$FIX_EMPTY/src/main.go"

echo ""
echo "[case 3: no _workspace dir -> scan 0 files, no warnings]"
out=$(bash "$LINTER" "$FIX_EMPTY" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 with no workspace"
assert_contains "scanned=0" "$out" "scanned 0 files"
assert_contains "roots=0" "$out" "0 workspace roots"

# ── Quiet mode suppresses per-file output ────────────────────
echo ""
echo "[case 4: --quiet suppresses per-file warnings and summary]"
out=$(bash "$LINTER" --quiet "$FIX_MIX" 2>&1); rc=$?
assert_exit 0 "$rc" "quiet exit 0"
assert_not_contains "WARN:" "$out" "no per-file warnings printed"
assert_not_contains "scanned=" "$out" "no summary line printed"

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do echo "  $e"; done
    exit 1
fi
exit 0
