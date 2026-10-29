#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for bash-guard-dispatcher.ps1
# Run: pwsh tests/hooks/test-bash-guard-dispatcher.ps1
#
# The dispatcher is the sole PreToolUse/Bash hook on Windows: it reads the
# payload once, then invokes the individual guards in-process. Two properties
# are load-bearing and neither is visible from a decision alone:
#
#   1. The payload must REACH each guard. stdin can only be drained once, so
#      the guards' own Read-HookInput calls depend on the process-lifetime cache
#      in lib/CommonHelpers.psm1. If that cache regresses, every guard sees
#      $null - fail-closed guards deny everything, fail-open guards silently
#      stop checking. A test that only asserts "deny" would still pass in the
#      first case, so the reason string is asserted too.
#   2. Unparseable input must fail CLOSED, matching dangerous-command-guard.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'bash-guard-dispatcher.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

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

$benign    = '{"tool_name":"Bash","tool_input":{"command":"git status --short"}}'
$dangerous = '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
$readEnv   = '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
$ghMerge   = '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --merge"}}'

Write-Host '=== bash-guard-dispatcher.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-closed on unparseable input]'
Assert-Decision -InputJson ''             -Expected 'deny' -Label 'Empty input -> deny'
Assert-Decision -InputJson 'INVALID_JSON' -Expected 'deny' -Label 'Malformed JSON -> deny'

Write-Host ''
Write-Host '[Routing: always-on guards]'
Assert-Decision -InputJson $dangerous -Expected 'deny'  -Label 'rm -rf / -> deny'
Assert-Decision -InputJson $benign    -Expected 'allow' -Label 'git status --short -> allow'

Write-Host ''
Write-Host '[Routing: Windows-only sensitive-read guard (#964)]'
Assert-Decision -InputJson $readEnv -Expected 'deny' -Label 'cat .env -> deny'

Write-Host ''
Write-Host '[Routing: gh family]'
# merge-gate-guard no longer restricts the merge method (#964). Without a PR
# number it never calls gh, so the --merge decision is deterministic: allow.
Assert-Decision -InputJson $ghMerge -Expected 'allow' -Label 'gh pr merge --merge -> allow'

Write-Host ''
Write-Host '[Payload reaches the guards (process-lifetime cache)]'
# The distinguishing evidence: a guard that received the payload denies with its
# own diagnosis. A guard that received $null denies with a parse-failure string.
# Both are "deny", so only the reason separates a working cache from a broken one.
Assert-ReasonMatches    -InputJson $dangerous -Pattern 'dangerous-command-guard' `
    -Label 'Deny is attributed to the guard that made it'
Assert-ReasonNotMatches -InputJson $dangerous -Pattern 'failed to parse hook input' `
    -Label 'Deny is NOT a parse failure (cache delivered the payload)'
Assert-ReasonNotMatches -InputJson $dangerous -Pattern 'guard failed \(fail-closed\)' `
    -Label 'No guard crashed while being invoked'
Assert-ReasonMatches    -InputJson $readEnv   -Pattern 'bash-sensitive-read-guard' `
    -Label 'sensitive-read deny is attributed to bash-sensitive-read-guard'

Write-Host ''
Write-Host '[Decision merge: deny > ask > allow (#964)]'
# Real guards: dangerous-command-guard asks before `git stash clear`, and
# bash-sensitive-read-guard denies a read of .env. The ask must survive the
# merge instead of being turned into a deny, and a deny must still win over it.
$askOnly  = '{"tool_name":"Bash","tool_input":{"command":"git stash clear"}}'
$askDeny  = '{"tool_name":"Bash","tool_input":{"command":"git stash clear && cat .env"}}'
Assert-Decision      -InputJson $askOnly -Expected 'ask'  -Label 'ask alone -> ask'
Assert-ReasonMatches -InputJson $askOnly -Pattern '\[dangerous-command-guard\]' `
    -Label 'ask reason is attributed to the guard that asked'
Assert-Decision      -InputJson $askDeny -Expected 'deny' -Label 'ask + deny -> deny'
Assert-ReasonMatches -InputJson $askDeny -Pattern '\[bash-sensitive-read-guard\]' `
    -Label 'ask + deny reason names the denying guard'
Assert-Decision      -InputJson $benign  -Expected 'allow' -Label 'allow only -> allow'

# Stub guards pin the merge itself, independent of any real guard's rules:
# a copy of the dispatcher runs next to stubs that answer from markers in
# the command (ASK:<guard> / DENY:<guard>).
$stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bgd-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stubRoot 'lib') -Force | Out-Null
Copy-Item -LiteralPath $script:HookPath -Destination $stubRoot
Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'global' 'hooks' 'lib' 'CommonHelpers.psm1') -Destination (Join-Path $stubRoot 'lib')
$stub = @'
param($HookInput)
$name = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$cmd = [string]$HookInput.tool_input.command
$d = 'allow'
if ($cmd -match "DENY:$name\b") { $d = 'deny' } elseif ($cmd -match "ASK:$name\b") { $d = 'ask' }
$o = @{ hookEventName = 'PreToolUse'; permissionDecision = $d }
if ($d -ne 'allow') { $o.permissionDecisionReason = "stub $d from $name" }
@{ hookSpecificOutput = $o } | ConvertTo-Json -Compress -Depth 3
'@
foreach ($g in @('dangerous-command-guard', 'bash-sensitive-read-guard', 'shell-env-secret-guard')) {
    Set-Content -LiteralPath (Join-Path $stubRoot "$g.ps1") -Value $stub
}
$realHook = $script:HookPath
$script:HookPath = Join-Path $stubRoot 'bash-guard-dispatcher.ps1'
$stubAsk     = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard"}}'
$stubAskDeny = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard DENY:shell-env-secret-guard"}}'
$stubTwoAsks = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard ASK:shell-env-secret-guard"}}'
$stubAllow   = '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
Assert-Decision      -InputJson $stubAsk     -Expected 'ask'   -Label 'stub: ask alone -> ask'
Assert-Decision      -InputJson $stubAskDeny -Expected 'deny'  -Label 'stub: ask + deny -> deny'
Assert-ReasonNotMatches -InputJson $stubAskDeny -Pattern 'stub ask' `
    -Label 'stub: deny reason does not carry the ask reason'
Assert-Decision      -InputJson $stubTwoAsks -Expected 'ask'   -Label 'stub: two asks -> one ask'
Assert-ReasonMatches -InputJson $stubTwoAsks -Pattern '(?s)\[dangerous-command-guard\].*\[shell-env-secret-guard\]' `
    -Label 'stub: one ask joins every asking guard''s reason'
Assert-Decision      -InputJson $stubAllow   -Expected 'allow' -Label 'stub: allow only -> allow'
$script:HookPath = $realHook
Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue

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
