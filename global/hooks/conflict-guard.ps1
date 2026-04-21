#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# conflict-guard.ps1
# Guards against git operations that could cause conflicts.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Fail-open: when parsing fails or git is not available, allow the
# command. This hook is advisory (conflict prevention), not
# security-critical.

function Respond-Allow {
    New-HookAllowResponse
    exit 0
}

function Respond-Deny {
    param([string]$Reason)
    New-HookDenyResponse -Reason $Reason
    exit 0
}

$json = Read-HookInput
if (-not $json) { Respond-Allow }

$cmd = $null
try { $cmd = $json.tool_input.command } catch { }
if (-not $cmd) { $cmd = $env:CLAUDE_TOOL_INPUT }
if (-not $cmd) { Respond-Allow }

# Scope: only check conflict-prone git subcommands.
if ($cmd -notmatch 'git\s+(merge|rebase|cherry-pick|pull)\b') {
    Respond-Allow
}

# Fail-open when git is unavailable.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Respond-Allow
}

# Resolve git dir; fail-open outside a repo.
$gitDir = $null
try {
    $gitDir = (& git rev-parse --git-dir 2>$null).Trim()
} catch { }
if (-not $gitDir) { Respond-Allow }

# Check 1: existing conflict state.
if (Test-Path -LiteralPath (Join-Path $gitDir 'MERGE_HEAD')) {
    Respond-Deny 'A merge is already in progress. Resolve or abort it before starting a new operation.'
}
if (Test-Path -LiteralPath (Join-Path $gitDir 'REBASE_HEAD')) {
    Respond-Deny 'A rebase is already in progress. Resolve or abort it before starting a new operation.'
}
if (Test-Path -LiteralPath (Join-Path $gitDir 'CHERRY_PICK_HEAD')) {
    Respond-Deny 'A cherry-pick is already in progress. Resolve or abort it before starting a new operation.'
}

# Check 2: uncommitted changes.
$subMatch = [regex]::Match($cmd, 'git\s+(merge|rebase|cherry-pick|pull)')
$sub = if ($subMatch.Success) { $subMatch.Groups[1].Value } else { 'operation' }

$dirty = $null
try {
    $dirty = (& git status --porcelain 2>$null)
} catch {
    Respond-Allow
}
if ($dirty) {
    Respond-Deny "Uncommitted changes detected. Commit or stash changes before running git $sub to prevent data loss."
}

Respond-Allow
