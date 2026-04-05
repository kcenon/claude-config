#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for cleanup.ps1
# Run: pwsh tests/hooks/test-cleanup.ps1
#
# cleanup.ps1 uses ${TMPDIR} or system temp for file cleanup.
# Tests override TMPDIR to an isolated directory for safe testing.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'cleanup.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

$TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "test-cleanup-$PID"
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

# Cleanup on exit
$cleanupAction = { if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir } }

try {
    # Run the hook with TMPDIR pointing to our test directory
    function Invoke-CleanupHook {
        & pwsh -NoProfile -Command "& { `$env:TMPDIR = '$TestDir'; & '$($script:HookPath)' }" 2>$null | Out-Null
        return $LASTEXITCODE
    }

    Write-Host '=== cleanup.ps1 tests ==='
    Write-Host ''

    # --- Script exits with 0 ---
    Write-Host '[Exit code]'
    $exitCode = Invoke-CleanupHook
    if ($exitCode -eq 0) {
        $script:Passed++
        Write-Host '  PASS: Exit code 0' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: Expected exit code 0, got: $exitCode")
        Write-Host '  FAIL: Exit code 0' -ForegroundColor Red
    }

    # --- Script does not produce stdout output ---
    Write-Host ''
    Write-Host '[No output]'
    $output = & pwsh -NoProfile -Command "& { `$env:TMPDIR = '$TestDir'; & '$($script:HookPath)' 2>`$null }"
    if ([string]::IsNullOrEmpty($output)) {
        $script:Passed++
        Write-Host '  PASS: No stdout output' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: Expected no stdout, got: $output")
        Write-Host '  FAIL: No stdout output' -ForegroundColor Red
    }

    # --- Script is idempotent ---
    Write-Host ''
    Write-Host '[Idempotent]'
    $exit1 = Invoke-CleanupHook
    $exit2 = Invoke-CleanupHook
    if ($exit1 -eq 0 -and $exit2 -eq 0) {
        $script:Passed++
        Write-Host '  PASS: Idempotent - multiple runs return 0' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: Non-zero exit on repeated run (exit1=$exit1, exit2=$exit2)")
        Write-Host '  FAIL: Idempotent - multiple runs return 0' -ForegroundColor Red
    }

    # --- Recent files should NOT be deleted (age < 60 min) ---
    Write-Host ''
    Write-Host '[Preserves recent files]'
    $recentFile = Join-Path $TestDir 'claude_test_recent'
    New-Item -ItemType File -Path $recentFile -Force | Out-Null
    $null = Invoke-CleanupHook
    if (Test-Path $recentFile) {
        $script:Passed++
        Write-Host '  PASS: Recent claude_* file preserved (< 60 min)' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Recent claude_* file was deleted')
        Write-Host '  FAIL: Recent claude_* file preserved (< 60 min)' -ForegroundColor Red
    }
    Remove-Item -Path $recentFile -Force -ErrorAction SilentlyContinue

    $recentTmp = Join-Path $TestDir 'tmp.test_recent'
    New-Item -ItemType File -Path $recentTmp -Force | Out-Null
    $null = Invoke-CleanupHook
    if (Test-Path $recentTmp) {
        $script:Passed++
        Write-Host '  PASS: Recent tmp.* file preserved (< 60 min)' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Recent tmp.* file was deleted')
        Write-Host '  FAIL: Recent tmp.* file preserved (< 60 min)' -ForegroundColor Red
    }
    Remove-Item -Path $recentTmp -Force -ErrorAction SilentlyContinue

    # --- Non-matching file should NOT be deleted ---
    Write-Host ''
    Write-Host '[Non-matching patterns preserved]'
    $safeFile = Join-Path $TestDir 'safe_file_test'
    New-Item -ItemType File -Path $safeFile -Force | Out-Null
    $null = Invoke-CleanupHook
    if (Test-Path $safeFile) {
        $script:Passed++
        Write-Host '  PASS: Non-matching file preserved' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Non-matching file was deleted')
        Write-Host '  FAIL: Non-matching file preserved' -ForegroundColor Red
    }
    Remove-Item -Path $safeFile -Force -ErrorAction SilentlyContinue

    # --- "claudetest" (no underscore) should NOT match "claude_*" ---
    Write-Host ''
    Write-Host '[Pattern specificity]'
    $claudeNoUnderscore = Join-Path $TestDir 'claudetest_file'
    New-Item -ItemType File -Path $claudeNoUnderscore -Force | Out-Null
    (Get-Item $claudeNoUnderscore).LastWriteTime = [datetime]::new(2020, 1, 1, 0, 0, 0)
    $null = Invoke-CleanupHook
    if (Test-Path $claudeNoUnderscore) {
        $script:Passed++
        Write-Host "  PASS: 'claudetest' (no underscore) preserved" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: 'claudetest' (no underscore) was deleted")
        Write-Host "  FAIL: 'claudetest' (no underscore) preserved" -ForegroundColor Red
    }
    Remove-Item -Path $claudeNoUnderscore -Force -ErrorAction SilentlyContinue

    # --- Old claude_* file SHOULD be deleted (age > 60 min) ---
    Write-Host ''
    Write-Host '[Old files deleted]'
    $oldClaude = Join-Path $TestDir 'claude_old_file'
    New-Item -ItemType File -Path $oldClaude -Force | Out-Null
    (Get-Item $oldClaude).LastWriteTime = [datetime]::new(2020, 1, 1, 0, 0, 0)
    $null = Invoke-CleanupHook
    if (-not (Test-Path $oldClaude)) {
        $script:Passed++
        Write-Host '  PASS: Old claude_* file deleted (> 60 min)' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Old claude_* file was not deleted')
        Write-Host '  FAIL: Old claude_* file deleted (> 60 min)' -ForegroundColor Red
    }

    $oldTmp = Join-Path $TestDir 'tmp.old_file'
    New-Item -ItemType File -Path $oldTmp -Force | Out-Null
    (Get-Item $oldTmp).LastWriteTime = [datetime]::new(2020, 1, 1, 0, 0, 0)
    $null = Invoke-CleanupHook
    if (-not (Test-Path $oldTmp)) {
        $script:Passed++
        Write-Host '  PASS: Old tmp.* file deleted (> 60 min)' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Old tmp.* file was not deleted')
        Write-Host '  FAIL: Old tmp.* file deleted (> 60 min)' -ForegroundColor Red
    }

    # --- maxdepth 1: nested files should NOT be touched ---
    Write-Host ''
    Write-Host '[Maxdepth 1 - subdirectory files not touched]'
    $subDir = Join-Path $TestDir 'subdir_test'
    New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    $nestedFile = Join-Path $subDir 'claude_nested'
    New-Item -ItemType File -Path $nestedFile -Force | Out-Null
    (Get-Item $nestedFile).LastWriteTime = [datetime]::new(2020, 1, 1, 0, 0, 0)
    $null = Invoke-CleanupHook
    if (Test-Path $nestedFile) {
        $script:Passed++
        Write-Host '  PASS: Nested file in subdirectory preserved' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Nested file in subdirectory was deleted')
        Write-Host '  FAIL: Nested file in subdirectory preserved' -ForegroundColor Red
    }
    Remove-Item -Recurse -Force $subDir -ErrorAction SilentlyContinue

    # --- Source-level checks ---
    Write-Host ''
    Write-Host '[Source verification]'
    $hookSource = Get-Content -Raw -LiteralPath $script:HookPath

    if ($hookSource -match '60' -and $hookSource -match 'minute|min|mmin|AddMinutes') {
        $script:Passed++
        Write-Host '  PASS: Uses 60-minute age threshold' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Missing 60-minute age threshold')
        Write-Host '  FAIL: Uses 60-minute age threshold' -ForegroundColor Red
    }

    if ($hookSource -match 'maxdepth|depth\s*1|Get-ChildItem(?!.*-Recurse)' -or $hookSource -notmatch '-Recurse') {
        $script:Passed++
        Write-Host '  PASS: Limits to top-level files (no recurse)' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Missing depth-1 constraint')
        Write-Host '  FAIL: Limits to top-level files (no recurse)' -ForegroundColor Red
    }

    if ($hookSource -match 'TMPDIR|GetTempPath') {
        $script:Passed++
        Write-Host '  PASS: Uses TMPDIR or system temp variable' -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add('FAIL: Does not use TMPDIR or system temp variable')
        Write-Host '  FAIL: Uses TMPDIR or system temp variable' -ForegroundColor Red
    }

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
