#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for edit-guard-dispatcher.ps1 (issue #920)
# Run: pwsh tests/hooks/test-edit-guard-dispatcher.ps1
#
# The dispatcher is the sole PreToolUse/Edit|Write|Read hook on Windows: it reads
# the payload once, then invokes the guards in-process. Three properties are
# load-bearing and none is visible from a decision alone:
#
#   1. The payload must REACH each guard. stdin can only be drained once, so the
#      guards' own Read-HookInput calls depend on the process-lifetime cache in
#      lib/CommonHelpers.psm1. If that cache regresses, every guard sees $null -
#      fail-closed guards deny everything, fail-open guards silently stop
#      checking. A test that only asserts "deny" would still pass in the first
#      case, so the reason string is asserted too.
#   2. Unparseable input must fail CLOSED, matching sensitive-file-guard (the
#      other two guards on this matcher fail open).
#   3. A file denied by sensitive-file-guard must NOT reach the read-set tracker
#      (issues #424, #521). Asserting only the absence would also pass if
#      short-circuiting had killed track mode outright, so a positive control
#      asserts that an ordinary path IS still tracked.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'edit-guard-dispatcher.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

# pre-edit-read-guard prefers $env:CLAUDE_SESSION_ID over the payload's
# session_id. Clear it so the tracker assertions below address the throwaway
# session this test creates, not the session running the test.
$script:SavedSessionId = $env:CLAUDE_SESSION_ID
$env:CLAUDE_SESSION_ID = ''

function Invoke-Dispatcher {
    param([string]$InputJson)
    $raw = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    $line = ($raw | Where-Object { $_ -match '"hookSpecificOutput"' } | Select-Object -Last 1)
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json).hookSpecificOutput } catch { return $null }
}

function Assert-Decision {
    param([string]$InputJson, [string]$Expected, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    if ($r -and $r.permissionDecision -eq $Expected) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $got = if ($r) { $r.permissionDecision } else { '(no parseable response)' }
        $script:Errors.Add("FAIL: $Label - expected $Expected, got: $got")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-ReasonMatches {
    param([string]$InputJson, [string]$Pattern, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    $reason = if ($r) { [string]$r.permissionDecisionReason } else { '' }
    if ($reason -match $Pattern) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - reason did not match /$Pattern/, got: $reason")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-ReasonNotMatches {
    param([string]$InputJson, [string]$Pattern, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    $reason = if ($r) { [string]$r.permissionDecisionReason } else { '' }
    if ($reason -notmatch $Pattern) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - reason unexpectedly matched /$Pattern/, got: $reason")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Condition {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label$(if ($Detail) { " - $Detail" })")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

# Build payloads. Paths need not exist: the guards resolve strings and only
# memory-write-guard touches the filesystem, and only under memory-shared.
$envName    = '.' + 'env'      # split so this file is not itself flagged by path scanners
$ordinary   = 'D:/Sources/claude-config/README.md'
$secretPath = "D:/Sources/claude-config/$envName"
$template   = "D:/Sources/claude-config/$envName.example"

# Every payload carries a session id, and each test group gets its own. Without
# one, pre-edit-read-guard falls back to the shared 'unknown' tracker: a leftover
# from any previous run then decides whether the routing assertions below see
# first-run safety (allow) or a tracker miss (deny), which makes them depend on
# machine state rather than on the dispatcher.
$script:BaseSession = "test-920-base-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"

function New-Payload {
    param([string]$Tool, [string]$Path, [string]$SessionId = '')
    if (-not $SessionId) { $SessionId = $script:BaseSession }
    $o = @{
        tool_name  = $Tool
        session_id = $SessionId
        tool_input = @{ file_path = $Path; old_string = 'a'; new_string = 'b' }
    }
    return ($o | ConvertTo-Json -Depth 4 -Compress)
}

Write-Host '=== edit-guard-dispatcher.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-closed on unparseable input]'
Assert-Decision -InputJson ''             -Expected 'deny' -Label 'Empty input -> deny'
Assert-Decision -InputJson 'INVALID_JSON' -Expected 'deny' -Label 'Malformed JSON -> deny'

Write-Host ''
Write-Host '[Routing: sensitive-file-guard]'
Assert-Decision -InputJson (New-Payload 'Edit' $secretPath) -Expected 'deny'  -Label 'Edit env file -> deny'
Assert-Decision -InputJson (New-Payload 'Read' $secretPath) -Expected 'deny'  -Label 'Read env file -> deny'
Assert-Decision -InputJson (New-Payload 'Edit' $template)   -Expected 'allow' -Label 'Edit env template -> allow'
Assert-Decision -InputJson (New-Payload 'Edit' $ordinary)   -Expected 'allow' -Label 'Edit ordinary file -> allow'

Write-Host ''
Write-Host '[Payload reaches the guards (process-lifetime cache)]'
# The distinguishing evidence: a guard that received the payload denies with its
# own diagnosis. A guard that received $null denies with a parse-failure string.
# Both are "deny", so only the reason separates a working cache from a broken one.
Assert-ReasonMatches    -InputJson (New-Payload 'Edit' $secretPath) -Pattern 'sensitive-file-guard' `
    -Label 'Deny is attributed to the guard that made it'
Assert-ReasonNotMatches -InputJson (New-Payload 'Edit' $secretPath) -Pattern 'failed to parse hook input' `
    -Label 'Deny is NOT a parse failure (cache delivered the payload)'
Assert-ReasonNotMatches -InputJson (New-Payload 'Edit' $secretPath) -Pattern 'guard failed \(fail-closed\)' `
    -Label 'No guard crashed while being invoked'

Write-Host ''
Write-Host '[Short-circuit: a denied file never reaches the read-set tracker]'
# Issues #424, #521. Registering the guards separately could not enforce this -
# the harness runs later hooks even after a denial - so it is the dispatcher's
# short-circuit that makes the invariant hold.
$trackerDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }

$denySession = "test-920-deny-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$denyTracker = Join-Path $trackerDir "claude-read-set-$denySession"
# A tracker must already exist, otherwise pre-edit-read-guard's first-run safety
# path allows without ever consulting it.
Set-Content -LiteralPath $denyTracker -Value 'D:/seed/placeholder.md' -Encoding utf8

Invoke-Dispatcher (New-Payload 'Read' $secretPath $denySession) | Out-Null
$denyContent = Get-Content -LiteralPath $denyTracker -Raw -ErrorAction SilentlyContinue
Assert-Condition (-not ($denyContent -match [regex]::Escape($envName))) `
    'Denied env path is absent from the tracker' "tracker content: $denyContent"

# Positive control: absence above must mean "short-circuited", not "track mode
# is dead". An ordinary Read still has to be recorded.
$okSession = "test-920-ok-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$okTracker = Join-Path $trackerDir "claude-read-set-$okSession"
Set-Content -LiteralPath $okTracker -Value 'D:/seed/placeholder.md' -Encoding utf8

Invoke-Dispatcher (New-Payload 'Read' $ordinary $okSession) | Out-Null
$okContent = Get-Content -LiteralPath $okTracker -Raw -ErrorAction SilentlyContinue
Assert-Condition ($okContent -match 'README') `
    'Ordinary Read is still tracked (track mode alive)' "tracker content: $okContent"

$baseTracker = Join-Path $trackerDir "claude-read-set-$($script:BaseSession)"
foreach ($t in @($denyTracker, $okTracker, $baseTracker)) {
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
}
if ($null -ne $script:SavedSessionId) { $env:CLAUDE_SESSION_ID = $script:SavedSessionId }

Write-Host ''
# Emit the summary in the repo-standard shape. test-runner.ps1 aggregates with
# /(\d+)\s+passed/ and /(\d+)\s+failed/, and PowerShell -match is
# case-insensitive, so a "Passed: N  Failed: M" line has its N read as the
# FAILED count ("N  Failed" matches the second pattern).
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Failed -gt 0) {
    Write-Host ''
    $script:Errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
exit 0
