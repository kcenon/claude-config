#!/bin/bash
# sensitive-file-guard.sh
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

FILE="${CLAUDE_FILE_PATH:-}"

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

# Helper function for allow response
allow_response() {
    cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
}

# Skip if no file path provided (allow by default)
if [ -z "$FILE" ]; then
    allow_response
fi

# Check sensitive file extensions
if echo "$FILE" | grep -qE '\.(env|pem|key|p12|pfx)$'; then
    deny_response "Access to sensitive file blocked: $FILE (protected extension)"
fi

# Check sensitive directories
if echo "$FILE" | grep -qiE '(secrets|credentials|passwords|private)[/\\]'; then
    deny_response "Access to sensitive directory blocked: $FILE (protected path)"
fi

allow_response
