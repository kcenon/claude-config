#!/bin/bash
# p4-timeline-reminder.sh
# SessionStart banner that surfaces the active P4 rollout window.
# Hook Type: SessionStart
# Exit codes: 0 (always - lifecycle event)
# Response format: none (writes to stderr; visible in terminal)
#
# Reads harness_policies timestamps from ~/.claude/settings.json and prints
# a colored banner on stderr indicating which window is currently active and
# how much time remains. Silent when the rollout is fully complete (now() >=
# p4_freeze_until) or when the relevant fields are absent.

SETTINGS_PATH="${P4_SETTINGS_PATH:-${HOME}/.claude/settings.json}"
POLICY_PATH="${P4_POLICY_PATH:-${HOME}/.claude/policies/p4-timeline.json}"

[ -f "$POLICY_PATH" ] || [ -f "$SETTINGS_PATH" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Phase 1 dual-read: prefer the new policy file, fall back to harness_policies in settings.json.
read_policy_value() {
    local jq_filter="$1"
    local val=""
    if [ -f "$POLICY_PATH" ]; then
        val=$(jq -r "${jq_filter} // empty" "$POLICY_PATH" 2>/dev/null)
    fi
    if [ -z "$val" ] && [ -f "$SETTINGS_PATH" ]; then
        val=$(jq -r ".harness_policies${jq_filter} // empty" "$SETTINGS_PATH" 2>/dev/null)
    fi
    printf '%s' "$val"
}

read_iso_epoch() {
    local field="$1"
    local iso
    iso=$(read_policy_value ".${field}")
    [ -z "$iso" ] && return 0
    if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null; then
        return 0
    fi
    date -u -d "$iso" +%s 2>/dev/null || true
}

GRACE_EPOCH=$(read_iso_epoch p4_grace_until)
OBS_EPOCH=$(read_iso_epoch p4_observation_until)
FREEZE_EPOCH=$(read_iso_epoch p4_freeze_until)

# Silent when no timeline is configured at all
if [ -z "$GRACE_EPOCH" ] && [ -z "$OBS_EPOCH" ] && [ -z "$FREEZE_EPOCH" ]; then
    exit 0
fi

NOW_EPOCH=$(date -u +%s)

# Silent when the rollout is fully complete
if [ -n "$FREEZE_EPOCH" ] && [ "$NOW_EPOCH" -ge "$FREEZE_EPOCH" ]; then
    exit 0
fi

# Color helpers - disabled when stderr is not a TTY
if [ -t 2 ]; then
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    GREEN='\033[1;32m'
    RESET='\033[0m'
else
    YELLOW=''
    CYAN=''
    GREEN=''
    RESET=''
fi

format_remaining() {
    local target="$1"
    local remain=$((target - NOW_EPOCH))
    if [ "$remain" -le 0 ]; then
        echo "ended"
        return
    fi
    local days=$((remain / 86400))
    local hours=$(((remain % 86400) / 3600))
    echo "${days}d ${hours}h remaining"
}

format_iso() {
    local epoch="$1"
    date -u -r "$epoch" "+%Y-%m-%d %H:%M UTC" 2>/dev/null || \
        date -u -d "@$epoch" "+%Y-%m-%d %H:%M UTC" 2>/dev/null
}

WINDOW=""
DEADLINE_EPOCH=""
NEXT_ACTION=""

if [ -n "$GRACE_EPOCH" ] && [ "$NOW_EPOCH" -lt "$GRACE_EPOCH" ]; then
    WINDOW="GRACE (lenient only)"
    DEADLINE_EPOCH="$GRACE_EPOCH"
    NEXT_ACTION="D2 (#462) merge eligible after grace ends"
elif [ -n "$OBS_EPOCH" ] && [ "$NOW_EPOCH" -lt "$OBS_EPOCH" ]; then
    WINDOW="OBSERVATION (collecting metrics)"
    DEADLINE_EPOCH="$OBS_EPOCH"
    NEXT_ACTION="p4_strict_schema flip eligible after observation ends"
elif [ -n "$FREEZE_EPOCH" ] && [ "$NOW_EPOCH" -lt "$FREEZE_EPOCH" ]; then
    WINDOW="FREEZE (72h post-D2)"
    DEADLINE_EPOCH="$FREEZE_EPOCH"
    NEXT_ACTION="Default toggle flip eligible after freeze ends"
else
    exit 0
fi

REMAINING=$(format_remaining "$DEADLINE_EPOCH")
DEADLINE_ISO=$(format_iso "$DEADLINE_EPOCH")

printf "%b" "${YELLOW}P4 Rollout Active${RESET}\n" >&2
printf "  Window:   ${CYAN}%s${RESET}\n" "$WINDOW" >&2
printf "  Ends:     %s (%s)\n" "$DEADLINE_ISO" "$REMAINING" >&2
printf "  Next:     ${GREEN}%s${RESET}\n" "$NEXT_ACTION" >&2
printf "  Override: CLAUDE_P4_OVERRIDE=1 (RCA required; see COMPATIBILITY.md)\n" >&2

exit 0
