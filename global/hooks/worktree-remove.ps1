# worktree-remove.ps1
# Cleans up and logs worktree removal events
# Hook Type: WorktreeRemove (async, type: command only)
# Triggers when a worktree is being removed/cleaned up
# Cannot block removal - cleanup and logging only
#
# Input (stdin): JSON with worktree_path field

$ErrorActionPreference = 'SilentlyContinue'

$LogDir = Join-Path $HOME ".claude/logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Read worktree path from stdin JSON if available
$WorktreePath = ''
try {
    $input_data = $input | Out-String
    if ($input_data) {
        $json = $input_data | ConvertFrom-Json
        $WorktreePath = $json.worktree_path
    }
} catch {}

if ([string]::IsNullOrEmpty($WorktreePath)) {
    $WorktreePath = if ($env:CLAUDE_WORKTREE_PATH) { $env:CLAUDE_WORKTREE_PATH } else { 'unknown' }
}

# Log removal event
$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logEntry = @"
[$Timestamp] Worktree removed
  Path: $WorktreePath
"@
Add-Content -Path (Join-Path $LogDir "worktrees.log") -Value $logEntry

exit 0
