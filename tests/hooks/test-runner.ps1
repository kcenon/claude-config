#!/usr/bin/env pwsh
#Requires -Version 7.0
# Hook test runner (PowerShell)
# Run: pwsh tests/hooks/test-runner.ps1
# Runs all test-*.ps1 scripts in this directory and reports results.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TotalPass = 0
$TotalFail = 0
$FailedSuites = [System.Collections.Generic.List[string]]::new()

Write-Host '========================================='
Write-Host '  Hook Test Suite'
Write-Host '========================================='
Write-Host ''

$testFiles = Get-ChildItem -Path $ScriptDir -Filter 'test-*.ps1' | Sort-Object Name
foreach ($testFile in $testFiles) {
    # Skip self
    if ($testFile.Name -eq 'test-runner.ps1') { continue }

    $suiteName = $testFile.BaseName -replace '^test-', ''

    Write-Host "--- $suiteName ---"
    try {
        $output = & pwsh -NoProfile -File $testFile.FullName 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }

    # Extract pass/fail counts from output
    $pass = 0
    $fail = 0
    if ($output -match '(\d+)\s+passed') { $pass = [int]$Matches[1] }
    if ($output -match '(\d+)\s+failed') { $fail = [int]$Matches[1] }

    $TotalPass += $pass
    $TotalFail += $fail

    if ($exitCode -ne 0) {
        $FailedSuites.Add($suiteName)
    }

    # Print last non-empty line from output
    $outputLines = ($output -split "`n") | Where-Object { $_.Trim() -ne '' }
    if ($outputLines.Count -gt 0) {
        Write-Host ($outputLines[-1].Trim())
    }
    Write-Host ''
}

Write-Host '========================================='
Write-Host "  Total: $TotalPass passed, $TotalFail failed"
Write-Host '========================================='

if ($FailedSuites.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failed suites:'
    foreach ($s in $FailedSuites) {
        Write-Host "  - $s"
    }
    exit 1
}

exit 0
