#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for team-limit-guard.ps1
# Run: pwsh tests/hooks/test-team-limit-guard.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'team-limit-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

# Create a temp dir to use as HOME so we don't touch the real ~/.claude/teams
$TestHome = Join-Path ([System.IO.Path]::GetTempPath()) "test-team-limit-guard-$PID"
New-Item -ItemType Directory -Path $TestHome -Force | Out-Null

# Cleanup on exit
$cleanupAction = { if (Test-Path $TestHome) { Remove-Item -Recurse -Force $TestHome } }

try {
    # Clear MAX_TEAMS from env so the hook uses its default (3)
    Remove-Item Env:MAX_TEAMS -ErrorAction SilentlyContinue

    function Assert-Deny {
        param([string]$InputJson, [string]$Label)
        $result = $InputJson | & pwsh -NoProfile -Command "& { `$env:HOME = '$TestHome'; & '$($script:HookPath)' }" 2>$null
        if ($result -match '"deny"') {
            $script:Passed++
            Write-Host "  PASS: $Label" -ForegroundColor Green
        } else {
            $script:Failed++
            $script:Errors.Add("FAIL: $Label - expected deny, got: $result")
            Write-Host "  FAIL: $Label" -ForegroundColor Red
        }
    }

    function Assert-Allow {
        param([string]$InputJson, [string]$Label)
        $result = $InputJson | & pwsh -NoProfile -Command "& { `$env:HOME = '$TestHome'; & '$($script:HookPath)' }" 2>$null
        if ($result -match '"allow"' -or [string]::IsNullOrEmpty($result)) {
            $script:Passed++
            Write-Host "  PASS: $Label" -ForegroundColor Green
        } else {
            $script:Failed++
            $script:Errors.Add("FAIL: $Label - expected allow, got: $result")
            Write-Host "  FAIL: $Label" -ForegroundColor Red
        }
    }

    Write-Host '=== team-limit-guard.ps1 tests ==='
    Write-Host ''

    # --- No teams directory ---
    Write-Host '[No teams directory]'
    $teamsDir = Join-Path $TestHome '.claude' 'teams'
    if (Test-Path $teamsDir) { Remove-Item -Recurse -Force $teamsDir }
    Assert-Allow -InputJson '{}' -Label 'No teams directory -> allow'

    # --- Empty teams directory ---
    Write-Host ''
    Write-Host '[Empty teams directory]'
    New-Item -ItemType Directory -Path $teamsDir -Force | Out-Null
    Assert-Allow -InputJson '{}' -Label 'Empty teams dir (0 teams, limit 3) -> allow'

    # --- Below limit ---
    Write-Host ''
    Write-Host '[Below limit]'
    New-Item -ItemType Directory -Path (Join-Path $teamsDir 'team-1') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $teamsDir 'team-2') -Force | Out-Null
    Assert-Allow -InputJson '{}' -Label '2 teams (limit 3) -> allow'

    # --- At limit (default MAX_TEAMS=3) ---
    Write-Host ''
    Write-Host '[At limit - default MAX_TEAMS=3]'
    New-Item -ItemType Directory -Path (Join-Path $teamsDir 'team-3') -Force | Out-Null
    Assert-Deny -InputJson '{}' -Label '3 teams (limit 3) -> deny'

    # --- Above limit ---
    Write-Host ''
    Write-Host '[Above limit]'
    New-Item -ItemType Directory -Path (Join-Path $teamsDir 'team-4') -Force | Out-Null
    Assert-Deny -InputJson '{}' -Label '4 teams (limit 3) -> deny'

    # --- MAX_TEAMS override from env ---
    Write-Host ''
    Write-Host '[MAX_TEAMS env override]'
    # With 4 teams and MAX_TEAMS=5, should allow
    $result = '{}' | & pwsh -NoProfile -Command "& { `$env:HOME = '$TestHome'; `$env:MAX_TEAMS = '5'; & '$($script:HookPath)' }" 2>$null
    if ($result -match '"allow"') {
        $script:Passed++
        Write-Host '  PASS: 4 teams with MAX_TEAMS=5 -> allow' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: 4 teams with MAX_TEAMS=5 - expected allow, got: $result")
        Write-Host '  FAIL: 4 teams with MAX_TEAMS=5 -> allow' -ForegroundColor Red
    }

    # With 4 teams and MAX_TEAMS=4, should deny
    $result = '{}' | & pwsh -NoProfile -Command "& { `$env:HOME = '$TestHome'; `$env:MAX_TEAMS = '4'; & '$($script:HookPath)' }" 2>$null
    if ($result -match '"deny"') {
        $script:Passed++
        Write-Host '  PASS: 4 teams with MAX_TEAMS=4 -> deny' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: 4 teams with MAX_TEAMS=4 - expected deny, got: $result")
        Write-Host '  FAIL: 4 teams with MAX_TEAMS=4 -> deny' -ForegroundColor Red
    }

    # With 4 teams and MAX_TEAMS=1, should deny
    $result = '{}' | & pwsh -NoProfile -Command "& { `$env:HOME = '$TestHome'; `$env:MAX_TEAMS = '1'; & '$($script:HookPath)' }" 2>$null
    if ($result -match '"deny"') {
        $script:Passed++
        Write-Host '  PASS: 4 teams with MAX_TEAMS=1 -> deny' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: 4 teams with MAX_TEAMS=1 - expected deny, got: $result")
        Write-Host '  FAIL: 4 teams with MAX_TEAMS=1 -> deny' -ForegroundColor Red
    }

    # --- Files in teams dir should not count (only directories) ---
    Write-Host ''
    Write-Host '[Only directories count]'
    if (Test-Path $teamsDir) { Remove-Item -Recurse -Force $teamsDir }
    New-Item -ItemType Directory -Path $teamsDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $teamsDir 'not-a-dir.txt') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $teamsDir 'also-not-a-dir') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $teamsDir 'real-team') -Force | Out-Null
    # 1 directory, 2 files - should allow with default limit 3
    Assert-Allow -InputJson '{}' -Label '1 dir + 2 files (limit 3) -> allow (files ignored)'

    # --- Cleanup and re-test allow after removing teams ---
    Write-Host ''
    Write-Host '[After removing teams]'
    if (Test-Path $teamsDir) { Remove-Item -Recurse -Force $teamsDir }
    New-Item -ItemType Directory -Path $teamsDir -Force | Out-Null
    Assert-Allow -InputJson '{}' -Label 'Cleared teams dir -> allow'

    Write-Host ''
    Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
    if ($script:Errors.Count -gt 0) {
        Write-Host ''
        foreach ($err in $script:Errors) {
            Write-Host "  $err"
        }
        exit 1
    }
    exit 0
}
finally {
    # Cleanup temp directory
    & $cleanupAction
}
