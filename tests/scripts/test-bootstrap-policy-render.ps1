#Requires -Version 7.0
<#
.SYNOPSIS
    Regression test for bootstrap.ps1 rendering commit-settings.md (#984).

.DESCRIPTION
    bootstrap.ps1 deployed the raw global/commit-settings.md for every content
    language policy, so an install under any other policy told Claude the English
    rule. It must deploy global/commit-settings.md.tmpl rendered for the resolved
    policy, as scripts/install.ps1 does.

    The policy is resolved only after the copy loop in Install-GlobalSettings,
    from the environment, from settings.json on a reinstall, or from a prompt. The
    reinstall case below is the one that fails if the render ever moves in front
    of that.

    Runs Install-GlobalSettings from the real tree into a temporary HOME through
    CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=global-install: no clone and no CLI check.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Bootstrap = Join-Path $RootDir 'bootstrap.ps1'
$Verify = Join-Path $RootDir 'scripts' 'verify.ps1'
$Tmpl = Join-Path $RootDir 'global' 'commit-settings.md.tmpl'
$Raw = Join-Path $RootDir 'global' 'commit-settings.md'

Import-Module (Join-Path $RootDir 'scripts' 'lib' 'InstallPrompts.psm1') -Force -DisableNameChecking
. (Join-Path $RootDir 'scripts' 'install-manifest.ps1')

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

function Test-SameBytes {
    param([string]$A, [string]$B)
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    return (Get-FileHash -LiteralPath $A).Hash -eq (Get-FileHash -LiteralPath $B).Hash
}

# Runs the global install. The language variables are unset unless passed, so a
# reinstall resolves its own policy. -Answer feeds the prompts on stdin.
function Invoke-Bootstrap {
    param(
        [Parameter(Mandatory)][string]$HomeDir,
        [string]$ContentLanguage = '',
        [string]$Answer = ''
    )
    $env:HOME = $HomeDir
    $env:USERPROFILE = $HomeDir
    $env:INSTALL_DIR = $RootDir
    $env:FORCE_MODE = '1'
    $env:INSTALL_NPM = 'n'
    $env:CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE = 'global-install'
    $env:BOOTSTRAP_FORCE = $null
    $env:MANIFEST_PATH = $null
    $env:AGENT_LANGUAGE = if ($ContentLanguage) { 'korean' } else { $null }
    $env:CONTENT_LANGUAGE = if ($ContentLanguage) { $ContentLanguage } else { $null }

    $output = $Answer | & pwsh -NoProfile -File $Bootstrap 2>&1 | Out-String
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Get-PromptCount {
    param([string]$Output)
    return ([regex]::Matches($Output, 'Local changes detected')).Count
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "bootstrap-policy-ps1-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

$saved = @{}
foreach ($n in 'HOME', 'USERPROFILE', 'INSTALL_DIR', 'FORCE_MODE', 'INSTALL_NPM', 'CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE',
    'BOOTSTRAP_FORCE', 'MANIFEST_PATH', 'AGENT_LANGUAGE', 'CONTENT_LANGUAGE') {
    $saved[$n] = [System.Environment]::GetEnvironmentVariable($n)
}

try {
    Write-Host '=== Bootstrap commit-settings render test (PowerShell, #984) ==='
    Write-Host ''

    $bilingual = Join-Path $scratch 'expected-bilingual.md'
    Invoke-PolicyTemplate -Source $Tmpl -Destination $bilingual -ContentLanguage 'exclusive_bilingual' -AgentDisplay 'Korean' -AgentLanguage 'korean'

    # The rendered text must differ from the raw file, or the checks below prove
    # nothing.
    Assert-True (-not (Test-SameBytes $bilingual $Raw)) 'the bilingual render differs from the raw file'

    Write-Host ''
    Write-Host '[Fresh install, exclusive_bilingual]'
    $homeA = Join-Path $scratch 'home-a'
    New-Item -ItemType Directory -Path $homeA -Force | Out-Null
    $installedA = Join-Path $homeA '.claude' 'commit-settings.md'
    $manifestA = Join-Path $homeA '.claude' '.install-manifest.json'

    $r = Invoke-Bootstrap -HomeDir $homeA -ContentLanguage 'exclusive_bilingual'
    if ($r.ExitCode -eq 0) {
        Pass 'install exits 0'
    } else {
        Fail 'install exits 0'
        Write-Host ($r.Output -replace '(?m)^', '    ')
    }
    Assert-True (Test-SameBytes $installedA $bilingual) 'commit-settings.md is the render for the policy'
    $text = if (Test-Path -LiteralPath $installedA) { Get-Content -LiteralPath $installedA -Raw } else { '' }
    Assert-True ($text.Contains('English or Korean (document-exclusive) by default')) 'it states the chosen policy'
    Assert-True (-not $text.Contains('tmpl-contract')) 'the tmpl-contract line does not leak'
    Assert-True ((Get-Content -LiteralPath $manifestA -Raw).Contains('"commit-settings.md"')) 'the manifest tracks it'

    # verify.ps1 runs from a directory with no install manifest, or it would also
    # compare a project. Off Windows it compares settings.json with the POSIX
    # profile while bootstrap.ps1 deploys the Windows one, so only the
    # commit-settings.md comparison means anything there.
    Push-Location $scratch
    try {
        $verifyOut = '' | & pwsh -NoProfile -File $Verify 2>&1 | Out-String
        $verifyRc = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($IsWindows) {
        if ($verifyRc -eq 0) {
            Pass 'verify.ps1 reports 0 failures'
        } else {
            Fail 'verify.ps1 reports 0 failures'
            Write-Host (($verifyOut -split "`n" | Where-Object { $_ -match 'DIFF|MISS|FAIL' }) -join "`n")
        }
    } else {
        Assert-True ($verifyOut -notmatch 'DIFF: commit-settings\.md') 'verify.ps1 reports no commit-settings.md DIFF'
    }

    Write-Host ''
    Write-Host '[Reinstall with the language variables unset]'
    $r = Invoke-Bootstrap -HomeDir $homeA
    Assert-True ($r.ExitCode -eq 0) 'reinstall exits 0'
    Assert-True (Test-SameBytes $installedA $bilingual) 'the policy from settings.json still renders'
    Assert-True ($r.Output -notmatch 'Select Language Profile Preset') 'no language prompt'
    Assert-True ((Get-PromptCount $r.Output) -eq 0) 'no local-change prompt'

    Write-Host ''
    Write-Host '[Upgrade from a raw copy an older bootstrap left]'
    Copy-Item -LiteralPath $Raw -Destination $installedA -Force
    $env:MANIFEST_PATH = $manifestA
    Write-ManifestEntry -Key 'commit-settings.md' -Sha (Get-FileSha256 -Path $Raw)
    $env:MANIFEST_PATH = $null
    $r = Invoke-Bootstrap -HomeDir $homeA
    Assert-True ($r.ExitCode -eq 0) 'upgrade exits 0'
    Assert-True (Test-SameBytes $installedA $bilingual) 'the raw copy is replaced by the render'
    Assert-True ((Get-PromptCount $r.Output) -eq 0) 'with no prompt, because it was not edited'

    Write-Host ''
    Write-Host '[Local edit, answering keep]'
    Add-Content -LiteralPath $installedA -Value 'local note'
    $edited = Join-Path $scratch 'edited.md'
    Copy-Item -LiteralPath $installedA -Destination $edited -Force
    $r = Invoke-Bootstrap -HomeDir $homeA -Answer 'k'
    Assert-True ((Get-PromptCount $r.Output) -eq 1) 'exactly one prompt'
    Assert-True ($r.Output.Contains('commit-settings.md')) 'the prompt names commit-settings.md'
    Assert-True (Test-SameBytes $installedA $edited) 'the edit stays'

    Write-Host ''
    Write-Host '[Default policy]'
    $homeB = Join-Path $scratch 'home-b'
    New-Item -ItemType Directory -Path $homeB -Force | Out-Null
    $null = Invoke-Bootstrap -HomeDir $homeB -ContentLanguage 'english'
    Assert-True (Test-SameBytes (Join-Path $homeB '.claude' 'commit-settings.md') $Raw) 'english equals the committed commit-settings.md'
}
finally {
    foreach ($n in $saved.Keys) { [System.Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "=== Results: $($script:PASS) passed, $($script:FAIL) failed ==="

if ($script:FAIL -gt 0) {
    Write-Host ''
    Write-Host 'Errors:'
    foreach ($err in $script:ERRORS) {
        Write-Host "  - $err"
    }
    exit 1
}

exit 0
