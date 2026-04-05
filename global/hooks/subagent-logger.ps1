#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# subagent-logger.ps1
# Logs subagent start/stop events for monitoring
# Hook Type: SubagentStart, SubagentStop (async)
#
# Usage: subagent-logger.ps1 <start|stop>
#
# Environment variables available:
# - CLAUDE_SUBAGENT_TYPE: Type of subagent (e.g., "Bash", "Explore", "Plan")
# - CLAUDE_SESSION_ID: Current session ID

$Action = if ($args.Count -gt 0) { $args[0] } else { 'unknown' }
$LogDir = Join-Path $HOME '.claude' 'logs'
$LogFile = Join-Path $LogDir 'subagents.log'

Ensure-Directory $LogDir | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$SubagentType = if ($env:CLAUDE_SUBAGENT_TYPE) { $env:CLAUDE_SUBAGENT_TYPE } else { 'unknown' }
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }

Add-Content -Path $LogFile -Value "[$Timestamp] Session ${SessionId}: Subagent $Action - $SubagentType"

exit 0
