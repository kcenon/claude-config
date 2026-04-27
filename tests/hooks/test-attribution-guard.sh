#!/bin/bash
# Test suite: attribution-guard.sh — gh pr|issue create|edit|comment scope.
# Run: bash tests/hooks/test-attribution-guard.sh
#
# Validates the 11 scope/regex cases from issue #475:
#   - 5 deny cases (each attribution marker in --title or --body)
#   - 3 allow cases (clean text, parser-limit deferrals)
#   - 3 scope cases (issue, comment, out-of-scope command)
#
# The guard wraps validate_no_attribution() from
# hooks/lib/validate-commit-message.sh, so the same regex must be enforced
# across commits, PR/issue titles, and PR/issue bodies.

HOOK="global/hooks/attribution-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_decision() {
    local label="$1"
    local expected="$2"
    local cmd="$3"

    # The guard reads JSON from stdin: {"tool_input":{"command":"<cmd>"}}.
    local payload
    payload=$(jq -cn --arg c "$cmd" '{tool_input:{command:$c}}')
    local result
    result=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)

    if echo "$result" | grep -q "\"$expected\""; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected $expected, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== attribution-guard.sh tests ==="
echo ""

echo "[deny: attribution markers in PR/issue text]"

# 1. claude in --title (case-insensitive)
assert_decision "PR create with 'claude' in --title → deny" "deny" \
    'gh pr create --title "feat: integrate Claude assistant" --body "feature work"'

# 2. anthropic anywhere in --body
assert_decision "PR create with 'anthropic' in --body → deny" "deny" \
    'gh pr create --title "feat: add api" --body "Implemented per Anthropic docs"'

# 3. ai-assisted phrase in --body
assert_decision "PR create with 'ai-assisted' in --body → deny" "deny" \
    'gh pr create --title "feat: tool" --body "AI-assisted refactor"'

# 4. co-authored-by: claude footer in --body
assert_decision "PR create with 'Co-Authored-By: Claude' in --body → deny" "deny" \
    'gh pr create --title "fix: bug" --body "Co-authored-by: Claude <noreply@anthropic.com>"'

# 5. generated with phrase in --body
assert_decision "PR create with 'generated with' in --body → deny" "deny" \
    'gh pr create --title "docs: update" --body "generated with assistance"'

echo ""
echo "[scope: issue / comment]"

# 6. attribution in `gh issue create --title`
assert_decision "issue create with 'claude' in --title → deny" "deny" \
    'gh issue create --title "Bug found by claude" --body "report"'

# 7. attribution in `gh issue comment --body`
assert_decision "issue comment with attribution in --body → deny" "deny" \
    'gh issue comment 42 --body "Generated with our pipeline tool"'

# 8. out-of-scope command — `gh repo view` is not gated
assert_decision "out-of-scope (gh repo view) → allow" "allow" \
    'gh repo view --json name,description'

echo ""
echo "[allow: clean and parser-deferred]"

# 9. clean PR create — neither title nor body matches the regex
assert_decision "clean PR create → allow" "allow" \
    'gh pr create --title "feat(api): add login endpoint" --body "Adds POST /auth/login"'

# 10. --body-file is deferred to other safeguards (commit-msg / CI verifier)
assert_decision "--body-file deferred → allow" "allow" \
    'gh pr create --title "feat: add ui" --body-file pr-body.md'

# 11. --body via $(...) command substitution — parser limit, deferred
assert_decision '$(...) command-substituted body → allow' "allow" \
    'gh pr create --title "feat: ship" --body "$(cat body.md)"'

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
