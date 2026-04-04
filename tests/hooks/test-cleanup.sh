#!/bin/bash
# Test suite for cleanup.sh
# Run: bash tests/hooks/test-cleanup.sh
#
# cleanup.sh uses ${TMPDIR:-/tmp} for file cleanup and sources lib/rotate.sh.
# Tests override TMPDIR to an isolated directory for safe testing.
# rotate.sh errors are suppressed (tested separately if it exists).

HOOK="global/hooks/cleanup.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

TEST_DIR="${TMPDIR:-/tmp}/test-cleanup-$$"
mkdir -p "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

# Run the hook with TMPDIR pointing to our test directory
run_hook() {
    TMPDIR="$TEST_DIR" bash "$HOOK" >/dev/null 2>&1
}

echo "=== cleanup.sh tests ==="
echo ""

# --- Script exits with 0 ---
echo "[Exit code]"
TMPDIR="$TEST_DIR" bash "$HOOK" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    ((PASS++))
    echo "  PASS: Exit code 0"
else
    ((FAIL++))
    ERRORS+=("FAIL: Expected exit code 0")
    echo "  FAIL: Exit code 0"
fi

# --- Script does not produce stdout output ---
echo ""
echo "[No output]"
output=$(TMPDIR="$TEST_DIR" bash "$HOOK" 2>/dev/null)
if [ -z "$output" ]; then
    ((PASS++))
    echo "  PASS: No stdout output"
else
    ((FAIL++))
    ERRORS+=("FAIL: Expected no stdout, got: $output")
    echo "  FAIL: No stdout output"
fi

# --- Script is idempotent ---
echo ""
echo "[Idempotent]"
run_hook; exit_1=$?
run_hook; exit_2=$?
if [ $exit_1 -eq 0 ] && [ $exit_2 -eq 0 ]; then
    ((PASS++))
    echo "  PASS: Idempotent — multiple runs return 0"
else
    ((FAIL++))
    ERRORS+=("FAIL: Non-zero exit on repeated run (exit1=$exit_1, exit2=$exit_2)")
    echo "  FAIL: Idempotent — multiple runs return 0"
fi

# --- Recent files should NOT be deleted (age < 60 min) ---
echo ""
echo "[Preserves recent files]"
RECENT_FILE="$TEST_DIR/claude_test_recent"
touch "$RECENT_FILE"
run_hook
if [ -f "$RECENT_FILE" ]; then
    ((PASS++))
    echo "  PASS: Recent claude_* file preserved (< 60 min)"
else
    ((FAIL++))
    ERRORS+=("FAIL: Recent claude_* file was deleted")
    echo "  FAIL: Recent claude_* file preserved (< 60 min)"
fi
rm -f "$RECENT_FILE"

RECENT_TMP="$TEST_DIR/tmp.test_recent"
touch "$RECENT_TMP"
run_hook
if [ -f "$RECENT_TMP" ]; then
    ((PASS++))
    echo "  PASS: Recent tmp.* file preserved (< 60 min)"
else
    ((FAIL++))
    ERRORS+=("FAIL: Recent tmp.* file was deleted")
    echo "  FAIL: Recent tmp.* file preserved (< 60 min)"
fi
rm -f "$RECENT_TMP"

# --- Non-matching file should NOT be deleted ---
echo ""
echo "[Non-matching patterns preserved]"
SAFE_FILE="$TEST_DIR/safe_file_test"
touch "$SAFE_FILE"
run_hook
if [ -f "$SAFE_FILE" ]; then
    ((PASS++))
    echo "  PASS: Non-matching file preserved"
else
    ((FAIL++))
    ERRORS+=("FAIL: Non-matching file was deleted")
    echo "  FAIL: Non-matching file preserved"
fi
rm -f "$SAFE_FILE"

# --- "claudetest" (no underscore) should NOT match "claude_*" ---
echo ""
echo "[Pattern specificity]"
CLAUDE_NO_UNDERSCORE="$TEST_DIR/claudetest_file"
touch "$CLAUDE_NO_UNDERSCORE"
touch -t 202001010000 "$CLAUDE_NO_UNDERSCORE"
run_hook
if [ -f "$CLAUDE_NO_UNDERSCORE" ]; then
    ((PASS++))
    echo "  PASS: 'claudetest' (no underscore) preserved"
else
    ((FAIL++))
    ERRORS+=("FAIL: 'claudetest' (no underscore) was deleted")
    echo "  FAIL: 'claudetest' (no underscore) preserved"
fi
rm -f "$CLAUDE_NO_UNDERSCORE"

# --- Old claude_* file SHOULD be deleted (age > 60 min) ---
echo ""
echo "[Old files deleted]"
OLD_CLAUDE="$TEST_DIR/claude_old_file"
touch "$OLD_CLAUDE"
touch -t 202001010000 "$OLD_CLAUDE"
run_hook
if [ ! -f "$OLD_CLAUDE" ]; then
    ((PASS++))
    echo "  PASS: Old claude_* file deleted (> 60 min)"
else
    ((FAIL++))
    ERRORS+=("FAIL: Old claude_* file was not deleted")
    echo "  FAIL: Old claude_* file deleted (> 60 min)"
fi

OLD_TMP="$TEST_DIR/tmp.old_file"
touch "$OLD_TMP"
touch -t 202001010000 "$OLD_TMP"
run_hook
if [ ! -f "$OLD_TMP" ]; then
    ((PASS++))
    echo "  PASS: Old tmp.* file deleted (> 60 min)"
else
    ((FAIL++))
    ERRORS+=("FAIL: Old tmp.* file was not deleted")
    echo "  FAIL: Old tmp.* file deleted (> 60 min)"
fi

# --- maxdepth 1: nested files should NOT be touched ---
echo ""
echo "[Maxdepth 1 — subdirectory files not touched]"
SUBDIR="$TEST_DIR/subdir_test"
mkdir -p "$SUBDIR"
NESTED_FILE="$SUBDIR/claude_nested"
touch "$NESTED_FILE"
touch -t 202001010000 "$NESTED_FILE"
run_hook
if [ -f "$NESTED_FILE" ]; then
    ((PASS++))
    echo "  PASS: Nested file in subdirectory preserved"
else
    ((FAIL++))
    ERRORS+=("FAIL: Nested file in subdirectory was deleted")
    echo "  FAIL: Nested file in subdirectory preserved"
fi
rm -rf "$SUBDIR"

# --- Source-level checks ---
echo ""
echo "[Source verification]"

if grep -q '\-mmin +60' "$HOOK"; then
    ((PASS++))
    echo "  PASS: Uses -mmin +60 age threshold"
else
    ((FAIL++))
    ERRORS+=("FAIL: Missing -mmin +60 age threshold")
    echo "  FAIL: Uses -mmin +60 age threshold"
fi

if grep -q '\-maxdepth 1' "$HOOK"; then
    ((PASS++))
    echo "  PASS: Uses -maxdepth 1"
else
    ((FAIL++))
    ERRORS+=("FAIL: Missing -maxdepth 1")
    echo "  FAIL: Uses -maxdepth 1"
fi

if grep -q 'TMPDIR' "$HOOK"; then
    ((PASS++))
    echo "  PASS: Uses TMPDIR variable"
else
    ((FAIL++))
    ERRORS+=("FAIL: Does not use TMPDIR variable")
    echo "  FAIL: Uses TMPDIR variable"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
