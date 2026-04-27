#!/bin/bash
# Parity test for p4-timeline-guard.sh and p4-timeline-guard.ps1 (#489).
# For every fixture, the bash decision and the PowerShell decision MUST agree.
# Skips silently when pwsh or jq is unavailable.
#
# Run: bash tests/hooks/test-p4-timeline-guard-parity.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
GUARD_SH="$ROOT_DIR/global/hooks/p4-timeline-guard.sh"
GUARD_PS="$ROOT_DIR/global/hooks/p4-timeline-guard.ps1"
REMINDER_SH="$ROOT_DIR/global/hooks/p4-timeline-reminder.sh"
REMINDER_PS="$ROOT_DIR/global/hooks/p4-timeline-reminder.ps1"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not in PATH" >&2
    exit 0
fi

if ! command -v pwsh >/dev/null 2>&1; then
    echo "SKIP: pwsh not in PATH (parity audit requires PowerShell 7+)" >&2
    exit 0
fi

if [ ! -f "$GUARD_PS" ]; then
    echo "FAIL: $GUARD_PS missing — PowerShell counterpart required for parity" >&2
    exit 1
fi
if [ ! -f "$REMINDER_PS" ]; then
    echo "FAIL: $REMINDER_PS missing — PowerShell counterpart required for parity" >&2
    exit 1
fi

PASS=0
FAIL=0
ERRORS=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

# Run guard (bash) and capture decision
sh_decision() {
    local settings="$1" input="$2"
    P4_SETTINGS_PATH="$settings" CLAUDE_P4_OVERRIDE="" bash "$GUARD_SH" <<<"$input" 2>/dev/null \
        | jq -r '.hookSpecificOutput.permissionDecision // "missing"'
}

# Run guard (pwsh) and capture decision
ps_decision() {
    local settings="$1" input="$2"
    P4_SETTINGS_PATH="$settings" CLAUDE_P4_OVERRIDE="" pwsh -NoProfile -File "$GUARD_PS" <<<"$input" 2>/dev/null \
        | jq -r '.hookSpecificOutput.permissionDecision // "missing"'
}

# Run guard (pwsh) with override env set
ps_decision_override() {
    local settings="$1" input="$2"
    P4_SETTINGS_PATH="$settings" CLAUDE_P4_OVERRIDE=1 pwsh -NoProfile -File "$GUARD_PS" <<<"$input" 2>/dev/null \
        | jq -r '.hookSpecificOutput.permissionDecision // "missing"'
}

# Run guard (bash) with override env set
sh_decision_override() {
    local settings="$1" input="$2"
    P4_SETTINGS_PATH="$settings" CLAUDE_P4_OVERRIDE=1 bash "$GUARD_SH" <<<"$input" 2>/dev/null \
        | jq -r '.hookSpecificOutput.permissionDecision // "missing"'
}

assert_parity() {
    local label="$1" sh="$2" ps="$3"
    if [ "$sh" = "$ps" ]; then
        PASS=$((PASS+1))
        echo "PASS: $label (both -> $sh)"
    else
        FAIL=$((FAIL+1))
        ERRORS+=("FAIL: $label (sh='$sh' vs ps='$ps')")
    fi
}

# ── Fixture set 1: future deadlines (windows still open) ────────────
FUTURE_SETTINGS="$WORK/future.json"
write_settings "$FUTURE_SETTINGS" "2099-01-01T00:00:00Z" "2099-02-01T00:00:00Z" "2099-03-01T00:00:00Z"

INPUT_FLIP_EDIT='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'
INPUT_FLIP_WRITE='{"tool_name":"Write","tool_input":{"file_path":"/x/settings.json","content":"{\"harness_policies\":{\"p4_strict_schema\":true}}"}}'
INPUT_OTHER='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.json","old_string":"a","new_string":"\"unrelated\": true"}}'
INPUT_DOC='{"tool_name":"Edit","tool_input":{"file_path":"/x/docs.md","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'
INPUT_LIST='{"tool_name":"Bash","tool_input":{"command":"gh pr list --repo foo/bar"}}'
INPUT_WINDOWS_FLIP='{"tool_name":"Edit","tool_input":{"file_path":"/x/settings.windows.json","old_string":"a","new_string":"\"p4_strict_schema\": true"}}'

assert_parity "future: Edit flip toggle (settings.json)" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_FLIP_EDIT")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_FLIP_EDIT")"

assert_parity "future: Write flip toggle (settings.json)" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_FLIP_WRITE")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_FLIP_WRITE")"

assert_parity "future: Edit unrelated field" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_OTHER")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_OTHER")"

assert_parity "future: Edit non-settings doc mentioning toggle" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_DOC")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_DOC")"

assert_parity "future: Bash gh pr list" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_LIST")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_LIST")"

assert_parity "future: Edit flip toggle (settings.windows.json)" \
    "$(sh_decision "$FUTURE_SETTINGS" "$INPUT_WINDOWS_FLIP")" \
    "$(ps_decision "$FUTURE_SETTINGS" "$INPUT_WINDOWS_FLIP")"

# Override env -> always allow on both implementations
assert_parity "future: override env on flip" \
    "$(sh_decision_override "$FUTURE_SETTINGS" "$INPUT_FLIP_EDIT")" \
    "$(ps_decision_override "$FUTURE_SETTINGS" "$INPUT_FLIP_EDIT")"

# ── Fixture set 2: past deadlines (windows closed) ──────────────────
PAST_SETTINGS="$WORK/past.json"
write_settings "$PAST_SETTINGS" "2000-01-01T00:00:00Z" "2000-02-01T00:00:00Z" "2000-03-01T00:00:00Z"

assert_parity "past: flip after observation closed" \
    "$(sh_decision "$PAST_SETTINGS" "$INPUT_FLIP_EDIT")" \
    "$(ps_decision "$PAST_SETTINGS" "$INPUT_FLIP_EDIT")"

assert_parity "past: Bash gh pr list (grace closed)" \
    "$(sh_decision "$PAST_SETTINGS" "$INPUT_LIST")" \
    "$(ps_decision "$PAST_SETTINGS" "$INPUT_LIST")"

# ── Fixture set 3: missing settings.json -> fail-open (allow) ───────
NOFILE="$WORK/does-not-exist.json"
assert_parity "missing settings.json -> fail-open" \
    "$(sh_decision "$NOFILE" "$INPUT_FLIP_EDIT")" \
    "$(ps_decision "$NOFILE" "$INPUT_FLIP_EDIT")"

# ── Fixture set 4: empty stdin -> allow ─────────────────────────────
EMPTY_SH=$(P4_SETTINGS_PATH="$FUTURE_SETTINGS" bash "$GUARD_SH" </dev/null 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // "missing"')
EMPTY_PS=$(P4_SETTINGS_PATH="$FUTURE_SETTINGS" pwsh -NoProfile -File "$GUARD_PS" </dev/null 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // "missing"')
assert_parity "empty stdin -> allow" "$EMPTY_SH" "$EMPTY_PS"

# ── Fixture set 5: reminder banner parity ───────────────────────────
# Reminder writes to stderr. We compare presence/absence of the banner header
# rather than exact byte equality (color codes, formatting may differ slightly).

reminder_emits_banner_sh() {
    local settings="$1"
    P4_SETTINGS_PATH="$settings" bash "$REMINDER_SH" 2>&1 >/dev/null \
        | grep -q "P4 Rollout Active" && echo "yes" || echo "no"
}
reminder_emits_banner_ps() {
    local settings="$1"
    P4_SETTINGS_PATH="$settings" pwsh -NoProfile -File "$REMINDER_PS" 2>&1 >/dev/null \
        | grep -q "P4 Rollout Active" && echo "yes" || echo "no"
}

assert_parity "reminder: banner inside grace window" \
    "$(reminder_emits_banner_sh "$FUTURE_SETTINGS")" \
    "$(reminder_emits_banner_ps "$FUTURE_SETTINGS")"

assert_parity "reminder: silent after rollout complete" \
    "$(reminder_emits_banner_sh "$PAST_SETTINGS")" \
    "$(reminder_emits_banner_ps "$PAST_SETTINGS")"

NO_TIMELINE="$WORK/no-timeline.json"
echo '{"harness_policies":{"p4_strict_schema":false}}' > "$NO_TIMELINE"
assert_parity "reminder: silent without timeline fields" \
    "$(reminder_emits_banner_sh "$NO_TIMELINE")" \
    "$(reminder_emits_banner_ps "$NO_TIMELINE")"

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "=== Parity Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '%s\n' "${ERRORS[@]}"
    exit 1
fi
exit 0
