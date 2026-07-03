#!/usr/bin/env pwsh
#Requires -Version 7.0
# Tests for push-target-guard.ps1 (issue #782). PowerShell parity with
# tests/hooks/test-push-target-guard.sh.
# Run: pwsh tests/hooks/test-push-target-guard.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'push-target-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Invoke-Push {
    param([string]$Cmd)
    $json = (@{ tool_input = @{ command = $Cmd } } | ConvertTo-Json -Compress)
    return ($json | & pwsh -NoProfile -File $script:HookPath 2>$null)
}

function Assert-Allow {
    param([string]$Cmd, [string]$Label)
    $r = Invoke-Push $Cmd
    if ($r -match '"allow"') {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected allow, got: $r")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Deny {
    param([string]$Cmd, [string]$Label)
    $r = Invoke-Push $Cmd
    if ($r -match '"deny"') {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected deny, got: $r")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== push-target-guard.ps1 tests ==='
Write-Host ''
Write-Host '[non-push commands pass through]'
Assert-Allow 'git status'              'git status -> allow'
Assert-Allow 'git commit -m "feat: x"' 'git commit -> allow'

Write-Host ''
Write-Host '[direct push to a protected branch -> deny]'
Assert-Deny 'git push origin main'            'push origin main -> deny'
Assert-Deny 'git push origin develop'         'push origin develop -> deny'
Assert-Deny 'git push origin master'          'push origin master -> deny'
Assert-Deny 'git push -u origin main'         'push -u origin main -> deny'
Assert-Deny 'git push --force origin develop' 'push --force develop -> deny'
Assert-Deny 'git push origin HEAD:main'       'push HEAD:main -> deny'
Assert-Deny 'git push origin +main'           'push +main -> deny'

Write-Host ''
Write-Host '[non-protected targets -> allow]'
Assert-Allow 'git push origin feature/x'     'push feature/x -> allow'
Assert-Allow 'git push origin main:feature'  'push main:feature (dst feature) -> allow'

Write-Host ''
Write-Host '[bare push resolves configured upstream]'
$tmpRepo = Join-Path ([System.IO.Path]::GetTempPath()) "push-target-guard-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmpRepo | Out-Null
try {
    Push-Location $tmpRepo
    & git init -q
    & git checkout -q -b feature/upstream-main
    & git config user.email 'test@example.com'
    & git config user.name 'Test'
    Set-Content -LiteralPath (Join-Path $tmpRepo 'seed.txt') -Value 'seed' -NoNewline
    & git add seed.txt
    & git commit -q -m 'test: seed'
    & git remote add origin https://example.invalid/repo.git
    & git update-ref refs/remotes/origin/main HEAD
    & git config branch.feature/upstream-main.remote origin
    & git config branch.feature/upstream-main.merge refs/heads/main
    Assert-Deny 'git push' 'bare push to upstream main -> deny'
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $tmpRepo -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '[--no-verify -> deny; dry-run -> allow]'
Assert-Deny  'git push --no-verify origin feature/x' 'push --no-verify -> deny'
Assert-Allow 'git push -n origin main'               'push -n (dry-run) main -> allow'
Assert-Allow 'git push --dry-run origin develop'     'push --dry-run develop -> allow'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
