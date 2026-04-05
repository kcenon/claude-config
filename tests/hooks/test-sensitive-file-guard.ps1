#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for sensitive-file-guard.ps1
# Run: pwsh tests/hooks/test-sensitive-file-guard.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'sensitive-file-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Assert-Deny {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"deny"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected deny, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Allow {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"allow"' -or [string]::IsNullOrEmpty($result)) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected allow, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== sensitive-file-guard.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-closed]'
Assert-Deny -InputJson '' -Label 'Empty input -> deny'
Assert-Deny -InputJson 'INVALID_JSON' -Label 'Malformed JSON -> deny'
Assert-Allow -InputJson '{}' -Label 'Missing tool_input -> allow (valid JSON, no file)'

Write-Host ''
Write-Host '[.env patterns]'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env"}}' -Label '.env -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env.local"}}' -Label '.env.local -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env.production"}}' -Label '.env.production -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env.development"}}' -Label '.env.development -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"config/.env"}}' -Label 'nested .env -> deny'

Write-Host ''
Write-Host '[Certificate/key patterns]'
Assert-Deny -InputJson '{"tool_input":{"file_path":"certs/server.pem"}}' -Label '.pem -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"keys/private.key"}}' -Label '.key -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"auth/cert.p12"}}' -Label '.p12 -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"auth/cert.pfx"}}' -Label '.pfx -> deny'

Write-Host ''
Write-Host '[Sensitive directories]'
Assert-Deny -InputJson '{"tool_input":{"file_path":"config/secrets/db.yml"}}' -Label 'secrets/ -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"config/credentials/aws.json"}}' -Label 'credentials/ -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"config/passwords/list.txt"}}' -Label 'passwords/ -> deny'

Write-Host ''
Write-Host '[Allowed system paths]'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/private/tmp/claude_test"}}' -Label '/private/tmp -> allow (macOS system)'

Write-Host ''
Write-Host '[Allowed files]'
Assert-Allow -InputJson '{"tool_input":{"file_path":"src/main.py"}}' -Label 'main.py -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"src/environment.ts"}}' -Label 'environment.ts -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"src/config.json"}}' -Label 'config.json -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"README.md"}}' -Label 'README.md -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"package.json"}}' -Label 'package.json -> allow'

Write-Host ''
Write-Host '[Edge cases]'
Assert-Allow -InputJson '{"tool_input":{"file_path":""}}' -Label 'Empty file path -> allow'
Assert-Allow -InputJson '{"tool_input":{}}' -Label 'No file_path field -> allow'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
