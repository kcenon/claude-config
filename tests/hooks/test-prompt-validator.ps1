#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for prompt-validator.ps1
# Run: pwsh tests/hooks/test-prompt-validator.ps1
#
# prompt-validator.ps1 reads CLAUDE_USER_PROMPT env var (not stdin JSON).
# It returns JSON with additionalContext for dangerous prompts, or exits silently for safe ones.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'prompt-validator.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Assert-Warning {
    param([string]$Prompt, [string]$Label)
    $result = & pwsh -NoProfile -Command "& { `$env:CLAUDE_USER_PROMPT = '$($Prompt -replace "'","''")'; & '$($script:HookPath)' 2>`$null }"
    if ($result -match '"additionalContext"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected warning, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Silent {
    param([string]$Prompt, [string]$Label)
    $result = & pwsh -NoProfile -Command "& { `$env:CLAUDE_USER_PROMPT = '$($Prompt -replace "'","''")'; & '$($script:HookPath)' 2>`$null }"
    # Silent allow: no JSON output (empty or no additionalContext)
    if ([string]::IsNullOrEmpty($result) -or $result -notmatch '"additionalContext"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected silent allow, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== prompt-validator.ps1 tests ==='
Write-Host ''

# --- Empty / missing prompt ---
Write-Host '[Empty prompt]'
$result = & pwsh -NoProfile -Command "& { `$env:CLAUDE_USER_PROMPT = ''; & '$($script:HookPath)' 2>`$null }"
$exitCode = $LASTEXITCODE
if ($exitCode -eq 0 -and [string]::IsNullOrEmpty($result)) {
    $script:Passed++
    Write-Host '  PASS: Empty prompt -> silent allow' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add('FAIL: Empty prompt - expected silent allow (exit 0, no output)')
    Write-Host '  FAIL: Empty prompt -> silent allow' -ForegroundColor Red
}

$result = & pwsh -NoProfile -Command "& { Remove-Item Env:CLAUDE_USER_PROMPT -ErrorAction SilentlyContinue; & '$($script:HookPath)' 2>`$null }"
$exitCode = $LASTEXITCODE
if ($exitCode -eq 0 -and [string]::IsNullOrEmpty($result)) {
    $script:Passed++
    Write-Host '  PASS: Unset prompt -> silent allow' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add('FAIL: Unset prompt - expected silent allow')
    Write-Host '  FAIL: Unset prompt -> silent allow' -ForegroundColor Red
}

# The hook regex: (delete|remove|drop)\s+(all|entire|whole|database|table|production)
# Only matches when the keyword is DIRECTLY followed by the target word (no "the" in between).

# --- Dangerous patterns: delete ---
Write-Host ''
Write-Host '[Dangerous: delete patterns]'
Assert-Warning -Prompt 'delete all files in the project' -Label 'delete all -> warning'
Assert-Warning -Prompt 'Delete entire database' -Label 'Delete entire -> warning'
Assert-Warning -Prompt 'delete whole directory now' -Label 'delete whole -> warning'
Assert-Warning -Prompt 'delete production data' -Label 'delete production -> warning'
Assert-Warning -Prompt 'delete table users' -Label 'delete table -> warning'
Assert-Warning -Prompt 'DELETE ALL records from the database' -Label 'DELETE ALL (uppercase) -> warning'
Assert-Warning -Prompt 'delete database completely' -Label 'delete database -> warning'

# --- Dangerous patterns: remove ---
Write-Host ''
Write-Host '[Dangerous: remove patterns]'
Assert-Warning -Prompt 'remove all data' -Label 'remove all -> warning'
Assert-Warning -Prompt 'Remove entire directory' -Label 'Remove entire -> warning'
Assert-Warning -Prompt 'remove whole cluster' -Label 'remove whole -> warning'
Assert-Warning -Prompt 'remove production environment' -Label 'remove production -> warning'
Assert-Warning -Prompt 'remove table sessions' -Label 'remove table -> warning'
Assert-Warning -Prompt 'remove database backup' -Label 'remove database -> warning'

# --- Dangerous patterns: drop ---
Write-Host ''
Write-Host '[Dangerous: drop patterns]'
Assert-Warning -Prompt 'drop all tables' -Label 'drop all -> warning'
Assert-Warning -Prompt 'drop entire schema' -Label 'drop entire -> warning'
Assert-Warning -Prompt 'drop database mydb' -Label 'drop database -> warning'
Assert-Warning -Prompt 'DROP TABLE users' -Label 'DROP TABLE (uppercase) -> warning'
Assert-Warning -Prompt 'drop production database' -Label 'drop production -> warning'
Assert-Warning -Prompt 'drop whole cluster' -Label 'drop whole -> warning'

# --- Patterns with intervening words (NOT matched by current regex) ---
Write-Host ''
Write-Host '[Not matched: intervening words]'
Assert-Silent -Prompt 'delete the production server' -Label "delete the production -> silent (intervening 'the')"
Assert-Silent -Prompt 'please delete the whole thing' -Label "delete the whole -> silent (intervening 'the')"
Assert-Silent -Prompt 'drop the database' -Label "drop the database -> silent (intervening 'the')"
Assert-Silent -Prompt 'drop the entire schema' -Label "drop the entire -> silent (intervening 'the')"
Assert-Silent -Prompt 'remove the production environment' -Label "remove the production -> silent (intervening 'the')"

# --- Safe prompts ---
Write-Host ''
Write-Host '[Safe prompts]'
Assert-Silent -Prompt 'list all files' -Label 'list all -> silent'
Assert-Silent -Prompt 'show me the database schema' -Label 'show database -> silent'
Assert-Silent -Prompt 'how do I delete a single record?' -Label 'question about delete -> silent'
Assert-Silent -Prompt 'create a new table' -Label 'create table -> silent'
Assert-Silent -Prompt 'refactor the authentication module' -Label 'refactor -> silent'
Assert-Silent -Prompt 'run the tests' -Label 'run tests -> silent'
Assert-Silent -Prompt 'fix the login bug' -Label 'fix bug -> silent'
Assert-Silent -Prompt 'add error handling to the controller' -Label 'add error handling -> silent'

# --- Edge cases: partial keyword matches ---
Write-Host ''
Write-Host '[Edge cases]'
Assert-Silent -Prompt 'the dropdown menu is broken' -Label "dropdown (contains 'drop') -> silent"
Assert-Silent -Prompt 'removed the unused import' -Label "past tense 'removed' -> silent"
Assert-Silent -Prompt 'undelete the record' -Label 'undelete -> silent'

# --- Exit code is always 0 ---
Write-Host ''
Write-Host '[Exit code always 0]'
$null = & pwsh -NoProfile -Command "& { `$env:CLAUDE_USER_PROMPT = 'delete all databases'; & '$($script:HookPath)' 2>`$null }" 2>$null
if ($LASTEXITCODE -eq 0) {
    $script:Passed++
    Write-Host '  PASS: Warning prompt -> exit 0' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add('FAIL: Warning prompt - expected exit 0')
    Write-Host '  FAIL: Warning prompt -> exit 0' -ForegroundColor Red
}

$null = & pwsh -NoProfile -Command "& { `$env:CLAUDE_USER_PROMPT = 'list files'; & '$($script:HookPath)' 2>`$null }" 2>$null
if ($LASTEXITCODE -eq 0) {
    $script:Passed++
    Write-Host '  PASS: Safe prompt -> exit 0' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add('FAIL: Safe prompt - expected exit 0')
    Write-Host '  FAIL: Safe prompt -> exit 0' -ForegroundColor Red
}

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
