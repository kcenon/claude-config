#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for markdown-anchor-validator.ps1
# Mirrors tests/hooks/test-markdown-anchor-validator.sh — shared fixtures live
# under tests/markdown-anchor-validator/fixtures/. Both runners must produce
# identical allow/deny decisions on the same fixture so the two variants stay
# behaviorally locked together (see issue #646).
# Run: pwsh tests/hooks/test-markdown-anchor-validator.ps1

$ErrorActionPreference = 'Stop'

$script:RepoRoot     = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath     = Join-Path $script:RepoRoot 'global' 'hooks' 'markdown-anchor-validator.ps1'
$script:FixturesDir  = Join-Path $script:RepoRoot 'tests' 'markdown-anchor-validator' 'fixtures'
$script:Passed       = 0
$script:Failed       = 0
$script:Errors       = [System.Collections.Generic.List[string]]::new()

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: git not on PATH; validator tests require git'
    exit 0
}

# Stage one fixture (and optionally drop a sidecar fixture next to it on
# disk WITHOUT staging) inside an isolated temp git repo, then invoke the
# hook with a synthetic `git commit` tool_input payload and capture the
# JSON response.
function Invoke-HookCapture {
    param(
        [Parameter(Mandatory)][string]$StagedFixture,
        [string]$StagedDest = '',
        [string]$SidecarFixture = '',
        [string]$SidecarDest = ''
    )

    if ([string]::IsNullOrEmpty($StagedDest)) {
        $StagedDest = "docs/$StagedFixture"
    }
    if ($SidecarFixture -and [string]::IsNullOrEmpty($SidecarDest)) {
        $SidecarDest = "docs/$SidecarFixture"
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    $origCwd = Get-Location
    try {
        Set-Location -LiteralPath $tmpDir
        & git init -q 2>$null
        & git config user.email 'ci@example.com'
        & git config user.name  'CI'

        $stagedFull = Join-Path $tmpDir $StagedDest
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagedFull) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:FixturesDir $StagedFixture) -Destination $stagedFull

        if ($SidecarFixture) {
            $sidecarFull = Join-Path $tmpDir $SidecarDest
            New-Item -ItemType Directory -Path (Split-Path -Parent $sidecarFull) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:FixturesDir $SidecarFixture) -Destination $sidecarFull
        }

        # Stage ONLY the primary fixture. The sidecar (if any) stays unstaged
        # — this is the regression scenario from issue #646.
        & git add -- $StagedDest 2>$null

        $payload = '{"tool_input":{"command":"git commit -m test"}}'
        # Redirect stderr (2>) and the warning stream (3>) to $null so the
        # CommonHelpers "unapproved verbs" warning does not leak into
        # stdout and break the JSON parse in Assert-ValidJson.
        $result  = $payload | & pwsh -NoProfile -File $script:HookPath 2>$null 3>$null
        return [string]$result
    } finally {
        Set-Location -LiteralPath $origCwd
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Deny {
    param([string]$Label, [hashtable]$Params)
    $out = Invoke-HookCapture @Params
    if ($out -match '"deny"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected deny, got: $out")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Allow {
    param([string]$Label, [hashtable]$Params)
    $out = Invoke-HookCapture @Params
    if ($out -match '"allow"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected allow, got: $out")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-ValidJson {
    param([string]$Label, [hashtable]$Params)
    $out = Invoke-HookCapture @Params
    # Strip the CommonHelpers "unapproved verbs" warning (and any ANSI escape
    # sequences PowerShell adds when stderr/warning streams leak into stdout)
    # before parsing. The warning is environmental noise unrelated to the
    # hook's JSON contract.
    $cleaned = ($out -split "`n" | Where-Object {
        $_ -notmatch 'WARNING:' -and $_ -notmatch 'unapproved verbs'
    }) -join "`n"
    $cleaned = $cleaned -replace "`e\[[0-9;]*m", ''
    $cleaned = $cleaned.Trim()
    try {
        $null = $cleaned | ConvertFrom-Json -ErrorAction Stop
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } catch {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - output is not valid JSON: $cleaned")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== markdown-anchor-validator.ps1 tests ==='
Write-Host ''

Write-Host '[Bug A: 7+ hashes are not headings]'
Assert-Deny -Label 'ref to ####### line -> deny (broken anchor)' `
    -Params @{ StagedFixture = 'bug-a-excessive-hashes.md' }

Write-Host ''
Write-Host '[Bug B: inline code spans are not live references]'
Assert-Allow -Label '`[a](#x)` inside backticks -> allow' `
    -Params @{ StagedFixture = 'bug-b-inline-code.md' }

Write-Host ''
Write-Host '[Bug C: JSON output remains well-formed with backslash in anchor]'
Assert-ValidJson -Label 'anchor with backslash -> valid JSON' `
    -Params @{ StagedFixture = 'bug-c-backslash.md' }

Write-Host ''
Write-Host '[Baseline: no false positives on well-formed markdown]'
Assert-Allow -Label 'valid intra-file refs -> allow' `
    -Params @{ StagedFixture = 'baseline-valid.md' }

Write-Host ''
Write-Host '[Parity: staged .md outside docs/ is also checked]'
Assert-Deny -Label 'root-level .md with broken anchor -> deny' `
    -Params @{ StagedFixture = 'bug-a-excessive-hashes.md'; StagedDest = 'top-level.md' }

Write-Host ''
Write-Host '[Cross-file resolution: unstaged target with valid anchor -> allow]'
# Regression target for issue #646: staged file references an anchor in a
# sibling file that exists on disk but is NOT staged. Lazy resolution must
# parse the unstaged sibling and recognize the anchor.
Assert-Allow -Label 'unstaged target heading -> allow' `
    -Params @{
        StagedFixture  = 'cross-file-source.md'
        SidecarFixture = 'cross-file-target.md'
    }

Write-Host ''
Write-Host '[Cross-file resolution: existing file but missing anchor -> deny]'
# Negative case authored inline — committing the broken-ref fixture itself
# would trip the validator at commit time, so we materialize the source
# file inside the temp repo at test time instead.
function Invoke-InlineHookCapture {
    param(
        [Parameter(Mandatory)][string]$SourceContent,
        [string]$SidecarFixture = ''
    )
    $tmpDir  = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    $origCwd = Get-Location
    try {
        Set-Location -LiteralPath $tmpDir
        & git init -q 2>$null
        & git config user.email 'ci@example.com'
        & git config user.name  'CI'

        $docs = Join-Path $tmpDir 'docs'
        New-Item -ItemType Directory -Path $docs -Force | Out-Null
        $src = Join-Path $docs 'source.md'
        Set-Content -LiteralPath $src -Value $SourceContent -Encoding utf8 -NoNewline

        if ($SidecarFixture) {
            Copy-Item -LiteralPath (Join-Path $script:FixturesDir $SidecarFixture) `
                      -Destination (Join-Path $docs $SidecarFixture)
        }

        & git add -- 'docs/source.md' 2>$null
        $payload = '{"tool_input":{"command":"git commit -m test"}}'
        $result  = $payload | & pwsh -NoProfile -File $script:HookPath 2>$null 3>$null
        return [string]$result
    } finally {
        Set-Location -LiteralPath $origCwd
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$missingAnchorOut = Invoke-InlineHookCapture `
    -SourceContent "# Source with missing anchor`n`n[missing](cross-file-target.md#definitely-missing-heading)`n" `
    -SidecarFixture 'cross-file-target.md'
if ($missingAnchorOut -match '"deny"') {
    $script:Passed++
    Write-Host '  PASS: unstaged target missing the requested anchor -> deny' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add("FAIL: missing anchor inline case - expected deny, got: $missingAnchorOut")
    Write-Host '  FAIL: unstaged target missing the requested anchor -> deny' -ForegroundColor Red
}

Write-Host ''
Write-Host '[Cross-file resolution: target file does not exist -> deny]'
$missingFileOut = Invoke-InlineHookCapture `
    -SourceContent "# Source with missing file`n`n[missing](no-such-file.md#whatever)`n"
if ($missingFileOut -match '"deny"') {
    $script:Passed++
    Write-Host '  PASS: missing referenced file -> deny' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add("FAIL: missing referenced file - expected deny, got: $missingFileOut")
    Write-Host '  FAIL: missing referenced file -> deny' -ForegroundColor Red
}

Write-Host ''
Write-Host '[Non-commit commands pass through]'
$result = '{"tool_input":{"command":"ls -la"}}' | & pwsh -NoProfile -File $script:HookPath 2>$null
if ($result -match '"allow"') {
    $script:Passed++; Write-Host '  PASS: ls -la -> allow' -ForegroundColor Green
} else {
    $script:Failed++
    $script:Errors.Add("FAIL: ls -la - got: $result")
    Write-Host '  FAIL: ls -la' -ForegroundColor Red
}

Write-Host ''
if ($script:Failed -gt 0) {
    Write-Host 'Failures:'
    foreach ($e in $script:Errors) {
        Write-Host "  $e"
    }
}
Write-Host "=== Results: $script:Passed passed, $script:Failed failed ==="

if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
