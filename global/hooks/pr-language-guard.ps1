#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# pr-language-guard.ps1
# Blocks gh pr/issue create|edit|comment commands whose --title or --body
# contains non-ASCII characters.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "All GitHub Issues and Pull Requests must be written in
# English" rule from commit-settings.md. Mirrors the commit-message-guard
# enforcement model that proved effective for commit messages.
#
# Allowed bytes: ASCII printable (0x20-0x7E) and ASCII whitespace
# (0x09-0x0D = tab, LF, VT, FF, CR). Anything else is rejected.
#
# NOTE: --body using $(...) substitution, heredocs, or --body-file is
# not parseable at this layer and the hook returns "allow" for those.

# Returns the first non-ASCII text element, or $null if all elements are ASCII.
# Uses StringInfo to walk grapheme clusters so surrogate pairs (emoji,
# CJK extensions in supplementary planes) are reported as a single unit.
function Get-FirstNonAscii {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $null
    }

    $info = [System.Globalization.StringInfo]::new($Text)
    for ($i = 0; $i -lt $info.LengthInTextElements; $i++) {
        $elem = $info.SubstringByTextElements($i, 1)
        $cp = [Char]::ConvertToUtf32($elem, 0)
        # ASCII printable (0x20-0x7E) or whitespace (0x09-0x0D)
        if (($cp -ge 0x20 -and $cp -le 0x7E) -or ($cp -ge 0x09 -and $cp -le 0x0D)) {
            continue
        }
        return $elem
    }
    return $null
}

# Extracts the value for a given long/short flag from a shell command string.
# Tries double-quoted then single-quoted forms; supports --flag value,
# --flag=value, and -f value layouts.
function Get-FlagValue {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LongFlag,
        [string]$ShortFlag
    )

    # Long flag, double-quoted: --title "value" or --title="value"
    $m = [regex]::Match($Command, "$LongFlag[\s=]+`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }

    # Long flag, single-quoted: --title 'value' or --title='value'
    $m = [regex]::Match($Command, "$LongFlag[\s=]+'([^']*)'")
    if ($m.Success) { return $m.Groups[1].Value }

    if ($ShortFlag) {
        # Short flag must be preceded by whitespace to avoid matching inside other tokens
        $m = [regex]::Match($Command, "(?:^|\s)$ShortFlag\s+`"([^`"]*)`"")
        if ($m.Success) { return $m.Groups[1].Value }

        $m = [regex]::Match($Command, "(?:^|\s)$ShortFlag\s+'([^']*)'")
        if ($m.Success) { return $m.Groups[1].Value }
    }

    return $null
}

# --- Read input from stdin ---
$json = Read-HookInput

# Empty input: fail open - nothing to validate
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

# Skip command-substitution / heredoc bodies — cannot parse reliably
if ($CMD -match '(?:--body|-b|--title|-t)[\s=]+"\$\(') {
    New-HookAllowResponse
    exit 0
}

# Skip --body-file references — content lives in a separate file
if ($CMD -match '--body-file[\s=]+') {
    New-HookAllowResponse
    exit 0
}

# Extract title and body
$title = Get-FlagValue -Command $CMD -LongFlag '--title' -ShortFlag '-t'
$body  = Get-FlagValue -Command $CMD -LongFlag '--body'  -ShortFlag '-b'

# Validate title
if ($title) {
    $bad = Get-FirstNonAscii -Text $title
    if ($null -ne $bad) {
        New-HookDenyResponse -Reason "PR/issue --title rejected: Text contains non-ASCII characters (first: '$bad'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md."
        exit 0
    }
}

# Validate body
if ($body) {
    $bad = Get-FirstNonAscii -Text $body
    if ($null -ne $bad) {
        New-HookDenyResponse -Reason "PR/issue --body rejected: Text contains non-ASCII characters (first: '$bad'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md."
        exit 0
    }
}

# All checks passed
New-HookAllowResponse
exit 0
