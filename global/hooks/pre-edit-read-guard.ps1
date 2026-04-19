#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# pre-edit-read-guard.ps1
# Enforces the "Read before Edit/Write" tool contract.
#
# Registered under TWO hook entries in global/settings.json:
#   1. PreToolUse  matcher "Edit|Write" - guard mode (deny when tracker lacks file_path)
#   2. PostToolUse matcher "Read"       - track mode (record file_path in tracker)
#
# Tracker: $env:TEMP\claude-read-set-<session-id>
#   One absolute path per line. Cleared naturally when $env:TEMP rotates.
#
# Exit codes: always 0. Decision is encoded in the JSON response for PreToolUse
# events; PostToolUse emits no JSON and is best-effort.

$json = Read-HookInput

# Fail-open on empty stdin (harness may not have wired input yet).
if (-not $json) {
    exit 0
}

$toolName = ''
$filePath = ''
$sessionId = $env:CLAUDE_SESSION_ID
try { $toolName = [string]$json.tool_name } catch {}
try { $filePath = [string]$json.tool_input.file_path } catch {}
if ([string]::IsNullOrEmpty($sessionId)) {
    try { $sessionId = [string]$json.session_id } catch {}
}
if ([string]::IsNullOrEmpty($sessionId)) { $sessionId = 'unknown' }

$trackerDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
$tracker = Join-Path $trackerDir ("claude-read-set-{0}" -f $sessionId)

function Resolve-Path-Safe {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return $Path
    }
}

switch ($toolName) {
    'Read' {
        # Track mode: append the Read path. Best-effort, no JSON output.
        if ([string]::IsNullOrEmpty($filePath)) { exit 0 }
        $resolved = Resolve-Path-Safe $filePath
        try {
            if (-not (Test-Path -LiteralPath $trackerDir)) {
                New-Item -ItemType Directory -Path $trackerDir -Force | Out-Null
            }
            $existing = @()
            if (Test-Path -LiteralPath $tracker) {
                $existing = Get-Content -LiteralPath $tracker -ErrorAction SilentlyContinue
            }
            if ($existing -notcontains $resolved) {
                Add-Content -LiteralPath $tracker -Value $resolved -ErrorAction SilentlyContinue
            }
        } catch {}
        exit 0
    }

    { $_ -eq 'Edit' -or $_ -eq 'Write' } {
        # Guard mode: deny unless the target has been Read this session.
        if ([string]::IsNullOrEmpty($filePath)) {
            New-HookAllowResponse
            exit 0
        }
        $resolved = Resolve-Path-Safe $filePath

        # First-run safety: no tracker file yet means this is a fresh session.
        if (-not (Test-Path -LiteralPath $tracker)) {
            New-HookAllowResponse
            exit 0
        }

        # Exempt genuinely new files for Write (Edit requires existing files).
        if ($toolName -eq 'Write' -and -not (Test-Path -LiteralPath $resolved)) {
            New-HookAllowResponse
            exit 0
        }

        $hit = $false
        try {
            $hit = (Get-Content -LiteralPath $tracker -ErrorAction SilentlyContinue) -contains $resolved
        } catch {}

        if ($hit) {
            New-HookAllowResponse
            exit 0
        }

        $reason = "Cannot $toolName '$filePath' without reading it first in this session. Call Read on '$filePath' and retry. (Session $sessionId, tracker $tracker.)"
        New-HookDenyResponse -Reason $reason
        exit 0
    }

    default {
        # Unknown tool - allow to avoid interfering with other matchers.
        New-HookAllowResponse
        exit 0
    }
}
