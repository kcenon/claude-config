#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for instructions-loaded-reinforcer.ps1
# Run: pwsh tests/hooks/test-instructions-loaded-reinforcer.ps1
#
# Asserts the InstructionsLoaded digest contract (issue #716):
# valid JSON envelope, payload size cap (~10 lines / ~500 bytes),
# the four required policy items, and no verbatim commit-settings.md copy.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'instructions-loaded-reinforcer.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== instructions-loaded-reinforcer.ps1 tests ==='
Write-Host ''

Write-Host '[output structure]'
$raw = '{}' | pwsh -NoProfile -File $script:HookPath 2>$null | Out-String
$raw = $raw.Trim()
$exitCode = $LASTEXITCODE
Assert-True ($exitCode -eq 0) 'exit code is 0'

$parsed = $null
try { $parsed = $raw | ConvertFrom-Json } catch {}
Assert-True ($null -ne $parsed) 'produces valid JSON'
Assert-True ($parsed.hookSpecificOutput.hookEventName -eq 'InstructionsLoaded') 'event name is InstructionsLoaded'

$ctx = $parsed.hookSpecificOutput.additionalContext
Assert-True (-not [string]::IsNullOrEmpty($ctx)) 'includes additionalContext payload'

Write-Host ''
Write-Host '[digest constraints (issue #716)]'
$ctxBytes = [System.Text.Encoding]::UTF8.GetByteCount($ctx)
Assert-True ($ctxBytes -le 500) "payload is at most 500 bytes (got $ctxBytes)"
$ctxLines = ($ctx -split "`n").Count
Assert-True ($ctxLines -le 10) "payload is at most 10 lines (got $ctxLines)"

# No verbatim copy of commit-settings.md: these markers exist only in the
# full policy file (and the old inline fallback), never in the digest.
Assert-True ($ctx -notmatch 'korean_plus_english') 'no verbatim copy marker: korean_plus_english'
Assert-True ($ctx -notmatch 'commit-message-guard') 'no verbatim copy marker: commit-message-guard'
Assert-True ($ctx -notmatch 'Enforced by') 'no verbatim copy marker: Enforced by'

# Four required digest items (issue #716 AC2).
Assert-True ($ctx -match 'No AI/Claude attribution') 'item 1: attribution ban'
Assert-True ($ctx -match 'CLAUDE_CONTENT_LANGUAGE' -and $ctx -match 'commit-settings\.md') 'item 2: content-language policy pointer'
Assert-True ($ctx -match 'develop' -and $ctx -match 'main' -and $ctx -match 'squash') 'item 3: protected branch rules'
Assert-True ($ctx -match [regex]::Escape('type(scope): description') -and $ctx -match 'lowercase first char' -and $ctx -match 'no trailing period') 'item 4: Conventional Commits format'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
