#Requires -Version 7.0

# Claude Configuration Bootstrap Script
# ======================================
# 원라인 설치 스크립트 - GitHub에서 직접 실행 가능
#
# 사용법:
#   irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
#
# 또는 (직접 실행):
#   pwsh -File bootstrap.ps1
# Ported from bootstrap.sh

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# GitHub repository settings
$GitHubUser   = if ($env:GITHUB_USER)   { $env:GITHUB_USER }   else { 'kcenon' }
$GitHubRepo   = if ($env:GITHUB_REPO)   { $env:GITHUB_REPO }   else { 'claude-config' }
$GitHubBranch = if ($env:GITHUB_BRANCH) { $env:GITHUB_BRANCH } else { 'main' }

# Installation directory
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $HOME 'claude_config_backup' }
$ClaudeDir  = Join-Path $HOME '.claude'

# ── Inline helpers (module not yet available during bootstrap) ─

function Write-Info    { param([string]$M) Write-Host "  $M" -ForegroundColor Cyan }
function Write-Ok      { param([string]$M) Write-Host "  $M" -ForegroundColor Green }
function Write-Warn    { param([string]$M) Write-Host "  $M" -ForegroundColor Yellow }
function Write-Fail    { param([string]$M) Write-Host "  $M" -ForegroundColor Red; exit 1 }

# ── Banner ───────────────────────────────────────────────────

Write-Host ""
Write-Host "`u{2554}$('=' * 63)`u{2557}" -ForegroundColor Cyan
Write-Host "`u{2551}                                                               `u{2551}" -ForegroundColor Cyan
Write-Host "`u{2551}       Claude Configuration Bootstrap Installer               `u{2551}" -ForegroundColor Cyan
Write-Host "`u{2551}                                                               `u{2551}" -ForegroundColor Cyan
Write-Host "`u{255A}$('=' * 63)`u{255D}" -ForegroundColor Cyan
Write-Host ""

# ── Dependency check ─────────────────────────────────────────

function Test-Dependencies {
    Write-Info "의존성 확인 중..."

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Fail "git이 설치되어 있지 않습니다. 먼저 git을 설치하세요."
    }

    Write-Ok "의존성 확인 완료"
}

# ── Clone repository ─────────────────────────────────────────

function Invoke-CloneRepository {
    Write-Info "저장소 클론 중..."

    if (Test-Path -LiteralPath $InstallDir -PathType Container) {
        Write-Warn "기존 설치 디렉토리가 존재합니다: $InstallDir"
        $overwrite = Read-Host "덮어쓰시겠습니까? (y/n) [기본값: n]"
        if ([string]::IsNullOrEmpty($overwrite)) { $overwrite = 'n' }

        if ($overwrite -eq 'y') {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
        }
        else {
            Write-Info "기존 디렉토리를 사용합니다. git pull 실행..."
            Push-Location $InstallDir
            try {
                & git pull origin $GitHubBranch
            }
            finally {
                Pop-Location
            }
            return
        }
    }

    & git clone "https://github.com/$GitHubUser/$GitHubRepo.git" $InstallDir
    Write-Ok "저장소 클론 완료: $InstallDir"
}

# ── Install global settings ──────────────────────────────────

function Install-GlobalSettings {
    Write-Info "글로벌 설정 설치 중..."

    # Create ~/.claude directory
    if (-not (Test-Path $ClaudeDir)) {
        New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    }

    # Load install-manifest helper (SHA-256-based preservation of local edits)
    $manifestHelper = Join-Path $InstallDir 'scripts' 'install-manifest.ps1'
    if (Test-Path -LiteralPath $manifestHelper) {
        . $manifestHelper
    }

    # Copy files (manifest-guarded: local edits preserved by default)
    $globalFiles = @('CLAUDE.md', 'commit-settings.md', 'conversation-language.md', 'git-identity.md', 'token-management.md')
    foreach ($gf in $globalFiles) {
        $src  = Join-Path $InstallDir 'global' $gf
        $dest = Join-Path $ClaudeDir $gf
        if (-not (Test-Path -LiteralPath $src)) { continue }

        if (Get-Command Invoke-GuardedCopy -ErrorAction SilentlyContinue) {
            if (Invoke-GuardedCopy -Src $src -Dest $dest -Key $gf) {
                Write-Ok "$gf 설치됨"
            }
            else {
                Write-Info "$gf 로컬 변경 유지"
            }
        }
        else {
            Copy-Item -LiteralPath $src -Destination $ClaudeDir -Force
            Write-Ok "$gf 설치됨"
        }
    }

    # tmux config installation
    $tmuxConf = Join-Path $InstallDir 'global' 'tmux.conf'
    if (Test-Path -LiteralPath $tmuxConf) {
        $homeTmux = Join-Path $HOME '.tmux.conf'
        Copy-Item -LiteralPath $tmuxConf -Destination $homeTmux -Force
        $tmuxLogDir = Join-Path $HOME '.local' 'tmux_logs'
        if (-not (Test-Path $tmuxLogDir)) {
            New-Item -ItemType Directory -Path $tmuxLogDir -Force | Out-Null
        }
        Write-Ok "tmux 설정 설치 완료"
    }

    # ccstatusline settings
    $ccstatuslineSrc = Join-Path $InstallDir 'global' 'ccstatusline'
    if (Test-Path -LiteralPath $ccstatuslineSrc -PathType Container) {
        $ccstatuslineDst = Join-Path $HOME '.config' 'ccstatusline'
        if (-not (Test-Path $ccstatuslineDst)) {
            New-Item -ItemType Directory -Path $ccstatuslineDst -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $ccstatuslineSrc 'settings.json') -Destination $ccstatuslineDst -Force
        Write-Ok "ccstatusline 설정 설치 완료"
    }

    # npm package installation (statusline dependencies)
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $installNpm = Read-Host "Statusline npm 패키지를 설치하시겠습니까? (y/n) [기본값: y]"
        if ([string]::IsNullOrEmpty($installNpm)) { $installNpm = 'y' }
        if ($installNpm -eq 'y') {
            try {
                $null = & npm install -g ccstatusline claude-limitline 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Ok "npm 패키지 설치 완료 (ccstatusline, claude-limitline)"
                }
                else {
                    Write-Warn "npm 패키지 설치 실패. 수동 설치: npm install -g ccstatusline claude-limitline"
                }
            }
            catch {
                Write-Warn "npm 패키지 설치 실패. 수동 설치: npm install -g ccstatusline claude-limitline"
            }
        }
    }
    else {
        Write-Warn "npm 미설치. Statusline 의존성: npm install -g ccstatusline claude-limitline"
    }

    Write-Ok "글로벌 설정 설치 완료"
}

# ── Git identity personalization ─────────────────────────────

function Invoke-PersonalizeGitIdentity {
    Write-Host ""
    Write-Warn "중요: Git Identity를 개인 정보로 수정해야 합니다!"
    Write-Host ""
    Write-Host "  현재 설정:"
    $gitIdFile = Join-Path $ClaudeDir 'git-identity.md'
    if (Test-Path $gitIdFile) {
        Get-Content $gitIdFile | Where-Object { $_ -match '^(name|email):' } | ForEach-Object {
            Write-Host "    $_"
        }
    }
    Write-Host ""
    Write-Host "  수정 방법:"
    if ($IsWindows) {
        Write-Host "    notepad `$HOME\.claude\git-identity.md"
    }
    else {
        Write-Host "    vi ~/.claude/git-identity.md"
    }
    Write-Host ""

    $editNow = Read-Host "지금 수정하시겠습니까? (y/n) [기본값: n]"
    if ([string]::IsNullOrEmpty($editNow)) { $editNow = 'n' }

    if ($editNow -eq 'y') {
        $editor = $env:EDITOR
        if ([string]::IsNullOrEmpty($editor)) {
            if ($IsWindows) { $editor = 'notepad' } else { $editor = 'vi' }
        }
        & $editor $gitIdFile
        Write-Ok "Git identity 수정 완료"
    }
}

# ── Install type selection ───────────────────────────────────

function Select-InstallType {
    Write-Host ""
    Write-Info "설치 타입을 선택하세요:"
    Write-Host "  1) 글로벌 설정만 설치 (~/.claude/)"
    Write-Host "  2) 프로젝트 설정만 설치 (현재 디렉토리)"
    Write-Host "  3) 둘 다 설치 (권장)"
    Write-Host "  4) 저장소만 클론 (수동 설치)"
    Write-Host ""
    $selection = Read-Host "선택 (1-4) [기본값: 1]"
    if ([string]::IsNullOrEmpty($selection)) { $selection = '1' }
    return $selection
}

# ── Install project settings ─────────────────────────────────

function Install-ProjectSettings {
    Write-Host ""
    $defaultDir = (Get-Location).Path
    $projDir = Read-Host "프로젝트 디렉토리 경로 [기본값: $defaultDir]"
    if ([string]::IsNullOrEmpty($projDir)) { $projDir = $defaultDir }

    if (-not (Test-Path -LiteralPath $projDir -PathType Container)) {
        Write-Fail "디렉토리가 존재하지 않습니다: $projDir"
    }

    Write-Info "프로젝트 설정 설치 중: $projDir"

    # Copy files
    Copy-Item -Path (Join-Path $InstallDir 'project' 'CLAUDE.md') -Destination $projDir -Force

    # .claude directory
    $projClaudeDir = Join-Path $projDir '.claude'
    if (-not (Test-Path $projClaudeDir)) {
        New-Item -ItemType Directory -Path $projClaudeDir -Force | Out-Null
    }

    $rulesDir = Join-Path $InstallDir 'project' '.claude' 'rules'
    if (Test-Path $rulesDir) {
        Copy-Item -Path $rulesDir -Destination $projClaudeDir -Recurse -Force
    }

    $skillsDir = Join-Path $InstallDir 'project' '.claude' 'skills'
    if (Test-Path $skillsDir) {
        Copy-Item -Path $skillsDir -Destination $projClaudeDir -Recurse -Force
    }

    $commandsDir = Join-Path $InstallDir 'project' '.claude' 'commands'
    if (Test-Path $commandsDir) {
        Copy-Item -Path $commandsDir -Destination $projClaudeDir -Recurse -Force
    }

    $agentsDir = Join-Path $InstallDir 'project' '.claude' 'agents'
    if (Test-Path $agentsDir) {
        Copy-Item -Path $agentsDir -Destination $projClaudeDir -Recurse -Force
    }

    $settingsJson = Join-Path $InstallDir 'project' '.claude' 'settings.json'
    if (Test-Path $settingsJson) {
        Copy-Item -Path $settingsJson -Destination $projClaudeDir -Force
    }

    $claudeIgnore = Join-Path $InstallDir 'project' '.claudeignore'
    if (Test-Path $claudeIgnore) {
        Copy-Item -Path $claudeIgnore -Destination $projDir -Force
    }

    Write-Ok "프로젝트 설정 설치 완료"

    # Store for summary
    $script:ProjectDir = $projDir
}

# ── Main ─────────────────────────────────────────────────────

function Invoke-Main {
    Test-Dependencies
    Invoke-CloneRepository

    $installType = Select-InstallType

    switch ($installType) {
        '1' {
            Install-GlobalSettings
            Invoke-PersonalizeGitIdentity
        }
        '2' {
            Install-ProjectSettings
        }
        '3' {
            Install-GlobalSettings
            Install-ProjectSettings
            Invoke-PersonalizeGitIdentity
        }
        '4' {
            Write-Info "저장소가 클론되었습니다: $InstallDir"
            Write-Info "수동으로 ./scripts/install.sh를 실행하세요."
        }
        default {
            Write-Fail "잘못된 선택입니다."
        }
    }

    Write-Host ""
    Write-Host "======================================================"
    Write-Ok "설치 완료!"
    Write-Host "======================================================"
    Write-Host ""

    Write-Info "설치된 위치:"
    Write-Host "  백업 저장소: $InstallDir"
    if ($installType -eq '1' -or $installType -eq '3') {
        Write-Host "  글로벌 설정: $ClaudeDir"
    }
    if ($installType -eq '2' -or $installType -eq '3') {
        $pd = if ($script:ProjectDir) { $script:ProjectDir } else { '(specified directory)' }
        Write-Host "  프로젝트 설정: $pd"
    }

    Write-Host ""
    Write-Info "다음 단계:"
    Write-Host "  1. Claude Code 재시작"
    if ($IsWindows) {
        Write-Host "  2. 설정 확인: Get-Content `$HOME\.claude\CLAUDE.md"
    }
    else {
        Write-Host "  2. 설정 확인: cat ~/.claude/CLAUDE.md"
    }
    Write-Host "  3. Statusline 패키지: npm install -g ccstatusline claude-limitline"
    Write-Host "  4. 동기화: cd $InstallDir && ./scripts/sync.sh"
    Write-Host ""

    Write-Ok "Happy Coding with Claude!"
}

# Execute
Invoke-Main
