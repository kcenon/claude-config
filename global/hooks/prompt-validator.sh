#!/bin/bash
# prompt-validator.sh
# Validates user prompts for dangerous operations
# Hook Type: UserPromptSubmit
# Exit codes: 0=allow (with optional warning)
# Response format: hookSpecificOutput with additionalContext (UserPromptSubmit)

set -euo pipefail

PROMPT="${CLAUDE_USER_PROMPT:-}"

# Helper function for allow response with warning.
# jq -nc --arg handles all escaping, avoiding the heredoc-interpolation
# injection class banned elsewhere in the suite (issue #567 / #579). This is an
# advisory UserPromptSubmit hook: if jq is unavailable, emit no context rather
# than risk a malformed payload (the prompt is still allowed).
allow_with_warning() {
    local warning="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg ctx "$warning" \
            '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
    fi
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
