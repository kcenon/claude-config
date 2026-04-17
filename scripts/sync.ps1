#Requires -Version 7.0

# Claude Configuration Sync Tool
# ===============================
# 현재 시스템과 백업 사이의 CLAUDE.md 설정을 동기화하는 스크립트
# Ported from sync.sh

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Import shared module
$ModulePath = Join-Path (Split-Path $PSScriptRoot) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
if (-not (Test-Path $ModulePath)) {
    $ModulePath = Join-Path $PSScriptRoot '..' 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
}
Import-Module $ModulePath -Force -WarningAction SilentlyContinue

# Script and backup directory paths
$ScriptDir = $PSScriptRoot
$BackupDir = Split-Path -Parent $ScriptDir

# Fast path: validate SKILL.md / plugin.json / settings.json against
# canonical Claude Code 2026 schemas. See scripts/schemas/.
if ($args.Count -gt 0 -and $args[0] -eq '--lint') {
    # Translate bash-style flags to a splatted hashtable so callers can use the
    # same flag names across both sync.sh and sync.ps1.
    $lintParams = @{}
    $lintFiles  = @()
    if ($args.Count -gt 1) {
        for ($i = 1; $i -lt $args.Count; $i++) {
            switch ($args[$i]) {
                '--warn-only' { $lintParams['WarnOnly'] = $true }
                '--strict'    { $lintParams['Strict']   = $true }
                '--quiet'     { $lintParams['Quiet']    = $true }
                '--mode'      {
                    if ($i + 1 -lt $args.Count) {
                        $i++
                        $lintParams['Mode'] = $args[$i]
                    }
                }
                default       { $lintFiles += $args[$i] }
            }
        }
    }
    & (Join-Path $ScriptDir 'spec_lint.ps1') @lintParams @lintFiles
    exit $LASTEXITCODE
}

# Pre-flight: refuse to sync if canonical files violate the schema.
# Bypass with --skip-lint for emergency syncs (e.g., reverting a bad change).
$skipLint = $args -contains '--skip-lint'
$specLintPs1 = Join-Path $ScriptDir 'spec_lint.ps1'
if (-not $skipLint -and (Test-Path -LiteralPath $specLintPs1)) {
    & $specLintPs1 -Quiet *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'spec_lint detected schema violations.' -ForegroundColor Red
        Write-Host "   Run: $ScriptDir\sync.ps1 --lint"
        Write-Host '   Sync aborted to prevent deploying drift.'
        Write-Host '   Bypass with --skip-lint (emergency only).'
        exit 1
    }
}

Write-Banner -Title 'Claude Configuration Sync Tool'

# ── File comparison function ─────────────────────────────────

function Compare-ConfigFiles {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Source) -and -not (Test-Path -LiteralPath $Target)) {
        Write-Host "    ${Name}: 양쪽 모두 없음"
        return 0
    }
    elseif (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "    ${Name}: 백업에만 있음 (시스템에 복사 가능)" -ForegroundColor Blue
        return 1
    }
    elseif (-not (Test-Path -LiteralPath $Target)) {
        Write-Host "    ${Name}: 시스템에만 있음 (백업으로 복사 가능)" -ForegroundColor Yellow
        return 2
    }
    else {
        $srcContent = Get-Content -LiteralPath $Source -ErrorAction SilentlyContinue
        $tgtContent = Get-Content -LiteralPath $Target -ErrorAction SilentlyContinue
        $diff = Compare-Object $srcContent $tgtContent -ErrorAction SilentlyContinue
        if ($null -eq $diff -or $diff.Count -eq 0) {
            Write-Host "    ${Name}: 동일함" -ForegroundColor Green
            return 0
        }
        else {
            Write-Host "    ${Name}: 다름" -ForegroundColor Red
            return 3
        }
    }
}

# ── Sync direction selection ─────────────────────────────────

Write-Host ""
Write-InfoMessage "동기화 방향을 선택하세요:"
Write-Host "  1) 백업 -> 시스템 (백업의 설정을 시스템에 적용)"
Write-Host "  2) 시스템 -> 백업 (시스템의 설정을 백업에 저장)"
Write-Host "  3) 차이점만 확인 (변경하지 않음)"
Write-Host ""
$syncDirection = Read-Host "선택 (1-3) [기본값: 3]"
if ([string]::IsNullOrEmpty($syncDirection)) { $syncDirection = '3' }

# ── Enterprise settings comparison ───────────────────────────

Write-Host ""
$checkEnterprise = Read-Host "Enterprise 설정도 비교하시겠습니까? (y/n) [기본값: n]"
if ([string]::IsNullOrEmpty($checkEnterprise)) { $checkEnterprise = 'n' }

$enterpriseDiff = 0
$enterpriseDir = Get-EnterprisePath

if ($checkEnterprise -eq 'y') {
    Write-Host ""
    Write-Host "======================================================"
    Write-InfoMessage "Enterprise 설정 비교"
    Write-Host "======================================================"
    Write-Host ""
    Write-InfoMessage "Enterprise 경로: $enterpriseDir"

    $result = Compare-ConfigFiles `
        -Source (Join-Path $BackupDir 'enterprise' 'CLAUDE.md') `
        -Target (Join-Path $enterpriseDir 'CLAUDE.md') `
        -Name 'Enterprise CLAUDE.md'
    if ($result -ne 0) { $enterpriseDiff = 1 }

    # rules directory comparison
    $backupRules = Join-Path $BackupDir 'enterprise' 'rules'
    $sysRules    = Join-Path $enterpriseDir 'rules'
    if ((Test-Path $backupRules) -or (Test-Path $sysRules)) {
        Write-Host "  Enterprise rules 디렉토리 비교:" -ForegroundColor Cyan
        if (-not (Test-Path $backupRules)) {
            Write-Host "    rules: 시스템에만 있음 (백업으로 복사 가능)" -ForegroundColor Yellow
            $enterpriseDiff = 1
        }
        elseif (-not (Test-Path $sysRules)) {
            Write-Host "    rules: 백업에만 있음 (시스템에 복사 가능)" -ForegroundColor Blue
            $enterpriseDiff = 1
        }
        else {
            # Compare files in both directories
            $srcFiles = Get-ChildItem -LiteralPath $backupRules -Recurse -File -ErrorAction SilentlyContinue
            foreach ($sf in $srcFiles) {
                $relPath = $sf.FullName.Substring($backupRules.Length)
                $targetFile = Join-Path $sysRules $relPath
                if (-not (Test-Path $targetFile)) {
                    Write-Host "    Only in backup: $relPath" -ForegroundColor Blue
                    $enterpriseDiff = 1
                }
                else {
                    $diff = Compare-Object (Get-Content $sf.FullName) (Get-Content $targetFile) -ErrorAction SilentlyContinue
                    if ($diff) {
                        Write-Host "    Differs: $relPath" -ForegroundColor Red
                        $enterpriseDiff = 1
                    }
                }
            }
        }
    }
}

# ── Global settings comparison ───────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "글로벌 설정 비교"
Write-Host "======================================================"
Write-Host ""

$globalDiff = 0
$claudeHome = Join-Path $HOME '.claude'

$result = Compare-ConfigFiles -Source (Join-Path $BackupDir 'global' 'CLAUDE.md')                -Target (Join-Path $claudeHome 'CLAUDE.md')                -Name 'CLAUDE.md'
if ($result -ne 0) { $globalDiff = 1 }

$result = Compare-ConfigFiles -Source (Join-Path $BackupDir 'global' 'conversation-language.md') -Target (Join-Path $claudeHome 'conversation-language.md') -Name 'conversation-language.md'
if ($result -ne 0) { $globalDiff = 1 }

$result = Compare-ConfigFiles -Source (Join-Path $BackupDir 'global' 'git-identity.md')          -Target (Join-Path $claudeHome 'git-identity.md')          -Name 'git-identity.md'
if ($result -ne 0) { $globalDiff = 1 }

$result = Compare-ConfigFiles -Source (Join-Path $BackupDir 'global' 'token-management.md')      -Target (Join-Path $claudeHome 'token-management.md')      -Name 'token-management.md'
if ($result -ne 0) { $globalDiff = 1 }

# ── Project settings comparison ──────────────────────────────

Write-Host ""
$checkProject = Read-Host "프로젝트 설정도 비교하시겠습니까? (y/n) [기본값: n]"
if ([string]::IsNullOrEmpty($checkProject)) { $checkProject = 'n' }

$projectDiff = 0
$projectDir  = ''

if ($checkProject -eq 'y') {
    $projectDir = Read-Host "프로젝트 디렉토리 경로"

    if (-not [string]::IsNullOrEmpty($projectDir) -and (Test-Path -LiteralPath $projectDir -PathType Container)) {
        Write-Host ""
        Write-Host "======================================================"
        Write-InfoMessage "프로젝트 설정 비교: $projectDir"
        Write-Host "======================================================"
        Write-Host ""

        $result = Compare-ConfigFiles `
            -Source (Join-Path $BackupDir 'project' 'CLAUDE.md') `
            -Target (Join-Path $projectDir 'CLAUDE.md') `
            -Name '프로젝트 CLAUDE.md'
        if ($result -ne 0) { $projectDiff = 1 }

        # rules directory comparison
        $backupRulesDir = Join-Path $BackupDir 'project' '.claude' 'rules'
        $projRulesDir   = Join-Path $projectDir '.claude' 'rules'
        if ((Test-Path $backupRulesDir) -and (Test-Path $projRulesDir)) {
            Write-Host "  rules 디렉토리 비교:" -ForegroundColor Cyan
            $srcFiles = Get-ChildItem -LiteralPath $backupRulesDir -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 10
            foreach ($sf in $srcFiles) {
                $relPath = $sf.FullName.Substring($backupRulesDir.Length)
                $targetFile = Join-Path $projRulesDir $relPath
                if (-not (Test-Path $targetFile)) {
                    Write-Host "    Only in backup: $relPath"
                    $projectDiff = 1
                }
                else {
                    $diff = Compare-Object (Get-Content $sf.FullName) (Get-Content $targetFile) -ErrorAction SilentlyContinue
                    if ($diff) {
                        Write-Host "    Differs: $relPath"
                        $projectDiff = 1
                    }
                }
            }
        }

        # skills directory comparison
        $backupSkillsDir = Join-Path $BackupDir 'project' '.claude' 'skills'
        $projSkillsDir   = Join-Path $projectDir '.claude' 'skills'
        if ((Test-Path $backupSkillsDir) -or (Test-Path $projSkillsDir)) {
            Write-Host "  skills 디렉토리 비교:" -ForegroundColor Cyan
            if (-not (Test-Path $backupSkillsDir)) {
                Write-Host "    skills: 시스템에만 있음 (백업으로 복사 가능)" -ForegroundColor Yellow
                $projectDiff = 1
            }
            elseif (-not (Test-Path $projSkillsDir)) {
                Write-Host "    skills: 백업에만 있음 (시스템에 복사 가능)" -ForegroundColor Blue
                $projectDiff = 1
            }
            else {
                $srcFiles = Get-ChildItem -LiteralPath $backupSkillsDir -Recurse -File -ErrorAction SilentlyContinue |
                    Select-Object -First 10
                foreach ($sf in $srcFiles) {
                    $relPath = $sf.FullName.Substring($backupSkillsDir.Length)
                    $targetFile = Join-Path $projSkillsDir $relPath
                    if (-not (Test-Path $targetFile)) {
                        Write-Host "    Only in backup: $relPath"
                        $projectDiff = 1
                    }
                    else {
                        $diff = Compare-Object (Get-Content $sf.FullName) (Get-Content $targetFile) -ErrorAction SilentlyContinue
                        if ($diff) {
                            Write-Host "    Differs: $relPath"
                            $projectDiff = 1
                        }
                    }
                }
            }
        }
    }
}

# ── Comparison only mode ─────────────────────────────────────

if ($syncDirection -eq '3') {
    Write-Host ""
    Write-SuccessMessage "비교 완료 (변경 없음)"
    exit 0
}

if ($globalDiff -eq 0 -and $projectDiff -eq 0 -and $enterpriseDiff -eq 0) {
    Write-Host ""
    Write-SuccessMessage "모든 파일이 동일합니다. 동기화 불필요!"
    exit 0
}

# ── Sync confirmation ────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-WarningMessage "동기화 확인"
Write-Host "======================================================"

if ($syncDirection -eq '1') {
    Write-Host ""
    Write-WarningMessage "백업의 설정이 시스템에 적용됩니다!"
    Write-Host "  * 기존 시스템 파일은 .backup_* 으로 백업됩니다"
    Write-Host ""
    $confirm = Read-Host "계속하시겠습니까? (y/n)"
}
else {
    Write-Host ""
    Write-WarningMessage "시스템의 설정이 백업에 저장됩니다!"
    Write-Host "  * 기존 백업 파일은 덮어씌워집니다"
    Write-Host ""
    $confirm = Read-Host "계속하시겠습니까? (y/n)"
}

if ($confirm -ne 'y') {
    Write-InfoMessage "동기화 취소됨"
    exit 0
}

# ── Execute sync ─────────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "동기화 진행 중..."
Write-Host "======================================================"

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if ($syncDirection -eq '1') {
    # Backup -> System

    # Enterprise sync
    if ($checkEnterprise -eq 'y') {
        $enterpriseMd = Join-Path $BackupDir 'enterprise' 'CLAUDE.md'
        if (Test-Path -LiteralPath $enterpriseMd) {
            $needsAdmin = $false
            $parentDir = Split-Path $enterpriseDir
            if (-not (Test-Path $parentDir) -or -not (Test-Path $enterpriseDir)) {
                $needsAdmin = -not (Test-Administrator)
            }

            if ($needsAdmin) {
                Write-WarningMessage "Enterprise 경로에 관리자 권한이 필요합니다."
                Write-InfoMessage "관리자 권한으로 다시 실행하세요."
            }
            else {
                Ensure-Directory $enterpriseDir | Out-Null
                Ensure-Directory (Join-Path $enterpriseDir 'rules') | Out-Null
                Copy-Item -LiteralPath $enterpriseMd -Destination $enterpriseDir -Force
                $backupEntRules = Join-Path $BackupDir 'enterprise' 'rules'
                if (Test-Path $backupEntRules) {
                    Copy-Item -Path (Join-Path $backupEntRules '*') -Destination (Join-Path $enterpriseDir 'rules') -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-SuccessMessage "Enterprise CLAUDE.md -> 시스템"
            }
        }
    }

    # Global files: backup -> system
    $globalSrc = Join-Path $BackupDir 'global'
    $globalFiles = @('CLAUDE.md', 'conversation-language.md', 'git-identity.md', 'token-management.md')

    foreach ($f in $globalFiles) {
        $src = Join-Path $globalSrc $f
        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $claudeHome $f
            if (Test-Path -LiteralPath $dst) {
                Copy-Item -LiteralPath $dst -Destination "${dst}.backup_${timestamp}" -Force
            }
            Copy-Item -LiteralPath $src -Destination $claudeHome -Force
            Write-SuccessMessage "$f -> 시스템"
        }
    }

    # Project sync
    if ($checkProject -eq 'y' -and -not [string]::IsNullOrEmpty($projectDir)) {
        $projClaudeMd = Join-Path $BackupDir 'project' 'CLAUDE.md'
        if (Test-Path -LiteralPath $projClaudeMd) {
            Copy-Item -LiteralPath $projClaudeMd -Destination $projectDir -Force
            Write-SuccessMessage "프로젝트 CLAUDE.md -> 시스템"
        }

        $backupRulesDir = Join-Path $BackupDir 'project' '.claude' 'rules'
        if (Test-Path $backupRulesDir) {
            $destRules = Join-Path $projectDir '.claude' 'rules'
            Ensure-Directory $destRules | Out-Null
            Copy-Item -Path (Join-Path $backupRulesDir '*') -Destination $destRules -Recurse -Force
            Write-SuccessMessage "rules -> 시스템"
        }

        $backupSkillsDir = Join-Path $BackupDir 'project' '.claude' 'skills'
        if (Test-Path $backupSkillsDir) {
            $destSkills = Join-Path $projectDir '.claude' 'skills'
            Ensure-Directory $destSkills | Out-Null
            Copy-Item -Path (Join-Path $backupSkillsDir '*') -Destination $destSkills -Recurse -Force
            Write-SuccessMessage "skills -> 시스템"
        }
    }
}
else {
    # System -> Backup

    # Enterprise sync
    if ($checkEnterprise -eq 'y') {
        $sysEntMd = Join-Path $enterpriseDir 'CLAUDE.md'
        if (Test-Path -LiteralPath $sysEntMd) {
            $entBackup = Join-Path $BackupDir 'enterprise'
            Ensure-Directory $entBackup | Out-Null
            Ensure-Directory (Join-Path $entBackup 'rules') | Out-Null
            Copy-Item -LiteralPath $sysEntMd -Destination $entBackup -Force
            $sysEntRules = Join-Path $enterpriseDir 'rules'
            if (Test-Path $sysEntRules) {
                Copy-Item -Path (Join-Path $sysEntRules '*') -Destination (Join-Path $entBackup 'rules') -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-SuccessMessage "Enterprise CLAUDE.md -> 백업"
        }
    }

    # Global files: system -> backup
    $globalDst = Join-Path $BackupDir 'global'
    $sysFiles = @(
        @{ Name = 'CLAUDE.md';                Src = Join-Path $claudeHome 'CLAUDE.md' }
        @{ Name = 'conversation-language.md';  Src = Join-Path $claudeHome 'conversation-language.md' }
        @{ Name = 'git-identity.md';           Src = Join-Path $claudeHome 'git-identity.md' }
        @{ Name = 'token-management.md';       Src = Join-Path $claudeHome 'token-management.md' }
    )

    foreach ($item in $sysFiles) {
        if (Test-Path -LiteralPath $item.Src) {
            Copy-Item -LiteralPath $item.Src -Destination $globalDst -Force
            Write-SuccessMessage "$($item.Name) -> 백업"
        }
    }

    # Project sync
    if ($checkProject -eq 'y' -and -not [string]::IsNullOrEmpty($projectDir)) {
        $projMd = Join-Path $projectDir 'CLAUDE.md'
        if (Test-Path -LiteralPath $projMd) {
            Copy-Item -LiteralPath $projMd -Destination (Join-Path $BackupDir 'project') -Force
            Write-SuccessMessage "프로젝트 CLAUDE.md -> 백업"
        }

        $projRulesDir = Join-Path $projectDir '.claude' 'rules'
        if (Test-Path $projRulesDir) {
            $destRules = Join-Path $BackupDir 'project' '.claude' 'rules'
            Ensure-Directory $destRules | Out-Null
            Copy-Item -Path (Join-Path $projRulesDir '*') -Destination $destRules -Recurse -Force
            Write-SuccessMessage "rules -> 백업"
        }

        $projSkillsDir = Join-Path $projectDir '.claude' 'skills'
        if (Test-Path $projSkillsDir) {
            $destSkills = Join-Path $BackupDir 'project' '.claude' 'skills'
            Ensure-Directory $destSkills | Out-Null
            Copy-Item -Path (Join-Path $projSkillsDir '*') -Destination $destSkills -Recurse -Force
            Write-SuccessMessage "skills -> 백업"
        }
    }
}

Write-Host ""
Write-Host "======================================================"
Write-SuccessMessage "동기화 완료!"
Write-Host "======================================================"
Write-Host ""

if ($syncDirection -eq '1') {
    Write-InfoMessage "다음 단계:"
    Write-Host "  1. Git identity 확인: vi ~/.claude/git-identity.md"
    Write-Host "  2. Claude Code 재시작"
}
else {
    Write-InfoMessage "다음 단계:"
    Write-Host "  1. 백업을 다른 시스템에 복사"
    Write-Host "  2. 새 시스템에서 ./scripts/install.sh 실행"
}

Write-Host ""
Write-SuccessMessage "동기화가 완료되었습니다!"

# ── Git Hooks Installation Audit ──────────────────────────────

function Invoke-HooksAudit {
    param(
        [string]$ScanDir = (Join-Path $HOME 'Sources')
    )

    Write-Host ""
    Write-Host "======================================================"
    Write-InfoMessage "Git Hooks Installation Audit"
    Write-Host "======================================================"
    Write-Host ""
    Write-InfoMessage "Scanning: $ScanDir"
    Write-Host ""

    $total = 0
    $complete = 0

    $gitDirs = Get-ChildItem -Path $ScanDir -Filter '.git' -Directory -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue

    foreach ($gitDir in $gitDirs) {
        $repo = $gitDir.Parent.FullName
        $repoName = $gitDir.Parent.Name
        $cmHook = Join-Path $gitDir.FullName 'hooks' 'commit-msg'

        $cmStatus = 'MISSING'
        if ((Test-Path $cmHook) -and (Select-String -Path $cmHook -Pattern 'validate-commit-message|conventional commit' -Quiet -ErrorAction SilentlyContinue)) {
            $cmStatus = 'installed'
        }

        $total++

        if ($cmStatus -eq 'installed') {
            $complete++
            Write-Host ("    {0,-35} commit-msg: {1}" -f $repoName, $cmStatus) -ForegroundColor Green
        } else {
            Write-Host ("    {0,-35} commit-msg: {1}" -f $repoName, $cmStatus) -ForegroundColor Red
        }
    }

    Write-Host ""
    if ($total -eq 0) {
        Write-InfoMessage "No git repositories found in $ScanDir"
    } else {
        Write-InfoMessage "$complete of $total repositories have commit-msg hook installed."
        if ($complete -lt $total) {
            Write-Host ""
            Write-InfoMessage "Install missing hooks with:"
            Write-Host "    .\hooks\install-hooks.ps1 <repo-path>"
        }
    }
}

# Run audit unless -NoAudit was passed
$noAudit = $args -contains '--no-audit'
if (-not $noAudit) {
    $scanIdx = [Array]::IndexOf($args, '--scan-dir')
    if ($scanIdx -ge 0 -and $scanIdx -lt ($args.Count - 1)) {
        $auditScanDir = $args[$scanIdx + 1]
    } else {
        $auditScanDir = Join-Path $HOME 'Sources'
    }

    if (Test-Path $auditScanDir -PathType Container) {
        Invoke-HooksAudit -ScanDir $auditScanDir
    }
}
