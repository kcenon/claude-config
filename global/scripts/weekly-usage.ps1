#!/usr/bin/env pwsh
#Requires -Version 7.0
# Weekly Usage Script for Claude Code Statusline
# Reads stats-cache.json and calculates weekly usage statistics

$ErrorActionPreference = 'SilentlyContinue'

# Import shared module
$modulePath = Join-Path (Split-Path $PSScriptRoot) 'hooks' 'lib' 'CommonHelpers.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

$StatsFile = Join-Path $HOME '.claude' 'stats-cache.json'

# Check if stats file exists
if (-not (Test-Path -LiteralPath $StatsFile)) {
    Write-Output 'W:N/A'
    exit 0
}

# Read and parse stats file
try {
    $stats = Get-Content -Raw -LiteralPath $StatsFile | ConvertFrom-Json
} catch {
    Write-Output 'W:N/A'
    exit 0
}

# Get current date info
$today = Get-Date
$dayOfWeek = [int]$today.DayOfWeek  # 0=Sunday, 6=Saturday

# Calculate days since Monday (week start)
# PowerShell DayOfWeek: 0=Sun, 1=Mon, ... 6=Sat
# Convert to ISO: Mon=1, Tue=2, ... Sun=7
$isoDayOfWeek = if ($dayOfWeek -eq 0) { 7 } else { $dayOfWeek }
$daysSinceMonday = $isoDayOfWeek - 1

# Calculate week start date (Monday)
$weekStart = $today.AddDays(-$daysSinceMonday).ToString('yyyy-MM-dd')

# Extract weekly message count from stats-cache.json
$weeklyMessages = 0
if ($stats.dailyActivity) {
    $weeklyMessages = @($stats.dailyActivity |
        Where-Object { $_.date -ge $weekStart } |
        ForEach-Object { $_.messageCount }) |
        Measure-Object -Sum |
        Select-Object -ExpandProperty Sum
    if ($null -eq $weeklyMessages) { $weeklyMessages = 0 }
}

# Extract weekly token count
$weeklyTokens = 0
if ($stats.dailyModelTokens) {
    $weeklyTokens = @($stats.dailyModelTokens |
        Where-Object { $_.date -ge $weekStart } |
        ForEach-Object {
            $entry = $_
            $sum = 0
            if ($entry.tokensByModel) {
                $entry.tokensByModel.PSObject.Properties | ForEach-Object {
                    $sum += $_.Value
                }
            }
            $sum
        }) |
        Measure-Object -Sum |
        Select-Object -ExpandProperty Sum
    if ($null -eq $weeklyTokens) { $weeklyTokens = 0 }
}

# Calculate days remaining until next Monday
$daysRemaining = 7 - $isoDayOfWeek
if ($daysRemaining -eq 7) { $daysRemaining = 0 }

# Format message count (K)
if ($weeklyMessages -ge 1000) {
    $msgDisplay = '{0:F1}K' -f ($weeklyMessages / 1000)
} else {
    $msgDisplay = [string]$weeklyMessages
}

# Format token count (K or M)
if ($weeklyTokens -ge 1000000) {
    $tokenDisplay = '{0:F1}M' -f ($weeklyTokens / 1000000)
} elseif ($weeklyTokens -ge 1000) {
    $tokenDisplay = '{0}K' -f [math]::Round($weeklyTokens / 1000)
} else {
    $tokenDisplay = [string]$weeklyTokens
}

# Output format: Week Reset in Xd | Msgs | Tokens
# Example: W:3d 35.7K/1.3M
Write-Output "W:${daysRemaining}d ${msgDisplay}/${tokenDisplay}"
