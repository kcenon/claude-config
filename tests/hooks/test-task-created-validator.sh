#!/bin/bash
# Test suite for task-created-validator.sh
# Run: bash tests/hooks/test-task-created-validator.sh

HOOK="global/hooks/task-created-validator.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_exit() {
    local input="$1" expected="$2" label="$3"
    local actual
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1
    actual=$?
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $actual)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected exit $expected, got $actual")
        echo "  FAIL: $label (expected $expected, got $actual)"
    fi
}

assert_stderr_contains() {
    local input="$1" needle="$2" label="$3"
    local stderr
    stderr=$(printf '%s' "$input" | bash "$HOOK" 2>&1 >/dev/null)
    if echo "$stderr" | grep -q "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — stderr did not contain '$needle': $stderr")
        echo "  FAIL: $label"
    fi
}

echo "=== task-created-validator.sh tests ==="
echo ""

echo "[valid task — passes]"
VALID='{"tool_input":{"description":"Implement feature with steps:\n- [ ] Step 1\n- [ ] Step 2"}}'
assert_exit "$VALID" 0 "long description with checkboxes -> approve"

VALID2='{"description":"Refactor module X for clarity:\n- [ ] Extract helper\n- [ ] Update tests"}'
assert_exit "$VALID2" 0 "top-level description field -> approve"

echo ""
echo "[short description — blocks]"
SHORT='{"tool_input":{"description":"do it"}}'
assert_exit "$SHORT" 2 "5-char description -> exit 2"
assert_stderr_contains "$SHORT" "at least 20 characters" "short description error message"

echo ""
echo "[missing checkbox — blocks]"
NO_BOX='{"tool_input":{"description":"Implement feature X with substantial scope and context"}}'
assert_exit "$NO_BOX" 2 "long description, no checkbox -> exit 2"
assert_stderr_contains "$NO_BOX" "checkbox" "missing checkbox error message"

echo ""
echo "[empty description — blocks]"
EMPTY='{"tool_input":{"description":""}}'
assert_exit "$EMPTY" 2 "empty description -> exit 2"
assert_stderr_contains "$EMPTY" "at least 20 characters" "empty description error message"

echo ""
echo "[edge cases — pass through]"
assert_exit '' 0 "empty stdin -> approve (fail open)"
assert_exit '{}' 0 "empty JSON object -> approve (fail open, no description)"

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
