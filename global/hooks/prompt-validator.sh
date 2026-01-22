#!/bin/bash
# prompt-validator.sh
# Validates user prompts for dangerous operations
# Hook Type: UserPromptSubmit
# Exit codes: 0=allow (with optional warning)

PROMPT="${CLAUDE_USER_PROMPT:-}"

# Skip if no prompt provided
if [ -z "$PROMPT" ]; then
    exit 0
fi

# Check for dangerous operation requests
if echo "$PROMPT" | grep -qiE '(delete|remove|drop)\s+(all|entire|whole|database|table|production)'; then
    echo "[WARNING] Dangerous operation request detected. Proceed with caution." >&2
fi

exit 0
