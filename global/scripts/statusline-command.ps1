#!/usr/bin/env pwsh
# Combined statusline: ccstatusline + claude-limitline usage info
# PowerShell equivalent of statusline-command.sh
#
# Requirements (optional):
#   npm install -g ccstatusline claude-limitline
#
# Usage in settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"& (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\\scripts\\statusline-command.ps1')\""
#   }

$ErrorActionPreference = 'SilentlyContinue'

# Force UTF-8 to match Claude Code's stdin encoding (Windows default is CP949)
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read stdin once and store it
$InputData = [Console]::In.ReadToEnd()

# Parse stdin JSON for fallback display (Claude Code provides this data)
# Use -InputObject to avoid pipeline splitting on newlines, and Trim() to strip trailing newline
$StdinData = $null
try { $StdinData = ConvertFrom-Json -InputObject $InputData.Trim() } catch { }

# Get ccstatusline output (pass stdin), fallback to stdin JSON parsing if unavailable
$CcStatus = $null
if (Get-Command ccstatusline -ErrorAction SilentlyContinue) {
    $CcStatus = $InputData | ccstatusline 2>$null
} elseif (Get-Command npx -ErrorAction SilentlyContinue) {
    $CcStatus = $InputData | npx ccstatusline@latest 2>$null
} elseif ($StdinData) {
    # Fallback: build status line directly from stdin JSON
    $ESC = [char]0x1B
    $model = if ($StdinData.model) { $StdinData.model.display_name } else { $null }
    $ctxPct = if ($StdinData.context_window) { $StdinData.context_window.used_percentage } else { $null }
    $cost = if ($StdinData.cost) { $StdinData.cost.total_cost_usd } else { $null }

    $fallbackParts = @()
    if ($model) { $fallbackParts += "${ESC}[1m${model}${ESC}[0m" }
    if ($null -ne $ctxPct) {
        $c = if ($ctxPct -lt 50) { '32' } elseif ($ctxPct -lt 80) { '33' } else { '31' }
        $fallbackParts += "${ESC}[${c}mCTX: $([math]::Round($ctxPct, 1))%${ESC}[0m"
    }
    if ($null -ne $cost -and $cost -gt 0) {
        $fallbackParts += "${ESC}[36m`$$([math]::Round($cost, 4))${ESC}[0m"
    }
    if ($fallbackParts.Count -gt 0) { $CcStatus = $fallbackParts -join ' | ' }
}

# Get claude-limitline output (pass stdin)
if (Get-Command claude-limitline -ErrorAction SilentlyContinue) {
    $LimitLine = $InputData | claude-limitline 2>$null
} else {
    $LimitLine = $null
}

# Join array output into single string for regex matching
$LimitLineStr = if ($LimitLine -is [array]) { $LimitLine -join "`n" } else { "$LimitLine" }

# Strip ANSI codes for parsing
$LimitLineClean = $LimitLineStr -replace '\x1B\[[0-9;]*m', ''

# Extract session usage: special char followed by XX%
$SessionUsage = $null
if ($LimitLineClean -match ([regex]::Escape([char]0x25AB) + '\s*(\d+)%') -or
    $LimitLineClean -match ([regex]::Escape([char]0x25EB) + '\s*(\d+)%') -or
    $LimitLineClean -match 'Session[:\s]*(\d+)%') {
    $SessionUsage = [int]$Matches[1]
}

# Extract weekly usage: special char followed by XX%
$WeeklyUsage = $null
if ($LimitLineClean -match ([regex]::Escape([char]0x25CB) + '\s*(\d+)%') -or
    $LimitLineClean -match 'Weekly[:\s]*(\d+)%') {
    $WeeklyUsage = [int]$Matches[1]
}

# ANSI color based on usage percentage
function Get-UsageColor([int]$Pct) {
    if ($Pct -lt 50) { '32' }       # green
    elseif ($Pct -lt 80) { '33' }   # yellow
    else { '31' }                     # red
}

# Resolve KST timezone (Windows: 'Korea Standard Time', Linux/macOS: 'Asia/Seoul')
function Get-KstTimeZone {
    try {
        [System.TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
    } catch {
        try {
            [System.TimeZoneInfo]::FindSystemTimeZoneById('Asia/Seoul')
        } catch {
            $null
        }
    }
}

# Calculate time until midnight KST (session reset)
function Get-SessionResetTime {
    $tz = Get-KstTimeZone
    if (-not $tz) { return 'midnight' }

    $nowKst = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
    $midnightKst = $nowKst.Date.AddDays(1)
    $diff = $midnightKst - $nowKst

    if ($diff.Hours -gt 0) {
        "$($diff.Hours)h $($diff.Minutes)m"
    } else {
        "$($diff.Minutes)m"
    }
}

# Calculate time until weekly reset (Thursday 5pm KST)
function Get-WeeklyResetTime {
    $tz = Get-KstTimeZone
    if (-not $tz) { return 'Thu 5pm' }

    $nowKst = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)

    # DayOfWeek: Sunday=0 ... Saturday=6 -> ISO: Mon=1 ... Sun=7
    $dow = [int]$nowKst.DayOfWeek
    $isoDow = if ($dow -eq 0) { 7 } else { $dow }

    # Days until Thursday (ISO day 4)
    $daysUntil = (4 - $isoDow + 7) % 7

    # If today is Thursday and past 5pm, next Thursday
    if ($daysUntil -eq 0 -and $nowKst.Hour -ge 17) {
        $daysUntil = 7
    }

    $target = $nowKst.Date.AddDays($daysUntil).AddHours(17)
    $diff = $target - $nowKst

    if ($diff.Days -gt 0) {
        "$($diff.Days)d $($diff.Hours)h"
    } else {
        "$($diff.Hours)h"
    }
}

$ESC = [char]0x1B

# Output ccstatusline rows first
if ($CcStatus) {
    Write-Output $CcStatus
}

# Build usage line
$parts = @()

if ($null -ne $SessionUsage) {
    $c = Get-UsageColor $SessionUsage
    $r = Get-SessionResetTime
    $parts += "$ESC[${c}mSession: ${SessionUsage}%$ESC[0m $ESC[36m(resets in ${r})$ESC[0m"
}

if ($null -ne $WeeklyUsage) {
    $c = Get-UsageColor $WeeklyUsage
    $r = Get-WeeklyResetTime
    $parts += "$ESC[${c}mWeekly: ${WeeklyUsage}%$ESC[0m $ESC[36m(resets in ${r})$ESC[0m"
}

if ($parts.Count -gt 0) {
    Write-Output ($parts -join ' | ')
}
