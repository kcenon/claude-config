#!/bin/bash
# dangerous-command-guard.sh
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

CMD="${CLAUDE_TOOL_INPUT:-}"

# Helper function for deny response
deny_response() {
    local reason="$1"
    cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 2
}

# Block recursive delete at root
if echo "$CMD" | grep -qE 'rm\s+(-rf|--recursive)\s+/($|[^a-zA-Z])'; then
    deny_response "Dangerous recursive delete at root directory blocked for safety"
fi

# Block dangerous chmod
if echo "$CMD" | grep -qE 'chmod\s+(777|a\+rwx)'; then
    deny_response "Dangerous permission change (777/a+rwx) blocked for security"
fi

# Block remote script execution
if echo "$CMD" | grep -qE '(curl|wget).*\|.*sh'; then
    deny_response "Remote script execution via pipe blocked for security"
fi

# Allow the command
cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
exit 0
