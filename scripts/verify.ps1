#Requires -Version 7.0

# Claude Configuration Verification Tool
# =======================================
# Ported from verify.sh

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

Write-Banner -Title 'Claude Configuration Verification Tool'

# Counters
$script:TOTAL_CHECKS   = 0
$script:PASSED_CHECKS  = 0
$script:FAILED_CHECKS  = 0
$script:WARNING_CHECKS = 0

# ── Verification functions ───────────────────────────────────

function Test-FileExists {
    param(
        [string]$FilePath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        $size = (Get-Item -LiteralPath $FilePath).Length
        Write-SuccessMessage "$Description (${size} bytes)"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-ErrorMessage "$Description (없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-DirExists {
    param(
        [string]$DirPath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $DirPath -PathType Container) {
        $count = (Get-ChildItem -LiteralPath $DirPath -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-SuccessMessage "$Description (${count} 파일)"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-ErrorMessage "$Description (없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-ExecutableFile {
    param(
        [string]$FilePath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        # On Windows all files are "executable"; on Unix check execute bit
        if ($IsWindows) {
            Write-SuccessMessage "$Description (실행 가능)"
            $script:PASSED_CHECKS++
            return $true
        }
        else {
            $mode = (Get-Item -LiteralPath $FilePath).UnixMode
            if ($mode -and $mode -match 'x') {
                Write-SuccessMessage "$Description (실행 가능)"
                $script:PASSED_CHECKS++
                return $true
            }
            else {
                Write-WarningMessage "$Description (실행 권한 없음)"
                $script:FAILED_CHECKS++
                return $false
            }
        }
    }
    else {
        Write-WarningMessage "$Description (실행 권한 없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-NpmPackage {
    param(
        [string]$Package,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    $cmd = Get-Command $Package -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = 'unknown'
        try { $version = & $Package --version 2>$null } catch {}
        Write-SuccessMessage "$Description (v${version})"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-WarningMessage "$Description (미설치 - 선택사항)"
        $script:WARNING_CHECKS++
        $script:PASSED_CHECKS++
        return $false
    }
}

function Test-ImportSyntax {
    <#
    .SYNOPSIS
        Validates @import syntax in CLAUDE.md / SKILL.md files.
    #>
    param([string]$FilePath)

    $lines = Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue
    $invalidLines = @()

    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        # Lines starting with @ but not ./ ~/ / or known directives
        if ($line -match '^@[^./~@]') {
            # Skip known patterns
            if ($line -match '^@https')    { continue }
            if ($line -match '^@load:')    { continue }
            if ($line -match '^@skip:')    { continue }
            if ($line -match '^@focus:')   { continue }
            if ($line -match '^@context:') { continue }
            if ($line -match '@app\.')     { continue }
            if ($line -match '@pytest\.')  { continue }
            if ($line -match '@limiter\.') { continue }
            if ($line -match '@before_')   { continue }
            if ($line -match '@after_')    { continue }
            $invalidLines += "${lineNum}: $line"
        }
    }

    if ($invalidLines.Count -gt 0) {
        Write-ErrorMessage "Invalid import syntax in $FilePath"
        Write-Host "  Use @./path for relative or @~/path for home directory"
        Write-Host "  Found:"
        foreach ($il in $invalidLines) {
            Write-Host "    $il"
        }
        return $false
    }
    return $true
}

# ── Backup directory structure verification ──────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "백업 구조 검증"
Write-Host "======================================================"
Write-Host ""

Write-Host "디렉토리 구조:"
Test-DirExists (Join-Path $BackupDir 'global')  '글로벌 설정 디렉토리' | Out-Null
Test-DirExists (Join-Path $BackupDir 'project') '프로젝트 설정 디렉토리' | Out-Null
Test-DirExists (Join-Path $BackupDir 'scripts') '스크립트 디렉토리' | Out-Null

# ── Global settings file verification ────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "글로벌 설정 파일 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'global' 'CLAUDE.md')           'CLAUDE.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'commit-settings.md')  'commit-settings.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'settings.json')       'settings.json (Hook 설정)' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'ccstatusline' 'settings.json') 'ccstatusline/settings.json (설치 대상: ~/.config/ccstatusline/)' | Out-Null

# JSON validity check for settings.json
$settingsJson = Join-Path $BackupDir 'global' 'settings.json'
if (Test-Path -LiteralPath $settingsJson -PathType Leaf) {
    $script:TOTAL_CHECKS++
    try {
        Get-Content -LiteralPath $settingsJson -Raw | ConvertFrom-Json | Out-Null
        Write-SuccessMessage "settings.json JSON 유효성 검사 통과"
        $script:PASSED_CHECKS++
    }
    catch {
        Write-ErrorMessage "settings.json JSON 유효성 검사 실패"
        $script:FAILED_CHECKS++
    }
}

# ── Project settings file verification ───────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "프로젝트 설정 파일 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'project' 'CLAUDE.md')                 '프로젝트 CLAUDE.md' | Out-Null
Test-DirExists  (Join-Path $BackupDir 'project' '.claude')                   '.claude 디렉토리' | Out-Null
Test-DirExists  (Join-Path $BackupDir 'project' '.claude' 'rules')           '.claude/rules 디렉토리' | Out-Null
Test-FileExists (Join-Path $BackupDir 'project' '.claude' 'settings.json')   '프로젝트 settings.json (Hook 설정)' | Out-Null

# Project settings.json JSON validity
$projSettings = Join-Path $BackupDir 'project' '.claude' 'settings.json'
if (Test-Path -LiteralPath $projSettings -PathType Leaf) {
    $script:TOTAL_CHECKS++
    try {
        Get-Content -LiteralPath $projSettings -Raw | ConvertFrom-Json | Out-Null
        Write-SuccessMessage "프로젝트 settings.json JSON 유효성 검사 통과"
        $script:PASSED_CHECKS++
    }
    catch {
        Write-ErrorMessage "프로젝트 settings.json JSON 유효성 검사 실패"
        $script:FAILED_CHECKS++
    }
}

# ── Skills directory verification ────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "Skills 디렉토리 검증"
Write-Host "======================================================"
Write-Host ""

Test-DirExists (Join-Path $BackupDir 'project' '.claude' 'skills') 'skills 디렉토리' | Out-Null

$skillsDir = Join-Path $BackupDir 'project' '.claude' 'skills'
if (Test-Path -LiteralPath $skillsDir -PathType Container) {
    foreach ($skillDir in (Get-ChildItem -LiteralPath $skillsDir -Directory)) {
        $skillName = $skillDir.Name
        $script:TOTAL_CHECKS++
        $skillMd = Join-Path $skillDir.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $skillMd -PathType Leaf) {
            Write-SuccessMessage "${skillName}/SKILL.md 존재"
            $script:PASSED_CHECKS++
        }
        else {
            Write-WarningMessage "${skillName}/SKILL.md 없음"
            $script:FAILED_CHECKS++
        }
    }
}

$rulesBase = Join-Path $BackupDir 'project' '.claude' 'rules'
if (Test-Path -LiteralPath $rulesBase -PathType Container) {
    Test-DirExists (Join-Path $rulesBase 'coding')             'rules/coding' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'operations')         'rules/operations' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'project-management') 'rules/project-management' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'workflow')           'rules/workflow' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'api')                'rules/api' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'core')               'rules/core' | Out-Null
}

# ── Script verification ──────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "스크립트 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists     (Join-Path $BackupDir 'scripts' 'install.sh') 'install.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'install.sh') 'install.sh 실행 권한' | Out-Null

Test-FileExists     (Join-Path $BackupDir 'scripts' 'backup.sh')  'backup.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'backup.sh')  'backup.sh 실행 권한' | Out-Null

Test-FileExists     (Join-Path $BackupDir 'scripts' 'sync.sh')    'sync.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'sync.sh')    'sync.sh 실행 권한' | Out-Null

# ── npm package verification (optional) ──────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "npm 패키지 검증 (선택사항)"
Write-Host "======================================================"
Write-Host ""

Test-NpmPackage 'ccstatusline'    'ccstatusline (Statusline 디스플레이)' | Out-Null
Test-NpmPackage 'claude-limitline' 'claude-limitline (사용량 표시)' | Out-Null

if ($script:WARNING_CHECKS -gt 0) {
    Write-Host ""
    Write-InfoMessage "누락된 npm 패키지 설치:"
    Write-Host "    npm install -g ccstatusline claude-limitline"
}

# ── Documentation verification ───────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "문서 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'README.md')    'README.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'QUICKSTART.md') 'QUICKSTART.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'HOOKS.md')      'HOOKS.md (Hook 가이드)' | Out-Null

# ── Import syntax verification ───────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "Import 문법 검증 (@import syntax)"
Write-Host "======================================================"
Write-Host ""

$importCheckFiles = @(
    (Join-Path $BackupDir 'global'  'CLAUDE.md')
    (Join-Path $BackupDir 'project' 'CLAUDE.md')
)

foreach ($checkFile in $importCheckFiles) {
    if (Test-Path -LiteralPath $checkFile -PathType Leaf) {
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $checkFile) {
            $parent = Split-Path (Split-Path $checkFile) -Leaf
            $name   = Split-Path $checkFile -Leaf
            Write-SuccessMessage "${parent}/${name} import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

# SKILL.md import syntax verification
$skillsDirProject = Join-Path $BackupDir 'project' '.claude' 'skills'
if (Test-Path -LiteralPath $skillsDirProject -PathType Container) {
    foreach ($sf in (Get-ChildItem -LiteralPath $skillsDirProject -Recurse -Filter 'SKILL.md')) {
        $skillName = $sf.Directory.Name
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $sf.FullName) {
            Write-SuccessMessage "skills/${skillName}/SKILL.md import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

$pluginSkillsDir = Join-Path $BackupDir 'plugin' 'skills'
if (Test-Path -LiteralPath $pluginSkillsDir -PathType Container) {
    foreach ($sf in (Get-ChildItem -LiteralPath $pluginSkillsDir -Recurse -Filter 'SKILL.md')) {
        $skillName = $sf.Directory.Name
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $sf.FullName) {
            Write-SuccessMessage "plugin/skills/${skillName}/SKILL.md import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

# ── System sync verification ─────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "시스템 동기화 검증 (source vs ~/.claude/)"
Write-Host "======================================================"
Write-Host ""

$SYNC_TOTAL = 0
$SYNC_OK    = 0
$SYNC_DIFF  = 0
$SYNC_MISS  = 0

function Test-SyncFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label
    )

    $script:SYNC_TOTAL++

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Write-WarningMessage "MISS: $Label"
        $script:SYNC_MISS++
    }
    else {
        $srcContent = Get-Content -LiteralPath $Source -ErrorAction SilentlyContinue
        $dstContent = Get-Content -LiteralPath $Destination -ErrorAction SilentlyContinue
        $diff = Compare-Object $srcContent $dstContent -ErrorAction SilentlyContinue
        if ($null -eq $diff -or $diff.Count -eq 0) {
            Write-SuccessMessage "SYNC: $Label"
            $script:SYNC_OK++
        }
        else {
            Write-ErrorMessage "DIFF: $Label"
            $script:SYNC_DIFF++
        }
    }
}

$GlobalDst = Join-Path $HOME '.claude'

# Global config files
Write-InfoMessage "글로벌 설정 파일 동기화:"
foreach ($f in @('CLAUDE.md', 'commit-settings.md', 'settings.json', '.claudeignore')) {
    $src = Join-Path $BackupDir 'global' $f
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Test-SyncFile -Source $src -Destination (Join-Path $GlobalDst $f) -Label $f
    }
}

# Global skills
Write-Host ""
Write-InfoMessage "글로벌 스킬 동기화:"
$globalSkillsDir = Join-Path $BackupDir 'global' 'skills'
if (Test-Path -LiteralPath $globalSkillsDir -PathType Container) {
    foreach ($srcFile in (Get-ChildItem -LiteralPath $globalSkillsDir -Recurse -Filter '*.md' | Sort-Object FullName)) {
        $rel = $srcFile.FullName.Substring($globalSkillsDir.Length + 1)
        Test-SyncFile -Source $srcFile.FullName -Destination (Join-Path $GlobalDst 'skills' $rel) -Label "skills/$rel"
    }
}

# Global hooks
Write-Host ""
Write-InfoMessage "글로벌 Hook 스크립트 동기화:"
$globalHooksDir = Join-Path $BackupDir 'global' 'hooks'
if (Test-Path -LiteralPath $globalHooksDir -PathType Container) {
    foreach ($srcFile in (Get-ChildItem -LiteralPath $globalHooksDir -Filter '*.sh')) {
        $base = $srcFile.Name
        Test-SyncFile -Source $srcFile.FullName -Destination (Join-Path $GlobalDst 'hooks' $base) -Label "hooks/$base"
    }
}

# Sync summary
Write-Host ""
Write-Host "  ─────────────────────────────────────────"
Write-Host "  동기화 검사:   ${SYNC_TOTAL}개"
Write-Host "  일치:          ${SYNC_OK}개" -ForegroundColor Green
if ($SYNC_DIFF -gt 0) {
    Write-Host "  불일치:        ${SYNC_DIFF}개" -ForegroundColor Red
}
if ($SYNC_MISS -gt 0) {
    Write-Host "  미설치:        ${SYNC_MISS}개" -ForegroundColor Yellow
}
Write-Host "  ─────────────────────────────────────────"

if ($SYNC_DIFF -gt 0 -or $SYNC_MISS -gt 0) {
    Write-Host ""
    Write-WarningMessage "시스템이 소스와 동기화되지 않았습니다."
    Write-InfoMessage "동기화 방법: ./scripts/install.sh (옵션 1: 글로벌 설정)"
}

# Add sync failures to main failure count
$script:FAILED_CHECKS += ($SYNC_DIFF + $SYNC_MISS)
$script:PASSED_CHECKS += $SYNC_OK
$script:TOTAL_CHECKS  += $SYNC_TOTAL

# ── Statistics ───────────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "통계 정보"
Write-Host "======================================================"
Write-Host ""

$totalFiles = (Get-ChildItem -LiteralPath $BackupDir -Recurse -File -ErrorAction SilentlyContinue).Count
Write-InfoMessage "총 파일 수: $totalFiles"

# Total size
$totalBytes = (Get-ChildItem -LiteralPath $BackupDir -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
if ($totalBytes -ge 1MB) {
    $totalSize = '{0:N1}M' -f ($totalBytes / 1MB)
}
elseif ($totalBytes -ge 1KB) {
    $totalSize = '{0:N1}K' -f ($totalBytes / 1KB)
}
else {
    $totalSize = "${totalBytes}B"
}
Write-InfoMessage "전체 크기: $totalSize"

$mdCount = (Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter '*.md' -ErrorAction SilentlyContinue).Count
$shCount = (Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter '*.sh' -ErrorAction SilentlyContinue).Count
Write-InfoMessage "Markdown 파일: $mdCount"
Write-InfoMessage "Shell 스크립트: $shCount"

# ── Verification result summary ──────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "검증 결과 요약"
Write-Host "======================================================"
Write-Host ""

Write-Host "  총 검사 항목:   $($script:TOTAL_CHECKS)"
Write-Host "  통과:          $($script:PASSED_CHECKS)"
Write-Host "  실패:          $($script:FAILED_CHECKS)"
Write-Host "  경고 (선택사항): $($script:WARNING_CHECKS)"

if ($script:TOTAL_CHECKS -gt 0) {
    $successRate = [math]::Floor($script:PASSED_CHECKS * 100 / $script:TOTAL_CHECKS)
}
else {
    $successRate = 0
}

Write-Host ""
if ($script:FAILED_CHECKS -eq 0) {
    Write-SuccessMessage "모든 검증 통과! (100%)"
    Write-Host ""
    Write-InfoMessage "백업이 완전하고 사용 가능합니다."
    Write-Host ""
    Write-Host "다음 단계:"
    Write-Host "  1. 다른 시스템에 복사"
    Write-Host "  2. ./scripts/install.sh 실행"
    exit 0
}
else {
    Write-WarningMessage "일부 검증 실패 (성공률: ${successRate}%)"
    Write-Host ""
    Write-InfoMessage "누락된 파일이 있습니다. 백업을 다시 생성하세요:"
    Write-Host "  ./scripts/backup.sh"
    exit 1
}
