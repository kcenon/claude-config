# Verify each consumer file's declared version matches VERSION_MAP.yml.
# Exits non-zero on drift. Each field tracks an independent SemVer.
#
# Consumers:
#   suite           -> README.md, README.ko.md (shields.io badge)
#   plugin          -> plugin/.claude-plugin/plugin.json
#   plugin-lite     -> plugin-lite/.claude-plugin/plugin.json
#   settings-schema -> global/settings.json, global/settings.windows.json
#
# Usage: pwsh scripts/check_versions.ps1

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
    if ($line -match "^${Key}:\s*([^\s#]+)") {
        return $Matches[1]
    }
    Write-Error "failed to parse field '$Key'"
    exit 1
}

$Suite          = Read-MapField 'suite'
$Plugin         = Read-MapField 'plugin'
$PluginLite     = Read-MapField 'plugin-lite'
$SettingsSchema = Read-MapField 'settings-schema'

$drift = 0

function Test-JsonVersion {
    param([string]$File, [string]$Expected, [string]$Label)
    $path = Join-Path $RootDir $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "FAIL: consumer missing: $File" -ForegroundColor Red
        $script:drift = 1
        return
    }
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match '"version"\s*:' } | Select-Object -First 1
    if ($line -match '"version"\s*:\s*"([^"]+)"') {
        $actual = $Matches[1]
        if ($actual -ne $Expected) {
            Write-Host "FAIL: $File version=$actual, VERSION_MAP[$Label]=$Expected" -ForegroundColor Red
            $script:drift = 1
        }
    } else {
        Write-Host "FAIL: $File has no version field" -ForegroundColor Red
        $script:drift = 1
    }
}

function Test-ReadmeBadge {
    param([string]$File, [string]$Expected)
    $path = Join-Path $RootDir $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "FAIL: consumer missing: $File" -ForegroundColor Red
        $script:drift = 1
        return
    }
    $content = Get-Content -LiteralPath $path -Raw
    if ($content -match 'shields\.io/badge/version-(\d+\.\d+\.\d+)') {
        $actual = $Matches[1]
        if ($actual -ne $Expected) {
            Write-Host "FAIL: $File badge=$actual, VERSION_MAP[suite]=$Expected" -ForegroundColor Red
            $script:drift = 1
        }
    } else {
        Write-Host "FAIL: $File has no shields.io version badge" -ForegroundColor Red
        $script:drift = 1
    }
}

Test-JsonVersion 'plugin/.claude-plugin/plugin.json'      $Plugin         'plugin'
Test-JsonVersion 'plugin-lite/.claude-plugin/plugin.json' $PluginLite     'plugin-lite'
Test-JsonVersion 'global/settings.json'                   $SettingsSchema 'settings-schema'
Test-JsonVersion 'global/settings.windows.json'           $SettingsSchema 'settings-schema'
Test-ReadmeBadge 'README.md'    $Suite
Test-ReadmeBadge 'README.ko.md' $Suite

if ($drift -eq 0) {
    Write-Host "check_versions: OK"
    Write-Host "  suite=$Suite  plugin=$Plugin  plugin-lite=$PluginLite  settings-schema=$SettingsSchema"
    exit 0
}

Write-Host ""
Write-Host "check_versions: drift detected. Update consumers to match VERSION_MAP.yml," -ForegroundColor Red
Write-Host "or run scripts/sync_versions.ps1 to auto-propagate map values to consumers." -ForegroundColor Red
exit 2
