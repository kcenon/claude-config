#Requires -Version 7.0
<#
.SYNOPSIS
    Regression test for bootstrap.ps1 settings/hooks atomic deployment (#798).

.DESCRIPTION
    Runs bootstrap.ps1 in an isolated test mode with a fake INSTALL_DIR. The
    success case proves settings.json is published after hook deployment. The
    failure case proves an existing settings.json is preserved when hook
    deployment fails.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Bootstrap = Join-Path $RootDir 'bootstrap.ps1'

$script:PASS = 0
$script:FAIL = 0
$script:ERRORS = @()

function Pass {
    param([string]$Message)
    $script:PASS++
    Write-Host "  PASS: $Message"
}

function Fail {
    param([string]$Message)
    $script:FAIL++
    $script:ERRORS += $Message
    Write-Host "  FAIL: $Message" -ForegroundColor Red
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Pass $Message } else { Fail $Message }
}

function New-Fixture {
    param([Parameter(Mandatory)][string]$Path)

    $hooks = Join-Path $Path 'global' 'hooks'
    $lib = Join-Path $hooks 'lib'
    $sharedLib = Join-Path $Path 'hooks' 'lib'
    $scripts = Join-Path $Path 'scripts'
    New-Item -ItemType Directory -Path $lib -Force | Out-Null
    New-Item -ItemType Directory -Path $sharedLib -Force | Out-Null
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $RootDir 'scripts' 'install-manifest.ps1') -Destination $scripts -Force
    Set-Content -LiteralPath (Join-Path $Path 'global' 'settings.windows.json') -Value @'
{
  "fixture": "powershell"
}
'@ -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'example.ps1') -Value 'exit 0' -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'example.sh') -Value "#!/bin/sh`nexit 0`n" -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'known-issues.json') -Value '{}' -NoNewline
    Set-Content -LiteralPath (Join-Path $lib 'CommonHelpers.psm1') -Value '' -NoNewline
    foreach ($name in @('tokenize-shell.sh', 'path-utils.sh', 'timeout-wrapper.sh', 'rotate.sh')) {
        Set-Content -LiteralPath (Join-Path $lib $name) -Value "#!/bin/sh`nreturn 0 2>/dev/null || exit 0`n" -NoNewline
    }
    foreach ($name in @('validate-commit-message.sh', 'validate-language.sh', 'validate-traceability.sh')) {
        Set-Content -LiteralPath (Join-Path $sharedLib $name) -Value "#!/bin/sh`nreturn 0 2>/dev/null || exit 0`n" -NoNewline
    }
}

function Invoke-AtomicDeploy {
    param(
        [Parameter(Mandatory)][string]$HomeDir,
        [Parameter(Mandatory)][string]$Fixture
    )

    $env:HOME = $HomeDir
    $env:USERPROFILE = $HomeDir
    $env:INSTALL_DIR = $Fixture
    $env:CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE = 'atomic-deploy'
    $env:AGENT_LANGUAGE = 'english'
    $env:CONTENT_LANGUAGE = 'english'

    $output = & pwsh -NoProfile -File $Bootstrap 2>&1 | Out-String
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "bootstrap-atomic-ps1-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

$origHome = $env:HOME
$origUserProfile = $env:USERPROFILE
$origInstallDir = $env:INSTALL_DIR
$origMode = $env:CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE
$origAgentLanguage = $env:AGENT_LANGUAGE
$origContentLanguage = $env:CONTENT_LANGUAGE

try {
    Write-Host "=== Bootstrap atomic deploy test (PowerShell, #798) ==="
    Write-Host ""

    $successFixture = Join-Path $scratch 'success-fixture'
    $successHome = Join-Path $scratch 'success-home'
    New-Fixture -Path $successFixture
    New-Item -ItemType Directory -Path $successHome -Force | Out-Null

    $result = Invoke-AtomicDeploy -HomeDir $successHome -Fixture $successFixture
    if ($result.ExitCode -eq 0) {
        Pass 'successful hook deployment exits 0'
    } else {
        Fail 'successful hook deployment exits 0'
        Write-Host ($result.Output -replace '(?m)^', '    ')
    }

    $successClaude = Join-Path $successHome '.claude'
    Assert-True (Select-String -LiteralPath (Join-Path $successClaude 'settings.json') -Pattern '"fixture": "powershell"' -Quiet) `
        'settings.json published after successful hook deployment'
    Assert-True (Test-Path -LiteralPath (Join-Path $successClaude 'hooks' 'example.ps1')) `
        'PowerShell hook deployed'
    Assert-True (Test-Path -LiteralPath (Join-Path $successClaude 'hooks' 'example.sh')) `
        'bash hook variant deployed'
    Assert-True (Test-Path -LiteralPath (Join-Path $successClaude 'hooks' 'lib' 'tokenize-shell.sh')) `
        'hook lib deployed'

    $failureFixture = Join-Path $scratch 'failure-fixture'
    $failureHome = Join-Path $scratch 'failure-home'
    New-Fixture -Path $failureFixture
    $failureClaude = Join-Path $failureHome '.claude'
    New-Item -ItemType Directory -Path $failureClaude -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failureClaude 'settings.json') -Value '{"sentinel":"keep"}' -NoNewline
    Set-Content -LiteralPath (Join-Path $failureClaude 'hooks') -Value 'not a directory' -NoNewline

    $result = Invoke-AtomicDeploy -HomeDir $failureHome -Fixture $failureFixture
    if ($result.ExitCode -ne 0) {
        Pass 'failed hook deployment exits non-zero'
    } else {
        Fail 'failed hook deployment exits non-zero'
    }

    Assert-True (Select-String -LiteralPath (Join-Path $failureClaude 'settings.json') -Pattern '"sentinel":"keep"' -Quiet) `
        'existing settings.json preserved when hook deployment fails'
    $temps = @(Get-ChildItem -LiteralPath $failureClaude -Filter '.settings.json.tmp.*' -File -ErrorAction SilentlyContinue)
    Assert-True ($temps.Count -eq 0) 'staged settings temp removed after hook deployment failure'

    $missingLibFixture = Join-Path $scratch 'missing-lib-fixture'
    $missingLibHome = Join-Path $scratch 'missing-lib-home'
    New-Fixture -Path $missingLibFixture
    Remove-Item -LiteralPath (Join-Path $missingLibFixture 'global' 'hooks' 'lib' 'tokenize-shell.sh') -Force
    $missingLibClaude = Join-Path $missingLibHome '.claude'
    New-Item -ItemType Directory -Path $missingLibClaude -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $missingLibClaude 'settings.json') -Value '{"sentinel":"missing-lib"}' -NoNewline

    $result = Invoke-AtomicDeploy -HomeDir $missingLibHome -Fixture $missingLibFixture
    if ($result.ExitCode -ne 0) {
        Pass 'missing required runtime lib exits non-zero'
    } else {
        Fail 'missing required runtime lib exits non-zero'
    }

    Assert-True (Select-String -LiteralPath (Join-Path $missingLibClaude 'settings.json') -Pattern '"sentinel":"missing-lib"' -Quiet) `
        'existing settings.json preserved when required runtime lib is missing'
    Assert-True ($result.Output -match 'settings\.json을 변경하지 않았습니다') `
        'missing runtime lib failure reports blocked settings publication'
}
finally {
    $env:HOME = $origHome
    $env:USERPROFILE = $origUserProfile
    $env:INSTALL_DIR = $origInstallDir
    $env:CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE = $origMode
    $env:AGENT_LANGUAGE = $origAgentLanguage
    $env:CONTENT_LANGUAGE = $origContentLanguage
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Results: $($script:PASS) passed, $($script:FAIL) failed ==="

if ($script:FAIL -gt 0) {
    Write-Host ""
    Write-Host "Errors:"
    foreach ($err in $script:ERRORS) {
        Write-Host "  - $err"
    }
    exit 1
}

exit 0
