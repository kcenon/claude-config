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

# ── Install commit-msg hook ─────────────────────────────────

Write-Host ""
Write-InfoMessage "commit-msg hook 설치 중..."

$commitMsgDst = Join-Path $GitHooksDir 'commit-msg'

if (Test-Path -LiteralPath $commitMsgDst) {
    Write-WarningMessage "기존 commit-msg hook이 존재합니다."
    $reply = Read-Host "덮어쓰시겠습니까? (y/n)"
    if ($reply -ne 'y' -and $reply -ne 'Y') {
        Write-InfoMessage "commit-msg 설치를 건너뜁니다."
    } else {
        $commitMsgSrc = Join-Path $ScriptDir 'commit-msg'
        Copy-Item -LiteralPath $commitMsgSrc -Destination $commitMsgDst -Force
        if (-not $IsWindows) { & chmod +x $commitMsgDst 2>$null }
        Write-SuccessMessage "commit-msg hook 설치 완료!"
    }
} else {
    $commitMsgSrc = Join-Path $ScriptDir 'commit-msg'
    Copy-Item -LiteralPath $commitMsgSrc -Destination $commitMsgDst -Force
    if (-not $IsWindows) { & chmod +x $commitMsgDst 2>$null }
    Write-SuccessMessage "commit-msg hook 설치 완료!"
}

# ── Install pre-push hook ──────────────────────────────────

Write-Host ""
Write-InfoMessage "pre-push hook 설치 중..."

$prePushDst = Join-Path $GitHooksDir 'pre-push'

if (Test-Path -LiteralPath $prePushDst) {
    Write-WarningMessage "기존 pre-push hook이 존재합니다."
    $reply = Read-Host "덮어쓰시겠습니까? (y/n)"
    if ($reply -ne 'y' -and $reply -ne 'Y') {
        Write-InfoMessage "pre-push 설치를 건너뜁니다."
    } else {
        $prePushSrc = Join-Path $ScriptDir 'pre-push'
        Copy-Item -LiteralPath $prePushSrc -Destination $prePushDst -Force
        if (-not $IsWindows) { & chmod +x $prePushDst 2>$null }
        Write-SuccessMessage "pre-push hook 설치 완료!"
    }
} else {
    $prePushSrc = Join-Path $ScriptDir 'pre-push'
    Copy-Item -LiteralPath $prePushSrc -Destination $prePushDst -Force
    if (-not $IsWindows) { & chmod +x $prePushDst 2>$null }
    Write-SuccessMessage "pre-push hook 설치 완료!"
}

# ── Install shared validation library ───────────────────────

Write-InfoMessage "검증 라이브러리 설치 중..."

$libDstDir = Join-Path $GitHooksDir 'lib'
if (-not (Test-Path -LiteralPath $libDstDir -PathType Container)) {
    New-Item -ItemType Directory -Path $libDstDir -Force | Out-Null
}

$validatorSrc = Join-Path $ScriptDir 'lib' 'validate-commit-message.sh'
$validatorDst = Join-Path $libDstDir 'validate-commit-message.sh'
Copy-Item -LiteralPath $validatorSrc -Destination $validatorDst -Force
if (-not $IsWindows) { & chmod +x $validatorDst 2>$null }
Write-SuccessMessage "검증 라이브러리 설치 완료!"

Write-Host ""
Write-InfoMessage "설치된 hooks:"
Get-ChildItem -LiteralPath $GitHooksDir -File |
    Where-Object { $_.Name -notlike '*.sample' } |
    ForEach-Object {
        Write-Host "  $($_.Name)  ($($_.Length) bytes)"
    }

Write-Host ""
Write-SuccessMessage "Git hooks 설치가 완료되었습니다."
Write-InfoMessage "커밋 시 SKILL.md 검증과 커밋 메시지 검증이 자동으로 실행됩니다."
Write-InfoMessage "push 시 보호 브랜치(main, develop) 직접 push가 차단됩니다."
