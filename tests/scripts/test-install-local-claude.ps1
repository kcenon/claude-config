#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression test for the CLAUDE.local.md question of scripts/install.ps1 (#1064).

.DESCRIPTION
    Runs install.ps1 in project-only mode against an isolated scratch HOME and
    a scratch project. A first install creates CLAUDE.local.md from the
    template; a reinstall over the manifest of that install does not put a
    removed file back; CREATE_LOCAL answers the question either way.
#>

$ErrorActionPreference = 'Stop'

$RootDir   = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Installer = Join-Path $RootDir 'scripts' 'install.ps1'

$script:PASS = 0
$script:FAIL = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:PASS++
        Write-Host "  PASS: $Message"
    } else {
        $script:FAIL++
        Write-Host "  FAIL: $Message" -ForegroundColor Red
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "install-local-claude-$([guid]::NewGuid())"
$project = Join-Path $scratch 'project'
New-Item -ItemType Directory -Path $project -Force | Out-Null
$localFile = Join-Path $project 'CLAUDE.local.md'

# The child pwsh takes $HOME from these at start, so they are set here.
$saved = @{}
foreach ($name in @('USERPROFILE', 'HOME', 'PATH', 'AGENT_LANGUAGE', 'CONTENT_LANGUAGE', 'CREATE_LOCAL')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}

# A stand-in claude on PATH: without one the installer first asks whether to
# install the CLI, and that question would take the install type below.
$fakeBin = Join-Path $scratch 'bin'
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
if ($IsWindows) {
    @('@echo off', 'echo 0.0.0-test (Claude Code)', 'exit /b 0') |
        Set-Content -LiteralPath (Join-Path $fakeBin 'claude.cmd')
} else {
    "#!/bin/sh`necho '0.0.0-test (Claude Code)'`n" |
        Set-Content -LiteralPath (Join-Path $fakeBin 'claude') -NoNewline
    & chmod +x (Join-Path $fakeBin 'claude')
}

function Invoke-ProjectInstall {
    # Answers: "2" = project only, then the project directory. The remaining
    # questions, the CLAUDE.local.md one among them, read end of file.
    param([string]$CreateLocal)
    if ($CreateLocal) { $env:CREATE_LOCAL = $CreateLocal } else { Remove-Item Env:CREATE_LOCAL -ErrorAction SilentlyContinue }
    $out = "2`n$project`n" | pwsh -NoProfile -File $Installer 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $out }
    return $LASTEXITCODE
}

try {
    $env:USERPROFILE = $scratch
    $env:HOME = $scratch
    $env:PATH = "$fakeBin$([System.IO.Path]::PathSeparator)$($saved['PATH'])"
    $env:AGENT_LANGUAGE = 'english'
    $env:CONTENT_LANGUAGE = 'english'

    Assert-True ((Invoke-ProjectInstall) -eq 0) 'first project install exits 0'
    Assert-True (Test-Path -LiteralPath (Join-Path $project '.claude' '.install-manifest.json')) 'the install wrote a project manifest'
    Assert-True (Test-Path -LiteralPath $localFile) 'first install creates CLAUDE.local.md'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scratch '.claude' 'settings.json'))) 'a project-only install leaves the scratch HOME alone'

    Remove-Item -LiteralPath $localFile -Force
    Assert-True ((Invoke-ProjectInstall) -eq 0) 'reinstall exits 0'
    Assert-True (-not (Test-Path -LiteralPath $localFile)) 'reinstall leaves a removed CLAUDE.local.md removed'

    Assert-True ((Invoke-ProjectInstall -CreateLocal 'y') -eq 0) 'reinstall with CREATE_LOCAL=y exits 0'
    Assert-True (Test-Path -LiteralPath $localFile) 'CREATE_LOCAL=y creates it on a reinstall'

    $fresh = Join-Path $scratch 'project-declined'
    New-Item -ItemType Directory -Path $fresh -Force | Out-Null
    $project = $fresh
    Assert-True ((Invoke-ProjectInstall -CreateLocal 'n') -eq 0) 'first install with CREATE_LOCAL=n exits 0'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fresh 'CLAUDE.local.md'))) 'CREATE_LOCAL=n skips it on a first install'
}
finally {
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name])
    }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "=== Results: $($script:PASS) passed, $($script:FAIL) failed ==="
if ($script:FAIL -gt 0) { exit 1 }
exit 0
