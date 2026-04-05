#Requires -Version 7.0
#
# gh_pr_read.ps1
#
# Read a GitHub Pull Request's description, comments, and review comments
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_pr_read.ps1 -Number 42                               # Auto-detect repo
#   ./gh_pr_read.ps1 -Repo owner/repo -Number 42              # Specific repo
#   ./gh_pr_read.ps1 -Number 42 -NoComments                   # Description only
#   ./gh_pr_read.ps1 -Number 42 -NoReviews                    # Skip review comments
#   ./gh_pr_read.ps1 -Number 42 -Json                         # JSON output
#   ./gh_pr_read.ps1 -Number 42 -Quiet                        # Minimal output
#   ./gh_pr_read.ps1 -Help                                     # Show help
#

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Number,
    [switch]$NoComments,
    [switch]$NoReviews,
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
    Write-Host "`u{2551}              GitHub Pull Request Reader                             `u{2551}" -ForegroundColor Green
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
        'MERGED' { return 'Magenta' }
        default  { return 'Yellow' }
    }
}

function Get-ReviewStateColor {
    param([string]$State)
    switch ($State) {
        'APPROVED'          { return 'Green' }
        'CHANGES_REQUESTED' { return 'Red' }
        'COMMENTED'         { return 'Cyan' }
        default             { return 'Yellow' }
    }
}

function Show-Help {
    Print-Header
    Write-Host 'Usage:' -ForegroundColor Cyan
    Write-Host "  $($MyInvocation.ScriptName) [OPTIONS]"
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Cyan
    Write-Host '  -Repo REPO          Target repo (owner/repo). Auto-detects if omitted.'
    Write-Host '  -Number NUMBER      PR number (required)'
    Write-Host '  -NoComments         Skip general comments'
    Write-Host '  -NoReviews          Skip review comments'
    Write-Host '  -Json               Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet              Suppress decorative output'
    Write-Host '  -Help               Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_pr_read.ps1 -Number 42                     # Auto-detect repo'
    Write-Host '  ./gh_pr_read.ps1 -Repo kcenon/thread_system -Number 10'
    Write-Host '  ./gh_pr_read.ps1 -Number 42 -NoReviews          # Skip review comments'
    Write-Host '  ./gh_pr_read.ps1 -Number 42 -Json                # Structured JSON'
    Write-Host ''
}

# =============================================================================
# JSON output function
# =============================================================================
function Output-PrJson {
    param(
        [string]$RepoName,
        [string]$PrNumber,
        [bool]$ShowComments,
        [bool]$ShowReviews
    )

    $prRaw = & gh pr view $PrNumber --repo $RepoName `
        --json number,title,state,body,author,labels,assignees,baseRefName,headRefName,additions,deletions,changedFiles,createdAt,updatedAt 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to fetch PR #$PrNumber from $RepoName"
        exit 1
    }
    $pr = $prRaw | ConvertFrom-Json

    $comments = @()
    if ($ShowComments) {
        try {
            $commentsRaw = & gh api "repos/$RepoName/issues/$PrNumber/comments" 2>$null
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
    }

    $reviews = @()
    if ($ShowReviews) {
        try {
            $reviewsRaw = & gh api "repos/$RepoName/pulls/$PrNumber/reviews" 2>$null
            if ($LASTEXITCODE -eq 0 -and $reviewsRaw) {
                $reviewsParsed = $reviewsRaw | ConvertFrom-Json
                $reviews = @($reviewsParsed | Where-Object { $_.body -and $_.body -ne '' } | ForEach-Object {
                    @{
                        author    = $_.user.login
                        state     = $_.state
                        body      = $_.body
                        submitted = $_.submitted_at
                    }
                })
            }
        } catch { $reviews = @() }
    }

    $labelNames = @()
    if ($pr.labels) { $labelNames = @($pr.labels | ForEach-Object { $_.name }) }
    $assigneeLogins = @()
    if ($pr.assignees) { $assigneeLogins = @($pr.assignees | ForEach-Object { $_.login }) }

    $output = [ordered]@{
        number        = $pr.number
        title         = $pr.title
        state         = $pr.state
        author        = $pr.author.login
        labels        = $labelNames
        assignees     = $assigneeLogins
        base          = $pr.baseRefName
        head          = $pr.headRefName
        additions     = $pr.additions
        deletions     = $pr.deletions
        changed_files = $pr.changedFiles
        body          = if ($pr.body) { $pr.body } else { '' }
        created       = $pr.createdAt
        updated       = $pr.updatedAt
        comments      = $comments
        reviews       = $reviews
    }

    $output | ConvertTo-Json -Depth 5
}

# =============================================================================
# Display functions
# =============================================================================
function Display-PrDetail {
    param([string]$RepoName, [string]$PrNumber)

    $prRaw = & gh pr view $PrNumber --repo $RepoName `
        --json number,title,state,body,author,labels,assignees,reviewRequests,baseRefName,headRefName,additions,deletions,changedFiles,commits,createdAt,updatedAt,mergeable,isDraft 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to fetch PR #$PrNumber from $RepoName"
        exit 1
    }
    $pr = $prRaw | ConvertFrom-Json

    $title = $pr.title
    $state = $pr.state
    $author = $pr.author.login
    $baseBranch = $pr.baseRefName
    $headBranch = $pr.headRefName
    $created = if ($pr.createdAt.Length -ge 10) { $pr.createdAt.Substring(0, 10) } else { $pr.createdAt }
    $updated = if ($pr.updatedAt.Length -ge 10) { $pr.updatedAt.Substring(0, 10) } else { $pr.updatedAt }
    $body = if ($pr.body) { $pr.body } else { '(no description)' }
    $labelStr = if ($pr.labels -and $pr.labels.Count -gt 0) { ($pr.labels | ForEach-Object { $_.name }) -join ', ' } else { '-' }
    $assigneeStr = if ($pr.assignees -and $pr.assignees.Count -gt 0) { ($pr.assignees | ForEach-Object { $_.login }) -join ', ' } else { '-' }
    $reviewerStr = if ($pr.reviewRequests -and $pr.reviewRequests.Count -gt 0) {
        ($pr.reviewRequests | ForEach-Object { if ($_.login) { $_.login } else { $_.name } }) -join ', '
    } else { '-' }
    $additions = $pr.additions
    $deletions = $pr.deletions
    $changedFiles = $pr.changedFiles
    $commitCount = if ($pr.commits -and $pr.commits.totalCount) { $pr.commits.totalCount } else { '0' }
    $isDraft = $pr.isDraft
    $mergeable = $pr.mergeable

    $stateColor = Get-StateColor -State $state

    Print-Section "PR #${PrNumber}: ${title}"
    Write-Host ''
    Write-Host -NoNewline '  State:      '; Write-Host $state -ForegroundColor $stateColor
    if ($isDraft -eq $true) { Write-Host -NoNewline '  Draft:      '; Write-Host 'yes' -ForegroundColor Yellow }
    Write-Host "  Author:     $author"
    Write-Host "  Branch:     $headBranch -> $baseBranch"
    Write-Host "  Labels:     $labelStr"
    Write-Host "  Assignees:  $assigneeStr"
    Write-Host "  Reviewers:  $reviewerStr"
    Write-Host "  Mergeable:  $mergeable"
    Write-Host -NoNewline '  Changes:    '
    Write-Host -NoNewline "+$additions" -ForegroundColor Green
    Write-Host -NoNewline ' '
    Write-Host -NoNewline "-$deletions" -ForegroundColor Red
    Write-Host " in $changedFiles files ($commitCount commits)"
    Write-Host "  Created:    $created"
    Write-Host "  Updated:    $updated"
    Write-Host ''
    Write-Host '  Description:' -ForegroundColor Cyan
    Print-Separator
    $body -split "`n" | ForEach-Object { Write-Host "  $_" }
    Print-Separator
}

function Display-Comments {
    param([string]$RepoName, [string]$PrNumber)

    $commentsRaw = & gh api "repos/$RepoName/issues/$PrNumber/comments" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "Failed to fetch comments for PR #$PrNumber"
        return
    }
    $commentsList = $commentsRaw | ConvertFrom-Json
    $count = @($commentsList).Count

    if ($count -eq 0) {
        Write-Host ''
        Print-Info 'No general comments on this PR.'
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

function Display-ReviewComments {
    param([string]$RepoName, [string]$PrNumber)

    $reviewsRaw = & gh api "repos/$RepoName/pulls/$PrNumber/reviews" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "Failed to fetch reviews for PR #$PrNumber"
        return
    }
    $reviewsList = $reviewsRaw | ConvertFrom-Json
    $withBody = @($reviewsList | Where-Object { $_.body -and $_.body -ne '' })
    $count = $withBody.Count

    if ($count -eq 0) {
        Write-Host ''
        Print-Info 'No review comments on this PR.'
        return
    }

    Print-Section "Reviews ($count)"

    foreach ($review in $withBody) {
        $rAuthor = $review.user.login
        $rState = $review.state
        $rBody = $review.body
        $rSubmitted = if ($review.submitted_at.Length -ge 10) { $review.submitted_at.Substring(0, 10) } else { $review.submitted_at }
        $rStateColor = Get-ReviewStateColor -State $rState

        Write-Host ''
        Write-Host -NoNewline "  @$rAuthor" -ForegroundColor Magenta
        Write-Host -NoNewline "  $rState" -ForegroundColor $rStateColor
        Write-Host "  $rSubmitted" -ForegroundColor DarkGray
        Print-Separator
        $rBody -split "`n" | ForEach-Object { Write-Host "  $_" }
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
    Print-Error 'PR number is required. Use -Number to provide one.'
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
    Output-PrJson -RepoName $Repo -PrNumber $Number -ShowComments (-not $NoComments) -ShowReviews (-not $NoReviews)
    exit 0
}

Print-Header
Print-Info "Repository: $Repo"

# Display PR
Display-PrDetail -RepoName $Repo -PrNumber $Number

# Display comments
if (-not $NoComments) {
    Display-Comments -RepoName $Repo -PrNumber $Number
}

# Display reviews
if (-not $NoReviews) {
    Display-ReviewComments -RepoName $Repo -PrNumber $Number
}

Write-Host ''
