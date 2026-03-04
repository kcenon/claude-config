# pre-compact-snapshot.ps1
# Captures working state before automatic context compaction
# Hook Type: PreCompact (async)
# Triggers when context window reaches ~95% and auto-compaction begins
#
# Environment variables available:
# - CLAUDE_SESSION_ID: Current session ID

$ErrorActionPreference = 'Stop'

$LogDir = Join-Path $HOME ".claude/logs"
$LogFile = Join-Path $LogDir "compact-snapshots.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }
$WorkingDir = try { (Get-Location).Path } catch { 'unknown' }

$entry = @"
=== PreCompact Snapshot ===
Time: $Timestamp
Session: $SessionId
Working Dir: $WorkingDir
===========================
"@

Add-Content -Path $LogFile -Value $entry

exit 0
