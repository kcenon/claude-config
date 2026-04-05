#Requires -Version 7.0
#
# gh_issue_read.ps1
#
# Read a GitHub Issue's description and comments
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_issue_read.ps1 -Number 42                            # Auto-detect repo
#   ./gh_issue_read.ps1 -Repo owner/repo -Number 42           # Specific repo
#   ./gh_issue_read.ps1 -Number 42 -NoComments                # Description only
#   ./gh_issue_read.ps1 -Number 42 -Json                      # JSON output
#   ./gh_issue_read.ps1 -Number 42 -Quiet                     # Minimal output
#   ./gh_issue_read.ps1 -Help                                  # Show help
#

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Number,
    [switch]$NoComments,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

# =============================================================================
# Helper functions
# =============================================================================
$script:IsTTY = Test-InteractiveTerminal

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

function Print-Header {
    if ($Json -or $Quiet) { return }
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}              GitHub Issue Reader                                    `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
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

function Print-Separator {
    if ($Json -or $Quiet) { return }
    $line = [string]::new([char]0x2500, 66)
    Write-Host "  $line" -ForegroundColor DarkGray
}

function Get-StateColor {
    param([string]$State)
    switch ($State) {
        'OPEN'   { return 'Green' }
        'CLOSED' { return 'Red' }
        default  { return 'Yellow' }
    }
}

function Show-Help {
    Print-Header
    Write-Host 'Usage:' -ForegroundColor Cyan
    Write-Host "  $($MyInvocation.ScriptName) [OPTIONS]"
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Cyan
    Write-Host '  -Repo REPO          Target repo (owner/repo). Auto-detects if omitted.'
    Write-Host '  -Number NUMBER      Issue number (required)'
    Write-Host '  -NoComments         Show only the issue description (skip comments)'
    Write-Host '  -Json               Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet              Suppress decorative output'
    Write-Host '  -Help               Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_issue_read.ps1 -Number 42                     # Auto-detect repo'
    Write-Host '  ./gh_issue_read.ps1 -Repo kcenon/thread_system -Number 10'
    Write-Host '  ./gh_issue_read.ps1 -Number 42 -NoComments         # Description only'
    Write-Host '  ./gh_issue_read.ps1 -Number 42 -Json                # Structured JSON'
    Write-Host ''
}

# =============================================================================
# JSON output function
# =============================================================================
function Output-IssueJson {
    param(
        [string]$RepoName,
        [string]$IssueNumber,
        [bool]$ShowComments
    )

    $issueRaw = & gh issue view $IssueNumber --repo $RepoName `
        --json number,title,state,body,author,labels,assignees,createdAt,updatedAt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to fetch issue #$IssueNumber from $RepoName"
        exit 1
    }
    $issue = $issueRaw | ConvertFrom-Json

    $labelNames = @()
    if ($issue.labels) { $labelNames = @($issue.labels | ForEach-Object { $_.name }) }
    $assigneeLogins = @()
    if ($issue.assignees) { $assigneeLogins = @($issue.assignees | ForEach-Object { $_.login }) }

    $output = [ordered]@{
        number    = $issue.number
        title     = $issue.title
        state     = $issue.state
        author    = $issue.author.login
        labels    = $labelNames
        assignees = $assigneeLogins
        body      = if ($issue.body) { $issue.body } else { '' }
        created   = $issue.createdAt
        updated   = $issue.updatedAt
    }

    if ($ShowComments) {
        $comments = @()
        try {
            $commentsRaw = & gh api "repos/$RepoName/issues/$IssueNumber/comments" 2>$null
            if ($LASTEXITCODE -eq 0 -and $commentsRaw) {
                $commentsParsed = $commentsRaw | ConvertFrom-Json
                $comments = @($commentsParsed | ForEach-Object {
                    @{
                        author  = $_.user.login
                        created = $_.created_at
                        body    = $_.body
                    }
                })
            }
        } catch { $comments = @() }
        $output['comments'] = $comments
    }

    $output | ConvertTo-Json -Depth 5
}

# =============================================================================
# Display functions
# =============================================================================
function Display-IssueDetail {
    param([string]$RepoName, [string]$IssueNumber)

    $issueRaw = & gh issue view $IssueNumber --repo $RepoName `
        --json number,title,state,body,author,labels,assignees,milestone,createdAt,updatedAt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to fetch issue #$IssueNumber from $RepoName"
        exit 1
    }
    $issue = $issueRaw | ConvertFrom-Json

    $title = $issue.title
    $state = $issue.state
    $author = $issue.author.login
    $created = if ($issue.createdAt.Length -ge 10) { $issue.createdAt.Substring(0, 10) } else { $issue.createdAt }
    $updated = if ($issue.updatedAt.Length -ge 10) { $issue.updatedAt.Substring(0, 10) } else { $issue.updatedAt }
    $body = if ($issue.body) { $issue.body } else { '(no description)' }
    $labelStr = if ($issue.labels -and $issue.labels.Count -gt 0) { ($issue.labels | ForEach-Object { $_.name }) -join ', ' } else { '-' }
    $assigneeStr = if ($issue.assignees -and $issue.assignees.Count -gt 0) { ($issue.assignees | ForEach-Object { $_.login }) -join ', ' } else { '-' }
    $milestoneName = if ($issue.milestone -and $issue.milestone.title) { $issue.milestone.title } else { '-' }

    $stateColor = Get-StateColor -State $state

    Print-Section "Issue #${IssueNumber}: ${title}"
    Write-Host ''
    Write-Host -NoNewline '  State:      '; Write-Host $state -ForegroundColor $stateColor
    Write-Host "  Author:     $author"
    Write-Host "  Labels:     $labelStr"
    Write-Host "  Assignees:  $assigneeStr"
    Write-Host "  Milestone:  $milestoneName"
    Write-Host "  Created:    $created"
    Write-Host "  Updated:    $updated"
    Write-Host ''
    Write-Host '  Description:' -ForegroundColor Cyan
    Print-Separator
    $body -split "`n" | ForEach-Object { Write-Host "  $_" }
    Print-Separator
}

function Display-Comments {
    param([string]$RepoName, [string]$IssueNumber)

    $commentsRaw = & gh api "repos/$RepoName/issues/$IssueNumber/comments" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "Failed to fetch comments for issue #$IssueNumber"
        return
    }
    $commentsList = $commentsRaw | ConvertFrom-Json
    $count = @($commentsList).Count

    if ($count -eq 0) {
        Write-Host ''
        Print-Info 'No comments on this issue.'
        return
    }

    Print-Section "Comments ($count)"

    foreach ($comment in $commentsList) {
        $cAuthor = $comment.user.login
        $cCreated = if ($comment.created_at.Length -ge 10) { $comment.created_at.Substring(0, 10) } else { $comment.created_at }
        $cBody = $comment.body

        Write-Host ''
        Write-Host -NoNewline "  @$cAuthor" -ForegroundColor Magenta
        Write-Host "  $cCreated" -ForegroundColor DarkGray
        Print-Separator
        $cBody -split "`n" | ForEach-Object { Write-Host "  $_" }
        Print-Separator
    }
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

if ([string]::IsNullOrWhiteSpace($Number)) {
    Print-Error 'Issue number is required. Use -Number to provide one.'
    Write-Host "Run '$($MyInvocation.ScriptName) -Help' for usage information." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = Get-GitHubRepo
    if ([string]::IsNullOrWhiteSpace($Repo)) {
        Print-Error 'Cannot detect repository. Use -Repo to specify one.'
        exit 1
    }
}

# JSON mode: output structured JSON and exit
if ($Json) {
    Output-IssueJson -RepoName $Repo -IssueNumber $Number -ShowComments (-not $NoComments)
    exit 0
}

Print-Header
Print-Info "Repository: $Repo"

# Display issue
Display-IssueDetail -RepoName $Repo -IssueNumber $Number

# Display comments
if (-not $NoComments) {
    Display-Comments -RepoName $Repo -IssueNumber $Number
}

Write-Host ''
