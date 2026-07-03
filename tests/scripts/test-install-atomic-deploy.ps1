#Requires -Version 7.0
<#
.SYNOPSIS
    Regression test for scripts/install.ps1 settings/hooks atomic deployment (#813).

.DESCRIPTION
    Runs install.ps1 in global-only mode against an isolated scratch HOME and a
    minimal fixture. The success case proves settings.json is published after
    hook deployment. Failure cases prove an existing settings.json is preserved
    when hook deployment fails.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

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

function New-FakeBin {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $claudeSh = Join-Path $Path 'claude'
    Set-Content -LiteralPath $claudeSh -Value "#!/bin/sh`necho claude test`n" -NoNewline
    if (-not ($IsWindows -or ($env:OS -eq 'Windows_NT'))) {
        & chmod +x $claudeSh
    }

    $claudeCmd = Join-Path $Path 'claude.cmd'
    Set-Content -LiteralPath $claudeCmd -Value "@echo off`r`necho claude test`r`n" -NoNewline
}

function New-Fixture {
    param([Parameter(Mandatory)][string]$Path)

    $scripts = Join-Path $Path 'scripts'
    $scriptLib = Join-Path $scripts 'lib'
    $hooks = Join-Path $Path 'global' 'hooks'
    $hooksLib = Join-Path $hooks 'lib'
    $sharedLib = Join-Path $Path 'hooks' 'lib'
    New-Item -ItemType Directory -Path $scriptLib, $hooksLib, $sharedLib -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $RootDir 'scripts' 'install.ps1') -Destination $scripts -Force
    Copy-Item -LiteralPath (Join-Path $RootDir 'scripts' 'install-manifest.ps1') -Destination $scripts -Force
    Copy-Item -LiteralPath (Join-Path $RootDir 'scripts' 'lib' 'InstallPrompts.psm1') -Destination $scriptLib -Force

    Set-Content -LiteralPath (Join-Path $Path 'global' 'settings.windows.json') -Value @'
{
  "fixture": "powershell"
}
'@ -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'example.ps1') -Value 'exit 0' -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'example.sh') -Value "#!/bin/sh`nexit 0`n" -NoNewline
    Set-Content -LiteralPath (Join-Path $hooks 'known-issues.json') -Value '{}' -NoNewline

    foreach ($name in @('CommonHelpers.psm1', 'LanguageValidator.psm1', 'AttributionValidator.psm1')) {
        Set-Content -LiteralPath (Join-Path $hooksLib $name) -Value '' -NoNewline
    }
    foreach ($name in @('tokenize-shell.sh', 'path-utils.sh', 'timeout-wrapper.sh', 'rotate.sh')) {
        Set-Content -LiteralPath (Join-Path $hooksLib $name) -Value "#!/bin/sh`nreturn 0 2>/dev/null || exit 0`n" -NoNewline
    }
    foreach ($name in @('validate-commit-message.sh', 'validate-language.sh', 'validate-traceability.sh')) {
        Set-Content -LiteralPath (Join-Path $sharedLib $name) -Value "#!/bin/sh`nreturn 0 2>/dev/null || exit 0`n" -NoNewline
    }
}

function Invoke-Install {
    param(
        [Parameter(Mandatory)][string]$HomeDir,
        [Parameter(Mandatory)][string]$Fixture,
        [Parameter(Mandatory)][string]$FakeBin
    )

    $origHome = $env:HOME
    $origUserProfile = $env:USERPROFILE
    $origPath = $env:PATH
    $origAgentLanguage = $env:AGENT_LANGUAGE
    $origContentLanguage = $env:CONTENT_LANGUAGE

    try {
        $env:HOME = $HomeDir
        $env:USERPROFILE = $HomeDir
        $env:PATH = "$FakeBin$([System.IO.Path]::PathSeparator)$origPath"
        $env:AGENT_LANGUAGE = 'english'
        $env:CONTENT_LANGUAGE = 'english'

        $installer = Join-Path $Fixture 'scripts' 'install.ps1'
        $inputs = "1`nn`n"
        $output = $inputs | pwsh -NoProfile -File $installer 2>&1 | Out-String
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
        }
    }
    finally {
        $env:HOME = $origHome
        $env:USERPROFILE = $origUserProfile
        $env:PATH = $origPath
        $env:AGENT_LANGUAGE = $origAgentLanguage
        $env:CONTENT_LANGUAGE = $origContentLanguage
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "install-atomic-ps1-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    Write-Host "=== Clone installer atomic deploy test (PowerShell, #813) ==="
    Write-Host ""

    $fakeBin = Join-Path $scratch 'fake-bin'
    New-FakeBin -Path $fakeBin

    $successFixture = Join-Path $scratch 'success-fixture'
    $successHome = Join-Path $scratch 'success-home'
    New-Fixture -Path $successFixture
    New-Item -ItemType Directory -Path $successHome -Force | Out-Null

    $result = Invoke-Install -HomeDir $successHome -Fixture $successFixture -FakeBin $fakeBin
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
    Assert-True (Test-Path -LiteralPath (Join-Path $successClaude 'hooks' 'lib' 'CommonHelpers.psm1')) `
        'PowerShell hook module deployed'
    Assert-True (Test-Path -LiteralPath (Join-Path $successClaude 'hooks' 'lib' 'validate-traceability.sh')) `
        'shared validator lib deployed'
    $settingsJson = Get-Content -Raw -LiteralPath (Join-Path $successClaude 'settings.json') | ConvertFrom-Json
    Assert-True ($settingsJson.language -eq 'english') 'staged settings receive agent language update'

    $failureFixture = Join-Path $scratch 'failure-fixture'
    $failureHome = Join-Path $scratch 'failure-home'
    New-Fixture -Path $failureFixture
    $failureClaude = Join-Path $failureHome '.claude'
    New-Item -ItemType Directory -Path $failureClaude -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failureClaude 'settings.json') -Value '{"sentinel":"keep"}' -NoNewline
    Set-Content -LiteralPath (Join-Path $failureClaude 'hooks') -Value 'not a directory' -NoNewline

    $result = Invoke-Install -HomeDir $failureHome -Fixture $failureFixture -FakeBin $fakeBin
    if ($result.ExitCode -ne 0) {
        Pass 'failed hook deployment exits non-zero'
    } else {
        Fail 'failed hook deployment exits non-zero'
    }

    Assert-True (Select-String -LiteralPath (Join-Path $failureClaude 'settings.json') -Pattern '"sentinel":"keep"' -Quiet) `
        'existing settings.json preserved when hook deployment fails'
    $temps = @(Get-ChildItem -LiteralPath $failureClaude -Filter '.settings.json.tmp.*' -File -ErrorAction SilentlyContinue)
    Assert-True ($temps.Count -eq 0) 'staged settings temp removed after hook deployment failure'
    Assert-True ($result.Output -match 'settings\.json을 변경하지 않았습니다') `
        'hook deployment failure reports blocked settings publication'

    $missingLibFixture = Join-Path $scratch 'missing-lib-fixture'
    $missingLibHome = Join-Path $scratch 'missing-lib-home'
    New-Fixture -Path $missingLibFixture
    Remove-Item -LiteralPath (Join-Path $missingLibFixture 'global' 'hooks' 'lib' 'tokenize-shell.sh') -Force
    $missingLibClaude = Join-Path $missingLibHome '.claude'
    New-Item -ItemType Directory -Path $missingLibClaude -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $missingLibClaude 'settings.json') -Value '{"sentinel":"missing-lib"}' -NoNewline

    $result = Invoke-Install -HomeDir $missingLibHome -Fixture $missingLibFixture -FakeBin $fakeBin
    if ($result.ExitCode -ne 0) {
        Pass 'missing required runtime lib exits non-zero'
    } else {
        Fail 'missing required runtime lib exits non-zero'
    }

    Assert-True (Select-String -LiteralPath (Join-Path $missingLibClaude 'settings.json') -Pattern '"sentinel":"missing-lib"' -Quiet) `
        'existing settings.json preserved when required runtime lib is missing'
    Assert-True ($result.Output -match 'settings\.json을 변경하지 않았습니다') `
        'missing runtime lib failure reports blocked settings publication'

    $missingModuleFixture = Join-Path $scratch 'missing-module-fixture'
    $missingModuleHome = Join-Path $scratch 'missing-module-home'
    New-Fixture -Path $missingModuleFixture
    Remove-Item -LiteralPath (Join-Path $missingModuleFixture 'global' 'hooks' 'lib' 'CommonHelpers.psm1') -Force
    $missingModuleClaude = Join-Path $missingModuleHome '.claude'
    New-Item -ItemType Directory -Path $missingModuleClaude -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $missingModuleClaude 'settings.json') -Value '{"sentinel":"missing-module"}' -NoNewline

    $result = Invoke-Install -HomeDir $missingModuleHome -Fixture $missingModuleFixture -FakeBin $fakeBin
    if ($result.ExitCode -ne 0) {
        Pass 'missing required PowerShell module exits non-zero'
    } else {
        Fail 'missing required PowerShell module exits non-zero'
    }

    Assert-True (Select-String -LiteralPath (Join-Path $missingModuleClaude 'settings.json') -Pattern '"sentinel":"missing-module"' -Quiet) `
        'existing settings.json preserved when required PowerShell module is missing'
    Assert-True ($result.Output -match 'settings\.json을 변경하지 않았습니다') `
        'missing PowerShell module failure reports blocked settings publication'
}
finally {
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
