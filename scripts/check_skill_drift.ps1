# Verify cross-layer SKILL.md copies match their drift contract.
# Exits with 2 if any watched frontmatter field or body drifts; 0 otherwise.
#
# Usage: pwsh scripts/check_skill_drift.ps1 [repo-root] [skill-drift-contract.yml]

param(
    [string]$RootDir,
    [string]$MapFile
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RootDir) {
    $RootDir = Split-Path -Parent $ScriptDir
}
if (-not $MapFile) {
    $MapFile = Join-Path $RootDir 'skill-drift-contract.yml'
}

if (-not (Test-Path -LiteralPath $MapFile -PathType Leaf)) {
    Write-Error "skill drift contract missing: $MapFile"
    exit 1
}

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

$depCheck = & $python -c 'import yaml' 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Missing Python dependency. Install with: pip install pyyaml`n$depCheck"
    exit 2
}

$Core = Join-Path $ScriptDir 'check_skill_drift.py'
if (Test-Path -LiteralPath $Core -PathType Leaf) {
    & $python $Core $RootDir $MapFile
    exit $LASTEXITCODE
}

Write-Error "check_skill_drift.py not found at $Core"
exit 1
