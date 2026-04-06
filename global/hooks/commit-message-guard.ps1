#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# commit-message-guard.ps1
# Deterministic git commit message validator
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Replaces the non-deterministic type:"prompt" validator (see #241).
# Same input always yields same output - safe as a validation gate.
#
# Rules enforced:
#   1. Conventional Commits format: type(scope)?: description
#   2. Description must start with a lowercase letter
#   3. Description must not end with a period
#   4. No AI/Claude attribution
#   5. No emojis

# Read input from stdin
$json = Read-HookInput

# Empty input: fail open (commit-msg git hook is the authoritative gate)
if (-not $json) {
    New-HookAllowResponse
    exit 0
}

# Extract command
$CMD = $null
try { $CMD = $json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }

# Scope: only validate git commit commands
if ($CMD -notmatch 'git\s+commit') {
    New-HookAllowResponse
    exit 0
}

# Skip command substitution cases — cannot parse reliably
if ($CMD -match '-a?m\s+"\$\(') {
    New-HookAllowResponse
    exit 0
}

# Extract message from -m "...", -am "...", or --message="..."
$msg = $null
if ($CMD -match '(?:^|\s)-m\s+"([^"]*)"') {
    $msg = $Matches[1]
} elseif ($CMD -match '(?:^|\s)-am\s+"([^"]*)"') {
    $msg = $Matches[1]
} elseif ($CMD -match '--message[=\s]+"([^"]*)"') {
    $msg = $Matches[1]
}

# No -m argument: git will open $EDITOR, nothing to validate here
if (-not $msg) {
    New-HookAllowResponse
    exit 0
}

# Rule 1: Conventional Commits format
$ccRegex = '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|security)(\([a-z0-9._-]+\))?: .+'
if ($msg -notmatch $ccRegex) {
    New-HookDenyResponse -Reason "Commit message must follow Conventional Commits: 'type(scope): description' or 'type: description'. Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, security."
    exit 0
}

# Extract description (everything after the first ': ')
$desc = $msg -replace '^[^:]*:\s*', ''

# Rule 2: Description starts with a lowercase letter
if ($desc.Length -eq 0 -or $desc[0] -cnotmatch '[a-z]') {
    New-HookDenyResponse -Reason 'Commit message description must start with a lowercase letter.'
    exit 0
}

# Rule 3: No trailing period
if ($desc.EndsWith('.')) {
    New-HookDenyResponse -Reason 'Commit message description must not end with a period.'
    exit 0
}

# Rule 4: No AI/Claude attribution
if ($msg -imatch '(claude|anthropic|ai-assisted|co-authored-by:\s*claude|generated\s+with)') {
    New-HookDenyResponse -Reason 'Commit message must not contain AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude).'
    exit 0
}

# Rule 5: No emojis
# Use UTF-32 code point iteration because .NET regex cannot match non-BMP
# ranges like U+1F300 directly with \u escapes.
$hasEmoji = $false
$info = [System.Globalization.StringInfo]::new($msg)
for ($i = 0; $i -lt $info.LengthInTextElements; $i++) {
    $elem = $info.SubstringByTextElements($i, 1)
    $cp = [Char]::ConvertToUtf32($elem, 0)
    if (($cp -ge 0x1F300 -and $cp -le 0x1F9FF) -or
        ($cp -ge 0x2600  -and $cp -le 0x26FF)  -or
        ($cp -ge 0x2700  -and $cp -le 0x27BF)  -or
        ($cp -ge 0x1F1E0 -and $cp -le 0x1F1FF)) {
        $hasEmoji = $true
        break
    }
}
if ($hasEmoji) {
    New-HookDenyResponse -Reason 'Commit message must not contain emojis.'
    exit 0
}

# All rules passed
New-HookAllowResponse
exit 0
