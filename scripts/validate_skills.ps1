#Requires -Version 7.0

# Claude Configuration Skills Validation Tool
# ===========================================
# SKILL.md 파일의 형식과 무결성을 검증하는 스크립트
# Ported from validate_skills.sh

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

Write-Banner -Title 'Claude Configuration Skills Validation Tool'

# Counters
$script:TOTAL_CHECKS   = 0
$script:PASSED_CHECKS  = 0
$script:FAILED_CHECKS  = 0
$script:WARNING_CHECKS = 0

# ── Result recording helpers ─────────────────────────────────

function Record-Pass {
    $script:TOTAL_CHECKS++
    $script:PASSED_CHECKS++
}

function Record-Fail {
    $script:TOTAL_CHECKS++
    $script:FAILED_CHECKS++
}

function Record-Warning {
    $script:WARNING_CHECKS++
}

# ── YAML frontmatter extraction ──────────────────────────────

function Get-Frontmatter {
    <#
    .SYNOPSIS
        Extracts text between the first and second '---' delimiters.
    #>
    param([string]$FilePath)

    $lines = Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -eq 0) { return '' }

    $inFrontmatter = $false
    $fmLines = @()
    $delimCount = 0

    foreach ($line in $lines) {
        if ($line -eq '---') {
            $delimCount++
            if ($delimCount -eq 1) {
                $inFrontmatter = $true
                continue
            }
            if ($delimCount -eq 2) {
                break
            }
        }
        if ($inFrontmatter) {
            $fmLines += $line
        }
    }

    return ($fmLines -join "`n")
}

function Get-FrontmatterField {
    <#
    .SYNOPSIS
        Extracts a field value from YAML frontmatter text.
    #>
    param(
        [string]$Content,
        [string]$Field
    )

    foreach ($line in ($Content -split "`n")) {
        if ($line -match "^${Field}:\s*(.*)$") {
            return $Matches[1].Trim()
        }
    }
    return ''
}

# ── SKILL.md validation function ─────────────────────────────

function Test-SkillFile {
    param([string]$SkillFile)

    $relativePath = $SkillFile
    if ($SkillFile.StartsWith($BackupDir)) {
        $relativePath = $SkillFile.Substring($BackupDir.Length + 1)
    }
    $skillErrors = 0

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-InfoMessage "검증 중: $relativePath"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    $lines = Get-Content -LiteralPath $SkillFile -ErrorAction SilentlyContinue

    # 1. YAML frontmatter existence check
    if (-not $lines -or $lines[0] -ne '---') {
        Write-ErrorMessage "YAML frontmatter 없음 (첫 줄이 '---'가 아님)"
        Record-Fail
        $skillErrors++
    }
    else {
        Write-SuccessMessage "YAML frontmatter 시작 확인"
        Record-Pass
    }

    # Find frontmatter end marker
    $frontmatterEnd = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') {
            $frontmatterEnd = $i + 1  # 1-based line number
            break
        }
    }

    if ($frontmatterEnd -eq -1) {
        Write-ErrorMessage "YAML frontmatter 종료 마커 없음"
        Record-Fail
        $skillErrors++
    }
    else {
        Write-SuccessMessage "YAML frontmatter 종료 확인 (${frontmatterEnd}번째 줄)"
        Record-Pass
    }

    # Extract frontmatter
    $frontmatter = Get-Frontmatter $SkillFile

    # 2. name field validation
    $name = Get-FrontmatterField -Content $frontmatter -Field 'name'

    if ([string]::IsNullOrEmpty($name)) {
        Write-ErrorMessage "name 필드 없음"
        Record-Fail
        $skillErrors++
    }
    else {
        # name format validation: lowercase, digits, hyphens only
        if ($name -notmatch '^[a-z0-9-]+$') {
            Write-ErrorMessage "name 형식 오류: '$name' (소문자, 숫자, 하이픈만 허용)"
            Record-Fail
            $skillErrors++
        }
        else {
            Write-SuccessMessage "name 형식 유효: '$name'"
            Record-Pass
        }

        # name length validation (max 64 characters)
        $nameLength = $name.Length
        if ($nameLength -gt 64) {
            Write-ErrorMessage "name 길이 초과: ${nameLength}자 (최대 64자)"
            Record-Fail
            $skillErrors++
        }
        else {
            Write-SuccessMessage "name 길이 유효: ${nameLength}자"
            Record-Pass
        }
    }

    # 3. description field validation
    $description = Get-FrontmatterField -Content $frontmatter -Field 'description'

    if ([string]::IsNullOrEmpty($description)) {
        Write-ErrorMessage "description 필드 없음"
        Record-Fail
        $skillErrors++
    }
    else {
        $descLength = $description.Length
        if ($descLength -gt 1024) {
            Write-ErrorMessage "description 길이 초과: ${descLength}자 (최대 1024자)"
            Record-Fail
            $skillErrors++
        }
        else {
            Write-SuccessMessage "description 유효: ${descLength}자"
            Record-Pass
        }

        # Description minimum length check (trigger quality)
        if ($descLength -lt 100) {
            Write-WarningMessage "description이 스킬 트리거에 불충분할 수 있음 (${descLength}자 < 100)"
            Record-Warning
        }
    }

    # 4. File line count validation (recommended: 500 lines or fewer)
    $lineCount = $lines.Count
    if ($lineCount -gt 500) {
        Write-WarningMessage "파일 길이 경고: ${lineCount}줄 (권장: 500줄 이하)"
        Record-Warning
    }
    else {
        Write-SuccessMessage "파일 길이 적정: ${lineCount}줄"
        Record-Pass
    }

    # 5. reference directory check
    $skillDir = Split-Path $SkillFile
    $refDir = Join-Path $skillDir 'reference'
    if (Test-Path -LiteralPath $refDir -PathType Container) {
        $refCount = (Get-ChildItem -LiteralPath $refDir -Filter '*.md' -ErrorAction SilentlyContinue).Count
        Write-SuccessMessage "reference 디렉토리 존재: ${refCount}개 문서"
        Record-Pass

        # Reference directory orphan check
        $refItems = Get-ChildItem -LiteralPath $refDir -ErrorAction SilentlyContinue
        if ($refItems.Count -gt 0) {
            $fileContent = Get-Content -LiteralPath $SkillFile -Raw -ErrorAction SilentlyContinue
            if ($fileContent -notmatch 'reference/') {
                Write-WarningMessage "reference/ 디렉토리가 존재하지만 SKILL.md에서 참조하지 않음 (고아 가능성)"
                Record-Warning
            }
        }
    }
    else {
        # Only warn about missing reference/ for skills approaching the 500-line limit.
        if ($lineCount -ge 250) {
            Write-WarningMessage "reference 디렉토리 없음 (${lineCount}줄 -- reference/ 분할 검토 권장)"
            Record-Warning
        }
    }

    # 6. 프론트매터 대 본문 일관성 (drift)
    $fileContent = Get-Content -LiteralPath $SkillFile -Raw -ErrorAction SilentlyContinue
    if ($null -eq $fileContent) { $fileContent = '' }

    if ($frontmatter -match '(?m)^(max_iterations|halt_condition):') {
        if ($fileContent -notmatch '(?i)(loop|retry|iteration|poll)') {
            Write-WarningMessage "max_iterations/halt_condition 선언되었으나 본문에 loop/retry/iteration/poll 참조 없음"
            Record-Warning
        }
        else {
            Write-SuccessMessage "loop 메타데이터 본문 일관성 확인"
            Record-Pass
        }
    }

    if ($frontmatter -match '(?m)^loop_safe:\s*false') {
        if ($fileContent -notmatch '(?m)^#+\s+.*([Ss]ide.[Ee]ffect|[Ii]dempoten|[Ll]oop.?[Ss]afety|[Nn]on-idempoten)') {
            Write-WarningMessage "loop_safe: false 선언되었으나 side-effect/idempoten 섹션 없음"
            Record-Warning
        }
        else {
            Write-SuccessMessage "loop_safe: false 본문 일관성 확인"
            Record-Pass
        }
    }

    return $skillErrors
}

# ── CLAUDE.md routing audit ──────────────────────────────────
# Classify non-blank, non-heading lines outside the footer as routing or prose.
# Fail if prose / (routing + prose) exceeds AUDIT_PROSE_RATIO (default 0.30).
function Test-ClaudeMd {
    param([string]$FilePath)

    $relativePath = $FilePath
    if ($FilePath.StartsWith($BackupDir)) {
        $relativePath = $FilePath.Substring($BackupDir.Length + 1)
    }

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-InfoMessage "라우팅 감사: $relativePath"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-WarningMessage "파일 없음 -- 건너뜀: $relativePath"
        Record-Warning
        return 0
    }

    $routing = 0
    $prose = 0
    $inInvariants = $false

    $lines = Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue
    foreach ($rawLine in $lines) {
        $line = $rawLine -replace "`r$", ""

        # First '---' treated as footer separator -- stop scanning body
        # (harness CLAUDE.md files do not use YAML frontmatter)
        if ($line -eq '---') { break }

        # Skip blank lines
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Headings: track invariants zone, do not count
        if ($line -match '^#+\s') {
            if ($line -match '[Ii]nvariant') {
                $inInvariants = $true
            }
            elseif ($line -match '^##\s') {
                $inInvariants = $false
            }
            continue
        }

        # Inside invariants block: all lines count as routing-equivalent
        if ($inInvariants) {
            $routing++
            continue
        }

        # Classify body lines
        if (($line -match '^\s*[-*+]\s') -or
            ($line -match '^\|') -or
            ($line -match '^\s*@\./') -or
            ($line -match '^>')) {
            $routing++
        }
        else {
            $prose++
        }
    }

    $total = $routing + $prose
    if ($total -eq 0) {
        Write-WarningMessage "검사 가능한 콘텐츠 없음: $relativePath"
        Record-Warning
        return 0
    }

    $threshold = 0.30
    if ($env:AUDIT_PROSE_RATIO) {
        $parsed = 0.0
        if ([double]::TryParse($env:AUDIT_PROSE_RATIO, [ref]$parsed) -and $parsed -gt 0) {
            $threshold = $parsed
        }
    }

    $ratio = $prose / $total
    $ratioPct = [math]::Round($ratio * 100, 1)
    $thresholdPct = [math]::Round($threshold * 100, 0)

    if ($ratio -gt $threshold) {
        Write-ErrorMessage ("산문 비율 초과: {0}% > {1}% (prose={2}, routing/invariant={3})" -f $ratioPct, $thresholdPct, $prose, $routing)
        Write-InfoMessage "힌트: 절차 규칙은 docs/, global/skills/, 또는 프로젝트 rule 파일로 이동"
        Record-Fail
        return 1
    }
    else {
        Write-SuccessMessage ("라우팅 규율 유효: prose={0}, routing/invariant={1}, ratio={2}% (임계 {3}%)" -f $prose, $routing, $ratioPct, $thresholdPct)
        Record-Pass
        return 0
    }
}

# ── Main logic ───────────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "Skills 디렉토리 검색"
Write-Host "======================================================"
Write-Host ""

# Skills directory locations
$skillDirs = @(
    (Join-Path $BackupDir 'project' '.claude' 'skills')
    (Join-Path $BackupDir 'plugin' 'skills')
    (Join-Path $BackupDir 'plugin-lite' 'skills')
    (Join-Path $BackupDir 'global' 'skills')
)

$skillFiles = @()
foreach ($dir in $skillDirs) {
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $rel = $dir
        if ($dir.StartsWith($BackupDir)) { $rel = $dir.Substring($BackupDir.Length + 1) }
        Write-InfoMessage "디렉토리 발견: $rel"
        $found = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'SKILL.md' -ErrorAction SilentlyContinue
        foreach ($f in $found) {
            $skillFiles += $f.FullName
        }
    }
}

if ($skillFiles.Count -eq 0) {
    Write-ErrorMessage "SKILL.md 파일을 찾을 수 없습니다"
    exit 1
}

Write-InfoMessage "총 $($skillFiles.Count)개의 SKILL.md 파일 발견"

# Validate each SKILL.md file
$totalSkillErrors = 0
foreach ($skillFile in $skillFiles) {
    $errors = Test-SkillFile $skillFile
    $totalSkillErrors += $errors
}

# ── CLAUDE.md routing audit ──────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "CLAUDE.md 라우팅 감사"
Write-Host "======================================================"

$claudeMdFiles = @(
    (Join-Path $BackupDir 'global' 'CLAUDE.md')
    (Join-Path $BackupDir 'project' 'CLAUDE.md')
    (Join-Path $BackupDir 'enterprise' 'CLAUDE.md')
)

foreach ($claudeMd in $claudeMdFiles) {
    $err = Test-ClaudeMd -FilePath $claudeMd
    $totalSkillErrors += $err
}

# ── YAML syntax validation ───────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "YAML 구문 검증"
Write-Host "======================================================"
Write-Host ""

# Use PowerShell-based YAML validation (parse frontmatter manually)
# Since PowerShell doesn't have a built-in YAML parser, we do basic structural validation
foreach ($skillFile in $skillFiles) {
    $relativePath = $skillFile
    if ($skillFile.StartsWith($BackupDir)) {
        $relativePath = $skillFile.Substring($BackupDir.Length + 1)
    }

    $lines = Get-Content -LiteralPath $skillFile -ErrorAction SilentlyContinue
    $valid = $true

    # Check frontmatter structure
    if (-not $lines -or $lines[0] -ne '---') {
        $valid = $false
    }
    else {
        $endFound = $false
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -eq '---') {
                $endFound = $true
                break
            }
        }
        if (-not $endFound) { $valid = $false }
    }

    if ($valid) {
        # Validate that key: value pairs have proper structure
        $fm = Get-Frontmatter $skillFile
        $hasName = ($fm -match '(?m)^name:')
        $hasDesc = ($fm -match '(?m)^description:')
        if ($hasName -and $hasDesc) {
            Write-SuccessMessage "${relativePath}: YAML 구문 유효"
            Record-Pass
        }
        else {
            Write-ErrorMessage "${relativePath}: YAML 필수 필드 누락"
            Record-Fail
        }
    }
    else {
        Write-ErrorMessage "${relativePath}: YAML 구문 오류"
        Record-Fail
    }
}

# ── Schema-based validation against canonical Claude Code 2026 spec ──
# Soft-fail (warn-only) so this incremental check can land without breaking
# downstream consumers. Tighten by removing -WarnOnly after a grace period.

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "공식 스펙 검증 (spec_lint)"
Write-Host "======================================================"
Write-Host ""

$specLintPs1 = Join-Path $ScriptDir 'spec_lint.ps1'
if (Test-Path -LiteralPath $specLintPs1) {
    & $specLintPs1 -WarnOnly -Quiet
    if ($LASTEXITCODE -eq 0) {
        Write-SuccessMessage "spec_lint: 위반 사항 없음"
        Record-Pass
    }
    else {
        Write-WarningMessage "spec_lint: 위반 사항 발견 (warn-only)"
        Record-Warning
    }
}
else {
    Write-WarningMessage "spec_lint.ps1 누락 -- 스키마 검증 건너뜀"
    Record-Warning
}

# ── Validation result summary ────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "검증 결과 요약"
Write-Host "======================================================"
Write-Host ""

Write-Host "  총 검사 항목:   $($script:TOTAL_CHECKS)"
Write-Host "  통과:          $($script:PASSED_CHECKS)"
Write-Host "  실패:          $($script:FAILED_CHECKS)"
Write-Host "  경고:          $($script:WARNING_CHECKS)"

Write-Host ""
if ($script:FAILED_CHECKS -eq 0) {
    Write-SuccessMessage "모든 검증 통과!"
    if ($script:WARNING_CHECKS -gt 0) {
        Write-WarningMessage "$($script:WARNING_CHECKS)개의 경고가 있습니다. 권장사항을 확인하세요."
    }
    exit 0
}
else {
    Write-ErrorMessage "$($script:FAILED_CHECKS)개의 검증 실패"
    Write-Host ""
    Write-InfoMessage "SKILL.md 형식 요구사항:"
    Write-Host "  - YAML frontmatter: '---' 로 시작하고 끝나야 함"
    Write-Host "  - name: 소문자, 숫자, 하이픈만 허용 (최대 64자)"
    Write-Host "  - description: 비어있지 않아야 함 (최대 1024자)"
    exit 1
}
