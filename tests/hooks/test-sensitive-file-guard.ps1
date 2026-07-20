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
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env.backup.20260101"}}' -Label '.env.backup.<ts> -> deny'

Write-Host ''
Write-Host '[.env template allow-list (issue #582)]'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.env.example"}}' -Label '.env.example -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.env.example.local"}}' -Label '.env.example.local -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.env.sample"}}' -Label '.env.sample -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.env.template"}}' -Label '.env.template -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"config/.env.example"}}' -Label 'nested .env.example -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.ENV.EXAMPLE"}}' -Label 'case-insensitive .env.example -> allow'

Write-Host ''
Write-Host '[Path normalization + direnv parity (issue #856)]'
Assert-Deny -InputJson '{"tool_input":{"file_path":".envrc"}}' -Label '.envrc -> deny (direnv config)'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.envrc"}}' -Label 'path-qualified .envrc -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/.env "}}' -Label '.env with trailing space -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"keys/secret.key "}}' -Label 'secret.key with trailing space -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"~/.env"}}' -Label 'tilde ~/.env -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"~/.envrc"}}' -Label 'tilde ~/.envrc -> deny'
# The allow-list is matched against the normalized basename too, so templates
# must survive the same tilde/whitespace handling that the deny paths apply.
Assert-Allow -InputJson '{"tool_input":{"file_path":"~/.env.example"}}' -Label 'tilde ~/.env.example -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/.env.template "}}' -Label '.env.template with trailing space -> allow'

Write-Host ''
Write-Host '[Bare *.env suffix form (issue #863)]'
# The suffix form denotes the same artifact as the .env.* dotfile form and is
# already denied by both Bash-channel guards. The template allow-list asserted
# in the issue #582 block above is load-bearing for this arm: it must keep
# winning for .env.example / .env.sample / .env.template now that *.env matches.
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/production.env"}}' -Label 'production.env -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/srv/app/staging.env"}}' -Label 'path-qualified staging.env -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/example.env"}}' -Label 'example.env -> deny (not a recognised template form)'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/template.env"}}' -Label 'template.env -> deny (not a recognised template form)'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/app/PRODUCTION.ENV"}}' -Label 'PRODUCTION.ENV -> deny (case-folded)'
Assert-Allow -InputJson '{"tool_input":{"file_path":"/app/foo.env.example"}}' -Label 'foo.env.example -> allow (ends in .example)'

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
Write-Host '[SSH private keys + AWS credentials (parity with .sh)]'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}' -Label 'id_rsa -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"id_ed25519"}}' -Label 'id_ed25519 -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/keys/id_ecdsa.bak"}}' -Label 'id_ecdsa.bak -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/home/u/.ssh/id_ed25519.pub"}}' -Label 'id_ed25519.pub -> deny (parity)'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/home/u/.aws/credentials"}}' -Label '.aws/credentials -> deny'
Assert-Deny -InputJson '{"tool_input":{"file_path":"/home/u/.aws/config"}}' -Label '.aws/config -> deny'
Assert-Allow -InputJson '{"tool_input":{"file_path":"src/config"}}' -Label 'non-.aws config -> allow'
Assert-Allow -InputJson '{"tool_input":{"file_path":"src/identity.py"}}' -Label 'id-prefixed non-key -> allow'

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
Write-Host '[UTF-8 stdin]'
$koreanText = -join ([char]0xD55C, [char]0xAE00)
$emoji = [char]::ConvertFromUtf32(0x1F680)
$utf8Json = '{"tool_input":{"file_path":"src/' + $koreanText + '-' + $emoji + '.txt"}}'
Assert-Allow -InputJson $utf8Json -Label 'Korean and emoji JSON -> allow'

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
