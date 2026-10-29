#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for edit-guard-dispatcher.ps1 (issues #920, #964)
# Run: pwsh tests/hooks/test-edit-guard-dispatcher.ps1
#
# The dispatcher is the sole PreToolUse/Edit|Write hook on Windows: it reads the
# payload once, then invokes the guards of its routing table in-process. Since
# #964 that table holds only memory-write-guard. Three properties are
# load-bearing and none is visible from a decision alone:
#
#   1. The payload must REACH the guard. stdin can only be drained once, so the
#      guard's own Read-HookInput call depends on the process-lifetime cache in
#      lib/CommonHelpers.psm1. memory-write-guard allows a $null payload
#      silently, so a broken cache would turn the guard off without changing
#      any decision. The test runs a copy of the dispatcher whose routed guard
#      is a stub that echoes the payload it received into additionalContext,
#      which pins the delivery contract independently of the real guard's
#      validators.
#   2. Unparseable input fails OPEN with a diagnostic, matching memory-write-guard
#      on both platforms (issue #521). The fail-closed policy existed for
#      sensitive-file-guard, which #964 removed.
#   3. The routing table holds exactly memory-write-guard, and an ordinary or a
#      sensitive path is allowed: sensitive files are denied by permissions.deny
#      now, not by a hook.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'edit-guard-dispatcher.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Invoke-Dispatcher {
    param([string]$InputJson, [string]$Path = $script:HookPath)
    $raw = $InputJson | & pwsh -NoProfile -File $Path 2>$null
    $line = ($raw | Where-Object { $_ -match '"hookSpecificOutput"' } | Select-Object -Last 1)
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json).hookSpecificOutput } catch { return $null }
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

function Assert-Decision {
    param([string]$InputJson, [string]$Expected, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    $got = if ($r) { [string]$r.permissionDecision } else { '(no parseable response)' }
    Assert-Condition ($got -eq $Expected) $Label "expected $Expected, got: $got"
}

function New-Payload {
    param([string]$Tool, [string]$Path)
    $o = @{
        tool_name  = $Tool
        session_id = 'test-964-edit-dispatcher'
        tool_input = @{ file_path = $Path; content = 'body'; old_string = 'a'; new_string = 'b' }
    }
    return ($o | ConvertTo-Json -Depth 4 -Compress)
}

# Paths need not exist: outside memory-shared nothing touches the filesystem.
$envName  = '.' + 'env'      # split so this file is not itself flagged by path scanners
$ordinary = 'D:/Sources/claude-config/README.md'
$envPath  = "D:/Sources/claude-config/$envName"

Write-Host '=== edit-guard-dispatcher.ps1 tests ==='
Write-Host ''

Write-Host '[Routing table holds exactly memory-write-guard]'
$src    = Get-Content -LiteralPath $script:HookPath -Raw
$routed = @([regex]::Matches($src, "name\s*=\s*'([A-Za-z0-9_.-]+)'") | ForEach-Object { $_.Groups[1].Value })
Assert-Condition (($routed -join ',') -eq 'memory-write-guard') 'Routing table is [memory-write-guard]' "parsed: $($routed -join ',')"

Write-Host ''
Write-Host '[Fail-open on unparseable input]'
foreach ($case in @(@{ in = ''; label = 'Empty input' }, @{ in = 'INVALID_JSON'; label = 'Malformed JSON' })) {
    $r = Invoke-Dispatcher $case.in
    Assert-Condition ($r -and $r.permissionDecision -eq 'allow') "$($case.label) -> allow" "got: $(if ($r) { $r.permissionDecision } else { '(none)' })"
    $ctx = if ($r) { [string]$r.additionalContext } else { '' }
    Assert-Condition ($ctx -match 'fail-open') "$($case.label) -> diagnostic says fail-open" "context: $ctx"
}

Write-Host ''
Write-Host '[No file-channel policy guard left]'
Assert-Decision -InputJson (New-Payload 'Edit'  $ordinary) -Expected 'allow' -Label 'Edit ordinary file -> allow'
Assert-Decision -InputJson (New-Payload 'Write' $ordinary) -Expected 'allow' -Label 'Write ordinary file -> allow'
Assert-Decision -InputJson (New-Payload 'Edit'  $envPath)  -Expected 'allow' -Label 'Edit env file -> allow (permissions.deny owns it)'

Write-Host ''
Write-Host '[Payload reaches the routed guard (process-lifetime cache)]'
# A copy of the dispatcher next to the real lib/, with a stub in place of
# memory-write-guard.ps1. The stub reads the payload the way every guard does
# and echoes what it got; a broken cache shows up as "received:null".
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "edit-dispatcher-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$hooks   = Join-Path $tmpRoot 'hooks'
New-Item -ItemType Directory -Path (Join-Path $hooks 'lib') -Force | Out-Null
$srcHooks = Join-Path $script:RepoRoot 'global' 'hooks'
Copy-Item -LiteralPath (Join-Path $srcHooks 'edit-guard-dispatcher.ps1') -Destination $hooks
Copy-Item -LiteralPath (Join-Path $srcHooks 'lib' 'CommonHelpers.psm1') -Destination (Join-Path $hooks 'lib')
$stub = @'
#Requires -Version 7.0
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue
$json = Read-HookInput
$got = if ($json) { "received:$($json.tool_name):$($json.tool_input.file_path)" } else { 'received:null' }
Write-Output (New-HookAllowResponse -AdditionalContext $got)
exit 0
'@
Set-Content -LiteralPath (Join-Path $hooks 'memory-write-guard.ps1') -Value $stub -Encoding utf8
$copied = Join-Path $hooks 'edit-guard-dispatcher.ps1'

try {
    $memFile = 'D:/Users/test-owner/.claude/memory-shared/memories/feedback_cache.md'
    $r = Invoke-Dispatcher -InputJson (New-Payload 'Write' $memFile) -Path $copied
    $ctx = if ($r) { [string]$r.additionalContext } else { '' }
    Assert-Condition ($ctx -eq "received:Write:$memFile") 'Routed guard received the full payload' "context: $ctx"

    # Control: the prefilter skips paths outside memory-shared and Read calls,
    # so the stub never runs and the dispatcher adds no context.
    $r = Invoke-Dispatcher -InputJson (New-Payload 'Write' $ordinary) -Path $copied
    $ctx = if ($r) { [string]$r.additionalContext } else { '' }
    Assert-Condition ($r -and $r.permissionDecision -eq 'allow' -and -not $ctx) 'Ordinary path skips the guard' "context: $ctx"
    $r = Invoke-Dispatcher -InputJson (New-Payload 'Read' $memFile) -Path $copied
    $ctx = if ($r) { [string]$r.additionalContext } else { '' }
    Assert-Condition ($r -and $r.permissionDecision -eq 'allow' -and -not $ctx) 'Read of a memory file skips the guard' "context: $ctx"
}
finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

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
