#Requires -Version 7.0
<#
.SYNOPSIS
    Test suite for scripts/spec_lint.{py,ps1}.

.DESCRIPTION
    PowerShell twin of test-spec-lint.sh. Exercises the same set of cases
    against spec_lint.py and the spec_lint.ps1 wrapper.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Linter  = Join-Path $RootDir 'scripts' 'spec_lint.py'
$Wrapper = Join-Path $RootDir 'scripts' 'spec_lint.ps1'

# Locate Python
$python = $null
foreach ($c in @('python3', 'python', 'py')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; break }
}
if (-not $python) {
    Write-Host "SKIP: python3/python not in PATH"
    exit 0
}

& $python -c "import yaml, jsonschema" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "SKIP: missing PyYAML or jsonschema"
    exit 0
}

$Work = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())) -Force
$script:PASS = 0
$script:FAIL = 0
$script:ERRORS = @()

function Write-Fixture {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content)
}

function Invoke-Lint {
    param(
        [string]$Mode,
        [string[]]$Files,
        [switch]$StrictSchema
    )
    $oldStrict = $env:STRICT_SCHEMA
    try {
        if ($StrictSchema) { $env:STRICT_SCHEMA = '1' }
        else { Remove-Item Env:STRICT_SCHEMA -ErrorAction SilentlyContinue }
        $output = & $python $Linter '--mode' $Mode '--quiet' @Files 2>&1 | Out-String
        return @{ Exit = $LASTEXITCODE; Output = $output }
    } finally {
        if ($null -eq $oldStrict) { Remove-Item Env:STRICT_SCHEMA -ErrorAction SilentlyContinue }
        else { $env:STRICT_SCHEMA = $oldStrict }
    }
}

function Assert-Exit {
    param([int]$Expected, [int]$Actual, [string]$Label)
    if ($Actual -eq $Expected) {
        $script:PASS++
        Write-Host "  PASS: $Label (exit $Actual)"
    } else {
        $script:FAIL++
        $script:ERRORS += "FAIL: $Label -- expected exit $Expected, got $Actual"
        Write-Host "  FAIL: $Label (expected $Expected, got $Actual)"
    }
}

function Assert-Contains {
    param([string]$Needle, [string]$Output, [string]$Label)
    if ($Output -like "*$Needle*") {
        $script:PASS++
        Write-Host "  PASS: $Label"
    } else {
        $script:FAIL++
        $script:ERRORS += "FAIL: $Label -- output did not contain '$Needle': $Output"
        Write-Host "  FAIL: $Label"
    }
}

Write-Host "=== spec_lint.py / spec_lint.ps1 tests ==="
Write-Host ""

# -- Fixture: valid SKILL.md -------------------------------------------------
$GoodSkill = Join-Path $Work 'good-skill.md'
Write-Fixture $GoodSkill @'
---
name: good-skill
description: A valid SKILL.md fixture used by the spec linter test suite. Long enough to satisfy any minimum length recommendations.
disable-model-invocation: true
user-invocable: true
allowed-tools: "Bash(git *)"
context: fork
effort: high
---

content
'@

Write-Host "[case 1: valid SKILL.md passes]"
$r = Invoke-Lint 'skill' @($GoodSkill)
Assert-Exit 0 $r.Exit 'valid SKILL.md -> exit 0'

# -- Fixture: underscore typo (did-you-mean) ---------------------------------
$TypoSkill = Join-Path $Work 'typo-skill.md'
Write-Fixture $TypoSkill @'
---
name: typo-skill
description: SKILL with underscore typo on disable_model_invocation field. Lenient accepts; strict + _internal/ catches with did-you-mean.
disable_model_invocation: true
---

content
'@

Write-Host ""
Write-Host "[case 2: lenient accepts underscore typo silently]"
$r = Invoke-Lint 'skill' @($TypoSkill)
Assert-Exit 0 $r.Exit 'lenient accepts unknown field -> exit 0'

$InternalTypoDir = Join-Path $Work 'repo/global/skills/_internal/typo'
$InternalTypo = Join-Path $InternalTypoDir 'SKILL.md'
Write-Fixture $InternalTypo @'
---
name: typo-strict
description: Strict-mode underscore-typo fixture under _internal/ path. additionalProperties:false must reject.
disable_model_invocation: true
---

content
'@

Write-Host ""
Write-Host "[case 2-strict: strict + _internal/ catches underscore typo with did-you-mean]"
$r = Invoke-Lint 'skill' @($InternalTypo) -StrictSchema
Assert-Exit 1 $r.Exit 'strict + _internal/ on typo -> exit 1'
Assert-Contains "did you mean 'disable-model-invocation'" $r.Output 'did-you-mean suggestion present'

# -- Fixture: unknown field accepted by lenient, rejected by strict ----------
$UnkSkill = Join-Path $Work 'unknown-field-skill.md'
Write-Fixture $UnkSkill @'
---
name: unknown-field
description: SKILL with a totally unknown field. Lenient accepts (additionalProperties:true); strict + _internal/ rejects.
memory: persistent
---

content
'@

Write-Host ""
Write-Host "[case 3: lenient accepts unknown 'memory' field]"
$r = Invoke-Lint 'skill' @($UnkSkill)
Assert-Exit 0 $r.Exit 'lenient accepts unknown -> exit 0'

$InternalUnkDir = Join-Path $Work 'repo/global/skills/_internal/unk'
$InternalUnk = Join-Path $InternalUnkDir 'SKILL.md'
Write-Fixture $InternalUnk @'
---
name: unk-strict
description: Strict-mode unknown-field fixture under _internal/. additionalProperties:false must reject.
memory: persistent
---

content
'@

Write-Host ""
Write-Host "[case 3-strict: strict + _internal/ rejects unknown 'memory' field]"
$r = Invoke-Lint 'skill' @($InternalUnk) -StrictSchema
Assert-Exit 1 $r.Exit "strict + _internal/ on unknown field -> exit 1"
Assert-Contains 'unknown field(s)' $r.Output 'unknown field message'

# -- Fixture: invalid enum values -------------------------------------------
$EnumSkill = Join-Path $Work 'bad-enum-skill.md'
Write-Fixture $EnumSkill @'
---
name: bad-enum
description: SKILL with invalid enum values for effort, context, and shell. Must be rejected by the schema.
effort: turbo
context: warp
shell: zsh
---

content
'@

Write-Host ""
Write-Host "[case 4: invalid enum values rejected]"
$r = Invoke-Lint 'skill' @($EnumSkill)
Assert-Exit 1 $r.Exit 'bad effort/context/shell -> exit 1'
Assert-Contains "'turbo' is not one of" $r.Output 'effort enum error'
Assert-Contains "'warp' is not one of"  $r.Output 'context enum error'
Assert-Contains "'zsh' is not one of"   $r.Output 'shell enum error'

# -- Fixture: description too long ------------------------------------------
$LongDesc = 'x' * 1600
$LongSkill = Join-Path $Work 'long-desc-skill.md'
Write-Fixture $LongSkill @"
---
name: long-desc
description: $LongDesc
---

content
"@

Write-Host ""
Write-Host "[case 5: description >1536 chars rejected]"
$r = Invoke-Lint 'skill' @($LongSkill)
Assert-Exit 1 $r.Exit '1600-char description -> exit 1'
Assert-Contains 'is too long' $r.Output 'max length error'

# -- Fixture: missing required name/description -----------------------------
$NoName = Join-Path $Work 'no-name-skill.md'
Write-Fixture $NoName @'
---
description: SKILL missing the required name field. Must be rejected by the linter as a required-field violation.
---

content
'@

Write-Host ""
Write-Host "[case 6: missing required name -> rejected]"
$r = Invoke-Lint 'skill' @($NoName)
Assert-Exit 1 $r.Exit 'missing name -> exit 1'
Assert-Contains "'name' is a required property" $r.Output 'missing name error'

$NoDesc = Join-Path $Work 'no-desc-skill.md'
Write-Fixture $NoDesc @'
---
name: no-desc
---

content
'@

Write-Host ""
Write-Host "[case 6b: missing required description -> rejected]"
$r = Invoke-Lint 'skill' @($NoDesc)
Assert-Exit 1 $r.Exit 'missing description -> exit 1'
Assert-Contains "'description' is a required property" $r.Output 'missing description error'

# -- Fixture: plugin.json with unknown field --------------------------------
$BadPlugin = Join-Path $Work 'bad-plugin.json'
Write-Fixture $BadPlugin @'
{
  "name": "test-plugin",
  "version": "not-a-semver",
  "description": "Plugin with invalid semver for version field validation.",
  "future_field": "tolerated"
}
'@

Write-Host ""
Write-Host "[case 7: plugin.json with bad semver rejected, unknown top-level tolerated]"
$r = Invoke-Lint 'plugin' @($BadPlugin)
Assert-Exit 1 $r.Exit 'bad semver -> exit 1'
Assert-Contains 'does not match' $r.Output 'semver pattern error'

# -- Fixture: settings.json with bad enums ----------------------------------
$BadSettings = Join-Path $Work 'bad-settings.json'
Write-Fixture $BadSettings @'
{
  "teammateMode": "telepathic",
  "effortLevel": "ludicrous",
  "permissions": {
    "defaultMode": "yolo"
  }
}
'@

Write-Host ""
Write-Host "[case 8: settings.json with bad enum rejected]"
$r = Invoke-Lint 'settings' @($BadSettings)
Assert-Exit 1 $r.Exit 'bad enums -> exit 1'
Assert-Contains "'telepathic' is not one of" $r.Output 'teammateMode enum error'
Assert-Contains "'ludicrous' is not one of"  $r.Output 'effortLevel enum error'
Assert-Contains "'yolo' is not one of"       $r.Output 'permissions.defaultMode enum error'

# -- Mode flags --------------------------------------------------------------
Write-Host ""
Write-Host "[case 9: --warn-only exits 0 even on violations]"
& $python $Linter '--mode' 'skill' '--warn-only' '--quiet' $EnumSkill *> $null
Assert-Exit 0 $LASTEXITCODE '--warn-only on violations -> exit 0'

Write-Host ""
Write-Host "[case 10: --strict exits 2 on violations]"
& $python $Linter '--mode' 'skill' '--strict' '--quiet' $EnumSkill *> $null
Assert-Exit 2 $LASTEXITCODE '--strict on violations -> exit 2'

# -- halt_conditions coverage (A1/P1, mirrors bash cases 10a-10j) -----------
$HaltArraySkill = Join-Path $Work 'halt-array-skill.md'
Write-Fixture $HaltArraySkill @'
---
name: halt-array-skill
description: SKILL.md verifying that the new halt_conditions array form is accepted by the schema.
max_iterations: 5
halt_conditions:
  - { type: success, expr: "All checks pass" }
  - { type: limit, expr: "max_iterations reached" }
loop_safe: true
---

content
'@

Write-Host ""
Write-Host "[case 10a: halt_conditions array form accepted]"
$r = Invoke-Lint 'skill' @($HaltArraySkill)
Assert-Exit 0 $r.Exit 'halt_conditions array -> exit 0'

$HaltStringSkill = Join-Path $Work 'halt-string-skill.md'
Write-Fixture $HaltStringSkill @'
---
name: halt-string-skill
description: SKILL.md verifying that the legacy halt_conditions single-string form is still accepted during the P1 grace period.
halt_conditions: "All checks pass OR user aborts"
---

content
'@

Write-Host ""
Write-Host "[case 10b: halt_conditions legacy string form accepted]"
$r = Invoke-Lint 'skill' @($HaltStringSkill)
Assert-Exit 0 $r.Exit 'halt_conditions string -> exit 0'

$HaltEmptySkill = Join-Path $Work 'halt-empty-skill.md'
Write-Fixture $HaltEmptySkill @'
---
name: halt-empty-skill
description: SKILL.md verifying that an empty halt_conditions array is rejected by the schema.
halt_conditions: []
---

content
'@

Write-Host ""
Write-Host "[case 10c: halt_conditions empty array rejected]"
$r = Invoke-Lint 'skill' @($HaltEmptySkill)
Assert-Exit 1 $r.Exit 'halt_conditions [] -> exit 1'

$HaltBadTypeSkill = Join-Path $Work 'halt-bad-type-skill.md'
Write-Fixture $HaltBadTypeSkill @'
---
name: halt-bad-type-skill
description: SKILL.md with an unknown halt_conditions entry type. Lenient accepts; strict + _internal/ rejects via enum.
halt_conditions:
  - { type: telepathy, expr: "psychic signal" }
---

content
'@

Write-Host ""
Write-Host "[case 10d: lenient accepts halt_conditions with unknown entry type]"
$r = Invoke-Lint 'skill' @($HaltBadTypeSkill)
Assert-Exit 0 $r.Exit 'lenient -> exit 0'

$InternalHaltBadDir = Join-Path $Work 'repo/global/skills/_internal/halt-bad'
$InternalHaltBad = Join-Path $InternalHaltBadDir 'SKILL.md'
Write-Fixture $InternalHaltBad @'
---
name: halt-bad-strict
description: Strict-mode fixture for halt_conditions enum violation under _internal/ path.
halt_conditions:
  - { type: telepathy, expr: "psychic signal" }
---

content
'@

Write-Host ""
Write-Host "[case 10d-strict: strict + _internal/ rejects unknown halt_conditions type]"
$r = Invoke-Lint 'skill' @($InternalHaltBad) -StrictSchema
Assert-Exit 1 $r.Exit 'strict + _internal/ on bad halt type -> exit 1'

$IterNoHaltSkill = Join-Path $Work 'iter-no-halt-skill.md'
Write-Fixture $IterNoHaltSkill @'
---
name: iter-no-halt-skill
description: SKILL.md declaring max_iterations but missing halt_conditions. Lenient accepts; strict + _internal/ path rejects.
max_iterations: 5
---

content
'@

Write-Host ""
Write-Host "[case 10e: lenient (default) accepts max_iterations without halt_conditions]"
$r = Invoke-Lint 'skill' @($IterNoHaltSkill)
Assert-Exit 0 $r.Exit 'lenient mode -> exit 0'

$LoopNoHaltSkill = Join-Path $Work 'loop-no-halt-skill.md'
Write-Fixture $LoopNoHaltSkill @'
---
name: loop-no-halt-skill
description: SKILL.md declaring loop_safe true but missing halt_conditions. Lenient accepts; strict + _internal/ path rejects.
loop_safe: true
---

content
'@

Write-Host ""
Write-Host "[case 10f: lenient (default) accepts loop_safe: true without halt_conditions]"
$r = Invoke-Lint 'skill' @($LoopNoHaltSkill)
Assert-Exit 0 $r.Exit 'lenient mode -> exit 0'

$LoopFalseSkill = Join-Path $Work 'loop-false-skill.md'
Write-Fixture $LoopFalseSkill @'
---
name: loop-false-skill
description: SKILL.md with loop_safe false and no halt_conditions. Always accepted (rule never applies).
loop_safe: false
---

content
'@

Write-Host ""
Write-Host "[case 10g: loop_safe: false without halt_conditions accepted (lenient and strict)]"
$r = Invoke-Lint 'skill' @($LoopFalseSkill)
Assert-Exit 0 $r.Exit 'lenient mode -> exit 0'

$InternalRoot = Join-Path $Work 'repo/global/skills/_internal'
$InternalIter = Join-Path $InternalRoot 'iter-strict/SKILL.md'
$InternalLoop = Join-Path $InternalRoot 'loop-strict/SKILL.md'
Write-Fixture $InternalIter @'
---
name: iter-strict
description: Strict-mode fixture (max_iterations declared, halt_conditions missing) under a simulated _internal/ path. P1-c must reject under STRICT_SCHEMA=1.
max_iterations: 5
---

content
'@
Write-Fixture $InternalLoop @'
---
name: loop-strict
description: Strict-mode fixture (loop_safe true, halt_conditions missing) under a simulated _internal/ path. P1-c must reject under STRICT_SCHEMA=1.
loop_safe: true
---

content
'@

Write-Host ""
Write-Host "[case 10h: strict + _internal/ rejects max_iterations without halt_conditions]"
$r = Invoke-Lint 'skill' @($InternalIter) -StrictSchema
Assert-Exit 1 $r.Exit 'strict + _internal/ on iter -> exit 1'
Assert-Contains "'halt_conditions' is a required property" $r.Output 'P1-c rejection message'

Write-Host ""
Write-Host "[case 10i: strict + _internal/ rejects loop_safe true without halt_conditions]"
$r = Invoke-Lint 'skill' @($InternalLoop) -StrictSchema
Assert-Exit 1 $r.Exit 'strict + _internal/ on loop_safe -> exit 1'
Assert-Contains "'halt_conditions' is a required property" $r.Output 'P1-c rejection message'

Write-Host ""
Write-Host "[case 10j: strict ON but path NOT in _internal/ -> dispatches to lenient]"
$r = Invoke-Lint 'skill' @($IterNoHaltSkill) -StrictSchema
Assert-Exit 0 $r.Exit 'strict ON outside _internal/ -> still lenient -> exit 0'

# -- Wrapper invocation ------------------------------------------------------
Write-Host ""
Write-Host "[case 11: spec_lint.ps1 wrapper works in -Mode form]"
& $Wrapper -Mode 'skill' $GoodSkill *> $null
Assert-Exit 0 $LASTEXITCODE 'wrapper -Mode skill on valid file -> exit 0'

& $Wrapper -Mode 'skill' $EnumSkill *> $null
Assert-Exit 1 $LASTEXITCODE 'wrapper -Mode skill on bad file -> exit 1'

& $Wrapper -Mode 'skill' -WarnOnly $EnumSkill *> $null
Assert-Exit 0 $LASTEXITCODE 'wrapper -WarnOnly -> exit 0 even on violations'

# -- Repo discovery ----------------------------------------------------------
Write-Host ""
Write-Host "[case 12: full repo lints clean (regression guard)]"
& $Wrapper -Quiet *> $null
Assert-Exit 0 $LASTEXITCODE 'all canonical SKILL.md/plugin.json/settings.json pass'

Write-Host ""
Write-Host "[case 12b: wrapper default output does not corrupt exit code]"
& $Wrapper -Quiet
Assert-Exit 0 $LASTEXITCODE 'wrapper -Quiet with visible output -> exit 0'

# -- sync.ps1 integration: --lint fast-path is side-effect free --------------
Write-Host ""
Write-Host "[case 13: sync.ps1 --lint is a side-effect-free fast path]"
$syncPs1 = Join-Path $RootDir 'scripts' 'sync.ps1'
& pwsh -NoProfile -File $syncPs1 '--lint' '--quiet' *> $null
Assert-Exit 0 $LASTEXITCODE 'sync.ps1 --lint returns linter exit code (no prompts)'

# -- sync.ps1 integration: pre-flight aborts on lint failure -----------------
Write-Host ""
Write-Host "[case 14: sync.ps1 (no flag) aborts when spec_lint detects violations]"
$Sandbox = Join-Path $Work 'sync-abort-sandbox'
$SandboxScripts = Join-Path $Sandbox 'scripts'
$SandboxLib     = Join-Path $Sandbox 'global' 'hooks' 'lib'
New-Item -ItemType Directory -Path $SandboxScripts -Force | Out-Null
New-Item -ItemType Directory -Path $SandboxLib     -Force | Out-Null
@'
#Requires -Version 7.0
exit 1
'@ | Set-Content -LiteralPath (Join-Path $SandboxScripts 'spec_lint.ps1') -Encoding UTF8
@'
function Write-InfoMessage    { param([string]$Msg) Write-Host $Msg }
function Write-SuccessMessage { param([string]$Msg) Write-Host $Msg }
function Write-WarningMessage { param([string]$Msg) Write-Host $Msg }
function Write-ErrorMessage   { param([string]$Msg) Write-Host $Msg }
function Write-Banner         { param([string]$Title) Write-Host "=== $Title ===" }
function Get-EnterprisePath   { return 'C:/stub/enterprise' }
function Test-Administrator   { return $true }
function Ensure-Directory     { param([string]$Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null }
Export-ModuleMember -Function *
'@ | Set-Content -LiteralPath (Join-Path $SandboxLib 'CommonHelpers.psm1') -Encoding UTF8
Copy-Item -LiteralPath $syncPs1 -Destination $SandboxScripts -Force
$abortOut = & pwsh -NoProfile -File (Join-Path $SandboxScripts 'sync.ps1') 2>&1 | Out-String
Assert-Exit 1 $LASTEXITCODE 'sync.ps1 aborts with exit 1 when linter fails'
Assert-Contains 'spec_lint detected schema violations' $abortOut 'abort message present'
Assert-Contains '--skip-lint' $abortOut 'bypass hint present'

# -- sync.ps1 integration: --skip-lint bypasses pre-flight -------------------
Write-Host ""
Write-Host "[case 15: sync.ps1 --skip-lint bypasses pre-flight even when linter fails]"
$bypassOut = '3' | & pwsh -NoProfile -File (Join-Path $SandboxScripts 'sync.ps1') '--skip-lint' 2>&1 | Out-String
if ($bypassOut -like '*spec_lint detected schema violations*') {
    $script:FAIL++
    $script:ERRORS += 'FAIL: --skip-lint should suppress abort message but did not'
    Write-Host '  FAIL: --skip-lint suppresses abort message'
} else {
    $script:PASS++
    Write-Host '  PASS: --skip-lint suppresses abort message'
}
Assert-Contains 'Claude Configuration Sync Tool' $bypassOut 'banner displayed (pre-flight bypassed)'

# -- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host '=== Summary ==='
Write-Host "  $($script:PASS) passed, $($script:FAIL) failed"
if ($script:ERRORS.Count -gt 0) {
    Write-Host ''
    Write-Host 'Errors:'
    foreach ($e in $script:ERRORS) { Write-Host "  $e" }
    Remove-Item -Recurse -Force $Work
    exit 1
}
Remove-Item -Recurse -Force $Work
exit 0
