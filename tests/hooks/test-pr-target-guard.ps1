#!/usr/bin/env pwsh
#Requires -Version 7.0
# PowerShell mirror of tests/hooks/test-pr-target-guard.sh.
# Validates pr-target-guard.ps1 parity (#616 hardening): blocks both main
# and master, and resolves the repo default branch via the
# PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE env var when --base is absent.
# Run: pwsh tests/hooks/test-pr-target-guard.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'pr-target-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Invoke-Hook {
    param([string]$Json, [string]$Branch)
    if ($Branch) {
        $env:PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE = $Branch
        try { return ($Json | & pwsh -NoProfile -File $script:HookPath 2>$null) }
        finally { $env:PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE = $null }
    }
    return ($Json | & pwsh -NoProfile -File $script:HookPath 2>$null)
}

function Assert-Decision {
    param([string]$Expect, [string]$Json, [string]$Label, [string]$Branch)
    $result = Invoke-Hook -Json $Json -Branch $Branch
    if ($result -match "`"$Expect`"") {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected $Expect, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== pr-target-guard.ps1 tests ==='
Write-Host ''
Write-Host '[Fail-closed]'
Assert-Decision 'deny'  ''              'Empty input -> deny'
Assert-Decision 'deny'  'INVALID_JSON'  'Malformed JSON -> deny'

Write-Host ''
Write-Host '[Scope: non-create gh commands pass through]'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr view 123"}}'        'gh pr view -> allow'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr merge 42 --squash"}}' 'gh pr merge -> allow (not create)'

Write-Host ''
Write-Host '[gh pr create targeting main: deny]'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --base main --title t"}}'  '--base main -> deny'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --base=main --title t"}}'  '--base=main -> deny'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create -B main --title t"}}'      '-B main -> deny'

Write-Host ''
Write-Host '[gh pr create targeting master: deny (parity fix)]'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --base master --head fix/x --title t"}}'  '--base master from feature -> deny'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --base=master --title t"}}'              '--base=master -> deny'

Write-Host ''
Write-Host '[Release exceptions: develop/release/* -> main|master allowed]'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --base main --head develop --title rel"}}'      'develop -> main -> allow'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --base master --head develop --title rel"}}'    'develop -> master -> allow'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --base main --head release/1.0 --title rel"}}'  'release/1.0 -> main -> allow'

Write-Host ''
Write-Host '[Normal workflow]'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --base develop --title t"}}'  '--base develop -> allow'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --base main-backup --title t"}}' '--base main-backup -> allow (not exact main)'

Write-Host ''
Write-Host '[Default-branch resolution when --base missing (#616 parity)]'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --head fix/x --title t"}}'   'main-default + feature head -> deny'   'main'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --head develop --title rel"}}' 'main-default + develop head -> allow' 'main'
Assert-Decision 'deny'  '{"tool_input":{"command":"gh pr create --head fix/x --title t"}}'   'master-default + feature head -> deny' 'master'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --title t"}}'                'develop-default + no base -> allow'    'develop'
Assert-Decision 'allow' '{"tool_input":{"command":"gh pr create --title t"}}'                'trunk-default -> allow (not main/master)' 'trunk'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
