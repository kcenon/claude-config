#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# attribution-guard.ps1
# Blocks gh pr/issue/release commands whose user-facing text fields contain
# AI/Claude attribution markers. Scope (Issue #480 extended): pr
# create|edit|comment|review, issue create|edit|comment, release create|edit.
# Inspected fields: --title/-t, --body/-b, --notes/-n.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Three-pattern design mirrors validate-commit-message.sh:
#   1. Trailer-style attribution at line start (Co-Authored-By: Claude ...)
#   2. Bot emoji adjacent to Claude/Anthropic
#   3. Generated|Created|Authored {with|by|using} {Claude|Anthropic} prose
# Casual prose mentions ("Claude API", "Anthropic SDK") are deliberately
# allowed to eliminate false positives on legitimate technical writing.
#
# Patterns must match hooks/lib/validate-commit-message.sh. When updating
# one, update the other to keep enforcement consistent across bash and
# PowerShell hosts.

$AttributionTrailerRegex = '(?m)^\s*(Co-[Aa]uthored-[Bb]y|Co-[Aa]uthor|[Gg]enerated[- ]?[Bb]y|[Cc]reated[- ]?[Bb]y|[Aa]uthored[- ]?[Bb]y|[Ss]igned-[Oo]ff-[Bb]y|[Aa]ssisted-[Bb]y)\s*:\s*.*([Cc]laude|[Aa]nthropic|AI[- ]?[Aa]ssisted)'
$AttributionEmojiRegex   = '🤖\s*\S*\s*([Cc]laude|[Aa]nthropic)'
$AttributionProseRegex   = '([Gg]enerated|[Cc]reated|[Aa]uthored|[Ww]ritten)\s+(with|by|using)\s+(Claude|Anthropic|AI[- ]?[Aa]ssistant)'

function Test-AttributionReason {
    param([string]$Text)
    if (-not $Text) { return $null }
    if ($Text -match $AttributionTrailerRegex) {
        return 'Text contains AI/Claude attribution trailer (Co-Authored-By: / Generated-by: / Authored-by: Claude or Anthropic). Remove the trailer before submitting.'
    }
    if ($Text -match $AttributionEmojiRegex) {
        return 'Text contains AI bot emoji adjacent to Claude/Anthropic attribution. Remove the marker before submitting.'
    }
    if ($Text -match $AttributionProseRegex) {
        return "Text contains AI/Claude attribution prose (e.g. 'Generated with Claude'). Remove the attribution before submitting."
    }
    return $null
}

# Extracts the value for a given long/short flag from a shell command string.
function Get-FlagValue {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LongFlag,
        [string]$ShortFlag
    )

    $m = [regex]::Match($Command, "$LongFlag[\s=]+`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }

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

$CMD = $null
try { $CMD = $json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }

if (-not $CMD) {
    New-HookAllowResponse
    exit 0
}

# Scope: pr create|edit|comment|review + issue create|edit|comment + release create|edit
if ($CMD -notmatch 'gh\s+(pr\s+(create|edit|comment|review)|issue\s+(create|edit|comment)|release\s+(create|edit))') {
    New-HookAllowResponse
    exit 0
}

# Skip command-substitution / heredoc bodies on any inspected channel
if ($CMD -match '(?:--body|-b|--title|-t|--notes|-n)[\s=]+"\$\(') {
    New-HookAllowResponse
    exit 0
}

# Skip file-based body/notes references
if ($CMD -match '(?:--body-file|--notes-file|-F)[\s=]+') {
    New-HookAllowResponse
    exit 0
}

# Extract title, body, and release notes
$title = Get-FlagValue -Command $CMD -LongFlag '--title' -ShortFlag '-t'
$body  = Get-FlagValue -Command $CMD -LongFlag '--body'  -ShortFlag '-b'
$notes = Get-FlagValue -Command $CMD -LongFlag '--notes' -ShortFlag '-n'

if ($title) {
    $reason = Test-AttributionReason $title
    if ($reason) { New-HookDenyResponse -Reason "--title rejected: $reason"; exit 0 }
}

if ($body) {
    $reason = Test-AttributionReason $body
    if ($reason) { New-HookDenyResponse -Reason "--body rejected: $reason"; exit 0 }
}

if ($notes) {
    $reason = Test-AttributionReason $notes
    if ($reason) { New-HookDenyResponse -Reason "release --notes rejected: $reason"; exit 0 }
}

New-HookAllowResponse
exit 0
