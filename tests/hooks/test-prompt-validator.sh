#!/bin/bash
# Test suite for prompt-validator.sh
# Run: bash tests/hooks/test-prompt-validator.sh
#
# prompt-validator.sh reads CLAUDE_USER_PROMPT env var (not stdin JSON).
# It returns JSON with additionalContext for dangerous prompts, or exits silently for safe ones.

HOOK="global/hooks/prompt-validator.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_warning() {
    local prompt="$1" label="$2"
    local result
    result=$(CLAUDE_USER_PROMPT="$prompt" bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"additionalContext"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected warning, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_silent() {
    local prompt="$1" label="$2"
    local result
    result=$(CLAUDE_USER_PROMPT="$prompt" bash "$HOOK" 2>/dev/null)
    # Silent allow: no JSON output (empty or no additionalContext)
    if [ -z "$result" ] || ! echo "$result" | grep -q '"additionalContext"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected silent allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== prompt-validator.sh tests ==="
echo ""

# --- Empty / missing prompt ---
echo "[Empty prompt]"
result=$(CLAUDE_USER_PROMPT="" bash "$HOOK" 2>/dev/null)
exit_code=$?
if [ $exit_code -eq 0 ] && [ -z "$result" ]; then
    ((PASS++))
    echo "  PASS: Empty prompt → silent allow"
else
    ((FAIL++))
    ERRORS+=("FAIL: Empty prompt — expected silent allow (exit 0, no output)")
    echo "  FAIL: Empty prompt → silent allow"
fi

result=$(unset CLAUDE_USER_PROMPT; bash "$HOOK" 2>/dev/null)
exit_code=$?
if [ $exit_code -eq 0 ] && [ -z "$result" ]; then
    ((PASS++))
    echo "  PASS: Unset prompt → silent allow"
else
    ((FAIL++))
    ERRORS+=("FAIL: Unset prompt — expected silent allow")
    echo "  FAIL: Unset prompt → silent allow"
fi

# The hook regex: (delete|remove|drop)\s+(all|entire|whole|database|table|production)
# Only matches when the keyword is DIRECTLY followed by the target word (no "the" in between).

# --- Dangerous patterns: delete ---
echo ""
echo "[Dangerous: delete patterns]"
assert_warning "delete all files in the project" "delete all → warning"
assert_warning "Delete entire database" "Delete entire → warning"
assert_warning "delete whole directory now" "delete whole → warning"
assert_warning "delete production data" "delete production → warning"
assert_warning "delete table users" "delete table → warning"
assert_warning "DELETE ALL records from the database" "DELETE ALL (uppercase) → warning"
assert_warning "delete database completely" "delete database → warning"

# --- Dangerous patterns: remove ---
echo ""
echo "[Dangerous: remove patterns]"
assert_warning "remove all data" "remove all → warning"
assert_warning "Remove entire directory" "Remove entire → warning"
assert_warning "remove whole cluster" "remove whole → warning"
assert_warning "remove production environment" "remove production → warning"
assert_warning "remove table sessions" "remove table → warning"
assert_warning "remove database backup" "remove database → warning"

# --- Dangerous patterns: drop ---
echo ""
echo "[Dangerous: drop patterns]"
assert_warning "drop all tables" "drop all → warning"
assert_warning "drop entire schema" "drop entire → warning"
assert_warning "drop database mydb" "drop database → warning"
assert_warning "DROP TABLE users" "DROP TABLE (uppercase) → warning"
assert_warning "drop production database" "drop production → warning"
assert_warning "drop whole cluster" "drop whole → warning"

# --- Patterns with intervening words (NOT matched by current regex) ---
echo ""
echo "[Not matched: intervening words]"
assert_silent "delete the production server" "delete the production → silent (intervening 'the')"
assert_silent "please delete the whole thing" "delete the whole → silent (intervening 'the')"
assert_silent "drop the database" "drop the database → silent (intervening 'the')"
assert_silent "drop the entire schema" "drop the entire → silent (intervening 'the')"
assert_silent "remove the production environment" "remove the production → silent (intervening 'the')"

# --- Safe prompts ---
echo ""
echo "[Safe prompts]"
assert_silent "list all files" "list all → silent"
assert_silent "show me the database schema" "show database → silent"
assert_silent "how do I delete a single record?" "question about delete → silent"
assert_silent "create a new table" "create table → silent"
assert_silent "refactor the authentication module" "refactor → silent"
assert_silent "run the tests" "run tests → silent"
assert_silent "fix the login bug" "fix bug → silent"
assert_silent "add error handling to the controller" "add error handling → silent"

# --- Edge cases: partial keyword matches ---
echo ""
echo "[Edge cases]"
assert_silent "the dropdown menu is broken" "dropdown (contains 'drop') → silent"
assert_silent "removed the unused import" "past tense 'removed' → silent"
assert_silent "undelete the record" "undelete → silent"

# --- Exit code is always 0 ---
echo ""
echo "[Exit code always 0]"
CLAUDE_USER_PROMPT="delete all databases" bash "$HOOK" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    ((PASS++))
    echo "  PASS: Warning prompt → exit 0"
else
    ((FAIL++))
    ERRORS+=("FAIL: Warning prompt — expected exit 0")
    echo "  FAIL: Warning prompt → exit 0"
fi

CLAUDE_USER_PROMPT="list files" bash "$HOOK" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    ((PASS++))
    echo "  PASS: Safe prompt → exit 0"
else
    ((FAIL++))
    ERRORS+=("FAIL: Safe prompt — expected exit 0")
    echo "  FAIL: Safe prompt → exit 0"
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
