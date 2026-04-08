#Requires -Version 7.0
#
# gh_pr_comment.ps1
#
# Add a comment to a GitHub Pull Request
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_pr_comment.ps1 -Number 42 -Body "Comment text"          # Auto-detect repo
#   ./gh_pr_comment.ps1 -Repo owner/repo -Number 42 -Body "LGTM"
#   ./gh_pr_comment.ps1 -Number 42 -Editor                        # Open editor
#   ./gh_pr_comment.ps1 -Number 42 -Body "LGTM" -Json             # JSON output
#   ./gh_pr_comment.ps1 -Number 42 -Body "LGTM" -Quiet            # Minimal output
#   ./gh_pr_comment.ps1 -Help                                      # Show help
#

[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Number,
    [string]$Body,
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
    Write-Host "`u{2551}              GitHub PR Comment                                      `u{2551}" -ForegroundColor Green
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
    Write-Host '  -Number NUMBER      PR number (required)'
    Write-Host '  -Body BODY          Comment body text (required unless -Editor is used)'
    Write-Host '  -Editor             Open editor for comment input'
    Write-Host '  -Json               Output result as JSON (for programmatic use)'
    Write-Host '  -Quiet              Suppress decorative output'
    Write-Host '  -Help               Show this help message'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  ./gh_pr_comment.ps1 -Number 42 -Body "LGTM, merging now"'
    Write-Host '  ./gh_pr_comment.ps1 -Repo kcenon/thread_system -Number 10 -Body "Please fix the typo"'
    Write-Host '  ./gh_pr_comment.ps1 -Number 42 -Editor'
    Write-Host '  ./gh_pr_comment.ps1 -Number 42 -Body "LGTM" -Json   # {"url":"..."}'
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

if ([string]::IsNullOrWhiteSpace($Number)) {
    Print-Error 'PR number is required. Use -Number to provide one.'
    Write-Host "Run '$($MyInvocation.ScriptName) -Help' for usage information." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Body) -and -not $Editor) {
    Print-Error 'Comment body is required. Use -Body or -Editor to provide one.'
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
Print-Info "PR:         #$Number"

# Build gh command
$ghArgs = @('pr', 'comment', $Number, '--repo', $Repo)

if ($Editor) {
    $ghArgs += '--editor'
} else {
    $ghArgs += @('--body', $Body)
    $preview = if ($Body.Length -gt 80) { $Body.Substring(0, 80) + '...' } else { $Body }
    Print-Info "Comment:    $preview"
}

if (-not $Json -and -not $Quiet) { Write-Host '' }

# Execute
$result = & gh @ghArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to add comment: $result"
    exit 1
}

# Output
if ($Json) {
    @{ url = "$result" } | ConvertTo-Json -Compress
} elseif ($Quiet) {
    Write-Output $result
} else {
    Write-Host ''
    Write-Host "`u{2554}$('=' * 70)`u{2557}" -ForegroundColor Green
    Write-Host "`u{2551}                   Comment Added Successfully                       `u{2551}" -ForegroundColor Green
    Write-Host "`u{255A}$('=' * 70)`u{255D}" -ForegroundColor Green
    Write-Host ''
    Write-Host "  URL: $result"
    Write-Host ''
}
