#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# cwd-change-logger.ps1
# Logs working-directory changes during a session for audit trails.
# Hook Type: CwdChanged
# Input: JSON via stdin with session_id, cwd, transcript_path, hook_event_name
# Response format: none (observation-only event; CwdChanged cannot block, exit 2 only shows stderr)

$json = Read-HookInput

$Cwd = if ($json -and $json.cwd) { $json.cwd } else { 'unknown' }
$SessionId = if ($json -and $json.session_id) { $json.session_id } else { 'unknown' }

$LogDir = Join-Path $HOME '.claude' 'logs'
$LogFile = Join-Path $LogDir 'session.log'

Ensure-Directory $LogDir | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: CWD_CHANGED cwd=$Cwd"

exit 0
