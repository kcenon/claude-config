#!/bin/bash
# Test suite for hooks/pre-push (git hook).
# Run: bash tests/hooks/test-pre-push.sh

HOOK="hooks/pre-push"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

if [ ! -f "$HOOK" ]; then
    echo "ERROR: $HOOK not found"
    exit 1
fi

ZERO_SHA="0000000000000000000000000000000000000000"
REAL_SHA_A="1111111111111111111111111111111111111111"
REAL_SHA_B="2222222222222222222222222222222222222222"

# Helper: pipe stdin lines to the hook and capture exit code.
# Args: <stdin lines separated by \n>
run_hook() {
    local input="$1"
    # Ensure every line — including the last — ends with a newline so the
    # `while read` loop in the hook processes each ref update.
    if [ -n "$input" ]; then
        printf '%s\n' "$input" | bash "$HOOK" origin https://example.invalid/repo.git >/dev/null 2>&1
    else
        : | bash "$HOOK" origin https://example.invalid/repo.git >/dev/null 2>&1
    fi
    return $?
}

assert_exit() {
    local expected="$1" input="$2" label="$3"
    run_hook "$input"
    local rc=$?
    if [ "$rc" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $rc)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected exit $expected, got $rc")
        echo "  FAIL: $label (expected $expected, got $rc)"
    fi
}

echo "=== pre-push hook tests ==="
echo ""

echo "[protected branches — block direct push]"
# Format: <local_ref> <local_sha> <remote_ref> <remote_sha>
assert_exit 1 "refs/heads/main $REAL_SHA_A refs/heads/main $REAL_SHA_B" "push to main blocked"
assert_exit 1 "refs/heads/develop $REAL_SHA_A refs/heads/develop $REAL_SHA_B" "push to develop blocked"

echo ""
echo "[protected branches — allow deletion]"
# Deletion push: local_sha is all zeros, remote_sha is the last known SHA.
assert_exit 0 "(delete) $ZERO_SHA refs/heads/main $REAL_SHA_B" "delete main allowed"
assert_exit 0 "(delete) $ZERO_SHA refs/heads/develop $REAL_SHA_B" "delete develop allowed"

echo ""
echo "[non-protected branches]"
assert_exit 0 "refs/heads/feat/x $REAL_SHA_A refs/heads/feat/x $REAL_SHA_B" "push to feat/x allowed"
assert_exit 0 "refs/heads/fix/y $REAL_SHA_A refs/heads/fix/y $REAL_SHA_B" "push to fix/y allowed"
assert_exit 0 "(delete) $ZERO_SHA refs/heads/feat/x $REAL_SHA_B" "delete feat/x allowed"

echo ""
echo "[multi-ref push]"
# A single push can update several refs — each arrives as one stdin line.
# Any protected branch update among them must still block.
MULTI_BLOCK="refs/heads/feat/x $REAL_SHA_A refs/heads/feat/x $REAL_SHA_B
refs/heads/main $REAL_SHA_A refs/heads/main $REAL_SHA_B"
assert_exit 1 "$MULTI_BLOCK" "multi-ref push containing main is blocked"

# Delete develop alongside a normal feature push → both allowed.
MULTI_ALLOW="refs/heads/feat/x $REAL_SHA_A refs/heads/feat/x $REAL_SHA_B
(delete) $ZERO_SHA refs/heads/develop $REAL_SHA_B"
assert_exit 0 "$MULTI_ALLOW" "multi-ref: feat push + develop delete allowed"

echo ""
echo "[empty stdin — nothing to push, hook must pass]"
assert_exit 0 "" "empty stdin allowed"

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
