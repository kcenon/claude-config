# prompt-validator.ps1
# Validates user prompts for dangerous operations
# Hook Type: UserPromptSubmit
# Exit codes: 0=allow (with optional warning)
# Response format: hookSpecificOutput (modern format)

$PROMPT = $env:CLAUDE_USER_PROMPT

# Skip if no prompt provided
if ([string]::IsNullOrEmpty($PROMPT)) {
    @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
    exit 0
}

# Check for dangerous operation requests
if ($PROMPT -match '(?i)(delete|remove|drop)\s+(all|entire|whole|database|table|production)') {
    @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  },
  "systemMessage": "Warning: Dangerous operation request detected. Proceed with caution and verify the scope of changes."
}
'@
    exit 0
}

@'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
exit 0
