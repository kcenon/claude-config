#Requires -Version 7.0
#
# gh_issue_create.ps1
#
# Create a GitHub Issue with title, body, labels, and assignees
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_issue_create.ps1 -Title "Bug title"                  # Minimal (auto-detect repo)
#   ./gh_issue_create.ps1 -Repo owner/repo -Title "Title" -Body "Body"
#   ./gh_issue_create.ps1 -Title "Title" -Labels "bug,urgent" -Assignees "user1"
#   ./gh_issue_create.ps1 -Title "Title" -Json                # JSON output
#   ./gh_issue_create.ps1 -Title "Title" -Quiet               # Minimal output
#   ./gh_issue_create.ps1 -Help                                # Show help
#

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Title,
    [string]$Body,
    [string]$Labels,
    [string]$Assignees,
    [string]$Milestone,
    [switch]$Editor,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

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

function Print-Header {
    if ($Json -or $Quiet) { return }
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}              GitHub Issue Creator                                   `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
}

function Show-Help {
    Print-Header
    Write-Host 'Usage:' -ForegroundColor Cyan
    Write-Host "  $($MyInvocation.ScriptName) [OPTIONS]"
    Write-Host ''
    Write-Host 'Options:' -ForegroundColor Cyan
    Write-Host '  -Repo REPO          Target repo (owner/repo). Auto-detects if omitted.'
    Write-Host '  -Title TITLE        Issue title (required)'
    Write-Host '  -Body BODY          Issue body text'
    Write-Host '  -Labels LABELS      Comma-separated labels (e.g. "bug,enhancement")'
    Write-Host '  -Assignees USERS    Comma-separated assignees (e.g. "user1,user2")'
    Write-Host '  -Milestone NAME     Milestone name'
    Write-Host '  -Editor             Open editor for body input'
    Write-Host '  -Json               Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet              Suppress decorative output'
    Write-Host '  -Help               Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_issue_create.ps1 -Title "Fix login bug" -Body "Login fails on timeout" -Labels "bug"'
    Write-Host '  ./gh_issue_create.ps1 -Repo kcenon/thread_system -Title "Add feature" -Assignees "kcenon"'
    Write-Host '  ./gh_issue_create.ps1 -Title "Design review" -Editor'
    Write-Host '  ./gh_issue_create.ps1 -Title "Bug" -Json                     # {"url":"...","number":42}'
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

if ([string]::IsNullOrWhiteSpace($Title)) {
    Print-Error 'Title is required. Use -Title to provide one.'
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

Print-Header
Print-Info "Repository: $Repo"
Print-Info "Title:      $Title"

# Build gh command
$ghArgs = @('issue', 'create', '--repo', $Repo, '--title', $Title)

if ($Editor) {
    $ghArgs += '--editor'
} elseif (-not [string]::IsNullOrWhiteSpace($Body)) {
    $ghArgs += @('--body', $Body)
    $preview = if ($Body.Length -gt 80) { $Body.Substring(0, 80) + '...' } else { $Body }
    Print-Info "Body:       $preview"
}

if (-not [string]::IsNullOrWhiteSpace($Labels)) {
    $ghArgs += @('--label', $Labels)
    Print-Info "Labels:     $Labels"
}

if (-not [string]::IsNullOrWhiteSpace($Assignees)) {
    $ghArgs += @('--assignee', $Assignees)
    Print-Info "Assignees:  $Assignees"
}

if (-not [string]::IsNullOrWhiteSpace($Milestone)) {
    $ghArgs += @('--milestone', $Milestone)
    Print-Info "Milestone:  $Milestone"
}

if (-not $Json -and -not $Quiet) { Write-Host '' }

# Execute
$result = & gh @ghArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to create issue: $result"
    exit 1
}

# Output
if ($Json) {
    $issueNumber = if ($result -match '(\d+)$') { $Matches[1] } else { '0' }
    @{ url = "$result"; number = [int]$issueNumber } | ConvertTo-Json -Compress
} elseif ($Quiet) {
    Write-Output $result
} else {
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}                     Issue Created Successfully                     `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
    Write-Host "  URL: $result"
    Write-Host ''
}
