#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# shell-env-secret-guard.ps1
# Blocks Bash commands that would print or dump secret-bearing environment
# variables into the transcript.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
#
# Rationale: Codex scrubs *KEY*/*SECRET*/*TOKEN*/AWS_* env vars from the child
# process via config.toml [shell_environment_policy].exclude. A Claude hook
# runs out-of-process and cannot mutate the Bash child's env, so the achievable
# analog is to DENY commands that leak a named secret var (echo/printf/printenv
# $SECRET) and WARN on bare env dumps. Deliberately narrow to avoid breaking
# legitimate tooling (e.g. `gh api`, which uses GH_TOKEN internally, not via
# $-expansion).
#
# Matching is CASE-SENSITIVE (-cmatch) and segment-aware: the secret keyword
# must be an underscore-delimited segment / suffix of an UPPER_SNAKE var name,
# so API_KEY / AWS_SECRET_ACCESS_KEY / GITHUB_TOKEN match, while TOKENIZER /
# KEYBOARD / monkey do not.

$logDir  = if ($env:CLAUDE_LOG_DIR) { $env:CLAUDE_LOG_DIR } else { Join-Path $HOME '.claude/logs' }
$logFile = Join-Path $logDir 'shell-env-secret-guard.log'

function Write-Decision {
    param([string]$Decision, [string]$Reason, [string]$Command)
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $entry = [ordered]@{
            ts       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            decision = $Decision
            reason   = $Reason
            command  = $Command
        }
        ($entry | ConvertTo-Json -Compress -Depth 3) | Out-File -FilePath $logFile -Append -Encoding utf8
    } catch { }
}

$json = Read-HookInput
if (-not $json) {
    # Fail-open: dangerous-command-guard in the same chain is fail-closed on
    # unparseable input, so this one stays quiet to avoid double-denial noise.
    New-HookAllowResponse
    exit 0
}

$CMD = $null
try { $CMD = [string]$json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }
if ([string]::IsNullOrWhiteSpace($CMD)) {
    New-HookAllowResponse
    exit 0
}

# Secret keyword as an underscore-delimited segment/suffix of an UPPER_SNAKE
# var name. The optional '([A-Z0-9_]*_)?' eats leading segments; the trailing
# '([^A-Z0-9]|$)' is the right boundary so TOKEN in TOKENIZER does not match.
$secretSeg = '([A-Z0-9_]*_)?(KEY|KEYS|SECRET|SECRETS|TOKEN|TOKENS|PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|CREDENTIALS)([^A-Z0-9]|$)'

# DENY 1: echo/printf expanding a secret var ($SECRET or ${SECRET}).
if ($CMD -cmatch ('(echo|printf)[^|;&]*[$]\{?' + $secretSeg)) {
    $reason = 'shell-env-secret-guard: refusing to print a secret-bearing env var. Do not echo secret values into the transcript; use the secret directly in the consuming command, or let the user run it.'
    Write-Decision -Decision 'deny' -Reason $reason -Command $CMD
    New-HookDenyResponse -Reason $reason
    exit 0
}

# DENY 2: printenv NAME where NAME is a secret var (no $ prefix for printenv).
if ($CMD -cmatch ('printenv\s+\{?' + $secretSeg)) {
    $reason = 'shell-env-secret-guard: refusing to printenv a secret-bearing env var into the transcript.'
    Write-Decision -Decision 'deny' -Reason $reason -Command $CMD
    New-HookDenyResponse -Reason $reason
    exit 0
}

# WARN: bare env dump that exposes ALL env vars (secrets included). Allowed
# (legitimate for debugging) but flagged so the model narrows it.
if ($CMD -cmatch '(^|[;&|]\s*)(env|printenv|set|export\s+-p|declare\s+-p|compgen\s+-v)\s*($|[;&|])') {
    $reason = 'shell-env-secret-guard: this dumps the full environment (secrets included) into the transcript. Narrow to the specific non-secret var you need.'
    Write-Decision -Decision 'allow-warn' -Reason $reason -Command $CMD
    New-HookAllowResponse -AdditionalContext $reason
    exit 0
}

Write-Decision -Decision 'allow' -Reason 'no secret-exposure pattern matched' -Command $CMD
New-HookAllowResponse
exit 0
