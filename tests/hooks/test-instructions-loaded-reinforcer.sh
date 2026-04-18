#!/bin/bash
# Test suite for instructions-loaded-reinforcer.sh
# Run: bash tests/hooks/test-instructions-loaded-reinforcer.sh

HOOK="global/hooks/instructions-loaded-reinforcer.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_contains() {
    local needle="$1" label="$2"
    local result
    result=$(echo '{}' | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — needle '$needle' not found")
        echo "  FAIL: $label"
    fi
}

assert_valid_json() {
    local label="$1"
    local result
    result=$(echo '{}' | bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq empty >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    elif echo "$result" | python3 -m json.tool >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    elif echo "$result" | python -m json.tool >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — invalid JSON: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== instructions-loaded-reinforcer.sh tests ==="
echo ""

echo "[output structure]"
assert_valid_json "produces valid JSON"
assert_contains '"hookEventName"' "includes hookEventName field"
assert_contains '"InstructionsLoaded"' "event name is InstructionsLoaded"
assert_contains '"additionalContext"' "includes additionalContext field"

echo ""
echo "[policy content]"
assert_contains 'Conventional Commits' "mentions Conventional Commits"
assert_contains 'AI/Claude attribution\|attribution' "mentions attribution policy"
assert_contains 'develop' "mentions develop branch policy"

echo ""
echo "[exit code]"
echo '{}' | bash "$HOOK" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: exit code is 0"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: exit code expected 0, got $RC")
    echo "  FAIL: exit code"
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
