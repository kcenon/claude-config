#Requires -Version 7.0
#
# cleanup_branches.ps1
#
# 지정된 경로(또는 현재 디렉토리)의 모든 Git 저장소에서
# main 브랜치를 제외한 모든 로컬 브랜치를 삭제하고
# main 브랜치를 최신으로 pull하는 스크립트
#
# 사용법:
#   ./cleanup_branches.ps1              # 현재 디렉토리의 모든 Git 저장소 대상
#   ./cleanup_branches.ps1 -Path <경로> # 지정된 경로의 모든 Git 저장소 대상
#   ./cleanup_branches.ps1 -Json        # JSON 결과 출력
#   ./cleanup_branches.ps1 -Quiet       # 최소 출력
#   ./cleanup_branches.ps1 -Help        # 도움말 표시
#

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

# =============================================================================
# Global state
# =============================================================================
$script:IsTTY = Test-InteractiveTerminal
$script:SuccessProjects = [System.Collections.Generic.List[string]]::new()
$script:FailedProjects = [System.Collections.Generic.List[string]]::new()
$script:SkippedProjects = [System.Collections.Generic.List[string]]::new()

# =============================================================================
# Helper functions
# =============================================================================
function Print-Error {
    param([string]$Message)
    Write-Host "$(if ($script:IsTTY) { "`u{2717}" } else { 'x' }) $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "$(if ($script:IsTTY) { "`u{26A0}" } else { '!' }) $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    if ($Json -or $Quiet) { return }
    Write-Host "$(if ($script:IsTTY) { "`u{2139}" } else { 'i' }) $Message" -ForegroundColor Cyan
}

function Print-Detail {
    param([string]$Message, [string]$Color)
    if ($Json -or $Quiet) { return }
    if ($Color) {
        Write-Host $Message -ForegroundColor $Color
    } else {
        Write-Host $Message
    }
}

# 도움말 출력
function Show-Help {
    if (-not $Json -and -not $Quiet) {
        Write-Host ''
        Write-Host "`u{2554}$('=' * 63)`u{2557}" -ForegroundColor Green
        Write-Host "`u{2551}       Git 브랜치 정리 및 main 브랜치 업데이트 스크립트        `u{2551}" -ForegroundColor Green
        Write-Host "`u{255A}$('=' * 63)`u{255D}" -ForegroundColor Green
        Write-Host ''
    }
    Write-Host ''
    Write-Host '사용법:' -ForegroundColor Cyan
    Write-Host "  $($MyInvocation.ScriptName)                  현재 디렉토리의 모든 Git 저장소에 대해 작업"
    Write-Host "  $($MyInvocation.ScriptName) -Path <경로>     지정된 경로의 모든 Git 저장소에 대해 작업"
    Write-Host "  $($MyInvocation.ScriptName) -Json            JSON 형식으로 결과 출력"
    Write-Host "  $($MyInvocation.ScriptName) -Quiet           장식적 출력 억제"
    Write-Host "  $($MyInvocation.ScriptName) -Help            이 도움말 표시"
    Write-Host ''
    Write-Host '예시:' -ForegroundColor Cyan
    Write-Host "  ./cleanup_branches.ps1                  # 현재 디렉토리의 모든 Git 저장소"
    Write-Host "  ./cleanup_branches.ps1 -Path .          # 현재 디렉토리 (위와 동일)"
    Write-Host "  ./cleanup_branches.ps1 -Path ../projects # ../projects 경로의 모든 Git 저장소"
    Write-Host "  ./cleanup_branches.ps1 -Path ~/Sources   # ~/Sources 경로의 모든 Git 저장소"
    Write-Host "  ./cleanup_branches.ps1 -Json             # {`"success`":[...],`"failed`":[...],`"skipped`":[...]}"
    Write-Host ''
    Write-Host '동작:' -ForegroundColor Cyan
    Write-Host '  1. 지정된 경로에서 Git 저장소 자동 탐색'
    Write-Host '  2. 각 저장소로 이동'
    Write-Host '  3. 커밋되지 않은 변경사항 자동 stash'
    Write-Host '  4. main 브랜치로 체크아웃'
    Write-Host '  5. main을 제외한 모든 로컬 브랜치 삭제'
    Write-Host '  6. git pull origin main 으로 최신화'
    Write-Host ''
}

# =============================================================================
# Core logic
# =============================================================================
function Cleanup-Project {
    param([string]$ProjectPath)

    $projectName = Split-Path $ProjectPath -Leaf

    Print-Detail ''
    $line = [string]::new([char]0x2501, 58)
    Print-Detail "  $line" 'Blue'
    Print-Detail "  프로젝트: $projectName" 'Blue'
    Print-Detail "     경로: $ProjectPath" 'Blue'
    Print-Detail "  $line" 'Blue'

    # 디렉토리 존재 확인
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        Print-Warning "디렉토리가 존재하지 않습니다: $ProjectPath"
        $script:SkippedProjects.Add("$projectName (디렉토리 없음)")
        return $false
    }

    # Git 저장소인지 확인
    $gitDir = Join-Path $ProjectPath '.git'
    if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
        Print-Warning "Git 저장소가 아닙니다: $ProjectPath"
        $script:SkippedProjects.Add("$projectName (Git 저장소 아님)")
        return $false
    }

    Push-Location $ProjectPath
    try {
        # 현재 브랜치 확인
        $currentBranch = & git branch --show-current 2>$null
        Print-Detail "   현재 브랜치: $currentBranch"

        # 변경사항 확인
        $null = & git diff-index --quiet HEAD -- 2>$null
        if ($LASTEXITCODE -ne 0) {
            Print-Warning "커밋되지 않은 변경사항이 있습니다. stash 처리합니다. ($projectName)"
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            & git stash push -m "Auto-stash by cleanup_branches.ps1 at $timestamp" 2>$null | Out-Null
        }

        # main 또는 master 브랜치 확인
        $targetBranch = 'main'
        $hasMain = (& git show-ref --verify --quiet refs/heads/main 2>$null; $LASTEXITCODE -eq 0) -or
                   (& git show-ref --verify --quiet refs/remotes/origin/main 2>$null; $LASTEXITCODE -eq 0)
        if (-not $hasMain) {
            $hasMaster = (& git show-ref --verify --quiet refs/heads/master 2>$null; $LASTEXITCODE -eq 0) -or
                         (& git show-ref --verify --quiet refs/remotes/origin/master 2>$null; $LASTEXITCODE -eq 0)
            if ($hasMaster) {
                $targetBranch = 'master'
            } else {
                Print-Error "main 또는 master 브랜치가 존재하지 않습니다. ($projectName)"
                $script:FailedProjects.Add("$projectName (main/master 없음)")
                return $false
            }
        }

        # 대상 브랜치로 체크아웃
        Print-Detail "   -> $targetBranch 브랜치로 체크아웃" 'Green'
        & git checkout $targetBranch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Print-Error "$targetBranch 브랜치 체크아웃 실패 ($projectName)"
            $script:FailedProjects.Add("$projectName ($targetBranch 체크아웃 실패)")
            return $false
        }

        # 대상 브랜치를 제외한 모든 로컬 브랜치 목록 가져오기
        $branchOutput = & git branch 2>$null
        $branches = @($branchOutput | ForEach-Object { $_.Trim().TrimStart('* ') } |
            Where-Object { $_ -ne '' -and $_ -ne $targetBranch -and $_ -notmatch '^\*' })

        if ($branches.Count -gt 0) {
            Print-Detail "   -> 삭제할 브랜치:" 'Yellow'
            foreach ($branch in $branches) {
                Print-Detail "      - $branch"
            }

            # 브랜치 삭제
            foreach ($branch in $branches) {
                if (-not [string]::IsNullOrWhiteSpace($branch)) {
                    Print-Detail "   x 삭제: $branch" 'Red'
                    & git branch -D $branch 2>$null | Out-Null
                }
            }
        } else {
            Print-Detail '   v 삭제할 브랜치가 없습니다.' 'Green'
        }

        # 대상 브랜치 pull
        Print-Detail "   -> $targetBranch 브랜치 pull" 'Green'
        $pullResult = & git pull origin $targetBranch 2>&1
        if ($LASTEXITCODE -eq 0) {
            Print-Detail '   v pull 완료' 'Green'
            $script:SuccessProjects.Add($projectName)
        } else {
            Print-Warning "pull 실패 (원격 저장소 연결 문제일 수 있음) ($projectName)"
            $script:FailedProjects.Add("$projectName (pull 실패)")
            return $false
        }

        return $true
    }
    finally {
        Pop-Location
    }
}

function Find-GitRepos {
    param([string]$SearchPath)
    $repos = [System.Collections.Generic.List[string]]::new()

    # 첫 번째 레벨 디렉토리만 검색 (깊은 탐색 방지)
    foreach ($dir in (Get-ChildItem -Path $SearchPath -Directory -ErrorAction SilentlyContinue)) {
        $gitDir = Join-Path $dir.FullName '.git'
        if (Test-Path -LiteralPath $gitDir -PathType Container) {
            $repos.Add($dir.FullName)
        }
    }

    return $repos
}

# =============================================================================
# Main logic
# =============================================================================
if ($Help) {
    Show-Help
    exit 0
}

# Resolve target path
$targetPath = if ([string]::IsNullOrWhiteSpace($Path)) {
    (Get-Location).Path
} elseif ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
} else {
    $resolved = Join-Path (Get-Location).Path $Path
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        (Resolve-Path -LiteralPath $resolved).Path
    } else {
        Print-Error "경로를 찾을 수 없습니다: $Path"
        exit 1
    }
}

if (-not $Json -and -not $Quiet) {
    Write-Host ''
    Write-Host "`u{2554}$('=' * 63)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}       Git 브랜치 정리 및 main 브랜치 업데이트 스크립트        `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 63)`u{255D}" -ForegroundColor Green
    Write-Host ''
}

Print-Detail "대상 경로: $targetPath" 'Cyan'
Print-Detail 'Git 저장소 검색 중...'

# 지정된 경로에서 Git 저장소 찾기
$repos = Find-GitRepos -SearchPath $targetPath

if ($repos.Count -eq 0) {
    Print-Warning '지정된 경로에서 Git 저장소를 찾을 수 없습니다.'
    if ($Json) {
        [ordered]@{
            success = @()
            failed  = @()
            skipped = @()
            counts  = [ordered]@{ success = 0; failed = 0; skipped = 0 }
        } | ConvertTo-Json -Depth 3
    }
    exit 1
}

$repoCount = $repos.Count
Print-Detail "발견된 Git 저장소: ${repoCount}개" 'Green'
Print-Detail ''

# 각 저장소 처리
foreach ($repoPath in $repos) {
    if (-not [string]::IsNullOrWhiteSpace($repoPath)) {
        $null = Cleanup-Project -ProjectPath $repoPath
    }
}

# Output
if ($Json) {
    [ordered]@{
        success = @($script:SuccessProjects)
        failed  = @($script:FailedProjects)
        skipped = @($script:SkippedProjects)
        counts  = [ordered]@{
            success = $script:SuccessProjects.Count
            failed  = $script:FailedProjects.Count
            skipped = $script:SkippedProjects.Count
        }
    } | ConvertTo-Json -Depth 3
} elseif ($Quiet) {
    Write-Output "success: $($script:SuccessProjects.Count), failed: $($script:FailedProjects.Count), skipped: $($script:SkippedProjects.Count)"
} else {
    # 결과 요약
    Write-Host ''
    Write-Host "`u{2554}$('=' * 63)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}                         결과 요약                             `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 63)`u{255D}" -ForegroundColor Green
    Write-Host ''

    Write-Host "v 성공: $($script:SuccessProjects.Count)개" -ForegroundColor Green
    foreach ($p in $script:SuccessProjects) {
        Write-Host "   - $p"
    }

    if ($script:FailedProjects.Count -gt 0) {
        Write-Host ''
        Write-Host "x 실패: $($script:FailedProjects.Count)개" -ForegroundColor Red
        foreach ($p in $script:FailedProjects) {
            Write-Host "   - $p"
        }
    }

    if ($script:SkippedProjects.Count -gt 0) {
        Write-Host ''
        Write-Host "! 건너뜀: $($script:SkippedProjects.Count)개" -ForegroundColor Yellow
        foreach ($p in $script:SkippedProjects) {
            Write-Host "   - $p"
        }
    }

    Write-Host ''
    Write-Host '작업 완료!' -ForegroundColor Blue
    Write-Host ''
}
