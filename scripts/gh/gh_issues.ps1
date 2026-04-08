#Requires -Version 7.0
#
# gh_issues.ps1
#
# Fetch and display GitHub Issues across repositories
# using the gh CLI with colored table output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_issues.ps1                           # All repos for authenticated user
#   ./gh_issues.ps1 -Repo owner/repo          # Specific repo
#   ./gh_issues.ps1 -State all -Limit 5       # All states, 5 per repo
#   ./gh_issues.ps1 -Json                     # JSON output
#   ./gh_issues.ps1 -Quiet                    # Minimal output
#   ./gh_issues.ps1 -Help                     # Show help
#

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$User,
    [ValidateSet('open', 'closed', 'all')]
    [string]$State = 'open',
    [int]$Limit = 30,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

# =============================================================================
# Global statistics
# =============================================================================
$script:TotalIssues = 0
$script:TotalRepos = 0
$script:FailedRepos = 0
$script:SkippedRepos = 0

# =============================================================================
# Helper functions
# =============================================================================
$script:IsTTY = Test-InteractiveTerminal

function Print-Success {
    param([string]$Message)
    if ($Json -or $Quiet) { return }
    Write-Host "$(if ($script:IsTTY) { "`u{2713}" } else { 'v' }) $Message" -ForegroundColor Green
}

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

function Print-Section {
    param([string]$Title)
    if ($Json -or $Quiet) { return }
    Write-Host ''
    $line = [string]::new([char]0x2501, 70)
    Write-Host "  $line" -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host "  $line" -ForegroundColor Blue
}

function Print-Header {
    if ($Json -or $Quiet) { return }
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}              GitHub Issues List Fetcher                             `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
}

function Show-Help {
    Print-Header
    Write-Host 'Usage:' -ForegroundColor Cyan
    Write-Host "  $($MyInvocation.ScriptName) [OPTIONS]"
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Cyan
    Write-Host '  -Repo REPO      Fetch issues from a specific repo (owner/repo format)'
    Write-Host '  -User USER      Fetch from a specific user''s repos (default: authenticated user)'
    Write-Host '  -State STATE    Filter by state: open, closed, all (default: open)'
    Write-Host '  -Limit LIMIT    Max issues per repo (default: 30)'
    Write-Host '  -Json           Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet          Suppress decorative output'
    Write-Host '  -Help           Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_issues.ps1                                # All repos, open issues'
    Write-Host '  ./gh_issues.ps1 -Repo kcenon/thread_system     # Specific repo'
    Write-Host '  ./gh_issues.ps1 -State all -Limit 10           # All states, 10 per repo'
    Write-Host '  ./gh_issues.ps1 -User octocat                  # Specific user''s repos'
    Write-Host '  ./gh_issues.ps1 -Json                          # [{"repo":"...","issues":[...]}]'
    Write-Host '  ./gh_issues.ps1 -Repo owner/repo -Json         # Direct issues JSON array'
    Write-Host ''
}

# =============================================================================
# Core logic
# =============================================================================
function Detect-CurrentUser {
    $userRaw = & gh api user --jq '.login' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($userRaw)) {
        Print-Error 'Failed to detect current user. Check gh auth status.'
        exit 1
    }
    return $userRaw.Trim()
}

function Fetch-UserRepos {
    param([string]$UserName)
    $reposRaw = & gh repo list $UserName --json nameWithOwner --jq '.[].nameWithOwner' --limit 1000 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to fetch repos for user: $UserName"
        exit 1
    }
    return ($reposRaw -split "`n" | Where-Object { $_ -ne '' })
}

function Fetch-Issues {
    param([string]$RepoName, [string]$IssueState, [int]$IssueLimit)
    $issuesRaw = & gh issue list --repo $RepoName --state $IssueState --limit $IssueLimit `
        --json number,title,state,labels,createdAt 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($issuesRaw)) {
        return @()
    }
    $parsed = $issuesRaw | ConvertFrom-Json
    return @($parsed)
}

function Truncate-String {
    param([string]$Str, [int]$MaxLen)
    if ($Str.Length -gt $MaxLen) {
        return $Str.Substring(0, $MaxLen - 3) + '...'
    }
    return $Str
}

# =============================================================================
# Display functions
# =============================================================================
function Display-TableHeader {
    if ($Json -or $Quiet) { return }
    $fmt = '  {0,-6} {1,-42} {2,-8} {3,-22} {4,-12}'
    Write-Host ($fmt -f '#', 'Title', 'State', 'Labels', 'Created') -ForegroundColor DarkGray
    Write-Host ($fmt -f '------', ('--' * 21), '--------', ('--' * 11), '------------') -ForegroundColor DarkGray
}

function Display-IssueRow {
    param([int]$IssueNumber, [string]$Title, [string]$IssueState, [string]$Labels, [string]$Created)
    if ($Json -or $Quiet) { return }

    $Title = Truncate-String $Title 40
    $Labels = Truncate-String $Labels 20
    $Created = if ($Created.Length -ge 10) { $Created.Substring(0, 10) } else { $Created }

    $stateColor = switch ($IssueState) {
        'OPEN'   { 'Green' }
        'CLOSED' { 'Red' }
        default  { 'Yellow' }
    }

    Write-Host -NoNewline ('  {0,-6} {1,-42} ' -f "#$IssueNumber", $Title)
    Write-Host -NoNewline ('{0,-8} ' -f $IssueState) -ForegroundColor $stateColor
    Write-Host -NoNewline ('{0,-22} ' -f $Labels)
    Write-Host $Created -ForegroundColor DarkGray
}

function Display-RepoIssues {
    param([string]$RepoName, [object[]]$Issues)

    $count = $Issues.Count
    if ($count -eq 0) {
        Print-Info "No issues found in $RepoName"
        $script:SkippedRepos++
        return
    }

    Print-Section "$RepoName  ($count issues)"
    Display-TableHeader

    foreach ($issue in $Issues) {
        $labelStr = if ($issue.labels -and $issue.labels.Count -gt 0) {
            ($issue.labels | ForEach-Object { $_.name }) -join ', '
        } else { '' }
        Display-IssueRow -IssueNumber $issue.number -Title $issue.title `
            -IssueState $issue.state -Labels $labelStr -Created $issue.createdAt
    }

    $script:TotalIssues += $count
    $script:TotalRepos++
}

function Display-Summary {
    if ($Json -or $Quiet) { return }
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}                            Summary                                 `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
    Write-Host "  Total issues:       $($script:TotalIssues)" -ForegroundColor Green
    Write-Host "  Repos scanned:      $($script:TotalRepos)" -ForegroundColor Blue
    if ($script:SkippedRepos -gt 0) {
        Write-Host "  Repos (no issues):  $($script:SkippedRepos)" -ForegroundColor Yellow
    }
    if ($script:FailedRepos -gt 0) {
        Write-Host "  Repos (failed):     $($script:FailedRepos)" -ForegroundColor Red
    }
    Write-Host ''
}

# =============================================================================
# Main logic
# =============================================================================
if ($Help) {
    Show-Help
    exit 0
}

# Validate prerequisites
if (-not (Test-Prerequisites @('gh'))) {
    exit 1
}

Print-Header

# Single repo mode
if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    Print-Info "Fetching issues from: $Repo (state: $State, limit: $Limit)"
    $issues = Fetch-Issues -RepoName $Repo -IssueState $State -IssueLimit $Limit

    if ($issues.Count -eq 0) {
        Print-Info "No issues found in $Repo"
        if ($Json) { Write-Output '[]' }
    } else {
        if ($Json) {
            # Single repo: output issues array directly
            $jsonIssues = @($issues | ForEach-Object {
                $labelNames = @()
                if ($_.labels) { $labelNames = @($_.labels | ForEach-Object { $_.name }) }
                [ordered]@{
                    number  = $_.number
                    title   = $_.title
                    state   = $_.state
                    labels  = $labelNames
                    created = $_.createdAt
                }
            })
            $jsonIssues | ConvertTo-Json -Depth 4
        } else {
            Display-RepoIssues -RepoName $Repo -Issues $issues
        }
    }

    Display-Summary
    exit 0
}

# Multi-repo mode
if ([string]::IsNullOrWhiteSpace($User)) {
    $User = Detect-CurrentUser
}

Print-Info "User: $User"
Print-Info "State: $State | Limit per repo: $Limit"
Print-Info 'Fetching repository list...'

$repos = Fetch-UserRepos -UserName $User
$repoCount = $repos.Count
Print-Info "Found $repoCount repositories. Scanning for issues..."

# JSON mode: accumulate results
$jsonAccumulator = [System.Collections.Generic.List[object]]::new()

foreach ($repoName in $repos) {
    if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

    $issues = @()
    try {
        $issues = Fetch-Issues -RepoName $repoName -IssueState $State -IssueLimit $Limit
    } catch {
        Print-Warning "Failed to fetch issues from $repoName"
        $script:FailedRepos++
        continue
    }

    if ($issues.Count -eq 0) {
        $script:SkippedRepos++
        continue
    }

    if ($Json) {
        $entry = @{
            repo   = $repoName
            issues = @($issues | ForEach-Object {
                $labelNames = @()
                if ($_.labels) { $labelNames = @($_.labels | ForEach-Object { $_.name }) }
                [ordered]@{
                    number  = $_.number
                    title   = $_.title
                    state   = $_.state
                    labels  = $labelNames
                    created = $_.createdAt
                }
            })
        }
        $jsonAccumulator.Add($entry)
    } else {
        Display-RepoIssues -RepoName $repoName -Issues $issues
    }

    # Rate limit protection
    Start-Sleep -Milliseconds 500
}

# Output
if ($Json) {
    $jsonAccumulator | ConvertTo-Json -Depth 5
} else {
    Display-Summary
}
