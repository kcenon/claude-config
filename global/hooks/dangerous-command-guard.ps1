#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# dangerous-command-guard.ps1
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
$json = Read-HookInput

# Fail-closed: deny if stdin is empty or missing
if (-not $json) {
    New-HookDenyResponse -Reason 'Failed to parse hook input — denying for safety (fail-closed)'
    exit 0
}

# Extract command from tool_input
$CMD = $null
try {
    $CMD = $json.tool_input.command
} catch {}

# Fail-closed: deny if jq parsing failed
if (-not $CMD) {
    # Fallback to environment variable for backward compatibility
    $CMD = $env:CLAUDE_TOOL_INPUT
}

# Block recursive delete at root
if ($CMD -match 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/') {
    New-HookDenyResponse -Reason 'Dangerous recursive delete at root directory blocked for safety'
    exit 0
}

# Block dangerous chmod
if ($CMD -match 'chmod\s+(0?777|a\+rwx)') {
    New-HookDenyResponse -Reason 'Dangerous permission change (777/a+rwx) blocked for security'
    exit 0
}

# Block remote script execution
if ($CMD -match '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b') {
    New-HookDenyResponse -Reason 'Remote script execution via pipe blocked for security'
    exit 0
}

# Allow the command
New-HookAllowResponse
exit 0
