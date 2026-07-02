#!/bin/bash
# Test suite for push-target-guard.sh (issue #782)
# Run: bash tests/hooks/test-push-target-guard.sh

HOOK="global/hooks/push-target-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local input="$1" label="$2" result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $label — expected deny, got: $result"); echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2" result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $label — expected allow, got: $result"); echo "  FAIL: $label"
    fi
}

echo "=== push-target-guard.sh tests ==="
echo ""

echo "[non-push commands pass through]"
assert_allow '{"tool_input":{"command":"git status"}}' "git status → allow"
assert_allow '{"tool_input":{"command":"git commit -m \"feat: x\""}}' "git commit → allow"
assert_allow '{"tool_input":{"command":"ls -la"}}' "ls -la → allow"

echo ""
echo "[direct push to a protected branch → deny]"
assert_deny '{"tool_input":{"command":"git push origin main"}}' "push origin main → deny"
assert_deny '{"tool_input":{"command":"git push origin master"}}' "push origin master → deny"
assert_deny '{"tool_input":{"command":"git push origin develop"}}' "push origin develop → deny"
assert_deny '{"tool_input":{"command":"git push -u origin main"}}' "push -u origin main → deny"
assert_deny '{"tool_input":{"command":"git push --force origin develop"}}' "push --force origin develop → deny"
assert_deny '{"tool_input":{"command":"git push origin HEAD:main"}}' "push HEAD:main → deny"
assert_deny '{"tool_input":{"command":"git push origin +main"}}' "push +main (force refspec) → deny"
assert_deny '{"tool_input":{"command":"git push origin refs/heads/develop"}}' "push refs/heads/develop → deny"

echo ""
echo "[non-protected targets → allow]"
assert_allow '{"tool_input":{"command":"git push origin feature/x"}}' "push feature/x → allow"
assert_allow '{"tool_input":{"command":"git push -u origin fix/issue-1"}}' "push fix/issue-1 → allow"
assert_allow '{"tool_input":{"command":"git push origin main:feature"}}' "push main:feature (dst feature) → allow"

echo ""
echo "[--no-verify defeats pre-push hook → deny]"
assert_deny '{"tool_input":{"command":"git push --no-verify origin feature/x"}}' "push --no-verify (non-protected) → deny"
assert_deny '{"tool_input":{"command":"git push origin feature/x --no-verify"}}' "push ... --no-verify (trailing) → deny"

echo ""
echo "[dry-run is harmless — -n is NOT --no-verify for push (issue #782)]"
assert_allow '{"tool_input":{"command":"git push -n origin main"}}' "push -n origin main (dry-run) → allow"
assert_allow '{"tool_input":{"command":"git push --dry-run origin develop"}}' "push --dry-run develop → allow"

echo ""
echo "[quoted-arg false-trigger guard]"
assert_allow '{"tool_input":{"command":"git push origin feature/no-verify-docs"}}' "branch name containing 'no-verify' → allow"

echo ""
echo "[fail-closed on unparseable input]"
assert_deny '' "empty input → deny (fail-closed)"

echo ""
echo "[determinism — same input yields same output across 3 runs]"
TI='{"tool_input":{"command":"git push origin main"}}'
R1=$(echo "$TI" | bash "$HOOK" 2>/dev/null); R2=$(echo "$TI" | bash "$HOOK" 2>/dev/null); R3=$(echo "$TI" | bash "$HOOK" 2>/dev/null)
if [ "$R1" = "$R2" ] && [ "$R2" = "$R3" ]; then
    PASS=$((PASS + 1)); echo "  PASS: deterministic across 3 runs"
else
    FAIL=$((FAIL + 1)); ERRORS+=("FAIL: non-deterministic output"); echo "  FAIL: non-deterministic"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
