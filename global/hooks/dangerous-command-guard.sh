#!/bin/bash
# dangerous-command-guard.sh
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

# Helper function for deny response
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

# Helper function for allow response
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

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# Fail-closed: deny if stdin is empty or missing
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fail-closed: deny if jq parsing failed
if [ $? -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi

# Fallback to environment variable for backward compatibility
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Block recursive delete at root
if echo "$CMD" | grep -qE 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/'; then
    deny_response "Dangerous recursive delete at root directory blocked for safety"
fi

# Block dangerous chmod
if echo "$CMD" | grep -qE 'chmod\s+(0?777|a\+rwx)'; then
    deny_response "Dangerous permission change (777/a+rwx) blocked for security"
fi

# Block remote script execution
if echo "$CMD" | grep -qE '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b'; then
    deny_response "Remote script execution via pipe blocked for security"
fi

# Allow the command
allow_response
