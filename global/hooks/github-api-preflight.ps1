#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# github-api-preflight.ps1
# Checks GitHub API connectivity before executing GitHub-related commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON, warning only)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
$json = Read-HookInput

$CMD = $null
try {
    $CMD = $json.tool_input.command
} catch {}
# Fallback to environment variable for backward compatibility
if ([string]::IsNullOrEmpty($CMD)) {
    $CMD = $env:CLAUDE_TOOL_INPUT
}

# Only check GitHub-related commands
if ($CMD -notmatch '(gh |github\.com|api\.github\.com)') {
    New-HookAllowResponse
    exit 0
}

# Test GitHub API connectivity with short timeout
$warnings = @()
try {
    $null = Invoke-WebRequest -Uri 'https://api.github.com/zen' -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
} catch {
    $warnings += 'GitHub API may be unreachable (sandbox/TLS issue detected). Suggestions: Use local git operations if possible, check network/certificate settings, consider /sandbox to manage restrictions.'
}

# Check GitHub CLI auth status for gh commands
if ($CMD -match '^gh ') {
    try {
        $null = & gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            $warnings += "GitHub CLI not authenticated. Run 'gh auth login' or 'gh auth status' to check."
        }
    } catch {
        $warnings += "GitHub CLI not authenticated. Run 'gh auth login' or 'gh auth status' to check."
    }
}

# Return allow with any accumulated warnings
if ($warnings.Count -gt 0) {
    $context = $warnings -join ' '
    New-HookAllowResponse -AdditionalContext $context
} else {
    New-HookAllowResponse
}
exit 0
