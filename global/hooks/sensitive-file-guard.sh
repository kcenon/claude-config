#!/bin/bash
# sensitive-file-guard.sh
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
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

# Fail-closed: deny if input is empty or unparseable
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ $? -ne 0 ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

# Fallback to environment variable for backward compatibility
if [ -z "$FILE" ]; then
    FILE="${CLAUDE_FILE_PATH:-}"
fi

# Skip if no file path provided (allow by default)
if [ -z "$FILE" ]; then
    allow_response
fi

# Check sensitive file extensions
if echo "$FILE" | grep -qE '(^|/)\.env($|\.)|\.(pem|key|p12|pfx)$'; then
    deny_response "Access to sensitive file blocked: $FILE (protected extension)"
fi

# Check sensitive directories
if echo "$FILE" | grep -qiE '(secrets|credentials|passwords)[/\\]'; then
    deny_response "Access to sensitive directory blocked: $FILE (protected path)"
fi

allow_response
