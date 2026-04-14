#!/usr/bin/env pwsh
# Statusline: ccstatusline handles all display including usage data
#
# Requirements:
#   npm install -g ccstatusline
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
$StdinData = $null
try { $StdinData = ConvertFrom-Json -InputObject $InputData.Trim() } catch { }

# Get ccstatusline output (pass stdin), fallback to stdin JSON parsing if unavailable
$CcslExe = $null
$CcslArgs = @()
if (Get-Command ccstatusline -ErrorAction SilentlyContinue) {
    $InputData | ccstatusline 2>$null
    $CcslExe = 'ccstatusline'
} elseif (Get-Command npx -ErrorAction SilentlyContinue) {
    $InputData | npx ccstatusline@latest 2>$null
    $CcslExe = 'npx'
    $CcslArgs = @('ccstatusline@latest')
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
    if ($fallbackParts.Count -gt 0) { Write-Output ($fallbackParts -join ' | ') }
}

# ccstatusline takes a "rate_limits shortcut": when Claude Code's stdin includes
# rate_limits, it skips the OAuth usage API call entirely. That means the cache
# file usage.json (which holds extraUsage* fields) never gets refreshed, and the
# Extra line below shows hours-old data while the rest of the bar stays fresh.
# Fix: when usage.json is older than ccstatusline's CACHE_MAX_AGE (180s), kick
# off a background ccstatusline run with rate_limits stripped from stdin to
# force fetchUsageData(). The next status bar refresh picks up the fresh file.
$UsageCache = Join-Path $HOME ".cache" "ccstatusline" "usage.json"
$UsageLock = Join-Path $HOME ".cache" "ccstatusline" "usage.lock"
$UsageCacheTtl = 180

# Detect ccstatusline's own rate-limit lock. When the OAuth usage API returns
# 429, ccstatusline writes {"blockedUntil":<epoch>} into usage.lock; until that
# timestamp passes, any spawned ccstatusline is a no-op. Skip the background
# refresh in that window to avoid spawning wasted jobs every 30s, and expose
# $lockRemaining so the Extra line can show the reason the values are stale.
$lockRemaining = 0
if (Test-Path $UsageLock) {
    try {
        $lockData = Get-Content $UsageLock -Raw | ConvertFrom-Json
        $blockedUntil = [int64]$lockData.blockedUntil
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($blockedUntil -gt $nowEpoch) {
            $lockRemaining = [int]($blockedUntil - $nowEpoch)
        }
    } catch { }
}

if ($CcslExe -and $StdinData) {
    $needsRefresh = $true
    if (Test-Path $UsageCache) {
        $cacheAge = (New-TimeSpan -Start (Get-Item $UsageCache).LastWriteTimeUtc -End ([DateTime]::UtcNow)).TotalSeconds
        if ($cacheAge -lt $UsageCacheTtl) { $needsRefresh = $false }
    }
    if ($needsRefresh -and $lockRemaining -eq 0) {
        try {
            $stripped = $StdinData | Select-Object -Property * -ExcludeProperty rate_limits | ConvertTo-Json -Depth 32 -Compress
            Start-Job -ScriptBlock {
                param($exe, $extraArgs, $payload)
                $payload | & $exe @extraArgs *> $null
            } -ArgumentList $CcslExe, $CcslArgs, $stripped | Out-Null
        } catch { }
    }
}

# Append extra usage line from ccstatusline cache
if (Test-Path $UsageCache) {
    try {
        $usage = Get-Content $UsageCache -Raw | ConvertFrom-Json
        if ($usage.extraUsageEnabled -eq $true) {
            $limitUsd = [math]::Floor($usage.extraUsageLimit / 100)
            $usedUsd = [math]::Round($usage.extraUsageUsed / 100, 2)
            $remainUsd = [math]::Round(($usage.extraUsageLimit - $usage.extraUsageUsed) / 100, 2)
            $remainPct = [math]::Floor(100 - $usage.extraUsageUtilization)
            $ESC = [char]0x1B
            $c = if ($remainPct -gt 50) { '32' } elseif ($remainPct -gt 20) { '33' } else { '31' }

            # When ccstatusline's usage lock is active, the cached values above
            # are frozen until the lock expires. Append a dim-gray "(locked Nm)"
            # marker so the user can tell the stale values are intentional.
            $lockedSuffix = ""
            if ($lockRemaining -gt 0) {
                if ($lockRemaining -ge 60) {
                    $lockedSuffix = " ${ESC}[90m(locked $([math]::Floor($lockRemaining / 60))m)${ESC}[0m"
                } else {
                    $lockedSuffix = " ${ESC}[90m(locked ${lockRemaining}s)${ESC}[0m"
                }
            }

            Write-Output "${ESC}[${c}mExtra: `$$usedUsd/`$$limitUsd (${remainPct}%)${ESC}[0m | ${ESC}[${c}mRemain: `$$remainUsd${ESC}[0m${lockedSuffix}"
        }
    } catch { }
}
