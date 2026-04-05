#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# sensitive-file-guard.ps1
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
$json = Read-HookInput

# Fail-closed: deny if input is empty or unparseable
if (-not $json) {
    New-HookDenyResponse -Reason 'Failed to parse hook input — denying for safety (fail-closed)'
    exit 0
}

# Extract file path from tool_input
$FILE = $null
try {
    $FILE = $json.tool_input.file_path
} catch {}

# Fallback to environment variable for backward compatibility
if ([string]::IsNullOrEmpty($FILE)) {
    $FILE = $env:CLAUDE_FILE_PATH
}

# Skip if no file path provided (allow by default)
if ([string]::IsNullOrEmpty($FILE)) {
    New-HookAllowResponse
    exit 0
}

# Check sensitive file extensions
if ($FILE -match '(^|[/\\])\.env($|\.)') {
    New-HookDenyResponse -Reason "Access to sensitive file blocked: $FILE (protected extension)"
    exit 0
}

if ($FILE -match '\.(pem|key|p12|pfx)$') {
    New-HookDenyResponse -Reason "Access to sensitive file blocked: $FILE (protected extension)"
    exit 0
}

# Check sensitive directories
if ($FILE -match '(?i)(secrets|credentials|passwords)[/\\]') {
    New-HookDenyResponse -Reason "Access to sensitive directory blocked: $FILE (protected path)"
    exit 0
}

New-HookAllowResponse
exit 0
