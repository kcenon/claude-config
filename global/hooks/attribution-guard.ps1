#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# attribution-guard.ps1
# Blocks gh pr/issue create|edit|comment commands whose --title or --body
# contains AI/Claude attribution markers.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "No AI/Claude attribution in commits, issues, or PRs" rule
# from commit-settings.md. Mirrors commit-message-guard / pr-language-guard /
# merge-gate-guard enforcement model.
#
# Regex must match hooks/lib/validate-commit-message.sh (CMV_ATTRIBUTION_REGEX).
# When updating one, update the other to keep enforcement consistent across
# bash and PowerShell hosts.

# Same pattern as CMV_ATTRIBUTION_REGEX in validate-commit-message.sh
$AttributionRegex = '(?i)(claude|anthropic|ai-assisted|co-authored-by:\s*claude|generated\s+with)'

# Extracts the value for a given long/short flag from a shell command string.
function Get-FlagValue {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LongFlag,
        [string]$ShortFlag
    )

    # Long flag, double-quoted
    $m = [regex]::Match($Command, "$LongFlag[\s=]+`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }

    # Long flag, single-quoted
    $m = [regex]::Match($Command, "$LongFlag[\s=]+'([^']*)'")
    if ($m.Success) { return $m.Groups[1].Value }

    if ($ShortFlag) {
        $m = [regex]::Match($Command, "(?:^|\s)$ShortFlag\s+`"([^`"]*)`"")
        if ($m.Success) { return $m.Groups[1].Value }

        $m = [regex]::Match($Command, "(?:^|\s)$ShortFlag\s+'([^']*)'")
        if ($m.Success) { return $m.Groups[1].Value }
    }

    return $null
}

# --- Read input from stdin ---
$json = Read-HookInput

# Empty input: fail open
if (-not $json) {
    New-HookAllowResponse
    exit 0
}

# Extract command
$CMD = $null
try { $CMD = $json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }

if (-not $CMD) {
    New-HookAllowResponse
    exit 0
}

# Scope gate: only check 'gh (pr|issue) (create|edit|comment)' commands
if ($CMD -notmatch 'gh\s+(pr|issue)\s+(create|edit|comment)') {
    New-HookAllowResponse
    exit 0
}

# Skip command-substitution / heredoc bodies
if ($CMD -match '(?:--body|-b|--title|-t)[\s=]+"\$\(') {
    New-HookAllowResponse
    exit 0
}

# Skip --body-file references
if ($CMD -match '--body-file[\s=]+') {
    New-HookAllowResponse
    exit 0
}

# Extract title and body
$title = Get-FlagValue -Command $CMD -LongFlag '--title' -ShortFlag '-t'
$body  = Get-FlagValue -Command $CMD -LongFlag '--body'  -ShortFlag '-b'

$denyReason = "Text contains AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude). Remove attribution before submitting."

# Validate title
if ($title -and ($title -match $AttributionRegex)) {
    New-HookDenyResponse -Reason "PR/issue --title rejected: $denyReason"
    exit 0
}

# Validate body
if ($body -and ($body -match $AttributionRegex)) {
    New-HookDenyResponse -Reason "PR/issue --body rejected: $denyReason"
    exit 0
}

New-HookAllowResponse
exit 0
