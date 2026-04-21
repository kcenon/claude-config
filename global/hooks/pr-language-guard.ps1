#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib' 'LanguageValidator.psm1') -Force

# pr-language-guard.ps1
# Blocks gh pr/issue create|edit|comment commands whose --title or --body
# violates the resolved CLAUDE_CONTENT_LANGUAGE policy.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the content-language rule from commit-settings.md. Default
# policy ("english", when CLAUDE_CONTENT_LANGUAGE is unset) matches the
# pre-dispatcher behavior byte-for-byte. See issue #410 for the dispatcher
# design.
#
# NOTE: --body using $(...) substitution, heredocs, or --body-file is
# not parseable at this layer and the hook returns "allow" for those.

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
    $result = Test-ContentLanguage -Text $title
    if (-not $result.Valid) {
        New-HookDenyResponse -Reason "PR/issue --title rejected: $($result.Reason)"
        exit 0
    }
}

# Validate body
if ($body) {
    $result = Test-ContentLanguage -Text $body
    if (-not $result.Valid) {
        New-HookDenyResponse -Reason "PR/issue --body rejected: $($result.Reason)"
        exit 0
    }
}

# All checks passed
New-HookAllowResponse
exit 0
