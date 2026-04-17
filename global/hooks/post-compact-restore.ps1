#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# post-compact-restore.ps1
# Re-injects core/principles.md after automatic context compaction.
# Pairs with pre-compact-snapshot.ps1 (PreCompact event).
# Hook Type: PostCompact (sync)
# Exit codes: 0 (always - context delivered via JSON)

$logDir = Join-Path $HOME '.claude' 'logs'
$logFile = Join-Path $logDir 'compact-snapshots.log'
Ensure-Directory $logDir | Out-Null

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$sessionId = if ($env:CLAUDE_SESSION_ID) { $env:CLAUDE_SESSION_ID } else { 'unknown' }
$workingDir = try { $PWD.Path } catch { 'unknown' }

$entry = @"
=== PostCompact Restore ===
Time: $timestamp
Session: $sessionId
Working Dir: $workingDir
===========================
"@
Add-Content -Path $logFile -Value $entry

$principlesText = $null
$candidates = @()
if ($env:CLAUDE_PROJECT_DIR) {
    $candidates += (Join-Path $env:CLAUDE_PROJECT_DIR '.claude' 'rules' 'core' 'principles.md')
}
$candidates += (Join-Path $HOME '.claude' 'rules' 'core' 'principles.md')
$candidates += (Join-Path $PWD.Path '.claude' 'rules' 'core' 'principles.md')
$candidates += (Join-Path (Split-Path -Parent $PWD.Path) '.claude' 'rules' 'core' 'principles.md')

foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $principlesText = (([System.IO.File]::ReadAllText($candidate, [System.Text.Encoding]::UTF8)) -replace "`r`n", "`n").TrimEnd("`n")
        break
    }
}

if (-not $principlesText) {
    $principlesText = @'
# Core Principles

1. **Think Before Acting** — State assumptions explicitly. If uncertain, ask.
2. **Minimize & Focus** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Precision** — Touch only what you must. Clean up only your own mess.
4. **Verify & Iterate** — Define success criteria. Loop until verified.

## Behavioral Guardrails

- Stay focused on the user's original request. Note unrelated issues at the end without acting on them.
- If the same approach fails 3 times, stop and propose alternatives rather than retrying blindly.
- Bias toward execution — start making changes immediately when asked to update or edit documents.
'@
}

$context = @"
## Post-Compaction Restore (auto-injected)

Context was just compacted. Re-asserting core principles to prevent drift:

$principlesText
"@

$context = ($context -replace "`r`n", "`n").TrimEnd("`n") + "`n"

$response = @{
    hookSpecificOutput = @{
        hookEventName     = 'PostCompact'
        additionalContext = $context
    }
}
Write-Output ($response | ConvertTo-Json -Depth 3 -Compress)
exit 0
