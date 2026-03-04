# prompt-validator.ps1
# Validates user prompts for dangerous operations
# Hook Type: UserPromptSubmit
# Exit codes: 0=allow (with optional warning)
# Response format: hookSpecificOutput with additionalContext (UserPromptSubmit)

$PROMPT = $env:CLAUDE_USER_PROMPT

# Skip if no prompt provided
if ([string]::IsNullOrEmpty($PROMPT)) {
    exit 0
}

# Check for dangerous operation requests
if ($PROMPT -match '(?i)(delete|remove|drop)\s+(all|entire|whole|database|table|production)') {
    @'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Warning: Dangerous operation request detected. Proceed with caution and verify the scope of changes."
  }
}
'@
    exit 0
}

exit 0
