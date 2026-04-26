#!/bin/bash
# Test suite for p4-timeline-guard.sh and p4-timeline-reminder.sh (#472).
# Run: bash tests/hooks/test-p4-timeline-guard.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
GUARD="$ROOT_DIR/global/hooks/p4-timeline-guard.sh"
REMINDER="$ROOT_DIR/global/hooks/p4-timeline-reminder.sh"

PASS=0
FAIL=0
ERRORS=()

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not in PATH" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Build a settings.json fixture with the given grace/observation timestamps
write_settings() {
    local file="$1" grace="$2" obs="$3" freeze="$4"
    cat > "$file" <<EOF
{
  "harness_policies": {
    "p4_strict_schema": false,
    "p4_d1_merged_at": "2026-04-26T22:15:57Z",
    "p4_grace_until": "$grace",
    "p4_observation_until": "$obs",
    "p4_freeze_until": "$freeze"
  }
}
EOF
}

# Run guard with given input + settings, capture decision
guard_decision() {
    local settings="$1" input="$2"
    P4_SETTINGS_PATH="$settings" CLAUDE_P4_OVERRIDE="" bash "$GUARD" <<<"$input" 2>/dev/null \
        | jq -r '.hookSpecificOutput.permissionDecision // "missing"'
}

# Run reminder with given settings, capture stderr
reminder_stderr() {
    local settings="$1"
    P4_SETTINGS_PATH="$settings" bash "$REMINDER" 2>&1 >/dev/null
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS+1))
        echo "PASS: $label"
    else
        FAIL=$((FAIL+1))
        ERRORS+=("FAIL: $label (expected '$expected', got '$actual')")
    fi
}

# ── Future deadlines (windows still open) ────────────────────────
FUTURE_SETTINGS="$WORK/future.json"
write_settings "$FUTURE_SETTINGS" "2099-01-01T00:00:00Z" "2099-02-01T00:00:00Z" "2099-03-01T00:00:00Z"

# 1. settings.json edit flipping p4_strict_schema to true -> deny
INPUT_FLIP='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'
assert_eq "deny" "$(guard_decision "$FUTURE_SETTINGS" "$INPUT_FLIP")" \
    "Edit flipping p4_strict_schema to true within observation -> deny"

# 2. Write new settings with toggle true -> deny
INPUT_WRITE='{"tool_name":"Write","tool_input":{"file_path":"/x/settings.json","content":"{\"harness_policies\":{\"p4_strict_schema\":true}}"}}'
assert_eq "deny" "$(guard_decision "$FUTURE_SETTINGS" "$INPUT_WRITE")" \
    "Write setting toggle true within observation -> deny"

# 3. Edit unrelated setting -> allow
INPUT_OTHER='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","old_string":"a","new_string":"\"unrelated\": true"}}'
assert_eq "allow" "$(guard_decision "$FUTURE_SETTINGS" "$INPUT_OTHER")" \
    "Edit unrelated settings field -> allow"

# 4. Edit non-settings file mentioning p4_strict_schema true -> allow (path not matched)
INPUT_DOC='{"tool_name":"Edit","tool_input":{"file_path":"/x/docs.md","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'
assert_eq "allow" "$(guard_decision "$FUTURE_SETTINGS" "$INPUT_DOC")" \
    "Edit non-settings file mentioning toggle -> allow"

# 5. Bash gh pr list -> allow
INPUT_LIST='{"tool_name":"Bash","tool_input":{"command":"gh pr list --repo foo/bar"}}'
assert_eq "allow" "$(guard_decision "$FUTURE_SETTINGS" "$INPUT_LIST")" \
    "Bash gh pr list -> allow"

# 6. Override env -> always allow
INPUT_FLIP_OVERRIDE='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'
ACT=$(P4_SETTINGS_PATH="$FUTURE_SETTINGS" CLAUDE_P4_OVERRIDE=1 bash "$GUARD" <<<"$INPUT_FLIP_OVERRIDE" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // "missing"')
assert_eq "allow" "$ACT" "Override env -> allow even on toggle flip"

# ── Past deadlines (windows already closed) ───────────────────────
PAST_SETTINGS="$WORK/past.json"
write_settings "$PAST_SETTINGS" "2000-01-01T00:00:00Z" "2000-02-01T00:00:00Z" "2000-03-01T00:00:00Z"

# 7. Toggle flip after observation closed -> allow
assert_eq "allow" "$(guard_decision "$PAST_SETTINGS" "$INPUT_FLIP")" \
    "Toggle flip after observation closed -> allow"

# ── Missing settings.json -> allow (fail-open per other guards) ───
NOFILE="$WORK/does-not-exist.json"
assert_eq "allow" "$(guard_decision "$NOFILE" "$INPUT_FLIP")" \
    "Missing settings.json -> allow (fail-open)"

# ── Reminder banner output ─────────────────────────────────────────
# Future window -> banner emitted
OUT=$(reminder_stderr "$FUTURE_SETTINGS")
if echo "$OUT" | grep -q "P4 Rollout Active"; then
    PASS=$((PASS+1)); echo "PASS: reminder emits banner inside grace"
else
    FAIL=$((FAIL+1)); ERRORS+=("FAIL: reminder did not emit banner inside grace")
fi
if echo "$OUT" | grep -q "GRACE"; then
    PASS=$((PASS+1)); echo "PASS: reminder marks GRACE window"
else
    FAIL=$((FAIL+1)); ERRORS+=("FAIL: reminder missing GRACE label")
fi

# Past window -> silent
OUT_PAST=$(reminder_stderr "$PAST_SETTINGS")
if [ -z "$OUT_PAST" ]; then
    PASS=$((PASS+1)); echo "PASS: reminder silent after rollout complete"
else
    FAIL=$((FAIL+1)); ERRORS+=("FAIL: reminder should be silent after rollout: $OUT_PAST")
fi

# Settings without timeline fields -> silent
NO_TIMELINE="$WORK/no-timeline.json"
echo '{"harness_policies":{"p4_strict_schema":false}}' > "$NO_TIMELINE"
OUT_NONE=$(reminder_stderr "$NO_TIMELINE")
if [ -z "$OUT_NONE" ]; then
    PASS=$((PASS+1)); echo "PASS: reminder silent when timeline fields absent"
else
    FAIL=$((FAIL+1)); ERRORS+=("FAIL: reminder should be silent without timeline: $OUT_NONE")
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "=== Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '%s\n' "${ERRORS[@]}"
    exit 1
fi
exit 0
