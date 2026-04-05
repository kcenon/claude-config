#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# task-completed-logger.ps1
# Logs task completion events for audit trail
# Hook Type: TaskCompleted (async)
# Input: JSON via stdin with task_id, task_subject, task_description

$json = Read-HookInput

$TaskId = if ($json -and $json.task_id) { $json.task_id } else { 'unknown' }
$TaskSubject = if ($json -and $json.task_subject) { $json.task_subject } else { 'unknown' }
$SessionId = if ($json -and $json.session_id) { $json.session_id } else { 'unknown' }

$LogDir = Join-Path $HOME '.claude' 'logs'
$LogFile = Join-Path $LogDir 'tasks.log'

Ensure-Directory $LogDir | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: Task #${TaskId} completed - $TaskSubject"

exit 0
