#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# worktree-remove.ps1
# Cleans up and logs worktree removal events
# Hook Type: WorktreeRemove (async, type: command only)
# Triggers when a worktree is being removed/cleaned up
# Cannot block removal - cleanup and logging only
#
# Input (stdin): JSON with worktree_path field

$LogDir = Join-Path $HOME '.claude' 'logs'
Ensure-Directory $LogDir | Out-Null

# Read worktree path from stdin JSON if available
$WorktreePath = ''
$json = Read-HookInput
if ($json -and $json.worktree_path) {
    $WorktreePath = $json.worktree_path
}

if ([string]::IsNullOrEmpty($WorktreePath)) {
    $WorktreePath = if ($env:CLAUDE_WORKTREE_PATH) { $env:CLAUDE_WORKTREE_PATH } else { 'unknown' }
}

# Log removal event
$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logEntry = @"
[$Timestamp] Worktree removed
  Path: $WorktreePath
"@
Add-Content -Path (Join-Path $LogDir 'worktrees.log') -Value $logEntry

exit 0
