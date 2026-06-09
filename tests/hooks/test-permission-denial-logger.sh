#!/bin/bash
# Test suite for permission-denial-logger.sh
# Run: bash tests/hooks/test-permission-denial-logger.sh
#
# The hook is a passive PermissionDenied logger: it must never emit
# permission-altering output, must redact secrets before writing, and must
# honor the CLAUDE_PERMISSION_LOGGER=0 opt-out. Tests run against an isolated
# CLAUDE_LOG_DIR so the real ~/.claude/logs is never touched.

HOOK="global/hooks/permission-denial-logger.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Fresh isolated log dir per invocation of the hook.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# run_hook <env-prefix> <json-input> -> echoes the log file path; populates
# global LAST_STDOUT and LAST_RC.
LAST_STDOUT=""
LAST_RC=0
run_hook() {
    local logdir="$TMP_ROOT/$RANDOM-$RANDOM/logs"
    LAST_STDOUT=$(printf '%s' "$2" | env CLAUDE_LOG_DIR="$logdir" $1 bash "$HOOK" 2>/dev/null)
    LAST_RC=$?
    echo "$logdir/permission-denials.jsonl"
}

assert_log_contains() {
    local logfile="$1" needle="$2" label="$3"
    if [ -f "$logfile" ] && grep -qF "$needle" "$logfile"; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label — '$needle' not found in $(cat "$logfile" 2>/dev/null)")
        echo "  FAIL: $label"
    fi
}

assert_log_absent_pattern() {
    local logfile="$1" pattern="$2" label="$3"
    if [ -f "$logfile" ] && grep -qE "$pattern" "$logfile"; then
        ((FAIL++)); ERRORS+=("FAIL: $label — leaked pattern '$pattern' in $(cat "$logfile")")
        echo "  FAIL: $label"
    else
        ((PASS++)); echo "  PASS: $label"
    fi
}

assert_no_logfile() {
    local logfile="$1" label="$2"
    if [ ! -f "$logfile" ]; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label — log file unexpectedly created")
        echo "  FAIL: $label"
    fi
}

assert_true() {
    local cond="$1" label="$2"
    if [ "$cond" = "1" ]; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label")
        echo "  FAIL: $label"
    fi
}

echo "=== permission-denial-logger.sh tests ==="
echo ""

echo "[Basic logging]"
LOG=$(run_hook "" '{"session_id":"sess-1","tool_name":"Bash","tool_input":{"command":"ls /etc"},"permission_suggestions":[]}')
assert_true "$([ "$LAST_RC" = "0" ] && echo 1)" "exit 0 on normal denial"
assert_log_contains "$LOG" '"tool_name":"Bash"' "records tool_name"
assert_log_contains "$LOG" '"session_id":"sess-1"' "records session_id"
assert_log_contains "$LOG" 'tool_input_redacted' "records tool_input_redacted field"

echo ""
echo "[Passive contract — no stdout, never blocks]"
run_hook "" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' >/dev/null
assert_true "$([ -z "$LAST_STDOUT" ] && echo 1)" "emits nothing on stdout (no permission output)"
assert_true "$([ "$LAST_RC" = "0" ] && echo 1)" "exit 0 even for a dangerous command"

echo ""
echo "[Opt-out]"
LOG=$(run_hook "CLAUDE_PERMISSION_LOGGER=0" '{"tool_name":"Bash","tool_input":{"command":"ls"}}')
assert_true "$([ "$LAST_RC" = "0" ] && echo 1)" "CLAUDE_PERMISSION_LOGGER=0 exits 0"
assert_no_logfile "$LOG" "CLAUDE_PERMISSION_LOGGER=0 writes nothing"

echo ""
echo "[Redaction — secrets must not reach disk]"
# Secret-shaped fixtures are assembled at runtime via adjacent-quote
# concatenation so no contiguous secret pattern appears in the committed
# source (would trip secret scanners such as GitGuardian). The assembled
# runtime values are real-shaped and exercise the hook's redaction regex.
fake_bearer='sk-''live-SECRET12345'
fake_urlpw='hunter2''PW'
fake_pat='ghp_''ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
redaction_cmd=$(printf 'curl -H "Authorization: Bearer %s" https://u:%s@h.example/x?token=%s' \
    "$fake_bearer" "$fake_urlpw" "$fake_pat")
redaction_input=$(jq -cn --arg cmd "$redaction_cmd" \
    '{tool_name:"Bash", tool_input:{command:$cmd}}')
LOG=$(run_hook "" "$redaction_input")
assert_log_contains "$LOG" '<REDACTED>' "writes a <REDACTED> marker"
assert_log_absent_pattern "$LOG" "$fake_bearer" "bearer token scrubbed"
assert_log_absent_pattern "$LOG" "$fake_urlpw" "URL inline password scrubbed"
assert_log_absent_pattern "$LOG" "$fake_pat" "github PAT scrubbed"

echo ""
echo "[Fail-closed input handling]"
LOG=$(run_hook "" '')
assert_true "$([ "$LAST_RC" = "0" ] && echo 1)" "empty stdin exits 0"
assert_log_contains "$LOG" 'empty or unparseable hook input' "empty stdin logs marker line"
LOG=$(run_hook "" 'NOT JSON {{{')
assert_true "$([ "$LAST_RC" = "0" ] && echo 1)" "malformed JSON exits 0"
assert_log_contains "$LOG" 'empty or unparseable hook input' "malformed JSON logs marker line"

echo ""
echo "[Valid JSONL output]"
LOG=$(run_hook "" '{"session_id":"s","tool_name":"Write","tool_input":{"file_path":"/x"},"permission_suggestions":[{"behavior":"allow","rule":"Write(/x)"}]}')
if command -v jq >/dev/null 2>&1; then
    if jq -e . "$LOG" >/dev/null 2>&1; then
        ((PASS++)); echo "  PASS: emitted line is valid JSON"
    else
        ((FAIL++)); ERRORS+=("FAIL: emitted line is not valid JSON: $(cat "$LOG")")
        echo "  FAIL: emitted line is not valid JSON"
    fi
else
    echo "  SKIP: jq unavailable — JSON validity check skipped"
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
