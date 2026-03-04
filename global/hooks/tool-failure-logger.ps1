# tool-failure-logger.ps1
# Logs tool execution failures for debugging and analysis
# Hook Type: PostToolUseFailure (async)
#
# Environment variables available:
# - CLAUDE_TOOL_NAME: Name of the tool that failed
# - CLAUDE_TOOL_INPUT: Input provided to the tool (JSON)
# - CLAUDE_TOOL_ERROR: Error message from the tool
# - CLAUDE_SESSION_ID: Current session ID

$ErrorActionPreference = 'Stop'

$LogDir = Join-Path $HOME ".claude/logs"
$LogFile = Join-Path $LogDir "tool-failures.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$ToolName = if ($env:CLAUDE_TOOL_NAME) { $env:CLAUDE_TOOL_NAME } else { 'unknown' }
$SessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }

$entry = @"
=== Tool Failure at $Timestamp ===
Session: $SessionId
Tool: $ToolName
"@

if ($env:CLAUDE_TOOL_ERROR) {
    $entry += "`nError: $($env:CLAUDE_TOOL_ERROR)"
}
$entry += "`n---"

Add-Content -Path $LogFile -Value $entry

exit 0
