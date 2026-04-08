#!/bin/bash
# conflict-guard.sh
# Guards against git operations that could cause conflicts
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Fail-open: if parsing fails or git is not available, allow the command.
# This hook is advisory (conflict prevention), not security-critical.

# --- Response helpers (match dangerous-command-guard.sh pattern) ---
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

# --- Read input from stdin ---
INPUT=$(cat)

# Fail-open: allow if stdin is empty
if [ -z "$INPUT" ]; then
    allow_response
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Fail-open: allow if no command parsed
if [ -z "$CMD" ]; then
    allow_response
fi

# --- Scope: only check conflict-prone git commands ---
if ! echo "$CMD" | grep -qE 'git[[:space:]]+(merge|rebase|cherry-pick|pull)\b'; then
    allow_response
fi

# Fail-open: allow if git is not available
if ! command -v git &>/dev/null; then
    allow_response
fi

# Determine git toplevel (fail-open if not in a repo)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || allow_response

# --- Check 1: Existing conflict state ---
if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
    deny_response "A merge is already in progress. Resolve or abort it before starting a new operation."
fi
if [ -f "$GIT_DIR/REBASE_HEAD" ]; then
    deny_response "A rebase is already in progress. Resolve or abort it before starting a new operation."
fi
if [ -f "$GIT_DIR/CHERRY_PICK_HEAD" ]; then
    deny_response "A cherry-pick is already in progress. Resolve or abort it before starting a new operation."
fi

# --- Check 2: Uncommitted changes ---
# Extract the specific git subcommand for the error message
SUBCMD=$(echo "$CMD" | grep -oE 'git[[:space:]]+(merge|rebase|cherry-pick|pull)' | awk '{print $2}')

DIRTY=$(git status --porcelain 2>/dev/null) || allow_response
if [ -n "$DIRTY" ]; then
    deny_response "Uncommitted changes detected. Commit or stash changes before running git $SUBCMD to prevent data loss."
fi

# All checks passed
allow_response
