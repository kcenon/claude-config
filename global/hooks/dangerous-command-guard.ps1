# dangerous-command-guard.ps1
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

function Deny-Response {
    param([string]$Reason)
    @"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$Reason"
  }
}
"@
    exit 2
}

# Read hook input from stdin
$inputJson = $input | Out-String

# Fail-closed: deny if stdin is empty or missing
if ([string]::IsNullOrWhiteSpace($inputJson)) {
    Deny-Response "Failed to parse hook input — denying for safety (fail-closed)"
}

try {
    $hookData = $inputJson | ConvertFrom-Json
    $CMD = $hookData.tool_input.command
} catch {
    Deny-Response "Failed to parse hook input JSON — denying for safety (fail-closed)"
}

# Block recursive delete at root
if ($CMD -match 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/') {
    Deny-Response "Dangerous recursive delete at root directory blocked for safety"
}

# Block dangerous chmod
if ($CMD -match 'chmod\s+(0?777|a\+rwx)') {
    Deny-Response "Dangerous permission change (777/a+rwx) blocked for security"
}

# Block remote script execution
if ($CMD -match '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b') {
    Deny-Response "Remote script execution via pipe blocked for security"
}

# Allow the command
@'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
exit 0
