#!/bin/bash
# shell-env-secret-guard.sh
# Blocks bash commands that would print or dump secret-bearing environment
# variables into the transcript.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Rationale: Codex scrubs *KEY*/*SECRET*/*TOKEN*/AWS_* env vars from the child
# process via config.toml [shell_environment_policy].exclude. A Claude hook runs
# out-of-process and cannot mutate the bash child's env, so the achievable
# analog is to DENY commands that leak a named secret var (echo/printf/printenv
# $SECRET) and WARN on bare env dumps. Deliberately narrow to avoid breaking
# legitimate tooling (e.g. `gh api`, which uses GH_TOKEN internally, not via
# $-expansion).
#
# Matching is CASE-SENSITIVE and segment-aware: the secret keyword must be an
# underscore-delimited segment/suffix of an UPPER_SNAKE var name, so API_KEY /
# AWS_SECRET_ACCESS_KEY / GITHUB_TOKEN match while TOKENIZER / KEYBOARD / monkey
# do not.

set -euo pipefail

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/shell-env-secret-guard.log"

log_decision() {
    local decision="$1" reason="$2" cmd="$3"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg ts "$ts" --arg d "$decision" --arg r "$reason" --arg c "$cmd" \
            '{ts:$ts, decision:$d, reason:$r, command:$c}' >>"$LOG_FILE" 2>/dev/null || true
    else
        local esc_cmd esc_reason
        esc_cmd=${cmd//\\/\\\\}; esc_cmd=${esc_cmd//\"/\\\"}
        esc_reason=${reason//\\/\\\\}; esc_reason=${esc_reason//\"/\\\"}
        printf '{"ts":"%s","decision":"%s","reason":"%s","command":"%s"}\n' \
            "$ts" "$decision" "$esc_reason" "$esc_cmd" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

deny_response() {
    local reason="$1"
    log_decision "deny" "$reason" "${CMD:-}"
    jq -nc --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

allow_response() {
    local reason="${1:-shell-env-secret-guard: no secret-exposure pattern matched}"
    log_decision "allow" "$reason" "${CMD:-}"
    jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
    exit 0
}

allow_with_context() {
    local reason="$1"
    log_decision "allow-warn" "$reason" "${CMD:-}"
    jq -nc --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", additionalContext: $reason}}'
    exit 0
}

INPUT=$(cat)

# Fail-open on unparseable/empty input: dangerous-command-guard in the same
# chain is fail-closed, so this guard stays quiet to avoid double-denial noise.
if [ -z "$INPUT" ]; then
    CMD=""
    allow_response
fi

JQ_RC=0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || JQ_RC=$?
if [ "$JQ_RC" -ne 0 ]; then
    CMD=""
    allow_response
fi
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi
if [ -z "$CMD" ]; then
    allow_response
fi

# Secret keyword as an underscore-delimited segment/suffix of an UPPER_SNAKE
# var name. Trailing '([^A-Z0-9]|$)' is the right boundary so TOKEN in
# TOKENIZER does not match.
SECRET_SEG='([A-Z0-9_]*_)?(KEY|KEYS|SECRET|SECRETS|TOKEN|TOKENS|PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|CREDENTIALS)([^A-Z0-9]|$)'

# DENY 1: echo/printf expanding a secret var ($SECRET or ${SECRET}).
if echo "$CMD" | grep -qE "(echo|printf)[^|;&]*[$][{]?$SECRET_SEG"; then
    deny_response "shell-env-secret-guard: refusing to print a secret-bearing env var. Do not echo secret values into the transcript; use the secret directly in the consuming command, or let the user run it."
fi

# DENY 2: printenv NAME where NAME is a secret var (no \$ prefix for printenv).
if echo "$CMD" | grep -qE "printenv[[:space:]]+[{]?$SECRET_SEG"; then
    deny_response "shell-env-secret-guard: refusing to printenv a secret-bearing env var into the transcript."
fi

# WARN: bare env dump that exposes ALL env vars (secrets included).
if echo "$CMD" | grep -qE '(^|[;&|][[:space:]]*)(env|printenv|set|export[[:space:]]+-p|declare[[:space:]]+-p|compgen[[:space:]]+-v)[[:space:]]*($|[;&|])'; then
    allow_with_context "shell-env-secret-guard: this dumps the full environment (secrets included) into the transcript. Narrow to the specific non-secret var you need."
fi

allow_response
