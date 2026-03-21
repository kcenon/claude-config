# team-limit-guard.ps1
# Limits the maximum number of concurrent Agent Teams
# Hook Type: PreToolUse (TeamCreate)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read hook input from stdin
$inputJson = $input | Out-String
try {
    $hookData = $inputJson | ConvertFrom-Json
} catch {
    # Parse failure — allow by default
}

# Configurable limit via environment variable (default: 3)
$maxTeams = if ($env:MAX_TEAMS) { [int]$env:MAX_TEAMS } else { 3 }
$teamsDir = Join-Path $HOME ".claude" "teams"

function Deny-Response {
    param([string]$Reason)
    $safeReason = $Reason -replace '\\', '\\\\' -replace '"', '\"'
    @"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$safeReason"
  }
}
"@
    exit 2
}

function Allow-Response {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Skip check if teams directory does not exist
if (-not (Test-Path $teamsDir)) {
    Allow-Response
}

# Count existing team directories
$currentTeams = (Get-ChildItem -Path $teamsDir -Directory -ErrorAction SilentlyContinue).Count

# Block if limit reached
if ($currentTeams -ge $maxTeams) {
    Deny-Response "Team limit reached ($currentTeams/$maxTeams). Delete unused teams with TeamDelete before creating new ones."
}

# Allow team creation
Allow-Response
