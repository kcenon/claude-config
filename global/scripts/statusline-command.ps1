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
if (Get-Command ccstatusline -ErrorAction SilentlyContinue) {
    $InputData | ccstatusline 2>$null
} elseif (Get-Command npx -ErrorAction SilentlyContinue) {
    $InputData | npx ccstatusline@latest 2>$null
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
