#!/bin/bash
# Test suite for commit-message-guard.sh
# Run: bash tests/hooks/test-commit-message-guard.sh

HOOK="global/hooks/commit-message-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== commit-message-guard.sh tests ==="
echo ""

echo "[non-commit commands pass through]"
assert_allow '{"tool_input":{"command":"ls -la"}}' "ls -la → allow"
assert_allow '{"tool_input":{"command":"git status"}}' "git status → allow"
assert_allow '{"tool_input":{"command":"git log --oneline"}}' "git log → allow"
assert_allow '{"tool_input":{"command":"gh issue view 123"}}' "gh issue view → allow"

echo ""
echo "[valid conventional commits]"
assert_allow '{"tool_input":{"command":"git commit -m \"feat: add new feature\""}}' "feat: add new feature → allow"
assert_allow '{"tool_input":{"command":"git commit -m \"fix(auth): handle null token\""}}' "fix(auth): handle null token → allow"
assert_allow '{"tool_input":{"command":"git commit -m \"docs(readme): update installation steps\""}}' "docs(readme): update → allow"
assert_allow '{"tool_input":{"command":"git commit -m \"security: patch credential leak\""}}' "security: patch → allow"
assert_allow '{"tool_input":{"command":"git commit -am \"refactor: simplify config loader\""}}' "git commit -am → allow"
assert_allow '{"tool_input":{"command":"git commit --message=\"chore: update dependencies\""}}' "--message= form → allow"

echo ""
echo "[format violations]"
assert_deny '{"tool_input":{"command":"git commit -m \"added new feature\""}}' "no type prefix → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"feat add new feature\""}}' "missing colon → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"wip: some stuff\""}}' "invalid type 'wip' → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"feat(BadScope): desc\""}}' "uppercase scope → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"update: things\""}}' "invalid type 'update' → deny"

echo ""
echo "[description rules]"
assert_deny '{"tool_input":{"command":"git commit -m \"feat: Added new feature\""}}' "uppercase first char → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"fix: resolve issue.\""}}' "trailing period → deny"

echo ""
echo "[AI attribution]"
assert_deny '{"tool_input":{"command":"git commit -m \"feat: add claude integration\""}}' "claude keyword → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"fix: anthropic API fallback\""}}' "anthropic keyword → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"fix: ai-assisted refactor\""}}' "ai-assisted → deny"
assert_deny '{"tool_input":{"command":"git commit -m \"feat: add feature generated with claude code\""}}' "generated with → deny"

echo ""
echo "[emoji detection]"
EMOJI_PARTY=$(printf '\xf0\x9f\x8e\x89')
assert_deny "{\"tool_input\":{\"command\":\"git commit -m \\\"feat: ${EMOJI_PARTY} party hat\\\"\"}}" "emoji party face → deny"

echo ""
echo "[edge cases]"
assert_allow '{"tool_input":{"command":"git commit"}}' "git commit without -m → allow (opens editor)"
assert_allow '{"tool_input":{"command":"git commit -m \"$(cat <<EOF\nfeat: multi-line\nEOF\n)\""}}' "command substitution → allow (defer to commit-msg)"
assert_allow '' "empty input → allow"

echo ""
echo "[determinism — same input yields same output across 3 runs]"
TEST_INPUT='{"tool_input":{"command":"git commit -m \"feat: deterministic check\""}}'
R1=$(echo "$TEST_INPUT" | bash "$HOOK" 2>/dev/null)
R2=$(echo "$TEST_INPUT" | bash "$HOOK" 2>/dev/null)
R3=$(echo "$TEST_INPUT" | bash "$HOOK" 2>/dev/null)
if [ "$R1" = "$R2" ] && [ "$R2" = "$R3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: 3 runs produced identical output"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: non-deterministic output across runs")
    echo "  FAIL: 3 runs differed"
fi

BAD_INPUT='{"tool_input":{"command":"git commit -m \"feat: Invalid Capital\""}}'
D1=$(echo "$BAD_INPUT" | bash "$HOOK" 2>/dev/null)
D2=$(echo "$BAD_INPUT" | bash "$HOOK" 2>/dev/null)
D3=$(echo "$BAD_INPUT" | bash "$HOOK" 2>/dev/null)
if [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: invalid input deny is also deterministic"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: deny response differs across runs")
    echo "  FAIL: deny response differs across runs"
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
