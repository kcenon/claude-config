#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# pr-target-guard.ps1
# Blocks PRs targeting 'main' from non-develop branches
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Branching policy: only 'develop' may merge into 'main'.
# Feature/fix branches must target 'develop'.
# Release PRs (develop -> main) are created via /release skill.

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

# Fallback to environment variable for backward compatibility
if (-not $CMD) {
    $CMD = $env:CLAUDE_TOOL_INPUT
}

# Scope gate: only check 'gh pr create' commands
if ($CMD -notmatch 'gh\s+pr\s+create') {
    New-HookAllowResponse
    exit 0
}

# Extract --base value (supports: --base main, --base=main, -B main)
$base = $null
$baseMatch = [regex]::Match($CMD, '(?:--base[= ]|-B\s*)["\x27]?([a-zA-Z0-9._/-]+)')
if ($baseMatch.Success) {
    $base = $baseMatch.Groups[1].Value
}

# If no --base flag found, the PR uses the repo default branch (develop).
# Allow it -- this is the normal feature-to-develop workflow.
if (-not $base) {
    New-HookAllowResponse
    exit 0
}

# Strip surrounding quotes if present
$base = $base -replace '^["\x27]|["\x27]$', ''

# Only block if base is exactly 'main'
if ($base -ne 'main') {
    New-HookAllowResponse
    exit 0
}

# Base is 'main' -- check if this is a release PR (--head develop)
$head = $null
$headMatch = [regex]::Match($CMD, '(?:--head[= ]|-H\s*)["\x27]?([a-zA-Z0-9._/-]+)')
if ($headMatch.Success) {
    $head = $headMatch.Groups[1].Value
    $head = $head -replace '^["\x27]|["\x27]$', ''
}

# Allow release PRs: develop -> main or release/* -> main
# (matches .github/workflows/validate-pr-target.yml server-side policy)
if ($head -eq 'develop') {
    New-HookAllowResponse
    exit 0
}
if ($head -like 'release/*') {
    New-HookAllowResponse
    exit 0
}

# Deny: non-develop/non-release branch targeting main
New-HookDenyResponse -Reason "PR targeting 'main' is blocked by branching policy. Only 'develop' or 'release/*' branches may merge into 'main'. Feature/fix branches must target 'develop'."
exit 0
