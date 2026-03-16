# dangerous-command-guard.ps1
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

# Read hook input from stdin
$inputJson = $input | Out-String
try {
    $hookData = $inputJson | ConvertFrom-Json
    $CMD = $hookData.tool_input.command
} catch {
    $CMD = ""
}

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

# Block recursive delete at root
if ($CMD -match 'rm\s+(-rf|--recursive)\s+/($|[^a-zA-Z])') {
    Deny-Response "Dangerous recursive delete at root directory blocked for safety"
}

# Block dangerous chmod
if ($CMD -match 'chmod\s+(777|a\+rwx)') {
    Deny-Response "Dangerous permission change (777/a+rwx) blocked for security"
}

# Block remote script execution
if ($CMD -match '(curl|wget).*\|.*sh') {
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
