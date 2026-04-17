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
    param([string]$Mode, [string[]]$Files)
    $output = & $python $Linter '--mode' $Mode '--quiet' @Files 2>&1 | Out-String
    return @{ Exit = $LASTEXITCODE; Output = $output }
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
        $script:ERRORS += "FAIL: $Label -- output did not contain '$Needle'"
        Write-Host "  FAIL: $Label"
    }
}

Write-Host "=== spec_lint.py / spec_lint.ps1 tests ==="
Write-Host ""

# ── Fixture: valid SKILL.md ──────────────────────────────────
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

# ── Fixture: underscore typo ─────────────────────────────────
$TypoSkill = Join-Path $Work 'typo-skill.md'
Write-Fixture $TypoSkill @'
---
name: typo-skill
description: SKILL with underscore typo on disable_model_invocation field for did-you-mean coverage.
disable_model_invocation: true
---

content
'@

Write-Host ""
Write-Host "[case 2: underscore typo caught with did-you-mean]"
$r = Invoke-Lint 'skill' @($TypoSkill)
Assert-Exit 1 $r.Exit 'underscore typo -> exit 1'
Assert-Contains "did you mean 'disable-model-invocation'" $r.Output 'did-you-mean suggestion present'

# ── Fixture: unknown field ───────────────────────────────────
$UnkSkill = Join-Path $Work 'unknown-field-skill.md'
Write-Fixture $UnkSkill @'
---
name: unknown-field
description: SKILL with a totally unknown field that must be rejected by the additionalProperties rule.
memory: persistent
---

content
'@

Write-Host ""
Write-Host "[case 3: unknown field rejected]"
$r = Invoke-Lint 'skill' @($UnkSkill)
Assert-Exit 1 $r.Exit "unknown 'memory' field -> exit 1"
Assert-Contains 'unknown field(s)' $r.Output 'unknown field message'

# ── Fixture: invalid enum values ─────────────────────────────
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

# ── Fixture: description too long ────────────────────────────
$LongDesc = 'x' * 1100
$LongSkill = Join-Path $Work 'long-desc-skill.md'
Write-Fixture $LongSkill @"
---
name: long-desc
description: $LongDesc
---

content
"@

Write-Host ""
Write-Host "[case 5: description >1024 chars rejected]"
$r = Invoke-Lint 'skill' @($LongSkill)
Assert-Exit 1 $r.Exit '1100-char description -> exit 1'
Assert-Contains 'is too long' $r.Output 'max length error'

# ── Fixture: missing required name ───────────────────────────
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

# ── Fixture: plugin.json bad semver ──────────────────────────
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
Write-Host "[case 7: plugin.json with bad semver rejected]"
$r = Invoke-Lint 'plugin' @($BadPlugin)
Assert-Exit 1 $r.Exit 'bad semver -> exit 1'
Assert-Contains 'does not match' $r.Output 'semver pattern error'

# ── Fixture: settings.json with bad enums ────────────────────
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

# ── Mode flags ───────────────────────────────────────────────
Write-Host ""
Write-Host "[case 9: --warn-only exits 0 even on violations]"
& $python $Linter '--mode' 'skill' '--warn-only' '--quiet' $EnumSkill *> $null
Assert-Exit 0 $LASTEXITCODE '--warn-only on violations -> exit 0'

Write-Host ""
Write-Host "[case 10: --strict exits 2 on violations]"
& $python $Linter '--mode' 'skill' '--strict' '--quiet' $EnumSkill *> $null
Assert-Exit 2 $LASTEXITCODE '--strict on violations -> exit 2'

# ── Wrapper invocation ───────────────────────────────────────
Write-Host ""
Write-Host "[case 11: spec_lint.ps1 wrapper works in -Mode form]"
& $Wrapper -Mode 'skill' $GoodSkill *> $null
Assert-Exit 0 $LASTEXITCODE 'wrapper -Mode skill on valid file -> exit 0'

& $Wrapper -Mode 'skill' $EnumSkill *> $null
Assert-Exit 1 $LASTEXITCODE 'wrapper -Mode skill on bad file -> exit 1'

& $Wrapper -Mode 'skill' -WarnOnly $EnumSkill *> $null
Assert-Exit 0 $LASTEXITCODE 'wrapper -WarnOnly -> exit 0 even on violations'

# ── Repo discovery ───────────────────────────────────────────
Write-Host ""
Write-Host "[case 12: full repo lints clean (regression guard)]"
& $Wrapper -Quiet *> $null
Assert-Exit 0 $LASTEXITCODE 'all canonical SKILL.md/plugin.json/settings.json pass'

# ── Summary ──────────────────────────────────────────────────
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
