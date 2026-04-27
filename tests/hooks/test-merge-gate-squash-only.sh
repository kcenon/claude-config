#!/bin/bash
# Test suite: merge-gate-guard.sh — squash-only enforcement (Issue #478)
# Run: bash tests/hooks/test-merge-gate-squash-only.sh
#
# Validates that --merge / --rebase flags are rejected before the hook
# ever calls `gh pr checks`. The squash-only check is a pre-CI gate so we
# do not need a stubbed gh binary for these cases.

HOOK="global/hooks/merge-gate-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local cmd="$1" label="$2" needle="$3"
    local fixture
    fixture=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
    local result
    result=$(printf '%s' "$fixture" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"deny"' && echo "$result" | grep -q "$needle"; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected deny mentioning '$needle', got: $result")
        echo "  FAIL: $label"
    fi
}

assert_passthrough() {
    local cmd="$1" label="$2"
    local fixture
    fixture=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
    # We do not assert allow/deny here — only that the squash-only branch
    # did NOT fire. The CI-checks branch may legitimately allow or deny
    # based on the (absent) gh CLI, so we just verify the response does
    # not mention "branching strategy requires squash".
    local result
    result=$(printf '%s' "$fixture" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q "branching strategy requires squash"; then
        ((FAIL++))
        ERRORS+=("FAIL: $label — squash-only branch unexpectedly fired: $result")
        echo "  FAIL: $label"
    else
        ((PASS++))
        echo "  PASS: $label"
    fi
}

echo "=== merge-gate-guard squash-only tests ==="
echo ""

echo "[deny — non-squash flags]"
assert_deny 'gh pr merge 1 --merge'   "long-form --merge"   "branching strategy requires squash"
assert_deny 'gh pr merge --merge 1'   "--merge before PR#"  "branching strategy requires squash"
assert_deny 'gh pr merge 1 --rebase'  "long-form --rebase"  "branching strategy requires squash"
assert_deny 'gh pr merge --rebase 7'  "--rebase before PR#" "branching strategy requires squash"

echo ""
echo "[allow-pass-through — squash and unrelated commands]"
assert_passthrough 'gh pr merge 1 --squash --delete-branch'      "--squash"
assert_passthrough 'gh pr view 1'                                 "non-merge gh"

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
