#!/bin/bash
# dangerous-command-guard.sh
# Blocks dangerous bash commands and records every decision.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Side effects:
#   Writes one JSON line per invocation to
#   ${CLAUDE_LOG_DIR:-$HOME/.claude/logs}/dangerous-command-guard.log
#   so an operator can verify whether the hook returned allow/deny for a
#   specific command. Compound commands (pipes, redirects) that Claude
#   Code's allowlist cannot match should still show up here as "allow".
#   If a prompt was presented despite an "allow" log entry, the root
#   cause is upstream of this hook (e.g. unsandboxed path, multi-hook
#   merge, permission mode), not the guard.

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/dangerous-command-guard.log"

# Best-effort log writer. Never blocks the decision on logging failure.
log_decision() {
    local decision="$1"
    local reason="$2"
    local cmd="$3"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Use jq to produce a safely escaped JSON line when available;
    # fall back to a minimal manual escape if jq is missing.
    if command -v jq >/dev/null 2>&1; then
        jq -cn \
            --arg ts "$ts" \
            --arg d "$decision" \
            --arg r "$reason" \
            --arg c "$cmd" \
            '{ts:$ts, decision:$d, reason:$r, command:$c}' \
            >>"$LOG_FILE" 2>/dev/null || true
    else
        local esc_cmd esc_reason
        esc_cmd=${cmd//\\/\\\\}
        esc_cmd=${esc_cmd//\"/\\\"}
        esc_reason=${reason//\\/\\\\}
        esc_reason=${esc_reason//\"/\\\"}
        printf '{"ts":"%s","decision":"%s","reason":"%s","command":"%s"}\n' \
            "$ts" "$decision" "$esc_reason" "$esc_cmd" \
            >>"$LOG_FILE" 2>/dev/null || true
    fi
}

deny_response() {
    local reason="$1"
    log_decision "deny" "$reason" "${CMD:-}"
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
    local reason="${1:-dangerous-command-guard: no dangerous pattern matched}"
    log_decision "allow" "$reason" "${CMD:-}"
    # Escape double quotes for JSON safety.
    local esc_reason=${reason//\"/\\\"}
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "$esc_reason"
  }
}
EOF
    exit 0
}

INPUT=$(cat)

if [ -z "$INPUT" ]; then
    CMD=""
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ $? -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi

if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

if echo "$CMD" | grep -qE 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/'; then
    deny_response "Dangerous recursive delete at root directory blocked for safety"
fi

if echo "$CMD" | grep -qE 'chmod\s+(0?777|a\+rwx)'; then
    deny_response "Dangerous permission change (777/a+rwx) blocked for security"
fi

if echo "$CMD" | grep -qE '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b'; then
    deny_response "Remote script execution via pipe blocked for security"
fi

# Tag well-known safe read-only compound patterns so the reason line
# explains why a pipe-bearing command was auto-allowed. This does not
# widen what is allowed (all non-dangerous commands already fall through
# to allow); it just produces a clearer audit trail.
SAFE_READ_ONLY_HEAD='^(git\s+(status|log|diff|show|branch|tag|remote|ls-files|rev-parse|describe|for-each-ref|worktree|fetch)|gh\s+(pr|issue|run|workflow|repo|release|auth)\s+(view|list|status|diff|checks))\b'
if echo "$CMD" | grep -qE '[|]|2>&1|>/dev/null|>\s*/dev/null'; then
    if echo "$CMD" | grep -qE "$SAFE_READ_ONLY_HEAD"; then
        allow_response "Safe read-only compound command (pipe/redirect with git/gh read verb)"
    fi
fi

allow_response
