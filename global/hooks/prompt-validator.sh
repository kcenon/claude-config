#!/bin/bash
# prompt-validator.sh
# Validates user prompts for dangerous operations
# Hook Type: UserPromptSubmit
# Exit codes: 0=allow (with optional warning)
# Response format: hookSpecificOutput with additionalContext (UserPromptSubmit)

PROMPT="${CLAUDE_USER_PROMPT:-}"

# Helper function for allow response with warning
allow_with_warning() {
    local warning="$1"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "$warning"
  }
}
EOF
    exit 0
}

# Helper function for allow response
allow_response() {
    exit 0
}

# Skip if no prompt provided
if [ -z "$PROMPT" ]; then
    allow_response
fi

# Check for dangerous operation requests
if echo "$PROMPT" | grep -qiE '(delete|remove|drop)\s+(all|entire|whole|database|table|production)'; then
    allow_with_warning "Warning: Dangerous operation request detected. Proceed with caution and verify the scope of changes."
fi

allow_response
