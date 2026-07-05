# Test suite for scripts/check_versions.ps1 and scripts/sync_versions.ps1.
# Run: pwsh -NoProfile -File tests/scripts/test-check-versions.ps1

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Check = Join-Path $RootDir 'scripts/check_versions.ps1'
$Sync = Join-Path $RootDir 'scripts/sync_versions.ps1'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("version-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null

$Pass = 0
$Fail = 0
$Errors = @()

function Write-Fixture {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Assert-Exit {
    param([int]$Expected, [int]$Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        $script:Errors += "FAIL: $Label -- expected exit $Expected, got $Actual"
        Write-Host "  FAIL: $Label (expected $Expected, got $Actual)"
    }
}

function Assert-Contains {
    param([string]$Needle, [string]$Haystack, [string]$Label)
    if ($Haystack.Contains($Needle)) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        $script:Errors += "FAIL: $Label -- output did not contain '$Needle': $Haystack"
        Write-Host "  FAIL: $Label"
    }
}

function Assert-FileContains {
    param([string]$Path, [string]$Needle, [string]$Label)
    $content = Get-Content -LiteralPath $Path -Raw
    if ($content.Contains($Needle)) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        $script:Errors += "FAIL: $Label -- $Path did not contain '$Needle'"
        Write-Host "  FAIL: $Label"
    }
}

function Write-FixtureRepo {
    param([string]$Repo)
    New-Item -ItemType Directory -Force -Path (Join-Path $Repo 'scripts') | Out-Null
    Copy-Item -LiteralPath $Check -Destination (Join-Path $Repo 'scripts/check_versions.ps1')
    Copy-Item -LiteralPath $Sync -Destination (Join-Path $Repo 'scripts/sync_versions.ps1')

    Write-Fixture (Join-Path $Repo 'VERSION_MAP.yml') @'
suite: 1.11.0
plugin: 2.3.0
plugin-lite: 1.1.0
settings-schema: 1.17.0
hooks: 1.1.1
'@
    Write-Fixture (Join-Path $Repo 'plugin/.claude-plugin/plugin.json') @'
{
  "version": "2.3.0"
}
'@
    Write-Fixture (Join-Path $Repo 'plugin-lite/.claude-plugin/plugin.json') @'
{
  "version": "1.1.0"
}
'@
    Write-Fixture (Join-Path $Repo 'global/settings.json') @'
{
  "version": "1.17.0"
}
'@
    Write-Fixture (Join-Path $Repo 'global/settings.windows.json') @'
{
  "version": "1.17.0"
}
'@
    Write-Fixture (Join-Path $Repo 'bootstrap.sh') @'
GITHUB_REF="${GITHUB_REF:-v1.10.0}"
'@
    Write-Fixture (Join-Path $Repo 'bootstrap.ps1') @'
$GitHubRef = if ($env:GITHUB_REF) { $env:GITHUB_REF }
             elseif ($env:GITHUB_BRANCH) { $env:GITHUB_BRANCH }
             else { 'v1.10.0' }
'@
    Write-Fixture (Join-Path $Repo 'README.md') @'
<img src="https://img.shields.io/badge/version-1.11.0-blue.svg">
GITHUB_REF=v1.10.0 \
| `GITHUB_REF` | latest release tag (e.g. `v1.10.0`) |
'@
    Write-Fixture (Join-Path $Repo 'README.ko.md') @'
<img src="https://img.shields.io/badge/version-1.11.0-blue.svg">
GITHUB_REF=v1.10.0 \
| `GITHUB_REF` | 최신 release tag (예: `v1.10.0`) |
'@
}

try {
    Write-Host "=== check_versions.ps1 tests ==="

    $Repo = Join-Path $Work 'repo'
    Write-FixtureRepo $Repo

    $out = & pwsh -NoProfile -File (Join-Path $Repo 'scripts/check_versions.ps1') 2>&1 | Out-String
    Assert-Exit 2 $LASTEXITCODE 'stale bootstrap and README GITHUB_REF pins fail'
    Assert-Contains 'bootstrap.sh GITHUB_REF=1.10.0, VERSION_MAP[suite]=1.11.0' $out 'bootstrap.sh drift is reported'
    Assert-Contains 'README.md GITHUB_REF pin=1.10.0, VERSION_MAP[suite]=1.11.0' $out 'README.md drift is reported'

    $out = & pwsh -NoProfile -File (Join-Path $Repo 'scripts/sync_versions.ps1') 2>&1 | Out-String
    Assert-Exit 0 $LASTEXITCODE 'sync exits 0'
    $out = & pwsh -NoProfile -File (Join-Path $Repo 'scripts/check_versions.ps1') 2>&1 | Out-String
    Assert-Exit 0 $LASTEXITCODE 'sync restores version drift'
    Assert-FileContains (Join-Path $Repo 'bootstrap.sh') 'GITHUB_REF="${GITHUB_REF:-v1.11.0}"' 'bootstrap.sh pin synced'
    Assert-FileContains (Join-Path $Repo 'bootstrap.ps1') "else { 'v1.11.0' }" 'bootstrap.ps1 pin synced'
    Assert-FileContains (Join-Path $Repo 'README.md') 'GITHUB_REF=v1.11.0 \' 'README.md code pin synced'
    Assert-FileContains (Join-Path $Repo 'README.ko.md') '예: `v1.11.0`' 'README.ko.md table pin synced'
}
finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  $Pass passed, $Fail failed"
if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors:"
    foreach ($err in $Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
