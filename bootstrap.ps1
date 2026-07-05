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

# Pin install source to a release tag for SLSA-aligned supply-chain hardening
# (#620). Floating refs (e.g. 'main') ship whatever HEAD is at install time,
# leaving no integrity baseline. GITHUB_BRANCH remains a one-release deprecation
# alias for the new GITHUB_REF variable.
if ($env:GITHUB_BRANCH) {
    Write-Warning "GITHUB_BRANCH is deprecated, use GITHUB_REF"
}
$GitHubRef = if ($env:GITHUB_REF) { $env:GITHUB_REF }
             elseif ($env:GITHUB_BRANCH) { $env:GITHUB_BRANCH }
             else { 'v1.11.0' }

# Anthropic Claude Code installer pin (#620 — supply-chain parity with bash).
# The Anthropic-hosted PowerShell installer is pinned by sha256 to prevent
# MITM substitution. Rotation policy mirrors docs/SUPPLY_CHAIN.md.
$AnthropicInstallerUrl    = if ($env:ANTHROPIC_INSTALLER_URL) { $env:ANTHROPIC_INSTALLER_URL } else { 'https://claude.ai/install.ps1' }
$AnthropicInstallerSha256 = if ($env:ANTHROPIC_INSTALLER_SHA256) { $env:ANTHROPIC_INSTALLER_SHA256 } else { 'acc15c3d844b8952e702a24b584d2fdc0b589ee1061c11202529cdd5702711df' }  # pinned 2026-05-09

# Installation directory
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $HOME 'claude_config_backup' }
$ClaudeDir  = Join-Path $HOME '.claude'

# ── Non-interactive prompt helper (issue #778) ───────────────────────────────
# Parity with bootstrap.sh: resolve a prompt value by honoring, in order,
#   1. a pre-set env override of the same name (install.sh vocabulary:
#      INSTALL_TYPE / PROJECT_DIR / INSTALL_NPM / OVERWRITE / ...),
#   2. $env:FORCE_MODE = '1' (unattended) -> the default with no prompt,
#   3. an interactive Read-Host.
# PowerShell's Read-Host reads the host console directly, so the bash /dev/tty
# concern does not apply; env overrides are the unattended path for `irm | iex`.
function Read-BootstrapValue {
    param(
        [Parameter(Mandatory)][string]$EnvName,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )
    $preset = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrEmpty($preset)) { return $preset }
    if ($env:FORCE_MODE -eq '1') { return $Default }
    $reply = Read-Host $Prompt
    if ([string]::IsNullOrEmpty($reply)) { return $Default }
    return $reply
}
# ─────────────────────────────────────────────────────────────────────────────

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

    # Hard requirements: parity with bootstrap.sh (git + gh). gh backs the
    # PreToolUse merge/attribution guards and the batch issue/pr scripts, so a
    # missing gh is a silent-failure trap on Windows just as on Unix (#781).
    $missing = @()
    foreach ($cmd in @('git', 'gh')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missing += $cmd
        }
    }
    if ($missing.Count -gt 0) {
        Write-Fail "필수 도구가 설치되어 있지 않습니다: $($missing -join ', '). 설치 안내는 PREREQUISITES.md를 참고하세요."
    }

    # Soft requirements: jq / perl are used by bash-channel tooling. The native
    # PowerShell hooks do not shell out to them, so warn rather than hard-fail
    # (verifier-refined in #781).
    foreach ($cmd in @('jq', 'perl')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Warn "$cmd 미설치 — 일부 bash 계열 도구가 제한될 수 있습니다 (PREREQUISITES.md)."
        }
    }

    Write-Ok "의존성 확인 완료"
}

# ── Ensure Claude Code CLI is installed ──────────────────────
# version-check.ps1, batch-issue-work.ps1 등이 `claude --version` / `claude`
# 명령을 호출하므로 미설치 시 silent failure가 발생한다. 본 함수는 부트스트랩
# 시점에 사용자 동의 하에 Anthropic 공식 native installer로 Claude Code CLI를
# 설치한다.
# 참고: https://code.claude.com/docs/en/setup
function Confirm-ClaudeCli {
    Write-Info "Claude Code CLI 확인 중..."

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        try {
            $ccVersion = (& claude --version 2>$null | Select-Object -First 1)
        }
        catch {
            $ccVersion = $null
        }
        if ([string]::IsNullOrWhiteSpace($ccVersion)) { $ccVersion = 'version unknown' }
        Write-Ok "Claude Code CLI 이미 설치됨: $ccVersion"
        return
    }

    Write-Warn "Claude Code CLI가 설치되어 있지 않습니다."
    Write-Host "  Claude Code CLI는 hooks(version-check), batch scripts(issue-work, pr-work) 등이"
    Write-Host "  의존하는 핵심 도구입니다. 미설치 상태에서는 일부 기능이 동작하지 않습니다."
    Write-Host ""

    $installClaude = Read-BootstrapValue -EnvName 'INSTALL_CLAUDE' -Prompt "Claude Code CLI를 지금 설치하시겠습니까? (y/n) [기본값: y]" -Default 'y'

    if ($installClaude -ne 'y') {
        Write-Warn "Claude Code CLI 설치 건너뜀. 추후 수동 설치:"
        Write-Host "    irm https://claude.ai/install.ps1 | iex"
        return
    }

    # Native installer는 Anthropic 공식 권장 방식이며 백그라운드 자동 업데이트를 지원한다.
    # 설치 경로: $env:USERPROFILE\.local\bin\claude.exe (Windows) /
    #           ~/.local/bin/claude (macOS, Linux, WSL)
    #
    # Supply-chain hardening (#620): delegates to InstallerFetch.psm1 which
    # mirrors hooks/lib/installer-fetch.sh. The chained 'irm | iex' pattern is
    # gone — the script is fetched, sha256-verified, then executed.
    $modulePath = Join-Path $InstallDir 'hooks' 'lib' 'InstallerFetch.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-Warn "InstallerFetch.psm1 missing at $modulePath — refusing unverified install"
        return
    }
    Import-Module $modulePath -Force -DisableNameChecking
    Write-Info "Native installer 실행 중: $AnthropicInstallerUrl"
    $rc = Invoke-InstallerFetchVerifyRun `
        -Url $AnthropicInstallerUrl `
        -ExpectedSha256 $AnthropicInstallerSha256 `
        -Label 'claude-installer'
    if ($rc -eq 0) {
        # PATH에 새로 추가된 ~/.local/bin이 아직 반영되지 않았을 수 있다.
        $localBin = Join-Path $HOME '.local' 'bin'
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            if (Test-Path $localBin) {
                $env:PATH = "$localBin$([System.IO.Path]::PathSeparator)$env:PATH"
            }
        }

        if (Get-Command claude -ErrorAction SilentlyContinue) {
            try {
                $ccVersion = (& claude --version 2>$null | Select-Object -First 1)
            }
            catch {
                $ccVersion = $null
            }
            if ([string]::IsNullOrWhiteSpace($ccVersion)) { $ccVersion = 'version unknown' }
            Write-Ok "Claude Code CLI 설치 완료: $ccVersion"
            $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
            if ($claudePath) { Write-Host "  설치 위치: $claudePath" }
        }
        else {
            Write-Warn "Native installer는 종료되었으나 'claude'를 PATH에서 찾을 수 없습니다."
            Write-Host "  새 PowerShell 세션을 시작하거나 PATH를 갱신하세요."
        }
    }
    else {
        Write-Warn "Claude Code CLI 자동 설치 실패 (Invoke-InstallerFetchVerifyRun rc=$rc)."
        Write-Host "  Anthropic 공식 가이드: https://code.claude.com/docs/en/setup"
    }
}

# ── Clone repository ─────────────────────────────────────────

function Invoke-CloneRepository {
    Write-Info "저장소 클론 중..."

    if (Test-Path -LiteralPath $InstallDir -PathType Container) {
        Write-Warn "기존 설치 디렉토리가 존재합니다: $InstallDir"
        $overwrite = Read-BootstrapValue -EnvName 'OVERWRITE' -Prompt "덮어쓰시겠습니까? (y/n) [기본값: n]" -Default 'n'

        if ($overwrite -eq 'y') {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
        }
        else {
            Write-Info "기존 디렉토리를 사용합니다. git pull 실행..."
            Push-Location $InstallDir
            try {
                & git pull origin $GitHubRef
            }
            finally {
                Pop-Location
            }
            return
        }
    }

    # Pinned to GITHUB_REF tag with --depth 1 for bandwidth efficiency.
    & git clone --branch $GitHubRef --depth 1 "https://github.com/$GitHubUser/$GitHubRepo.git" $InstallDir
    Write-Ok "저장소 클론 완료: $InstallDir (ref: $GitHubRef)"
}

function Copy-BootstrapHookFiles {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][string[]]$Filters
    )

    if (-not (Test-Path -LiteralPath $DestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force -ErrorAction Stop | Out-Null
    }

    foreach ($filter in $Filters) {
        $items = @(Get-ChildItem -LiteralPath $SourceDir -Filter $filter -File -ErrorAction Stop)
        foreach ($item in $items) {
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $DestinationDir $item.Name) -Force -ErrorAction Stop
        }
    }
}

function Deploy-BootstrapHooks {
    $hooksSrc = Join-Path $InstallDir 'global' 'hooks'
    if (-not (Test-Path -LiteralPath $hooksSrc -PathType Container)) {
        throw "hook source directory missing: $hooksSrc"
    }

    $hooksDst = Join-Path $ClaudeDir 'hooks'
    # Windows 훅은 `pwsh -File ...ps1`; .sh/.json은 WSL/parity 목적으로 함께 복사.
    Copy-BootstrapHookFiles -SourceDir $hooksSrc -DestinationDir $hooksDst -Filters @('*.ps1', '*.sh', '*.json')

    # global/hooks/lib/* 배포 (issue #586): 공유 라이브러리는 top-level glob에
    # 잡히지 않으므로 별도 복사한다. 없으면 4개 Bash 가드가 약화된다.
    $hooksLibSrc = Join-Path $hooksSrc 'lib'
    if (Test-Path -LiteralPath $hooksLibSrc -PathType Container) {
        $hooksLibDst = Join-Path $hooksDst 'lib'
        Copy-BootstrapHookFiles -SourceDir $hooksLibSrc -DestinationDir $hooksLibDst -Filters @('*.ps1', '*.psm1', '*.sh')
    }

    # Shared bash validator libraries used by the deployed Bash hook variants.
    # Mirrors scripts/install.sh so native Windows and WSL/container mounts get
    # the same runtime library set before settings.json is published.
    $sharedLibSrc = Join-Path $InstallDir 'hooks' 'lib'
    if (Test-Path -LiteralPath $sharedLibSrc -PathType Container) {
        $hooksLibDst = Join-Path $hooksDst 'lib'
        Copy-BootstrapHookFiles -SourceDir $sharedLibSrc -DestinationDir $hooksLibDst -Filters @(
            'validate-commit-message.sh',
            'validate-language.sh',
            'validate-traceability.sh'
        )
    }

    $requiredLibs = @(
        'tokenize-shell.sh',
        'path-utils.sh',
        'timeout-wrapper.sh',
        'rotate.sh',
        'validate-commit-message.sh',
        'validate-language.sh',
        'validate-traceability.sh'
    )
    foreach ($lib in $requiredLibs) {
        if (-not (Test-Path -LiteralPath (Join-Path $hooksDst 'lib' $lib) -PathType Leaf)) {
            throw "required hook runtime library missing after deploy: hooks/lib/$lib"
        }
    }
}

function Deploy-BootstrapUtilityScripts {
    $scriptsSrc = Join-Path $InstallDir 'global' 'scripts'
    if (-not (Test-Path -LiteralPath $scriptsSrc -PathType Container)) { return }

    $scriptsDst = Join-Path $ClaudeDir 'scripts'
    if (-not (Test-Path -LiteralPath $scriptsDst -PathType Container)) {
        New-Item -ItemType Directory -Path $scriptsDst -Force -ErrorAction Stop | Out-Null
    }
    Copy-Item -Path (Join-Path $scriptsSrc '*') -Destination $scriptsDst -Force -ErrorAction Stop
}

function Install-BootstrapSettingsAndHooks {
    # Intentionally bypasses Invoke-GuardedCopy: policy attributes (.language,
    # .env.CLAUDE_CONTENT_LANGUAGE) must be enforced on every install.
    # Update-ClaudeSettingsJson injects them into a staged file first; the
    # final settings.json is published only after hook deployment succeeds.
    # PARITY: scripts/install.ps1 selects global/settings.windows.json on this
    # PowerShell installer — its hooks invoke `pwsh -File ...ps1`. Using
    # global/settings.json here would ship bare `.sh` hook commands that native
    # Windows cannot execute. Destination filename stays settings.json.
    $settingsSrc = Join-Path $InstallDir 'global' 'settings.windows.json'
    if (-not (Test-Path -LiteralPath $settingsSrc)) { return }

    $settingsDst = Join-Path $ClaudeDir 'settings.json'
    $settingsTmp = Join-Path $ClaudeDir ".settings.json.tmp.$PID"
    $agentLanguage = if ($script:agentLanguage) { $script:agentLanguage } else { 'korean' }
    $contentLanguage = if ($script:contentLanguage) { $script:contentLanguage } else { 'english' }
    $settingsUpdated = $false

    try {
        Remove-Item -LiteralPath $settingsTmp -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $settingsSrc -Destination $settingsTmp -Force -ErrorAction Stop

        $settingsUpdated = Update-ClaudeSettingsJson -SettingsPath $settingsTmp -AgentLang $agentLanguage -ContentLang $contentLanguage

        Deploy-BootstrapHooks
        Deploy-BootstrapUtilityScripts

        Move-Item -LiteralPath $settingsTmp -Destination $settingsDst -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $settingsTmp -Force -ErrorAction SilentlyContinue
        Write-Fail "Hook 스크립트 배포 실패. settings.json을 변경하지 않았습니다. $_"
    }

    if ($settingsUpdated) {
        Write-Ok "settings.json (에이전트: $agentLanguage, 컨텐츠: $contentLanguage) 설치 완료"
    } else {
        Write-Ok "settings.json 설치 완료 (기본값)"
    }
    Write-Ok "Hook 스크립트 (hooks/ + lib/) 설치 완료!"
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

    # Load shared installer prompts (single source of truth, mirrored at
    # scripts/lib/install-prompts.sh for bash).
    $promptsModule = Join-Path $InstallDir 'scripts' 'lib' 'InstallPrompts.psm1'
    if (Test-Path -LiteralPath $promptsModule) {
        Import-Module $promptsModule -Force -DisableNameChecking
    }

    # Copy files (manifest-guarded: local edits preserved by default)
    $globalFiles = @('CLAUDE.md', 'commit-settings.md', 'git-identity.md', 'token-management.md')
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
        } else {
            Copy-Item -LiteralPath $src -Destination $ClaudeDir -Force
            Write-Ok "$gf 설치됨"
        }
    }

    # Auto-seed git identity from `git config --global` (issue #777). Shared
    # with scripts/install.ps1 via Set-GitIdentitySeed in InstallPrompts.psm1,
    # so the later Invoke-PersonalizeGitIdentity step becomes confirm-only when
    # the user already has a global git identity configured.
    if (Get-Command Set-GitIdentitySeed -ErrorAction SilentlyContinue) {
        $gitIdTarget = Join-Path $ClaudeDir 'git-identity.md'
        if (Set-GitIdentitySeed -Path $gitIdTarget) {
            Write-Ok "git-identity.md: git config로 자동 채우기 완료 ($($script:SeededGitName) <$($script:SeededGitEmail)>)"
        }
    }

    # Language policy selection (Unified Language Profile)
    # Stored at script scope so the project-install path (Install-ProjectSettings)
    # can reuse the resolved values for rule-template rendering (issue #760).
    $settingsPath = Join-Path $ClaudeDir 'settings.json'
    $seededPolicy = $null
    if (Get-Command Seed-LanguageFromSettings -ErrorAction SilentlyContinue) {
        $seededPolicy = Seed-LanguageFromSettings -SettingsPath $settingsPath
    }
    if ($seededPolicy) {
        $profileChoice = Show-LanguageProfilePrompt -AgentLanguage $seededPolicy.AgentLanguage -ContentLanguage $seededPolicy.ContentLanguage
    }
    else {
        $profileChoice = Show-LanguageProfilePrompt
    }
    $script:agentLanguage = $profileChoice.AgentLanguage
    $script:displayLang = $profileChoice.AgentDisplay
    $script:contentLanguage = $profileChoice.ContentLanguage
    $displayLang = $script:displayLang
    $contentLanguage = $script:contentLanguage

    # conversation-language.md 템플릿 처리
    $tmplPath = Join-Path $InstallDir 'global' 'conversation-language.md.tmpl'
    if (Test-Path -LiteralPath $tmplPath) {
        $dest = Join-Path $ClaudeDir "conversation-language.md"
        if (Invoke-GuardedTemplateCopy -SrcTmpl $tmplPath -Dest $dest -Key "conversation-language.md" -DisplayLang $displayLang) {
            Write-Ok "conversation-language.md 설치됨 (언어: $displayLang)"
        } else {
            Write-Info "conversation-language.md 로컬 변경 유지"
        }
    } else {
        # Static-file fallback. The default repo ships only the .tmpl, so this
        # branch is unreachable in normal use. It exists to support fork users
        # who replace the .tmpl with a hand-edited static .md — preserving
        # their file via Invoke-GuardedCopy instead of silently dropping it.
        $staticMd = Join-Path $InstallDir 'global' 'conversation-language.md'
        if (Test-Path -LiteralPath $staticMd) {
            $dest = Join-Path $ClaudeDir 'conversation-language.md'
            if (Invoke-GuardedCopy -Src $staticMd -Dest $dest -Key "conversation-language.md") {
                Write-Ok "conversation-language.md 설치됨"
            } else {
                Write-Info "conversation-language.md 로컬 변경 유지"
            }
        }
    }

    # Legacy settings.json migration warning (informational only).
    $null = Show-LegacySettingsWarning -SettingsPath (Join-Path $HOME '.claude/settings.json') -NewSelection $contentLanguage

    # Install global skills and commands.
    # `_internal/` 하위 격리 + `disable-model-invocation: true`가 적용된 스킬군은
    # Claude Code 슬래시 카탈로그에 노출되지 않으며, 글로벌 CLAUDE.md의
    # "Skill Aliases" 표에 따라 leading keyword 호출로만 실행된다.
    $globalSkillsSrc = Join-Path $InstallDir 'global' 'skills'
    if (Test-Path -LiteralPath $globalSkillsSrc -PathType Container) {
        $globalSkillsDst = Join-Path $ClaudeDir 'skills'
        if (-not (Test-Path $globalSkillsDst)) {
            New-Item -ItemType Directory -Path $globalSkillsDst -Force | Out-Null
        }
        Copy-Item -Path "$globalSkillsSrc\*" -Destination $globalSkillsDst -Recurse -Force
        $skillCount = (Get-ChildItem -Path $globalSkillsDst -Filter SKILL.md -Recurse -ErrorAction SilentlyContinue).Count
        Write-Ok "글로벌 skills 설치 완료 ($skillCount 개)"
    }
    $globalCommandsSrc = Join-Path $InstallDir 'global' 'commands'
    if (Test-Path -LiteralPath $globalCommandsSrc -PathType Container) {
        $globalCommandsDst = Join-Path $ClaudeDir 'commands'
        if (-not (Test-Path $globalCommandsDst)) {
            New-Item -ItemType Directory -Path $globalCommandsDst -Force | Out-Null
        }
        Copy-Item -Path "$globalCommandsSrc\*" -Destination $globalCommandsDst -Recurse -Force
        Write-Ok "글로벌 commands 설치 완료"
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

    # settings.json (ccstatusline)
    $ccstatuslineSrc = Join-Path $InstallDir 'global' 'ccstatusline'
    if (Test-Path -LiteralPath $ccstatuslineSrc -PathType Container) {
        $ccstatuslineDst = Join-Path $HOME '.config' 'ccstatusline'
        if (-not (Test-Path $ccstatuslineDst)) {
            New-Item -ItemType Directory -Path $ccstatuslineDst -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $ccstatuslineSrc 'settings.json') -Destination $ccstatuslineDst -Force
        Write-Ok "ccstatusline 설정 설치 완료"
    }

    # settings.json + hooks 디렉토리 설치 (settings.json이 참조하는 런타임 가드)
    # settings.windows.json은 `pwsh -File ...ps1` 훅 다수를 참조하므로, 설정 복사와
    # 훅 배포를 한 트랜잭션으로 처리해 "설정은 있는데 훅이 없는" 조용한 보안 공백을
    # 막는다. Hook 배포 실패 시 settings.json은 게시하지 않는다.
    Install-BootstrapSettingsAndHooks

    # npm package installation (statusline dependencies)
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $installNpm = Read-BootstrapValue -EnvName 'INSTALL_NPM' -Prompt "Statusline npm 패키지를 설치하시겠습니까? (y/n) [기본값: y]" -Default 'y'
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
    $gitIdFile = Join-Path $ClaudeDir 'git-identity.md'
    $needsGitIdentityEdit = $false
    if (Test-Path $gitIdFile) {
        $needsGitIdentityEdit = [bool](Select-String -Path $gitIdFile -Pattern 'YOUR NAME|YOUR EMAIL' -Quiet)
    }
    if ($needsGitIdentityEdit) {
        Write-Warn "Git Identity에 기본 placeholder가 남아 있습니다. 개인 정보로 수정하세요."
    }
    else {
        Write-Info "Git Identity가 준비되었습니다. 필요하면 값을 확인하거나 수정하세요."
    }
    Write-Host ""
    Write-Host "  현재 설정:"
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

    $editNow = Read-BootstrapValue -EnvName 'EDIT_NOW' -Prompt "지금 수정하시겠습니까? (y/n) [기본값: n]" -Default 'n'

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
    $selection = Read-BootstrapValue -EnvName 'INSTALL_TYPE' -Prompt "선택 (1-4) [기본값: 1]" -Default '1'
    return $selection
}

# ── Install project settings ─────────────────────────────────

function Install-ProjectSettings {
    Write-Host ""
    $defaultDir = (Get-Location).Path
    $projDir = Read-BootstrapValue -EnvName 'PROJECT_DIR' -Prompt "프로젝트 디렉토리 경로 [기본값: $defaultDir]" -Default $defaultDir

    if (-not (Test-Path -LiteralPath $projDir -PathType Container)) {
        Write-Fail "디렉토리가 존재하지 않습니다: $projDir"
    }

    Write-Info "프로젝트 설정 설치 중: $projDir"

    # Policy-template render prerequisites (issue #760).
    # InstallPrompts.psm1 provides Invoke-PolicyTemplatesInDir and the language
    # profile prompt. On the project-only path (install type 2) Install-GlobalSettings
    # is not called, so the module import and language resolution must happen here.
    # Both are idempotent / guarded:
    #   - Import-Module -Force is safe to repeat.
    #   - Resolve the profile only when the script-scoped values are not already
    #     set (type 3 resolved them in Install-GlobalSettings), to avoid a second prompt.
    $promptsModule = Join-Path $InstallDir 'scripts' 'lib' 'InstallPrompts.psm1'
    if (Test-Path -LiteralPath $promptsModule) {
        Import-Module $promptsModule -Force -DisableNameChecking
    }
    if (-not $script:contentLanguage -or -not $script:agentLanguage) {
        if (Get-Command Show-LanguageProfilePrompt -ErrorAction SilentlyContinue) {
            $profileChoice = Show-LanguageProfilePrompt
            $script:agentLanguage = $profileChoice.AgentLanguage
            $script:displayLang = $profileChoice.AgentDisplay
            $script:contentLanguage = $profileChoice.ContentLanguage
        }
    }

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
        # issue #760: render any .md.tmpl under the copied rules/ via the same
        # single-source function install.ps1 uses. Unset language values fall
        # back to safe defaults inside Invoke-PolicyTemplate.
        if (Get-Command Invoke-PolicyTemplatesInDir -ErrorAction SilentlyContinue) {
            Invoke-PolicyTemplatesInDir -Path (Join-Path $projClaudeDir 'rules') `
                -ContentLanguage $script:contentLanguage -AgentDisplay $script:displayLang -AgentLanguage $script:agentLanguage
        }
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
    # Invoke-CloneRepository must run before Confirm-ClaudeCli — the latter
    # imports hooks/lib/InstallerFetch.psm1 from the just-cloned tag (#620).
    # Trust root: GITHUB_REF tag → cloned hooks/lib/* → pinned sha256 verify.
    Invoke-CloneRepository
    Confirm-ClaudeCli

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
if ($env:CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE -eq 'atomic-deploy') {
    if (-not (Test-Path $ClaudeDir)) {
        New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    }
    $manifestHelper = Join-Path $InstallDir 'scripts' 'install-manifest.ps1'
    if (-not (Test-Path -LiteralPath $manifestHelper)) {
        Write-Fail "install-manifest.ps1 not found for atomic-deploy test mode"
    }
    . $manifestHelper
    Install-BootstrapSettingsAndHooks
    exit 0
}

Invoke-Main
