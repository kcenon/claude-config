# subagent-logger.ps1
# Logs subagent start/stop events for monitoring
# Hook Type: SubagentStart, SubagentStop (async)
#
# Usage: subagent-logger.ps1 <start|stop>
#
# Environment variables available:
# - CLAUDE_SUBAGENT_TYPE: Type of subagent
# - CLAUDE_SESSION_ID: Current session ID

$ErrorActionPreference = 'Stop'

$Action = if ($args.Count -gt 0) { $args[0] } else { 'unknown' }
$LogDir = Join-Path $HOME ".claude/logs"
$LogFile = Join-Path $LogDir "subagents.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$SubagentType = if ($env:CLAUDE_SUBAGENT_TYPE) { $env:CLAUDE_SUBAGENT_TYPE } else { 'unknown' }
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: Subagent $Action - $SubagentType"

exit 0
