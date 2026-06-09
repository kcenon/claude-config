#!/usr/bin/env pwsh
#Requires -Version 7.0
# Tests for commit-message-guard.ps1 Rule 4 (attribution) after the switch
# from the broad substring regex to the shared AttributionValidator
# three-pattern design. Casual technical mentions of Claude/Anthropic must
# be allowed; only real attribution shapes are denied.
# Run: pwsh tests/hooks/test-commit-message-guard.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'commit-message-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Invoke-Commit {
    param([string]$Message)
    $cmd = 'git commit -m "' + $Message + '"'
    $json = (@{ tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress)
    return ($json | & pwsh -NoProfile -File $script:HookPath 2>$null)
}

function Assert-Allow {
    param([string]$Message, [string]$Label)
    $r = Invoke-Commit $Message
    if ($r -match '"allow"' -or [string]::IsNullOrEmpty($r)) {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected allow, got: $r")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Deny {
    param([string]$Message, [string]$Label)
    $r = Invoke-Commit $Message
    if ($r -match '"deny"') {
        $script:Passed++; Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++; $script:Errors.Add("FAIL: $Label - expected deny, got: $r")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== commit-message-guard.ps1 attribution (Rule 4) tests ==='
Write-Host ''
Write-Host '[Casual technical mentions allowed - no false positives]'
Assert-Allow 'docs: clarify Claude API behavior'        'Claude API mention -> allow'
Assert-Allow 'feat: add Anthropic SDK integration'      'Anthropic SDK mention -> allow'
Assert-Allow 'fix: handle ai-assisted suggestions panel' 'ai-assisted as feature noun -> allow'
Assert-Allow 'fix: resolve null pointer in parser'      'plain commit -> allow'

Write-Host ''
Write-Host '[Real attribution shapes denied]'
Assert-Deny 'feat: generated with Claude'   'prose generated with Claude -> deny'
Assert-Deny 'docs: created by Anthropic'     'prose created by Anthropic -> deny'

Write-Host ''
Write-Host '[Other rules still enforced]'
Assert-Deny 'random text without a type prefix' 'non-conventional format -> deny'
Assert-Deny 'Feat: capitalized conventional type' 'capitalized type -> deny (case-sensitive, parity with .sh)'
Assert-Deny 'FIX: uppercase type'                 'uppercase type -> deny (case-sensitive)'
Assert-Deny 'feat: trailing period.'            'trailing period -> deny'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
