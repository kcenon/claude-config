#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# pre-compact-snapshot.ps1
# Captures working state before automatic context compaction
# Hook Type: PreCompact (async)
# Triggers when context window reaches ~95% and auto-compaction begins
#
# Environment variables available:
# - CLAUDE_SESSION_ID: Current session ID

$LogDir = Join-Path $HOME '.claude' 'logs'
$LogFile = Join-Path $LogDir 'compact-snapshots.log'

Ensure-Directory $LogDir | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }
$WorkingDir = try { $PWD.Path } catch { 'unknown' }

$entry = @"
=== PreCompact Snapshot ===
Time: $Timestamp
Session: $SessionId
Working Dir: $WorkingDir
===========================
"@

Add-Content -Path $LogFile -Value $entry

exit 0
