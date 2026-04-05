#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# config-change-logger.ps1
# Logs configuration file changes during session
# Hook Type: ConfigChange
# Input: JSON via stdin with source, file_path
# Response format: none (lifecycle event, no JSON output needed)

$json = Read-HookInput

$Source = if ($json -and $json.source) { $json.source } else { 'unknown' }
$FilePath = if ($json -and $json.file_path) { $json.file_path } else { 'unknown' }
$SessionId = if ($json -and $json.session_id) { $json.session_id } else { 'unknown' }

$LogDir = Join-Path $HOME '.claude' 'logs'
$LogFile = Join-Path $LogDir 'session.log'

Ensure-Directory $LogDir | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: CONFIG_CHANGED source=$Source file=$FilePath"

exit 0
