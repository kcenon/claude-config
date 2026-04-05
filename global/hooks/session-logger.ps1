#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# session-logger.ps1
# Logs session start/end events
# Hook Type: SessionStart, SessionEnd, Stop, TeammateIdle
# Usage: session-logger.ps1 [start|end|stop|teammate-idle]
# Response format: none (lifecycle event, no JSON output needed)

$LogFile = Join-Path $HOME '.claude' 'session.log'
$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Ensure log directory exists
Ensure-Directory (Split-Path $LogFile -Parent) | Out-Null

$action = if ($args.Count -gt 0) { $args[0] } else { '' }

$message = switch ($action) {
    'start'         { "[Session] Claude Code session started: $Timestamp" }
    'end'           { "[Session] Claude Code session ended: $Timestamp" }
    'stop'          { "[Stop] Claude Code task stopped: $Timestamp" }
    'teammate-idle' { "[TeammateIdle] Teammate went idle: $Timestamp" }
    default         { "[Session] Claude Code event: $Timestamp" }
}

Add-Content -Path $LogFile -Value $message -ErrorAction SilentlyContinue

exit 0
