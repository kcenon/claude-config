#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# worktree-create.ps1
# Creates an isolated worktree directory for non-git environments
# Hook Type: WorktreeCreate (synchronous, type: command only)
# Triggers when worktree isolation is requested outside a git repository
#
# IMPORTANT: Must print the absolute path of the created worktree to stdout.
# Non-zero exit code fails the worktree creation.
#
# Input (stdin): JSON with worktree creation context
# Output (stdout): Absolute path to the created worktree directory

$LogDir = Join-Path $HOME '.claude' 'logs'
$WorktreeBase = Join-Path $HOME '.claude' 'worktrees'

Ensure-Directory $LogDir | Out-Null
Ensure-Directory $WorktreeBase | Out-Null

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }
$SourceDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }

# Create unique worktree directory
$WorktreeDir = Join-Path $WorktreeBase "${Timestamp}_$PID"
New-Item -ItemType Directory -Path $WorktreeDir -Force | Out-Null

# Log creation event
$logTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logEntry = @"
[$logTimestamp] Worktree created
  Path: $WorktreeDir
  Source: $SourceDir
  Session: $SessionId
"@
Add-Content -Path (Join-Path $LogDir 'worktrees.log') -Value $logEntry

# Output the created worktree path (REQUIRED by WorktreeCreate contract)
Write-Output $WorktreeDir
