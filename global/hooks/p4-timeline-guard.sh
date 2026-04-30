#!/bin/bash
# p4-timeline-guard.sh
# Blocks Claude-initiated actions that violate the EPIC #454 P4 rollout timeline.
# Hook Type: PreToolUse (Bash | Edit | Write)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName + permissionDecision
#
# Two protected actions:
#   1. gh pr merge of a PR whose diff touches global/skills/_internal/
#      -> blocked until p4_grace_until passes
#   2. Edit/Write to settings.json that flips harness_policies.p4_strict_schema
#      from false to true
#      -> blocked until p4_observation_until passes
#
# Override: set CLAUDE_P4_OVERRIDE=1 in the environment with the reason
# documented in COMPATIBILITY.md (incident response, RCA-required).

SETTINGS_PATH="${P4_SETTINGS_PATH:-${HOME}/.claude/settings.json}"
POLICY_PATH="${P4_POLICY_PATH:-${HOME}/.claude/policies/p4-timeline.json}"

deny_response() {
    local reason="$1"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0
}

allow_response() {
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
}

# Override gate
if [ "${CLAUDE_P4_OVERRIDE:-}" = "1" ]; then
    allow_response
fi

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    allow_response
fi

# Required deps - if jq missing, fail-open (other guards already enforce policy)
if ! command -v jq >/dev/null 2>&1; then
    allow_response
fi

# Neither policy file nor settings.json present on fresh installs - allow
if [ ! -f "$POLICY_PATH" ] && [ ! -f "$SETTINGS_PATH" ]; then
    allow_response
fi

# Helper: read a value from the policy file (dot-prefixed jq filter, e.g. ".p4_strict_schema").
# Falls back to .harness_policies.<key> in settings.json when the policy file is absent or
# returns empty/null. Phase 1 dual-read; Phase 2 will drop the settings.json fallback.
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

# Helper: read ISO timestamp field, output epoch seconds (or empty)
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

NOW_EPOCH=$(date -u +%s)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# ── Branch 1: Bash matcher ──────────────────────────────────────
if [ "$TOOL" = "Bash" ]; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    case "$CMD" in
        *"gh pr merge"*)
            GRACE_EPOCH=$(read_iso_epoch p4_grace_until)
            if [ -z "$GRACE_EPOCH" ]; then
                allow_response
            fi
            if [ "$NOW_EPOCH" -ge "$GRACE_EPOCH" ]; then
                allow_response
            fi
            # Extract PR number; if missing, allow (cannot evaluate)
            PR_NUM=$(echo "$CMD" | grep -oE 'gh pr merge[[:space:]]+([0-9]+)' | grep -oE '[0-9]+' | head -1)
            if [ -z "$PR_NUM" ]; then
                allow_response
            fi
            REPO_FLAG=$(echo "$CMD" | grep -oE -- '--repo[[:space:]]+[^[:space:]]+' | awk '{print $2}')
            REPO_ARG=""
            [ -n "$REPO_FLAG" ] && REPO_ARG="--repo $REPO_FLAG"
            # If gh unavailable or call fails, allow (cannot evaluate diff)
            if ! command -v gh >/dev/null 2>&1; then
                allow_response
            fi
            DIFF_FILES=$(gh pr diff $REPO_ARG "$PR_NUM" --name-only 2>/dev/null || true)
            if echo "$DIFF_FILES" | grep -q "^global/skills/_internal/"; then
                REMAIN=$((GRACE_EPOCH - NOW_EPOCH))
                DAYS=$((REMAIN / 86400))
                HOURS=$(((REMAIN % 86400) / 3600))
                deny_response "P4 grace window not closed (${DAYS}d ${HOURS}h remaining). PR #${PR_NUM} touches global/skills/_internal/ which requires the 7-day grace window to pass first per EPIC #454. Override with CLAUDE_P4_OVERRIDE=1 (RCA required)."
            fi
            allow_response
            ;;
    esac
fi

# ── Branch 2: Edit/Write matcher (settings.json toggle flip) ────
if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    case "$FILE_PATH" in
        *settings.json|*settings.windows.json)
            OBS_EPOCH=$(read_iso_epoch p4_observation_until)
            if [ -z "$OBS_EPOCH" ] || [ "$NOW_EPOCH" -ge "$OBS_EPOCH" ]; then
                allow_response
            fi
            # Detect a flip: new content sets p4_strict_schema true while
            # current value is false.
            CURRENT=$(read_policy_value '.p4_strict_schema')
            [ "$CURRENT" = "true" ] && allow_response
            NEW_BLOB=""
            if [ "$TOOL" = "Write" ]; then
                NEW_BLOB=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
            else
                NEW_BLOB=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
            fi
            # Match the JSON form `"p4_strict_schema": true` (whitespace-tolerant)
            if echo "$NEW_BLOB" | grep -qE '"p4_strict_schema"[[:space:]]*:[[:space:]]*true'; then
                REMAIN=$((OBS_EPOCH - NOW_EPOCH))
                DAYS=$((REMAIN / 86400))
                HOURS=$(((REMAIN % 86400) / 3600))
                deny_response "P4 observation window not closed (${DAYS}d ${HOURS}h remaining). harness_policies.p4_strict_schema cannot be flipped to true until the 14-day observation window passes per EPIC #454. Override with CLAUDE_P4_OVERRIDE=1 (RCA required)."
            fi
            ;;
    esac
fi

allow_response
