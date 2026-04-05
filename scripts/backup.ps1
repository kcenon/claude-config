#Requires -Version 7.0

# Claude Configuration Backup Tool
# =================================
# 현재 시스템의 CLAUDE.md 설정을 백업하는 스크립트
# Ported from backup.sh

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Import shared module
$ModulePath = Join-Path (Split-Path $PSScriptRoot) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
if (-not (Test-Path $ModulePath)) {
    $ModulePath = Join-Path $PSScriptRoot '..' 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
}
Import-Module $ModulePath -Force

# Script and backup directory paths
$ScriptDir = $PSScriptRoot
$BackupDir = Split-Path -Parent $ScriptDir

Write-Banner -Title 'Claude Configuration Backup Tool'

# ── Backup type selection ────────────────────────────────────

Write-Host ""
Write-InfoMessage "백업 타입을 선택하세요:"
Write-Host "  1) 글로벌 설정만 백업 (~/.claude/)"
Write-Host "  2) 프로젝트 설정만 백업"
Write-Host "  3) 둘 다 백업 (권장)"
Write-Host "  4) Enterprise 설정만 백업 (관리자 권한 필요할 수 있음)"
Write-Host "  5) 전체 백업 (Enterprise + Global + Project)"
Write-Host ""
$backupType = Read-Host "선택 (1-5) [기본값: 3]"
if ([string]::IsNullOrEmpty($backupType)) { $backupType = '3' }

# Create temporary backup directory
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$tempBackup = Join-Path $BackupDir "backup_${timestamp}"
Ensure-Directory (Join-Path $tempBackup 'global') | Out-Null
Ensure-Directory (Join-Path $tempBackup 'project' '.claude' 'rules') | Out-Null
Ensure-Directory (Join-Path $tempBackup 'enterprise' 'rules') | Out-Null

# ── Enterprise settings backup ───────────────────────────────

if ($backupType -eq '4' -or $backupType -eq '5') {
    Write-Host ""
    Write-Host "======================================================"
    Write-InfoMessage "Enterprise 설정 백업 중..."
    Write-Host "======================================================"

    $enterpriseDir = Get-EnterprisePath
    Write-InfoMessage "Enterprise 경로: $enterpriseDir"

    if (Test-Path -LiteralPath $enterpriseDir -PathType Container) {
        $entMd = Join-Path $enterpriseDir 'CLAUDE.md'
        if (Test-Path -LiteralPath $entMd) {
            Copy-Item -LiteralPath $entMd -Destination (Join-Path $tempBackup 'enterprise') -Force
            Write-SuccessMessage "CLAUDE.md 백업됨"
        }
        else {
            Write-WarningMessage "CLAUDE.md 없음"
        }

        $entRules = Join-Path $enterpriseDir 'rules'
        if (Test-Path -LiteralPath $entRules -PathType Container) {
            Copy-Item -Path (Join-Path $entRules '*') -Destination (Join-Path $tempBackup 'enterprise' 'rules') -Recurse -Force -ErrorAction SilentlyContinue
            Write-SuccessMessage "rules 디렉토리 백업됨"
        }
    }
    else {
        Write-WarningMessage "Enterprise 디렉토리가 존재하지 않습니다: $enterpriseDir"
    }
}

# ── Global settings backup ───────────────────────────────────

if ($backupType -eq '1' -or $backupType -eq '3' -or $backupType -eq '5') {
    Write-Host ""
    Write-Host "======================================================"
    Write-InfoMessage "글로벌 설정 백업 중..."
    Write-Host "======================================================"

    $claudeHome = Join-Path $HOME '.claude'

    $globalFiles = @(
        @{ Name = 'CLAUDE.md';                Path = Join-Path $claudeHome 'CLAUDE.md' }
        @{ Name = 'conversation-language.md';  Path = Join-Path $claudeHome 'conversation-language.md' }
        @{ Name = 'git-identity.md';           Path = Join-Path $claudeHome 'git-identity.md' }
        @{ Name = 'token-management.md';       Path = Join-Path $claudeHome 'token-management.md' }
        @{ Name = 'settings.json';             Path = Join-Path $claudeHome 'settings.json' }
    )

    foreach ($item in $globalFiles) {
        if (Test-Path -LiteralPath $item.Path -PathType Leaf) {
            Copy-Item -LiteralPath $item.Path -Destination (Join-Path $tempBackup 'global') -Force
            Write-SuccessMessage "$($item.Name) 백업됨"
        }
        elseif ($item.Name -eq 'CLAUDE.md') {
            Write-WarningMessage "CLAUDE.md 없음"
        }
    }

    # hooks directory backup
    $hooksDir = Join-Path $claudeHome 'hooks'
    if (Test-Path -LiteralPath $hooksDir -PathType Container) {
        $hooksBackup = Join-Path $tempBackup 'global' 'hooks'
        Ensure-Directory $hooksBackup | Out-Null
        Copy-Item -Path (Join-Path $hooksDir '*.sh') -Destination $hooksBackup -Force -ErrorAction SilentlyContinue
        Write-SuccessMessage "hooks 디렉토리 백업됨"
    }
}

# ── Project settings backup ──────────────────────────────────

if ($backupType -eq '2' -or $backupType -eq '3' -or $backupType -eq '5') {
    Write-Host ""
    Write-Host "======================================================"
    Write-InfoMessage "프로젝트 설정 백업 중..."
    Write-Host "======================================================"

    $projectDir = Read-Host "프로젝트 디렉토리 경로"

    if ([string]::IsNullOrEmpty($projectDir)) {
        Write-WarningMessage "프로젝트 디렉토리 미지정, 건너뜀"
    }
    elseif (-not (Test-Path -LiteralPath $projectDir -PathType Container)) {
        Write-ErrorMessage "디렉토리가 존재하지 않음: $projectDir"
    }
    else {
        $projMd = Join-Path $projectDir 'CLAUDE.md'
        if (Test-Path -LiteralPath $projMd) {
            Copy-Item -LiteralPath $projMd -Destination (Join-Path $tempBackup 'project') -Force
            Write-SuccessMessage "프로젝트 CLAUDE.md 백업됨"
        }

        # .claude/rules directory
        $rulesDir = Join-Path $projectDir '.claude' 'rules'
        if (Test-Path -LiteralPath $rulesDir -PathType Container) {
            Copy-Item -Path (Join-Path $rulesDir '*') -Destination (Join-Path $tempBackup 'project' '.claude' 'rules') -Recurse -Force
            Write-SuccessMessage ".claude/rules 디렉토리 백업됨"
        }

        # .claude/settings.json
        $projSettings = Join-Path $projectDir '.claude' 'settings.json'
        if (Test-Path -LiteralPath $projSettings -PathType Leaf) {
            Copy-Item -LiteralPath $projSettings -Destination (Join-Path $tempBackup 'project' '.claude') -Force
            Write-SuccessMessage ".claude/settings.json 백업됨"
        }

        # Skills directory
        $skillsDir = Join-Path $projectDir '.claude' 'skills'
        if (Test-Path -LiteralPath $skillsDir -PathType Container) {
            $skillsBackup = Join-Path $tempBackup 'project' '.claude' 'skills'
            Ensure-Directory $skillsBackup | Out-Null
            Copy-Item -Path (Join-Path $skillsDir '*') -Destination $skillsBackup -Recurse -Force
            Write-SuccessMessage "skills 디렉토리 백업됨"
        }

        # Commands directory
        $commandsDir = Join-Path $projectDir '.claude' 'commands'
        if (Test-Path -LiteralPath $commandsDir -PathType Container) {
            $commandsBackup = Join-Path $tempBackup 'project' '.claude' 'commands'
            Ensure-Directory $commandsBackup | Out-Null
            Copy-Item -Path (Join-Path $commandsDir '*') -Destination $commandsBackup -Recurse -Force
            Write-SuccessMessage "commands 디렉토리 백업됨"
        }

        # Agents directory
        $agentsDir = Join-Path $projectDir '.claude' 'agents'
        if (Test-Path -LiteralPath $agentsDir -PathType Container) {
            $agentsBackup = Join-Path $tempBackup 'project' '.claude' 'agents'
            Ensure-Directory $agentsBackup | Out-Null
            Copy-Item -Path (Join-Path $agentsDir '*') -Destination $agentsBackup -Recurse -Force
            Write-SuccessMessage "agents 디렉토리 백업됨"
        }
    }
}

# ── Post-backup processing ───────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "백업 완료 처리 중..."
Write-Host "======================================================"

Write-Host ""
$replace = Read-Host "기존 백업을 이 백업으로 대체하시겠습니까? (y/n) [기본값: y]"
if ([string]::IsNullOrEmpty($replace)) { $replace = 'y' }

if ($replace -eq 'y') {
    # Update enterprise directory
    $entTemp = Join-Path $tempBackup 'enterprise'
    $entItems = Get-ChildItem -LiteralPath $entTemp -ErrorAction SilentlyContinue
    if ($entItems.Count -gt 0) {
        $entDest = Join-Path $BackupDir 'enterprise'
        if (Test-Path $entDest) {
            Remove-Item -LiteralPath $entDest -Recurse -Force
        }
        Ensure-Directory $entDest | Out-Null
        Ensure-Directory (Join-Path $entDest 'rules') | Out-Null
        Copy-Item -Path (Join-Path $entTemp '*') -Destination $entDest -Recurse -Force -ErrorAction SilentlyContinue
        Write-SuccessMessage "Enterprise 백업 업데이트됨"
    }

    # Update global directory
    $globalTemp = Join-Path $tempBackup 'global'
    $globalItems = Get-ChildItem -LiteralPath $globalTemp -ErrorAction SilentlyContinue
    if ($globalItems.Count -gt 0) {
        $globalDest = Join-Path $BackupDir 'global'
        if (Test-Path $globalDest) {
            Remove-Item -LiteralPath $globalDest -Recurse -Force
        }
        Ensure-Directory $globalDest | Out-Null
        Copy-Item -Path (Join-Path $globalTemp '*') -Destination $globalDest -Recurse -Force -ErrorAction SilentlyContinue
        Write-SuccessMessage "글로벌 백업 업데이트됨"
    }

    # Update project directory
    $projTemp = Join-Path $tempBackup 'project'
    $projItems = Get-ChildItem -LiteralPath $projTemp -ErrorAction SilentlyContinue
    if ($projItems.Count -gt 0) {
        $projDest = Join-Path $BackupDir 'project'
        if (Test-Path $projDest) {
            Remove-Item -LiteralPath $projDest -Recurse -Force
        }
        Ensure-Directory $projDest | Out-Null
        Copy-Item -Path (Join-Path $projTemp '*') -Destination $projDest -Recurse -Force -ErrorAction SilentlyContinue
        Write-SuccessMessage "프로젝트 백업 업데이트됨"
    }

    # Remove temporary backup
    Remove-Item -LiteralPath $tempBackup -Recurse -Force
    Write-InfoMessage "임시 백업 제거됨"
}
else {
    Write-SuccessMessage "타임스탬프 백업 유지: $tempBackup"
}

# ── Backup summary ───────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-SuccessMessage "백업 완료!"
Write-Host "======================================================"
Write-Host ""

Write-InfoMessage "백업된 파일 위치: $BackupDir"
Write-Host ""

$entDir = Join-Path $BackupDir 'enterprise'
if ((Test-Path $entDir) -and (Get-ChildItem $entDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "  Enterprise 설정:"
    $entMdFile = Join-Path $entDir 'CLAUDE.md'
    if (Test-Path $entMdFile) {
        Write-Host "    - CLAUDE.md"
    }
    $entRulesDir = Join-Path $entDir 'rules'
    if ((Test-Path $entRulesDir) -and (Get-ChildItem $entRulesDir -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host "    - rules/"
    }
    Write-Host ""
}

Write-Host "  글로벌 설정:"
$globalDir = Join-Path $BackupDir 'global'
if (Test-Path $globalDir) {
    $globalFiles = Get-ChildItem -LiteralPath $globalDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'hooks' }
    foreach ($f in $globalFiles) {
        Write-Host "    - $($f.Name)"
    }
    $hooksDir = Join-Path $globalDir 'hooks'
    if ((Test-Path $hooksDir) -and (Get-ChildItem $hooksDir -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host "    - hooks/"
    }
}
else {
    Write-Host "    (없음)"
}

Write-Host ""
Write-Host "  프로젝트 설정:"
$projDir = Join-Path $BackupDir 'project'
$projMdFile = Join-Path $projDir 'CLAUDE.md'
if (Test-Path $projMdFile) { Write-Host "    - CLAUDE.md" }

$projRulesDir = Join-Path $projDir '.claude' 'rules'
if ((Test-Path $projRulesDir) -and (Get-ChildItem $projRulesDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "    - .claude/rules/"
}

$projSkillsDir = Join-Path $projDir '.claude' 'skills'
if ((Test-Path $projSkillsDir) -and (Get-ChildItem $projSkillsDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "    - .claude/skills/"
}

$projCommandsDir = Join-Path $projDir '.claude' 'commands'
if ((Test-Path $projCommandsDir) -and (Get-ChildItem $projCommandsDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "    - .claude/commands/"
}

$projAgentsDir = Join-Path $projDir '.claude' 'agents'
if ((Test-Path $projAgentsDir) -and (Get-ChildItem $projAgentsDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "    - .claude/agents/"
}

Write-Host ""
Write-InfoMessage "다음 단계:"
Write-Host "  1. 백업 내용 확인: Get-ChildItem $BackupDir"
Write-Host "  2. 다른 시스템에 복사"
Write-Host "  3. 새 시스템에서 ./scripts/install.sh 실행"
Write-Host ""

Write-SuccessMessage "백업이 완료되었습니다!"
