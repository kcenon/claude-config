#!/bin/bash
# Test suite for pr-target-guard.sh
# Run: bash tests/hooks/test-pr-target-guard.sh

HOOK="global/hooks/pr-target-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== pr-target-guard.sh tests ==="
echo ""

echo "[Fail-closed]"
assert_deny '' "Empty input → deny"
assert_deny 'INVALID_JSON' "Malformed JSON → deny"

echo ""
echo "[Scope: non-gh commands pass through]"
assert_allow '{"tool_input":{"command":"ls -la"}}' "ls -la → allow"
assert_allow '{"tool_input":{"command":"git push origin main"}}' "git push → allow (handled by pre-push hook)"
assert_allow '{"tool_input":{"command":"gh issue create --title test"}}' "gh issue create → allow"
assert_allow '{"tool_input":{"command":"gh pr view 123"}}' "gh pr view → allow"
assert_allow '{"tool_input":{"command":"gh pr checks 42"}}' "gh pr checks → allow"
assert_allow '{"tool_input":{"command":"gh pr merge 42 --squash"}}' "gh pr merge → allow (not gh pr create)"

echo ""
echo "[gh pr create targeting main: deny]"
assert_deny '{"tool_input":{"command":"gh pr create --base main --title \"fix: something\""}}' "--base main → deny"
assert_deny '{"tool_input":{"command":"gh pr create --base=main --title \"fix: something\""}}' "--base=main → deny"
assert_deny '{"tool_input":{"command":"gh pr create -B main --title \"fix: something\""}}' "-B main → deny"
assert_deny '{"tool_input":{"command":"gh pr create --title \"fix: something\" --base main --body \"desc\""}}' "--base main (mid-command) → deny"
assert_deny '{"tool_input":{"command":"gh pr create --base main --head fix/some-branch"}}' "--head fix/some-branch to main → deny"
assert_deny '{"tool_input":{"command":"gh pr create --base main --head feature/issue-42"}}' "--head feature/ to main → deny"

echo ""
echo "[Release exception: develop → main allowed]"
assert_allow '{"tool_input":{"command":"gh pr create --base main --head develop --title \"release: v1.0.0\""}}' "--base main --head develop → allow"
assert_allow '{"tool_input":{"command":"gh pr create --head develop --base main --title \"release: v2.0.0\""}}' "reversed order → allow"
assert_allow '{"tool_input":{"command":"gh pr create --base=main --head=develop --title \"release\""}}' "equals form → allow"

echo ""
echo "[Release exception: release/* → main allowed]"
assert_allow '{"tool_input":{"command":"gh pr create --base main --head release/1.10.0 --title \"release: v1.10.0\""}}' "--head release/1.10.0 → allow"
assert_allow '{"tool_input":{"command":"gh pr create --base main --head release/2.0.0-beta.1 --title \"release: beta\""}}' "--head release/<semver> → allow"
assert_allow '{"tool_input":{"command":"gh pr create --base=main --head=release/v3 --title \"release\""}}' "--head=release/v3 (equals form) → allow"
assert_allow '{"tool_input":{"command":"gh pr create --base main --head release/2026-04-18 --title \"release\""}}' "--head release/<date> → allow"
assert_deny '{"tool_input":{"command":"gh pr create --base main --head release --title \"release\""}}' "--head release (bare, no slash) → deny"
assert_deny '{"tool_input":{"command":"gh pr create --base main --head release-candidate --title \"release\""}}' "--head release-candidate (no slash) → deny"

echo ""
echo "[Normal workflow: allow]"
assert_allow '{"tool_input":{"command":"gh pr create --base develop --title \"feat: new feature\""}}' "--base develop → allow"
assert_allow '{"tool_input":{"command":"gh pr create --title \"feat: something\""}}' "no --base (defaults to develop) → allow"
assert_allow '{"tool_input":{"command":"gh pr create --base develop --head feat/issue-42"}}' "--base develop --head feat/ → allow"

echo ""
echo "[Edge cases]"
assert_allow '{"tool_input":{"command":"gh pr create --base main-backup --title \"test\""}}' "--base main-backup → allow (not exact main)"
assert_allow '{"tool_input":{"command":"gh pr create --base maintain --title \"test\""}}' "--base maintain → allow (not exact main)"
assert_deny '{"tool_input":{"command":"cd repo && gh pr create --base main --title \"fix\""}}' "chained command with --base main → deny"
assert_deny '{"tool_input":{"command":"gh pr create --repo org/repo --base main --title \"fix\""}}' "--repo with --base main → deny"

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
