#!/bin/bash
# Test suite for team-limit-guard.sh
# Run: bash tests/hooks/test-team-limit-guard.sh

HOOK="global/hooks/team-limit-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Create a temp dir to use as HOME so we don't touch the real ~/.claude/teams
TEST_HOME="${TMPDIR:-/tmp}/test-team-limit-guard-$$"
mkdir -p "$TEST_HOME"
trap 'rm -rf "$TEST_HOME"' EXIT

# Clear MAX_TEAMS from env so the hook uses its default (3)
unset MAX_TEAMS

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | HOME="$TEST_HOME" bash "$HOOK" 2>/dev/null)
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
    result=$(echo "$input" | HOME="$TEST_HOME" bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== team-limit-guard.sh tests ==="
echo ""

# --- No teams directory ---
echo "[No teams directory]"
rm -rf "$TEST_HOME/.claude/teams"
assert_allow '{}' "No teams directory → allow"

# --- Empty teams directory ---
echo ""
echo "[Empty teams directory]"
mkdir -p "$TEST_HOME/.claude/teams"
assert_allow '{}' "Empty teams dir (0 teams, limit 3) → allow"

# --- Below limit ---
echo ""
echo "[Below limit]"
mkdir -p "$TEST_HOME/.claude/teams/team-1"
mkdir -p "$TEST_HOME/.claude/teams/team-2"
assert_allow '{}' "2 teams (limit 3) → allow"

# --- At limit (default MAX_TEAMS=3) ---
echo ""
echo "[At limit — default MAX_TEAMS=3]"
mkdir -p "$TEST_HOME/.claude/teams/team-3"
assert_deny '{}' "3 teams (limit 3) → deny"

# --- Above limit ---
echo ""
echo "[Above limit]"
mkdir -p "$TEST_HOME/.claude/teams/team-4"
assert_deny '{}' "4 teams (limit 3) → deny"

# --- MAX_TEAMS override from env ---
echo ""
echo "[MAX_TEAMS env override]"
# With 4 teams and MAX_TEAMS=5, should allow
result=$(echo '{}' | HOME="$TEST_HOME" MAX_TEAMS=5 bash "$HOOK" 2>/dev/null)
if echo "$result" | grep -q '"allow"'; then
    ((PASS++))
    echo "  PASS: 4 teams with MAX_TEAMS=5 → allow"
else
    ((FAIL++))
    ERRORS+=("FAIL: 4 teams with MAX_TEAMS=5 — expected allow, got: $result")
    echo "  FAIL: 4 teams with MAX_TEAMS=5 → allow"
fi

# With 4 teams and MAX_TEAMS=4, should deny
result=$(echo '{}' | HOME="$TEST_HOME" MAX_TEAMS=4 bash "$HOOK" 2>/dev/null)
if echo "$result" | grep -q '"deny"'; then
    ((PASS++))
    echo "  PASS: 4 teams with MAX_TEAMS=4 → deny"
else
    ((FAIL++))
    ERRORS+=("FAIL: 4 teams with MAX_TEAMS=4 — expected deny, got: $result")
    echo "  FAIL: 4 teams with MAX_TEAMS=4 → deny"
fi

# With 4 teams and MAX_TEAMS=1, should deny
result=$(echo '{}' | HOME="$TEST_HOME" MAX_TEAMS=1 bash "$HOOK" 2>/dev/null)
if echo "$result" | grep -q '"deny"'; then
    ((PASS++))
    echo "  PASS: 4 teams with MAX_TEAMS=1 → deny"
else
    ((FAIL++))
    ERRORS+=("FAIL: 4 teams with MAX_TEAMS=1 — expected deny, got: $result")
    echo "  FAIL: 4 teams with MAX_TEAMS=1 → deny"
fi

# --- Files in teams dir should not count (only directories) ---
echo ""
echo "[Only directories count]"
rm -rf "$TEST_HOME/.claude/teams"
mkdir -p "$TEST_HOME/.claude/teams"
touch "$TEST_HOME/.claude/teams/not-a-dir.txt"
touch "$TEST_HOME/.claude/teams/also-not-a-dir"
mkdir -p "$TEST_HOME/.claude/teams/real-team"
# 1 directory, 2 files — should allow with default limit 3
assert_allow '{}' "1 dir + 2 files (limit 3) → allow (files ignored)"

# --- Cleanup and re-test allow after removing teams ---
echo ""
echo "[After removing teams]"
rm -rf "$TEST_HOME/.claude/teams"
mkdir -p "$TEST_HOME/.claude/teams"
assert_allow '{}' "Cleared teams dir → allow"

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
