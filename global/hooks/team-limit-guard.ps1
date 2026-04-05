#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# team-limit-guard.ps1
# Limits the maximum number of concurrent Agent Teams
# Hook Type: PreToolUse (TeamCreate)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
$json = Read-HookInput

# Configurable limit via environment variable (default: 3)
$maxTeams = if ($env:MAX_TEAMS) { [int]$env:MAX_TEAMS } else { 3 }
$teamsDir = Join-Path $HOME '.claude' 'teams'

# Skip check if teams directory does not exist
if (-not (Test-Path -LiteralPath $teamsDir -PathType Container)) {
    New-HookAllowResponse
    exit 0
}

# Count existing team directories
$currentTeams = (Get-ChildItem -Path $teamsDir -Directory -ErrorAction SilentlyContinue).Count

# Block if limit reached
if ($currentTeams -ge $maxTeams) {
    New-HookDenyResponse -Reason "Team limit reached ($currentTeams/$maxTeams). Delete unused teams with TeamDelete before creating new ones."
    exit 0
}

# Allow team creation
New-HookAllowResponse
exit 0
