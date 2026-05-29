#!/usr/bin/env pwsh
#Requires -Version 7.0
# PowerShell mirror of tests/hooks/test-merge-gate-squash-only.sh.
# Validates merge-gate-guard.ps1 squash-only enforcement (Issue #478): the
# --merge / --rebase flags must be denied before any gh pr checks call.
# Run: pwsh tests/hooks/test-merge-gate-squash-only.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'merge-gate-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Assert-SquashDeny {
    param([string]$Cmd, [string]$Label)
    $json = (@{ tool_input = @{ command = $Cmd } } | ConvertTo-Json -Compress)
    $result = $json | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"deny"' -and $result -match 'branching strategy requires squash') {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected squash deny, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-NotSquashDeny {
    param([string]$Cmd, [string]$Label)
    # The squash-only branch must NOT fire. The downstream CI-checks branch
    # may legitimately allow or deny depending on the (absent) gh CLI, so we
    # only assert the squash-specific reason is not present.
    $json = (@{ tool_input = @{ command = $Cmd } } | ConvertTo-Json -Compress)
    $result = $json | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match 'branching strategy requires squash') {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - squash-only branch unexpectedly fired: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    } else {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    }
}

Write-Host '=== merge-gate-guard.ps1 squash-only tests ==='
Write-Host ''
Write-Host '[deny - non-squash flags]'
Assert-SquashDeny 'gh pr merge 1 --merge'   'long-form --merge'
Assert-SquashDeny 'gh pr merge --merge 1'   '--merge before PR#'
Assert-SquashDeny 'gh pr merge 1 --rebase'  'long-form --rebase'
Assert-SquashDeny 'gh pr merge --rebase 7'  '--rebase before PR#'

Write-Host ''
Write-Host '[pass-through - squash and unrelated commands]'
Assert-NotSquashDeny 'gh pr merge 1 --squash --delete-branch' '--squash'
Assert-NotSquashDeny 'gh pr view 1'                            'non-merge gh'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
