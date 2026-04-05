#!/usr/bin/env pwsh
#Requires -Version 7.0
# team-report.ps1 — Team activity summary
# Usage: pwsh team-report.ps1 [days]
# Reads plain-text logs from ~/.claude/ and outputs a summary report.

param([int]$Days = 7)

$ErrorActionPreference = 'Stop'

# Import shared module
$modulePath = Join-Path (Split-Path $PSScriptRoot) 'hooks' 'lib' 'CommonHelpers.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

$SessionLog   = Join-Path $HOME '.claude' 'session.log'
$SubagentLog  = Join-Path $HOME '.claude' 'logs' 'subagents.log'
$TaskLog      = Join-Path $HOME '.claude' 'logs' 'tasks.log'
$ToolFailLog  = Join-Path $HOME '.claude' 'logs' 'tool-failures.log'

# Compute cutoff date (YYYY-MM-DD)
$Cutoff = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')

# --- Helper: filter lines with [YYYY-MM-DD HH:MM:SS] prefix by date ---
function Filter-BracketedLines {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return @() }
    $lines = Get-Content -LiteralPath $FilePath
    $filtered = @()
    foreach ($line in $lines) {
        if ($line -match '\[(\d{4}-\d{2}-\d{2})') {
            $dateStr = $Matches[1]
            if ($dateStr -ge $Cutoff) {
                $filtered += $line
            }
        }
    }
    return $filtered
}

# --- Helper: filter session.log lines (date after colon) ---
function Filter-SessionLines {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return @() }
    $lines = Get-Content -LiteralPath $FilePath
    $filtered = @()
    foreach ($line in $lines) {
        if ($line -match ':\s*(\d{4}-\d{2}-\d{2})') {
            $dateStr = $Matches[1]
            if ($dateStr -ge $Cutoff) {
                $filtered += $line
            }
        }
    }
    return $filtered
}

# --- Helper: filter tool-failures.log (multi-line blocks) ---
function Filter-ToolFailureLines {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return @() }
    $lines = Get-Content -LiteralPath $FilePath
    $filtered = @()
    $inRange = $false
    foreach ($line in $lines) {
        if ($line -match '^=== Tool Failure at ') {
            if ($line -match '(\d{4}-\d{2}-\d{2})') {
                $dateStr = $Matches[1]
                $inRange = ($dateStr -ge $Cutoff)
            }
        }
        if ($inRange) {
            $filtered += $line
        }
    }
    return $filtered
}

$today = (Get-Date).ToString('yyyy-MM-dd')

Write-Output '========================================'
Write-Output '  Team Activity Report'
Write-Output "  Period: $Cutoff ~ $today ($Days days)"
Write-Output '========================================'
Write-Output ''

# --- Sessions ---
Write-Output '--- Sessions ---'
if (Test-Path -LiteralPath $SessionLog) {
    $sessionLines = Filter-SessionLines -FilePath $SessionLog
    $started = @($sessionLines | Where-Object { $_ -match 'session started' }).Count
    $ended   = @($sessionLines | Where-Object { $_ -match 'session ended' }).Count
    Write-Output "  Started : $started"
    Write-Output "  Ended   : $ended"
} else {
    Write-Output '  (no session log found)'
}
Write-Output ''

# --- Subagents ---
Write-Output '--- Subagent Starts (by type) ---'
if (Test-Path -LiteralPath $SubagentLog) {
    $subagentLines = Filter-BracketedLines -FilePath $SubagentLog | Where-Object { $_ -match 'Subagent start' }
    if ($subagentLines.Count -gt 0) {
        $names = $subagentLines | ForEach-Object {
            if ($_ -match 'Subagent start[: -]*\s*(.+)$') {
                $Matches[1].Trim()
            }
        }
        $grouped = $names | Group-Object | Sort-Object Count -Descending
        foreach ($g in $grouped) {
            Write-Output ("  {0,-20} {1}" -f $g.Name, $g.Count)
        }
    } else {
        Write-Output '  (none in period)'
    }
} else {
    Write-Output '  (no subagent log found)'
}
Write-Output ''

# --- Task Completions ---
Write-Output '--- Task Completions ---'
if (Test-Path -LiteralPath $TaskLog) {
    $taskLines = Filter-BracketedLines -FilePath $TaskLog | Where-Object { $_ -match 'Task #.*completed' }
    Write-Output "  Completed : $($taskLines.Count)"
} else {
    Write-Output '  (no task log found)'
}
Write-Output ''

# --- Tool Failures ---
Write-Output '--- Tool Failures (by tool) ---'
if (Test-Path -LiteralPath $ToolFailLog) {
    $failLines = Filter-ToolFailureLines -FilePath $ToolFailLog | Where-Object { $_ -match '^Tool: ' }
    if ($failLines.Count -gt 0) {
        $toolNames = $failLines | ForEach-Object { ($_ -replace '^Tool: ', '').Trim() }
        Write-Output "  Total: $($toolNames.Count)"
        $grouped = $toolNames | Group-Object | Sort-Object Count -Descending
        foreach ($g in $grouped) {
            Write-Output ("  {0,-20} {1}" -f $g.Name, $g.Count)
        }
    } else {
        Write-Output '  (none in period)'
    }
} else {
    Write-Output '  (no tool-failure log found)'
}
Write-Output ''
Write-Output '========================================'
