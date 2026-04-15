#Requires -Version 7.0

# Batch issue-work orchestrator (PowerShell)
# ===========================================
# Spawns one fresh `claude` CLI process per open issue. Each process handles
# exactly one item, so context state cannot leak between items -- item N+1
# starts with the same CLAUDE.md / skill attention pool as item 1.
#
# Usage:
#   .\scripts\batch-issue-work.ps1 -OrgProject <org/repo> [-Limit <n>]
#
# Example:
#   .\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config
#   .\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config -Limit 3
#
# Per-item logs are written to:
#   $HOME/.claude/batch-logs/<timestamp>/issue-<number>.log
#
# On any item failure, the batch pauses and exits with a non-zero code so
# the operator can inspect the log before deciding to continue.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$OrgProject,

    [Parameter(Position = 1)]
    [ValidateRange(1, 100)]
    [int]$Limit = 5
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Info      { param([string]$Message) Write-Host "[info] $Message" -ForegroundColor Blue }
function Write-Ok        { param([string]$Message) Write-Host "[ok]   $Message" -ForegroundColor Green }
function Write-Warn      { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }
function Write-Err       { param([string]$Message) Write-Host "[err]  $Message" -ForegroundColor Red }
function Write-Highlight { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Err 'claude CLI not found on PATH. Install Claude Code and re-run.'
    exit 2
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Err 'gh CLI not found on PATH. Install GitHub CLI and re-run.'
    exit 2
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir    = Join-Path $HOME ".claude/batch-logs/$Timestamp"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Highlight 'Batch issue-work orchestrator'
Write-Info "Repository : $OrgProject"
Write-Info "Limit      : $Limit"
Write-Info "Log dir    : $LogDir"
Write-Host ''

$IssuesJson = gh issue list --repo $OrgProject --state open --limit $Limit `
    --json number,title | ConvertFrom-Json

if (-not $IssuesJson -or $IssuesJson.Count -eq 0) {
    Write-Warn "No open issues found in $OrgProject"
    exit 0
}

$Total      = $IssuesJson.Count
$Processed  = 0
$FailedItem = $null

foreach ($Issue in $IssuesJson) {
    $Processed++
    $LogFile = Join-Path $LogDir "issue-$($Issue.number).log"

    Write-Highlight "[$Processed/$Total] Processing #$($Issue.number) -- $($Issue.title)"
    Write-Info "Log: $LogFile"

    # Each item runs in a fresh claude process so its context state is
    # discarded on exit. --print exits after the turn completes.
    $Prompt = "/issue-work $OrgProject $($Issue.number) --solo"
    & claude --print $Prompt *>$LogFile

    if ($LASTEXITCODE -ne 0) {
        Write-Err "#$($Issue.number) failed (exit $LASTEXITCODE). Pausing batch."
        Write-Err "Inspect the log before continuing: $LogFile"
        $FailedItem = "#$($Issue.number)"
        break
    }

    Write-Ok "#$($Issue.number) completed"
}

Write-Host ''
if ($FailedItem) {
    Write-Err "Batch paused on $FailedItem ($Processed/$Total processed)"
    Write-Err "Logs: $LogDir"
    exit 1
}

Write-Ok "Batch complete: $Processed/$Total items processed"
Write-Info "Logs: $LogDir"
