# config-change-logger.ps1
# Logs configuration file changes during session
# Hook Type: ConfigChange
# Input: JSON via stdin with source, file_path
# Decision control: JSON response ({"decision": "allow"})

$ErrorActionPreference = 'Stop'

$input_data = $input | Out-String
$json = $input_data | ConvertFrom-Json

$Source = if ($json.source) { $json.source } else { 'unknown' }
$FilePath = if ($json.file_path) { $json.file_path } else { 'unknown' }
$SessionId = if ($json.session_id) { $json.session_id } else { 'unknown' }

$LogDir = Join-Path $HOME ".claude/logs"
$LogFile = Join-Path $LogDir "session.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: CONFIG_CHANGED source=$Source file=$FilePath"

Write-Output '{"decision": "allow"}'
exit 0
