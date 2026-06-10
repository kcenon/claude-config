#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# post-compact-restore.ps1
# Re-asserts the four core principles after automatic context compaction.
# Pairs with pre-compact-snapshot.ps1 (PreCompact event).
# Hook Type: SessionStart (matcher: compact, sync)
# Exit codes: 0 (always - silent no-op unless stdin source is "compact")

# Defense in depth (issue #720): the settings matcher ("compact") already
# filters SessionStart invocations, but stay silent if the hook is ever
# wired without a matcher so startup/resume/clear sessions are not spammed.
$json = Read-HookInput
$source = ''
if ($null -ne $json) {
    try { $source = [string]$json.source } catch { $source = '' }
}
if ($source -ne 'compact') { exit 0 }

# --- Logging (mirrors pre-compact-snapshot.ps1 contract) ---
$logDir = Join-Path $HOME '.claude' 'logs'
$logFile = Join-Path $logDir 'compact-snapshots.log'
Ensure-Directory $logDir | Out-Null

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$sessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }
$workingDir = try { $PWD.Path } catch { 'unknown' }

$entry = @"
=== Post-Compact Restore ===
Time: $timestamp
Session: $sessionId
Working Dir: $workingDir
===========================
"@
Add-Content -Path $logFile -Value $entry

# Fixed short digest (issue #720): the PostCompact event does not support
# hookSpecificOutput, so this hook listens on SessionStart (source ==
# "compact") - the official channel for injecting context after compaction.
# Keep the payload to a few lines and never read rule files into it.
# Must stay byte-equivalent to the digest in post-compact-restore.sh.
$digest = @'
## Post-Compaction Restore (digest)

Context was just compacted. Re-asserting the four core principles:

1. Think Before Acting - state assumptions explicitly; if uncertain, ask.
2. Minimize & Focus - minimum code that solves the problem; nothing speculative.
3. Surgical Precision - touch only what you must; clean up only your own mess.
4. Verify & Iterate - define success criteria; loop until verified.

Self-check: "Would a senior engineer say this diff is focused, minimal, and well-verified?"
'@

$digest = ($digest -replace "`r`n", "`n").TrimEnd("`n")

$response = @{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $digest
    }
}
Write-Output ($response | ConvertTo-Json -Depth 3 -Compress)
exit 0
