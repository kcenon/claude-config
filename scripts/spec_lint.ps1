#Requires -Version 7.0

<#
.SYNOPSIS
    Validate Claude Code SKILL.md, plugin.json, and settings.json against canonical 2026 schemas.

.DESCRIPTION
    PowerShell twin of spec_lint.sh. Discovers known files in the repo and dispatches each
    group to spec_lint.py for schema validation.

.PARAMETER WarnOnly
    Print violations but exit 0 (advisory mode for soft rollouts).

.PARAMETER Strict
    Exit with code 2 (instead of 1) on violations. Lets CI distinguish strict-mode
    failures from regular violations.

.PARAMETER Quiet
    Print only violations and the final summary line.

.PARAMETER Mode
    Explicit mode: skill, plugin, or settings. When set, the remaining positional
    arguments are treated as file paths to lint.

.PARAMETER Files
    Files to lint when -Mode is supplied. Ignored otherwise.

.EXAMPLE
    .\scripts\spec_lint.ps1
    Lints every known SKILL.md / plugin.json / settings.json file in the repo.

.EXAMPLE
    .\scripts\spec_lint.ps1 -WarnOnly
    Reports violations without failing.

.EXAMPLE
    .\scripts\spec_lint.ps1 -Mode skill global\skills\release\SKILL.md
    Lints a single SKILL.md file.
#>

[CmdletBinding()]
param(
    [switch]$WarnOnly,
    [switch]$Strict,
    [switch]$Quiet,
    [ValidateSet('skill', 'plugin', 'settings')]
    [string]$Mode,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir   = $PSScriptRoot
$RootDir     = Split-Path -Parent $ScriptDir
$SpecLintPy  = Join-Path $ScriptDir 'spec_lint.py'

# ── Locate Python interpreter ────────────────────────────────

function Find-Python {
    foreach ($candidate in @('python3', 'python', 'py')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

$python = Find-Python
if (-not $python) {
    Write-Error 'python3 (or python) not found in PATH'
    exit 2
}

# Verify Python deps
$depCheck = & $python -c "import yaml, jsonschema" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Missing Python dependencies. Install with: pip install pyyaml jsonschema`n$depCheck"
    exit 2
}

if (-not (Test-Path -LiteralPath $SpecLintPy)) {
    Write-Error "spec_lint.py not found at $SpecLintPy"
    exit 2
}

# ── Build common Python args ─────────────────────────────────

$commonArgs = @()
if ($WarnOnly) { $commonArgs += '--warn-only' }
if ($Strict)   { $commonArgs += '--strict' }
if ($Quiet)    { $commonArgs += '--quiet' }

# ── Explicit mode (caller supplied files) ────────────────────

if ($Mode) {
    if (-not $Files -or $Files.Count -eq 0) {
        Write-Error '-Mode requires at least one file path'
        exit 2
    }
    & $python $SpecLintPy '--mode' $Mode @commonArgs @Files
    exit $LASTEXITCODE
}

# ── Default mode: discover and lint all known files ──────────

$overallRc = 0

function Invoke-LintGroup {
    param(
        [string]$ModeName,
        [string[]]$Paths
    )
    if (-not $Paths -or $Paths.Count -eq 0) { return 0 }
    Write-Host "[spec_lint] mode=$ModeName files=$($Paths.Count)"
    & $python $SpecLintPy '--mode' $ModeName @script:commonArgs @Paths
    return $LASTEXITCODE
}

# Make commonArgs visible to helper
$script:commonArgs = $commonArgs

# 1. SKILL.md frontmatter
$skillDirs = @(
    (Join-Path $RootDir 'project' '.claude' 'skills'),
    (Join-Path $RootDir 'plugin' 'skills'),
    (Join-Path $RootDir 'plugin-lite' 'skills'),
    (Join-Path $RootDir 'global' 'skills')
)
$skillFiles = @()
foreach ($dir in $skillDirs) {
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $skillFiles += Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'SKILL.md' `
            -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }
}
if ($skillFiles.Count -gt 0) {
    if ((Invoke-LintGroup 'skill' $skillFiles) -ne 0) { $overallRc = 1 }
}

# 2. plugin.json
$pluginCandidates = @(
    (Join-Path $RootDir 'plugin'      '.claude-plugin' 'plugin.json'),
    (Join-Path $RootDir 'plugin-lite' '.claude-plugin' 'plugin.json')
)
$pluginFiles = $pluginCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
if ($pluginFiles.Count -gt 0) {
    if ((Invoke-LintGroup 'plugin' $pluginFiles) -ne 0) { $overallRc = 1 }
}

# 3. settings.json
$settingsCandidates = @(
    (Join-Path $RootDir 'global'  'settings.json'),
    (Join-Path $RootDir 'global'  'settings.windows.json'),
    (Join-Path $RootDir 'project' '.claude' 'settings.json')
)
$settingsFiles = $settingsCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
if ($settingsFiles.Count -gt 0) {
    if ((Invoke-LintGroup 'settings' $settingsFiles) -ne 0) { $overallRc = 1 }
}

exit $overallRc
