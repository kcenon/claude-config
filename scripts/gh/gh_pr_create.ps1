#Requires -Version 7.0
#
# gh_pr_create.ps1
#
# Create a GitHub Pull Request with title, body, labels, and reviewers
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_pr_create.ps1 -Title "PR title"                     # Minimal (auto-detect repo)
#   ./gh_pr_create.ps1 -Repo owner/repo -Title "Title" -Body "Body"
#   ./gh_pr_create.ps1 -Title "Title" -Base main -Head feature/x -Labels "enhancement"
#   ./gh_pr_create.ps1 -Title "Title" -Json                   # JSON output
#   ./gh_pr_create.ps1 -Title "Title" -Quiet                  # Minimal output
#   ./gh_pr_create.ps1 -Help                                   # Show help
#

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Title,
    [string]$Body,
    [string]$Base,
    [string]$Head,
    [string]$Labels,
    [string]$Reviewers,
    [switch]$Draft,
    [switch]$Editor,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
Import-Module $ModulePath -Force

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
    Write-Host "`u{2551}              GitHub Pull Request Creator                            `u{2551}" -ForegroundColor Green
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
    Write-Host '  -Title TITLE        PR title (required)'
    Write-Host '  -Body BODY          PR body text'
    Write-Host '  -Base BRANCH        Base branch (default: main)'
    Write-Host '  -Head BRANCH        Head branch (default: current branch)'
    Write-Host '  -Labels LABELS      Comma-separated labels (e.g. "enhancement,review")'
    Write-Host '  -Reviewers USERS    Comma-separated reviewers (e.g. "user1,user2")'
    Write-Host '  -Draft              Create as draft PR'
    Write-Host '  -Editor             Open editor for body input'
    Write-Host '  -Json               Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet              Suppress decorative output'
    Write-Host '  -Help               Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_pr_create.ps1 -Title "Add login feature" -Body "Implements OAuth2 login" -Labels "enhancement"'
    Write-Host '  ./gh_pr_create.ps1 -Repo kcenon/thread_system -Title "Fix race condition" -Base main -Draft'
    Write-Host '  ./gh_pr_create.ps1 -Title "Refactor" -Reviewers "reviewer1" -Editor'
    Write-Host '  ./gh_pr_create.ps1 -Title "Fix" -Json                        # {"url":"...","number":42}'
    Write-Host ''
}

# =============================================================================
# Validation functions
# =============================================================================
function Detect-CurrentBranch {
    $branch = & git branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        Print-Error 'Cannot detect current branch. Use -Head to specify one.'
        exit 1
    }
    return $branch.Trim()
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

if ([string]::IsNullOrWhiteSpace($Head)) {
    $Head = Detect-CurrentBranch
}

Print-Header
Print-Info "Repository: $Repo"
Print-Info "Title:      $Title"
Print-Info "Head:       $Head"
if (-not [string]::IsNullOrWhiteSpace($Base)) { Print-Info "Base:       $Base" }
if ($Draft) { Print-Info 'Draft:      yes' }

# Build gh command
$ghArgs = @('pr', 'create', '--repo', $Repo, '--title', $Title, '--head', $Head)

if (-not [string]::IsNullOrWhiteSpace($Base)) {
    $ghArgs += @('--base', $Base)
}

if ($Editor) {
    $ghArgs += '--editor'
} elseif (-not [string]::IsNullOrWhiteSpace($Body)) {
    $ghArgs += @('--body', $Body)
    $preview = if ($Body.Length -gt 80) { $Body.Substring(0, 80) + '...' } else { $Body }
    Print-Info "Body:       $preview"
} else {
    $ghArgs += @('--body', '')
}

if (-not [string]::IsNullOrWhiteSpace($Labels)) {
    $ghArgs += @('--label', $Labels)
    Print-Info "Labels:     $Labels"
}

if (-not [string]::IsNullOrWhiteSpace($Reviewers)) {
    $ghArgs += @('--reviewer', $Reviewers)
    Print-Info "Reviewers:  $Reviewers"
}

if ($Draft) {
    $ghArgs += '--draft'
}

if (-not $Json -and -not $Quiet) { Write-Host '' }

# Execute
$result = & gh @ghArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to create PR: $result"
    exit 1
}

# Output
if ($Json) {
    $prNumber = if ($result -match '(\d+)$') { $Matches[1] } else { '0' }
    @{ url = "$result"; number = [int]$prNumber } | ConvertTo-Json -Compress
} elseif ($Quiet) {
    Write-Output $result
} else {
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}                      PR Created Successfully                       `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
    Write-Host "  URL: $result"
    Write-Host ''
}
