#Requires -Version 7.0

# Batch pr-work orchestrator (PowerShell)
# ========================================
# Spawns one fresh `claude` CLI process per failing PR. Each process handles
# exactly one PR, so CI log accumulation and diff-read state cannot leak
# between items -- PR N+1 starts with the same CLAUDE.md / skill attention
# pool as PR 1.
#
# Usage:
#   .\scripts\batch-pr-work.ps1 -OrgProject <org/repo> [-Limit <n>]
#
# Example:
#   .\scripts\batch-pr-work.ps1 -OrgProject kcenon/claude-config
#   .\scripts\batch-pr-work.ps1 -OrgProject kcenon/claude-config -Limit 3
#
# Per-item logs are written to:
#   $HOME/.claude/batch-logs/<timestamp>/pr-<number>.log
#
# A PR is considered "failing" if at least one check has conclusion
# FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, or STARTUP_FAILURE.
# Passing and in-progress PRs are skipped.

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

Write-Highlight 'Batch pr-work orchestrator'
Write-Info "Repository : $OrgProject"
Write-Info "Limit      : $Limit"
Write-Info "Log dir    : $LogDir"
Write-Host ''

$FailingConclusions = @('FAILURE', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE')

$AllPrs = gh pr list --repo $OrgProject --state open --limit 100 `
    --json number,title,statusCheckRollup | ConvertFrom-Json

$FailingPrs = @($AllPrs | Where-Object {
    $_.statusCheckRollup -and (
        $_.statusCheckRollup | Where-Object {
            $FailingConclusions -contains $_.conclusion
        }
    )
} | Select-Object -First $Limit)

if ($FailingPrs.Count -eq 0) {
    Write-Warn "No open PRs with failing checks found in $OrgProject"
    exit 0
}

$Total      = $FailingPrs.Count
$Processed  = 0
$FailedItem = $null

foreach ($Pr in $FailingPrs) {
    $Processed++
    $LogFile = Join-Path $LogDir "pr-$($Pr.number).log"

    Write-Highlight "[$Processed/$Total] Processing PR #$($Pr.number) -- $($Pr.title)"
    Write-Info "Log: $LogFile"

    $Prompt = "/pr-work $OrgProject $($Pr.number) --solo"
    & claude --print $Prompt *>$LogFile

    if ($LASTEXITCODE -ne 0) {
        Write-Err "PR #$($Pr.number) failed (exit $LASTEXITCODE). Pausing batch."
        Write-Err "Inspect the log before continuing: $LogFile"
        $FailedItem = "PR #$($Pr.number)"
        break
    }

    Write-Ok "PR #$($Pr.number) completed"
}

Write-Host ''
if ($FailedItem) {
    Write-Err "Batch paused on $FailedItem ($Processed/$Total processed)"
    Write-Err "Logs: $LogDir"
    exit 1
}

Write-Ok "Batch complete: $Processed/$Total items processed"
Write-Info "Logs: $LogDir"
