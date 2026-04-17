# Propagate VERSION_MAP.yml values into consumer files.
# Use after editing VERSION_MAP.yml (typically invoked by the /release skill).
#
# Consumers:
#   suite           -> README.md, README.ko.md (shields.io badge)
#   plugin          -> plugin/.claude-plugin/plugin.json
#   plugin-lite     -> plugin-lite/.claude-plugin/plugin.json
#   settings-schema -> global/settings.json, global/settings.windows.json
#
# Usage: pwsh scripts/sync_versions.ps1

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$MapFile = Join-Path $RootDir 'VERSION_MAP.yml'

if (-not (Test-Path -LiteralPath $MapFile -PathType Leaf)) {
    Write-Error "VERSION_MAP.yml not found at $MapFile"
    exit 1
}

function Read-MapField {
    param([string]$Key)
    $line = Get-Content -LiteralPath $MapFile | Where-Object { $_ -match "^${Key}:" } | Select-Object -First 1
    if (-not $line) {
        Write-Error "field '$Key' not found in VERSION_MAP.yml"
        exit 1
    }
    if ($line -match "^${Key}:\s*([^\s#]+)") { return $Matches[1] }
    Write-Error "failed to parse field '$Key'"
    exit 1
}

$Suite          = Read-MapField 'suite'
$Plugin         = Read-MapField 'plugin'
$PluginLite     = Read-MapField 'plugin-lite'
$SettingsSchema = Read-MapField 'settings-schema'

function Set-JsonVersion {
    param([string]$File, [string]$NewVersion)
    $path = Join-Path $RootDir $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "SKIP: $File (not found)"
        return
    }
    $content = Get-Content -LiteralPath $path -Raw
    $pattern = '("version"\s*:\s*")[^"]+(")'
    $replacement = '${1}' + $NewVersion + '${2}'
    $updated = [regex]::Replace($content, $pattern, $replacement, 'None', [System.TimeSpan]::FromSeconds(2))
    Set-Content -LiteralPath $path -Value $updated -NoNewline
    Write-Host "synced: $File -> version=$NewVersion"
}

function Set-ReadmeBadge {
    param([string]$File, [string]$NewVersion)
    $path = Join-Path $RootDir $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "SKIP: $File (not found)"
        return
    }
    $content = Get-Content -LiteralPath $path -Raw
    $pattern = '(shields\.io/badge/version-)\d+\.\d+\.\d+'
    $replacement = '${1}' + $NewVersion
    $updated = [regex]::Replace($content, $pattern, $replacement)
    Set-Content -LiteralPath $path -Value $updated -NoNewline
    Write-Host "synced: $File -> badge=$NewVersion"
}

Set-JsonVersion 'plugin/.claude-plugin/plugin.json'      $Plugin
Set-JsonVersion 'plugin-lite/.claude-plugin/plugin.json' $PluginLite
Set-JsonVersion 'global/settings.json'                   $SettingsSchema
Set-JsonVersion 'global/settings.windows.json'           $SettingsSchema
Set-ReadmeBadge 'README.md'    $Suite
Set-ReadmeBadge 'README.ko.md' $Suite

Write-Host ""
Write-Host "sync_versions: done. Run scripts/check_versions.ps1 to verify."
