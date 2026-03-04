# task-completed-logger.ps1
# Logs task completion events for audit trail
# Hook Type: TaskCompleted (async)
# Input: JSON via stdin with task_id, task_subject, task_description

$ErrorActionPreference = 'Stop'

$input_data = $input | Out-String
$json = $input_data | ConvertFrom-Json

$TaskId = if ($json.task_id) { $json.task_id } else { 'unknown' }
$TaskSubject = if ($json.task_subject) { $json.task_subject } else { 'unknown' }
$SessionId = if ($json.session_id) { $json.session_id } else { 'unknown' }

$LogDir = Join-Path $HOME ".claude/logs"
$LogFile = Join-Path $LogDir "tasks.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: Task #${TaskId} completed - $TaskSubject"

exit 0
