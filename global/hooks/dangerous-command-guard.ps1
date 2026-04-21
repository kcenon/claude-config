#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# dangerous-command-guard.ps1
# Blocks dangerous bash commands and records every decision.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Side effects:
#   Writes one JSON line per invocation to
#   ${env:CLAUDE_LOG_DIR}/dangerous-command-guard.log (defaults to
#   ~/.claude/logs) so an operator can verify whether the hook returned
#   allow/deny for a specific command.

$logDir = if ($env:CLAUDE_LOG_DIR) { $env:CLAUDE_LOG_DIR } else { Join-Path $HOME '.claude/logs' }
$logFile = Join-Path $logDir 'dangerous-command-guard.log'

function Write-Decision {
    param(
        [string]$Decision,
        [string]$Reason,
        [string]$Command
    )
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $entry = [ordered]@{
            ts       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            decision = $Decision
            reason   = $Reason
            command  = $Command
        }
        ($entry | ConvertTo-Json -Compress -Depth 3) | Out-File -FilePath $logFile -Append -Encoding utf8
    } catch {
        # Best-effort; never fail the decision on a logging failure.
    }
}

function Respond-Deny {
    param([string]$Reason)
    Write-Decision -Decision 'deny' -Reason $Reason -Command $CMD
    New-HookDenyResponse -Reason $Reason
    exit 0
}

function Respond-Allow {
    param([string]$Reason = 'dangerous-command-guard: no dangerous pattern matched')
    Write-Decision -Decision 'allow' -Reason $Reason -Command $CMD
    New-HookAllowResponse -AdditionalContext $Reason
    exit 0
}

$json = Read-HookInput
$CMD = $null

if (-not $json) {
    Respond-Deny 'Failed to parse hook input - denying for safety (fail-closed)'
}

try {
    $CMD = $json.tool_input.command
} catch {}

if (-not $CMD) {
    $CMD = $env:CLAUDE_TOOL_INPUT
}

if ($CMD -match 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/') {
    Respond-Deny 'Dangerous recursive delete at root directory blocked for safety'
}

if ($CMD -match 'chmod\s+(0?777|a\+rwx)') {
    Respond-Deny 'Dangerous permission change (777/a+rwx) blocked for security'
}

if ($CMD -match '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b') {
    Respond-Deny 'Remote script execution via pipe blocked for security'
}

# Tag safe read-only compound patterns (pipe/redirect + git/gh read verb)
# so the audit trail explains why they were auto-allowed even when
# Claude Code's allowlist cannot match a compound command.
$safeHead = '^(git\s+(status|log|diff|show|branch|tag|remote|ls-files|rev-parse|describe|for-each-ref|worktree|fetch)|gh\s+(pr|issue|run|workflow|repo|release|auth)\s+(view|list|status|diff|checks))\b'
if (($CMD -match '\|') -or ($CMD -match '2>&1') -or ($CMD -match '>\s*/dev/null')) {
    if ($CMD -match $safeHead) {
        Respond-Allow 'Safe read-only compound command (pipe/redirect with git/gh read verb)'
    }
}

Respond-Allow
