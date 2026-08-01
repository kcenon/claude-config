# Test suite for scripts/check_skill_drift.ps1.
# Run: pwsh -NoProfile -File tests/scripts/test-check-skill-drift.ps1

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Check = Join-Path $RootDir 'scripts/check_skill_drift.ps1'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-drift-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null

$Pass = 0
$Fail = 0
$Errors = @()

function Find-Python {
    foreach ($candidate in @('python3', 'python', 'py')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Write-Fixture {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-Skill {
    param(
        [string]$Path,
        [string]$AllowedTools,
        [string]$Body
    )

    Write-Fixture $Path @"
---
name: drift-demo
description: Demo skill used by the PowerShell skill drift contract tests.
allowed-tools: $AllowedTools
disable-model-invocation: true
finding_levels: [S1, S2, S3]
---

$Body
"@
}

function Write-Contract {
    param(
        [string]$Path,
        [string]$Extra = ''
    )

    Write-Fixture $Path @"
version: 1
default_watched_fields:
  - name
  - description
  - allowed-tools
  - finding_levels
pairs:
  - id: drift-demo-pair
    source: plugin/skills/drift-demo/SKILL.md
    target: project/.claude/skills/drift-demo/SKILL.md
    body:
      mode: exact
$Extra
"@
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

function New-RepoFixture {
    param([string]$Name)

    $repo = Join-Path $Work $Name
    New-Item -ItemType Directory -Path $repo | Out-Null
    Write-Contract (Join-Path $repo 'skill-drift-contract.yml')
    return $repo
}

$python = Find-Python
if (-not $python) {
    Write-Host 'SKIP: python3/python not in PATH'
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
& $python -c 'import yaml' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'SKIP: missing PyYAML'
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

try {
    Write-Host "=== check_skill_drift.ps1 tests ==="

    $Repo = New-RepoFixture 'matching'
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    Write-Skill (Join-Path $Repo 'project/.claude/skills/drift-demo/SKILL.md') '[Read, Grep, Glob]' "# Drift Demo`n`nShared body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 0 $LASTEXITCODE 'matching watched fields and body pass'

    $Repo = New-RepoFixture 'watched-field-drift'
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    Write-Skill (Join-Path $Repo 'project/.claude/skills/drift-demo/SKILL.md') '[Read, Edit, Glob]' "# Drift Demo`n`nShared body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 2 $LASTEXITCODE 'watched field drift exits 2'

    $Repo = New-RepoFixture 'exception'
    Write-Contract (Join-Path $Repo 'skill-drift-contract.yml') @'
    exceptions:
      - field: allowed-tools
        source: [Read, Grep, Glob]
        target: [Read, Edit, Glob]
        reason: Test fixture intentionally grants Edit in the target layer.
'@
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    Write-Skill (Join-Path $Repo 'project/.claude/skills/drift-demo/SKILL.md') '[Read, Edit, Glob]' "# Drift Demo`n`nShared body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 0 $LASTEXITCODE 'explicit exception permits watched field difference'

    $Repo = New-RepoFixture 'unwatched-exception'
    Write-Contract (Join-Path $Repo 'skill-drift-contract.yml') @'
    exceptions:
      - field: model
        source: null
        target: sonnet
        reason: Test fixture should fail because model is not watched here.
'@
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    Write-Skill (Join-Path $Repo 'project/.claude/skills/drift-demo/SKILL.md') '[Read, Grep, Glob]' "# Drift Demo`n`nShared body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 2 $LASTEXITCODE 'exception for unwatched field exits 2'

    $Repo = New-RepoFixture 'body-drift'
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    Write-Skill (Join-Path $Repo 'project/.claude/skills/drift-demo/SKILL.md') '[Read, Grep, Glob]' "# Drift Demo`n`nChanged body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 2 $LASTEXITCODE 'body drift exits 2'

    $Repo = New-RepoFixture 'missing-pair'
    Write-Skill (Join-Path $Repo 'plugin/skills/drift-demo/SKILL.md') 'Read, Grep, Glob' "# Drift Demo`n`nShared body."
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'skill-drift-contract.yml') *> $null
    Assert-Exit 2 $LASTEXITCODE 'missing paired skill exits 2'
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
