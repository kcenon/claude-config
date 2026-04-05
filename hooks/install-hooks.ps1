#Requires -Version 7.0

# Git Hooks Installation Script
# =============================
# Git hooks를 설치하는 스크립트
# Ported from install-hooks.sh

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Import shared module
$ModulePath = Join-Path (Split-Path $PSScriptRoot) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
if (-not (Test-Path $ModulePath)) {
    $ModulePath = Join-Path $PSScriptRoot '..' 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
}
Import-Module $ModulePath -Force

# Script and repo root directories
$ScriptDir = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $ScriptDir
$GitHooksDir = Join-Path $RepoRoot '.git' 'hooks'

Write-Banner -Title 'Git Hooks Installation Script'

# ── Verify git repository ────────────────────────────────────

$gitDir = Join-Path $RepoRoot '.git'
if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
    Write-ErrorMessage "Git 저장소가 아닙니다."
    exit 1
}

# ── Ensure hooks directory ───────────────────────────────────

if (-not (Test-Path -LiteralPath $GitHooksDir -PathType Container)) {
    New-Item -ItemType Directory -Path $GitHooksDir -Force | Out-Null
    Write-SuccessMessage "Git hooks 디렉토리 생성: $GitHooksDir"
}

# ── Install pre-commit hook ──────────────────────────────────

Write-InfoMessage "pre-commit hook 설치 중..."

$preCommitDst = Join-Path $GitHooksDir 'pre-commit'

if (Test-Path -LiteralPath $preCommitDst) {
    Write-WarningMessage "기존 pre-commit hook이 존재합니다."
    $reply = Read-Host "덮어쓰시겠습니까? (y/n)"
    if ($reply -ne 'y' -and $reply -ne 'Y') {
        Write-InfoMessage "설치를 건너뜁니다."
        exit 0
    }
}

$preCommitSrc = Join-Path $ScriptDir 'pre-commit'
Copy-Item -LiteralPath $preCommitSrc -Destination $preCommitDst -Force

# On Unix, set the execute bit (no-op on Windows)
if (-not $IsWindows) {
    & chmod +x $preCommitDst 2>$null
}

Write-SuccessMessage "pre-commit hook 설치 완료!"

Write-Host ""
Write-InfoMessage "설치된 hooks:"
Get-ChildItem -LiteralPath $GitHooksDir -File |
    Where-Object { $_.Name -notlike '*.sample' } |
    ForEach-Object {
        Write-Host "  $($_.Name)  ($($_.Length) bytes)"
    }

Write-Host ""
Write-SuccessMessage "Git hooks 설치가 완료되었습니다."
Write-InfoMessage "SKILL.md 파일을 커밋할 때 자동으로 검증이 실행됩니다."
