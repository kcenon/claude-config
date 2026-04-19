#!/bin/bash
# Test suite for pre-edit-read-guard.sh
# Run: bash tests/hooks/test-pre-edit-read-guard.sh

HOOK="global/hooks/pre-edit-read-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Per-test sandbox so the tracker does not leak between assertions.
TEST_SESSION="test-$$-${RANDOM}"
# Use the caller's TMPDIR (falls back to /tmp) so we stay within whatever
# sandbox write policy the runner enforces. mktemp is avoided because some
# harnesses deny mkdir in /var/folders.
BASE_TMPDIR="${TMPDIR:-/tmp}"
TRACKER_DIR="${BASE_TMPDIR%/}/claude-hook-test-$$-${RANDOM}"
mkdir -p "$TRACKER_DIR" || { echo "Cannot create $TRACKER_DIR"; exit 2; }
export TMPDIR="$TRACKER_DIR"
export CLAUDE_SESSION_ID="$TEST_SESSION"
TRACKER="$TRACKER_DIR/claude-read-set-$TEST_SESSION"

cleanup() {
    rm -rf "$TRACKER_DIR" 2>/dev/null || true
}
trap cleanup EXIT

reset_tracker() {
    rm -f "$TRACKER" 2>/dev/null || true
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(run_hook "$input")
    if echo "$result" | grep -q '"deny"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label -- expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2"
    local result
    result=$(run_hook "$input")
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label -- expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_silent() {
    local input="$1" label="$2"
    local result
    result=$(run_hook "$input")
    if [ -z "$result" ]; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label -- expected no output, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== pre-edit-read-guard.sh tests ==="
echo ""

# --- Fixtures ---------------------------------------------------------------
EXISTING_FILE="$TRACKER_DIR/existing.txt"
NEW_FILE="$TRACKER_DIR/brand-new.txt"
echo "seed" > "$EXISTING_FILE"
# Resolve to absolute path the hook will compute.
EXISTING_RESOLVED=$(realpath "$EXISTING_FILE" 2>/dev/null || echo "$EXISTING_FILE")
NEW_RESOLVED=$(realpath "$NEW_FILE" 2>/dev/null || echo "$NEW_FILE")

# --- Fail-open ------------------------------------------------------------
echo "[Fail-open]"
reset_tracker
# Empty input → exit 0 with no body (always fail-open).
OUT=$(run_hook '')
if [ -z "$OUT" ]; then
    ((PASS++)); echo "  PASS: Empty input -> silent fail-open"
else
    ((FAIL++)); ERRORS+=("Empty input should produce no output, got: $OUT"); echo "  FAIL: Empty input"
fi
# Malformed JSON → fail-open (hook cannot extract tool_name).
assert_allow '{"tool_name":"Edit","tool_input":{"file_path":"'"$EXISTING_RESOLVED"'"}}' "[warmup] allow when tracker absent (first-run safety)"

# --- Guard mode: tracker-missing ---------------------------------------------
echo ""
echo "[Guard: tracker missing -> first-run allow]"
reset_tracker
assert_allow "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Edit with no tracker -> allow"
assert_allow "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Write with no tracker -> allow"

# --- Guard mode: tracker present, file not read -----------------------------
echo ""
echo "[Guard: tracker present but file absent from it]"
reset_tracker
# Create tracker with a different path (to simulate "some other file was read").
mkdir -p "$TRACKER_DIR"
echo "/some/other/file" > "$TRACKER"
assert_deny "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Edit on unread existing file -> deny"
# Write on a non-existent target must still be allowed (new file).
assert_allow "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$NEW_RESOLVED\"}}" "Write on new (non-existent) file -> allow"
# Write on an EXISTING unread file should be denied too.
assert_deny "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Write on existing unread file -> deny"

# --- Track mode: Read populates tracker -------------------------------------
echo ""
echo "[Track: Read -> tracker append]"
reset_tracker
# Tracker starts absent.
[ ! -f "$TRACKER" ] && { ((PASS++)); echo "  PASS: Tracker initially absent"; } \
    || { ((FAIL++)); ERRORS+=("Tracker should be absent at start"); echo "  FAIL: Tracker leaked"; }
assert_silent "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Read emits no JSON"
# Tracker must now list the file.
if grep -Fxq "$EXISTING_RESOLVED" "$TRACKER" 2>/dev/null; then
    ((PASS++)); echo "  PASS: Tracker contains read file"
else
    ((FAIL++)); ERRORS+=("Tracker missing entry for $EXISTING_RESOLVED after Read"); echo "  FAIL: tracker not populated"
fi
# Running Read again must not double-count (deduplication).
assert_silent "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Read again emits no JSON"
COUNT=$(grep -Fxc "$EXISTING_RESOLVED" "$TRACKER" 2>/dev/null || echo 0)
if [ "$COUNT" = "1" ]; then
    ((PASS++)); echo "  PASS: Duplicate Read deduplicated"
else
    ((FAIL++)); ERRORS+=("Tracker dup count=$COUNT expected 1"); echo "  FAIL: duplicate entries"
fi

# --- Read-then-Edit allows the edit -----------------------------------------
echo ""
echo "[Read-then-Edit unlock]"
assert_allow "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Edit after Read -> allow"
assert_allow "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$EXISTING_RESOLVED\"}}" "Write after Read -> allow"

# --- Unknown tool pass-through ----------------------------------------------
echo ""
echo "[Unknown tool]"
assert_allow "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi\"}}" "Unknown tool -> allow (non-interfering)"

# --- Summary ----------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
exit 0
