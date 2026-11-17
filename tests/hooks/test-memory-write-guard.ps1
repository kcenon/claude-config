#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for memory-write-guard.ps1 (issue #972)
# Run: pwsh tests/hooks/test-memory-write-guard.ps1
#
# PowerShell counterpart of test-memory-write-guard.sh. Before #972 the guard
# threw on every path under the memory root (`Split-Path -LiteralPath` cannot
# be combined with -Leaf or -Parent), and edit-guard-dispatcher.ps1 runs it
# fail-open, so every memory write on Windows went through unvalidated. The
# guard runs here as its own process: a crash prints no JSON, which the cases
# report as "(no parseable response)" instead of an allow.
#
# HOME and USERPROFILE point at a temporary directory, reached through a
# symlink where the platform allows one (as in the .sh suite). The validators
# are not installed under that HOME, so the guard's last locator candidate
# (../../scripts/memory next to the hook) finds the repo's copies. They run
# through `bash`; without one on PATH the validator cases print SKIP.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'memory-write-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Invoke-Guard {
    param([string]$InputJson)
    $raw = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
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
    $r = Invoke-Guard $InputJson
    $got = if ($r) { [string]$r.permissionDecision } else { '(no parseable response)' }
    Assert-Condition ($got -eq $Expected) $Label "expected $Expected, got: $got"
}

function New-WritePayload {
    param([string]$Tool, [string]$Path, [string]$Content)
    return (@{ tool_name = $Tool; tool_input = @{ file_path = $Path; content = $Content } } | ConvertTo-Json -Depth 4 -Compress)
}

function New-EditPayload {
    param([string]$Path, [string]$Old, [string]$New, [bool]$ReplaceAll = $false)
    $o = @{ tool_name = 'Edit'; tool_input = @{ file_path = $Path; old_string = $Old; new_string = $New; replace_all = $ReplaceAll } }
    return ($o | ConvertTo-Json -Depth 4 -Compress)
}

# .ps1 files are checked out with CRLF (.gitattributes); the validators parse
# LF frontmatter, so fixtures are normalized before use.
function ConvertTo-Lf { param([string]$Text) return ($Text -replace "`r", '') }

$CleanBody = ConvertTo-Lf @'
---
name: Clean memory
description: A clean test fixture.
type: feedback
---

This is a body. **Why:** because we need a clean test fixture incident reference. **How to apply:** use this exact pattern when validating new feedback memories.
'@

$MissingFieldBody = ConvertTo-Lf @'
---
name: Missing description
type: feedback
---

This is a body. **Why:** because we need a structural failure fixture. **How to apply:** use this exact pattern when validating new feedback memories.
'@

$SecretBody = ConvertTo-Lf @'
---
name: Bad memory
description: Has a leaked AWS key.
type: feedback
---

body body body body body. **Why:** test reason. **How to apply:** key is AKIAIOSFODNN7EXAMPLE oh no.
'@

$NestedTypeBody = ConvertTo-Lf @'
---
name: Nested type memory
description: Auto-memory layout with type nested under metadata.
metadata:
  node_type: memory
  type: feedback
---

This is a body. **Why:** because auto-memory writes type under metadata. **How to apply:** accept the nested layout when validating memory writes.
'@

$InjectionBody = ConvertTo-Lf @'
---
name: Strict rule
description: Multiple absolute commands.
type: feedback
---

You must always commit messages. Never skip CI. Always run tests because incident #142 happened. From now on we always test. **Why:** safety. **How to apply:** read the rules.
'@

$EditTargetBody = ConvertTo-Lf @'
---
name: Edit target
description: An existing memory used to test edit-time validation.
type: feedback
---

Original body. **Why:** because we set it up. **How to apply:** read the original.
'@

# ----- temporary HOME ---------------------------------------------------------

$saved = @{}
foreach ($n in 'HOME', 'USERPROFILE', 'OWNER_EMAILS', 'OWNER_GITHUB_HANDLE', 'OWNER_HOME_USER') {
    $saved[$n] = [System.Environment]::GetEnvironmentVariable($n)
}

$homeReal = Join-Path ([System.IO.Path]::GetTempPath()) "mwg-home-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $homeReal -Force | Out-Null
$homeLink = "$homeReal.link"
$testHome = $homeReal
try {
    New-Item -ItemType SymbolicLink -Path $homeLink -Target $homeReal -ErrorAction Stop | Out-Null
    $testHome = $homeLink
} catch {}

try {
    $env:HOME        = $testHome
    $env:USERPROFILE = $testHome
    # secret-check.sh fails closed without OWNER_EMAILS (#618); same test owner
    # as the .sh suite and CI.
    $env:OWNER_EMAILS        = 'test-owner@example.com'
    $env:OWNER_GITHUB_HANDLE = 'test-owner'
    $env:OWNER_HOME_USER     = 'test-owner'

    $mem = Join-Path $testHome '.claude' 'memory-shared' 'memories'
    New-Item -ItemType Directory -Path $mem -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testHome '.claude' 'other') -Force | Out-Null

    $bash = Get-Command bash -ErrorAction SilentlyContinue

    Write-Host '=== memory-write-guard.ps1 tests ==='
    Write-Host "  HOME: $testHome"
    Write-Host "  bash: $(if ($bash) { $bash.Source } else { '(not found)' })"
    Write-Host ''

    Write-Host '[Pass-through]'
    Assert-Decision '' 'allow' 'Empty stdin -> allow (fail-open)'
    Assert-Decision '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' 'allow' 'Read tool -> allow (only Edit/Write guarded)'
    Assert-Decision '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 'allow' 'Bash tool -> allow'
    Assert-Decision '{"tool_name":"Write","tool_input":{"content":"x"}}' 'allow' 'Missing file_path -> allow (fail-open)'
    Assert-Decision (New-WritePayload 'Write' (Join-Path $testHome 'notes' 'non-memory.md') $SecretBody) 'allow' 'Path outside the memory root -> allow'
    Assert-Decision (New-WritePayload 'Write' (Join-Path $mem 'MEMORY.md') 'index') 'allow' 'MEMORY.md -> allow (exempt)'

    Write-Host ''
    if (-not $bash) {
        Write-Host '  SKIP: memory write decisions, Edit simulation, path normalization (no bash on PATH to run the validators)'
    } else {
        Write-Host '[Memory write decisions]'
        Assert-Decision (New-WritePayload 'Write' (Join-Path $mem 'feedback_clean.md') $CleanBody) 'allow' 'Clean memory write -> allow'
        Assert-Decision (New-WritePayload 'Write' (Join-Path $mem 'feedback_nested.md') $NestedTypeBody) 'allow' 'Auto-memory metadata.type layout -> allow (#956)'
        Assert-Decision (New-WritePayload 'Write' (Join-Path $mem 'feedback_nodesc.md') $MissingFieldBody) 'deny' 'Missing frontmatter field -> deny'
        Assert-Decision (New-WritePayload 'Write' (Join-Path $mem 'feedback_leak.md') $SecretBody) 'deny' 'Secret in memory -> deny'
        $r = Invoke-Guard (New-WritePayload 'Write' (Join-Path $mem 'feedback_strict.md') $InjectionBody)
        $ctx = if ($r) { [string]$r.additionalContext } else { '' }
        Assert-Condition ($r -and $r.permissionDecision -eq 'allow' -and $ctx -match 'injection-check') 'Injection density -> allow with feedback (warn-only)' "decision: $(if ($r) { $r.permissionDecision } else { '(none)' }), context: $ctx"

        Write-Host ''
        Write-Host '[Edit simulation]'
        $target = Join-Path $mem 'feedback_edit_target.md'
        [System.IO.File]::WriteAllText($target, $EditTargetBody)
        Assert-Decision (New-EditPayload $target 'Original body' 'Updated body') 'allow' 'Clean Edit -> allow'
        Assert-Decision (New-EditPayload $target "description: An existing memory used to test edit-time validation.`n" '') 'deny' 'Edit removes a required field -> deny'
        Assert-Decision (New-EditPayload $target 'Original body.' 'AKIAIOSFODNN7EXAMPLE leaked.') 'deny' 'Edit injects secret -> deny'
        Assert-Decision (New-EditPayload $target 'the' 'AKIAIOSFODNN7EXAMPLE' $true) 'deny' 'Edit replace_all injects secret -> deny'

        Write-Host ''
        Write-Host '[Path normalization]'
        # A new file whose parent exists is resolved through that parent, so a
        # dot segment cannot carry it past the prefix gate. Before #972 this
        # resolution threw inside a try and returned the raw path.
        $dotted = Join-Path $testHome '.claude' 'other' '..' 'memory-shared' 'memories' 'feedback_dotted.md'
        Assert-Decision (New-WritePayload 'Write' $dotted $SecretBody) 'deny' 'New file through a dot segment -> resolved and denied'

        Write-Host ''
        Write-Host '[Symlinked HOME]'
        # Another spelling of the same memory file must not miss the prefix gate
        # and go unvalidated, as memory-write-guard.sh already ensures (#983).
        if ($testHome -ne $homeLink) {
            Write-Host '  SKIP: symlinked HOME (this platform could not create the link)'
        } else {
            Write-Host "  link target: $((Get-Item -LiteralPath $homeLink).ResolveLinkTarget($true).FullName)"
            $viaReal = Join-Path $homeReal '.claude' 'memory-shared' 'memories' 'feedback_viareal.md'
            $viaLink = Join-Path $homeLink '.claude' 'memory-shared' 'memories' 'feedback_vialink.md'
            Assert-Decision (New-WritePayload 'Write' $viaReal $SecretBody) 'deny' 'HOME on a link, write through the real path -> denied'
            Assert-Decision (New-WritePayload 'Write' $viaLink $SecretBody) 'deny' 'HOME on a link, write through the link -> denied'
            Assert-Decision (New-WritePayload 'Write' $viaReal $CleanBody) 'allow' 'HOME on a link, clean write through the real path -> allowed'

            $env:HOME = $homeReal
            $env:USERPROFILE = $homeReal
            try {
                Assert-Decision (New-WritePayload 'Write' $viaLink $SecretBody) 'deny' 'real HOME, write through a link -> denied'
                Assert-Decision (New-WritePayload 'Write' $viaReal $SecretBody) 'deny' 'real HOME, write through the real path -> denied'
            }
            finally {
                $env:HOME = $testHome
                $env:USERPROFILE = $testHome
            }
        }
    }
}
finally {
    foreach ($n in $saved.Keys) { [System.Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    if ($testHome -eq $homeLink) { Remove-Item -LiteralPath $homeLink -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $homeReal -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
# Repo-standard summary shape; test-runner.ps1 aggregates /(\d+)\s+passed/ and
# /(\d+)\s+failed/.
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Failed -gt 0) {
    Write-Host ''
    $script:Errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
exit 0
