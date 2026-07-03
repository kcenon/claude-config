#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for post-compact-restore.ps1
# Run: pwsh tests/hooks/test-post-compact-restore.ps1
#
# Asserts the SessionStart(compact) restore contract (issue #720):
# the PostCompact event does not support hookSpecificOutput, so the hook
# must emit a SessionStart envelope with exactly the schema keys
# {hookSpecificOutput: {hookEventName, additionalContext}}, keep the
# digest small, and stay silent for non-compact sources.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'post-compact-restore.ps1'
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

$compactInput = '{"session_id":"test","hook_event_name":"SessionStart","source":"compact"}'
$startupInput = '{"session_id":"test","hook_event_name":"SessionStart","source":"startup"}'

Write-Host '=== post-compact-restore.ps1 tests ==='
Write-Host ''

Write-Host '[output structure (source == compact)]'
$raw = $compactInput | pwsh -NoProfile -File $script:HookPath 2>$null | Out-String
$raw = $raw.Trim()
$exitCode = $LASTEXITCODE
Assert-True ($exitCode -eq 0) 'exit code is 0'

$parsed = $null
try { $parsed = $raw | ConvertFrom-Json } catch {}
Assert-True ($null -ne $parsed) 'produces valid JSON'
Assert-True ($parsed.hookSpecificOutput.hookEventName -eq 'SessionStart') 'event name is SessionStart'
Assert-True ($raw -notmatch 'PostCompact') 'no PostCompact string in output (unsupported event)'

$ctx = $parsed.hookSpecificOutput.additionalContext
Assert-True (-not [string]::IsNullOrEmpty($ctx)) 'includes additionalContext payload'

Write-Host ''
Write-Host '[schema exactness (issue #720 AC4)]'
$topKeys = @($parsed.PSObject.Properties.Name)
Assert-True (($topKeys.Count -eq 1) -and ($topKeys[0] -eq 'hookSpecificOutput')) 'top-level keys are exactly {hookSpecificOutput}'
$innerKeys = @($parsed.hookSpecificOutput.PSObject.Properties.Name | Sort-Object)
Assert-True (($innerKeys.Count -eq 2) -and ($innerKeys[0] -eq 'additionalContext') -and ($innerKeys[1] -eq 'hookEventName')) 'hookSpecificOutput keys are exactly {hookEventName, additionalContext}'

Write-Host ''
Write-Host '[digest constraints (issue #720)]'
$ctxBytes = [System.Text.Encoding]::UTF8.GetByteCount($ctx)
Assert-True ($ctxBytes -le 1000) "payload is at most 1000 bytes (got $ctxBytes)"
$ctxLines = ($ctx -split "`n").Count
Assert-True ($ctxLines -le 12) "payload is at most 12 lines (got $ctxLines)"

# No full-document re-injection: these markers exist only in the full
# core/principles.md file (frontmatter, guardrail section), never in
# the digest.
Assert-True ($ctx -notmatch 'alwaysApply') 'no full-document marker: alwaysApply'
Assert-True ($ctx -notmatch 'Behavioral Guardrails') 'no full-document marker: Behavioral Guardrails'

# Digest items: the four core principles plus the self-check line.
Assert-True ($ctx -match 'Think Before Acting') 'principle 1: Think Before Acting'
Assert-True ($ctx -match 'Minimize & Focus') 'principle 2: Minimize & Focus'
Assert-True ($ctx -match 'Surgical Precision') 'principle 3: Surgical Precision'
Assert-True ($ctx -match 'Verify & Iterate') 'principle 4: Verify & Iterate'
Assert-True ($ctx -match 'senior engineer') 'self-check line present'

Write-Host ''
Write-Host '[source gating (defense in depth)]'
$startupOut = ($startupInput | pwsh -NoProfile -File $script:HookPath 2>$null | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0) 'source startup: exit code is 0'
Assert-True ([string]::IsNullOrEmpty($startupOut)) 'source startup: stdout is empty'

$noSrcOut = ('{}' | pwsh -NoProfile -File $script:HookPath 2>$null | Out-String).Trim()
Assert-True (($LASTEXITCODE -eq 0) -and [string]::IsNullOrEmpty($noSrcOut)) 'missing source field: silent exit 0'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
