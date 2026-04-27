#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# merge-gate-guard.ps1
# Blocks gh pr merge commands when any PR check is not passing.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "ABSOLUTE CI GATE" rule from global/CLAUDE.md at the Bash
# tool boundary. Mirrors the commit-message-guard / pr-language-guard
# enforcement model.
#
# Allow policy: every check must be in bucket "pass" or "skipping".
# Anything in bucket "fail", "pending", or "cancel" blocks the merge.
#
# Fail policy: FAIL-OPEN on gh CLI errors. If gh is missing, unauthenticated,
# or the API call fails, the merge is allowed and a diagnostic is written
# to stderr. Server-side branch protection rules remain as authoritative.

function Write-Diag {
    param([string]$Message)
    [Console]::Error.WriteLine("merge-gate-guard: $Message")
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

# Scope gate: only check 'gh pr merge' commands
if ($CMD -notmatch 'gh\s+pr\s+merge') {
    New-HookAllowResponse
    exit 0
}

# --- Extract PR number ---
$prNum = $null

# Try positional integer immediately after 'gh pr merge'
$m = [regex]::Match($CMD, 'gh\s+pr\s+merge\s+(\d+)')
if ($m.Success) { $prNum = $m.Groups[1].Value }

# Try URL form
if (-not $prNum) {
    $m = [regex]::Match($CMD, 'gh\s+pr\s+merge\s+https?://github\.com/[^/]+/[^/]+/pull/(\d+)')
    if ($m.Success) { $prNum = $m.Groups[1].Value }
}

# Try positional integer anywhere after 'gh pr merge' (handles flags before PR)
if (-not $prNum) {
    $m = [regex]::Match($CMD, 'gh\s+pr\s+merge[^\d]*?(?:^|\s)(\d+)(?:\s|$)')
    if ($m.Success) { $prNum = $m.Groups[1].Value }
}

# No PR number found - likely interactive mode. Allow and let gh handle it.
if (-not $prNum) {
    Write-Diag 'could not extract PR number from command, allowing'
    New-HookAllowResponse
    exit 0
}

# --- Extract repo (-R / --repo) ---
$repo = $null
$m = [regex]::Match($CMD, "--repo[\s=]+[`"']?([^\s`"']+)")
if ($m.Success) { $repo = $m.Groups[1].Value }

if (-not $repo) {
    $m = [regex]::Match($CMD, "(?:^|\s)-R\s+[`"']?([^\s`"']+)")
    if ($m.Success) { $repo = $m.Groups[1].Value }
}

# --- Verify gh is available ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Diag 'gh CLI not installed, allowing merge (fail-open)'
    New-HookAllowResponse
    exit 0
}

# --- Call gh pr checks (bounded by Start-Job/Wait-Job timeout) ---
# Wall-clock budget for a single `gh pr checks` invocation. Mirrors the
# Bash GH_CHECKS_TIMEOUT_SEC contract.
$timeoutSec = if ($env:GH_CHECKS_TIMEOUT_SEC) { [int]$env:GH_CHECKS_TIMEOUT_SEC } else { 10 }

$ghArgs = @('pr', 'checks', $prNum, '--json', 'bucket,name,state')
if ($repo) { $ghArgs += @('-R', $repo) }

$checksRaw = $null
$ghExit = 0
$timedOut = $false

try {
    $job = Start-Job -ScriptBlock {
        param($ghArgs)
        $out = & gh @ghArgs 2>&1
        [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
    } -ArgumentList (,$ghArgs)

    if (Wait-Job $job -Timeout $timeoutSec) {
        $result = Receive-Job $job
        if ($result) {
            $checksRaw = $result.Output
            $ghExit = $result.ExitCode
        }
    } else {
        Stop-Job $job | Out-Null
        $timedOut = $true
    }
    Remove-Job $job -Force | Out-Null
} catch {
    Write-Diag "gh invocation threw: $_"
    New-HookAllowResponse
    exit 0
}

if ($timedOut) {
    Write-Diag "gh pr checks timed out after ${timeoutSec}s, allowing merge (fail-open)"
    New-HookAllowResponse
    exit 0
}

if ($ghExit -ne 0) {
    Write-Diag "gh pr checks failed (exit $ghExit), allowing merge (fail-open): $checksRaw"
    New-HookAllowResponse
    exit 0
}

# Empty result means no checks configured for this PR
if (-not $checksRaw -or "$checksRaw".Trim() -eq '[]') {
    Write-Diag "no checks configured for PR #$prNum, allowing"
    New-HookAllowResponse
    exit 0
}

# --- Parse non-passing checks ---
try {
    $checks = $checksRaw | ConvertFrom-Json
} catch {
    Write-Diag "ConvertFrom-Json failed, allowing merge (fail-open): $_"
    New-HookAllowResponse
    exit 0
}

$nonPassing = @()
foreach ($c in $checks) {
    if ($c.bucket -ne 'pass' -and $c.bucket -ne 'skipping') {
        $nonPassing += "$($c.name) [$($c.bucket)/$($c.state)]"
    }
}

if ($nonPassing.Count -gt 0) {
    $list = $nonPassing -join ', '
    New-HookDenyResponse -Reason "Merge blocked by ABSOLUTE CI GATE: PR #$prNum has non-passing checks: $list. Wait for all checks to pass before merging — never rationalize a failure as unrelated, infrastructure, or pre-existing."
    exit 0
}

New-HookAllowResponse
exit 0
