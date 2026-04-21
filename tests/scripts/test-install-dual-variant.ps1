#Requires -Version 7.0
<#
.SYNOPSIS
    Regression test for scripts/install.ps1 dual-variant hook deployment (Issue #407).

.DESCRIPTION
    Runs install.ps1 in global-only mode against an isolated scratch $HOME and
    verifies:
      1. Both .ps1 and .sh hook variants land in ~/.claude/hooks/
      2. All installed .sh files use LF-only line endings (no CRLF)
      3. All installed .sh files are UTF-8 without BOM
      4. hooks/lib/ and hooks/known-issues.json are present
      5. scripts/ contains both .ps1 and .sh variants
      6. Every hook stem present in BOTH variants in the source lands in BOTH
         variants in the destination. Pre-existing source-level orphans (a
         .sh with no .ps1 pair, or vice versa) are reported but do not fail
         the test — fixing source orphans is out of scope for the installer.

    Uses plain PowerShell assertions — no Pester dependency.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir    = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Installer  = Join-Path $RootDir 'scripts' 'install.ps1'
$SrcHooks   = Join-Path $RootDir 'global'  'hooks'
$SrcScripts = Join-Path $RootDir 'global'  'scripts'

if (-not (Test-Path $Installer)) {
    Write-Host "FAIL: installer not found at $Installer"
    exit 1
}

$script:PASS = 0
$script:FAIL = 0
$script:ERRORS = @()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:PASS++
        Write-Host "  PASS: $Message"
    } else {
        $script:FAIL++
        $script:ERRORS += $Message
        Write-Host "  FAIL: $Message" -ForegroundColor Red
    }
}

# Scratch HOME (isolated)
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "install-ps1-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Write-Host "Scratch HOME: $scratch"

# Save and override env so the child pwsh initializes $HOME from the scratch path.
# PowerShell resolves $HOME once at session start from $env:HOME (Unix) or
# $env:USERPROFILE (Windows). Setting these env vars inside the child's
# -Command wrapper is too late — they must be set on the parent process
# before spawning the child.
$origUserProfile = $env:USERPROFILE
$origHome        = $env:HOME

try {
    $env:USERPROFILE = $scratch
    $env:HOME        = $scratch

    # Inputs for install.ps1 prompts:
    #   "1" = global-only install type
    #   "n" = skip npm package install
    $inputs = "1`nn`n"
    $inputs | pwsh -NoProfile -File $Installer 2>&1 | Out-String | Write-Host

    $claudeDir  = Join-Path $scratch  '.claude'
    $hooksDir   = Join-Path $claudeDir 'hooks'
    $scriptsDir = Join-Path $claudeDir 'scripts'

    # --- Source-level pairing baseline --------------------------------------
    $srcPs1Stems = @(Get-ChildItem -Path $SrcHooks -Filter '*.ps1' -File | ForEach-Object { $_.BaseName })
    $srcShStems  = @(Get-ChildItem -Path $SrcHooks -Filter '*.sh'  -File | ForEach-Object { $_.BaseName })
    $pairedStems = @($srcPs1Stems | Where-Object { $_ -in $srcShStems })
    $sourceOrphans = @(@($srcPs1Stems | Where-Object { $_ -notin $srcShStems }) +
                      @($srcShStems  | Where-Object { $_ -notin $srcPs1Stems }))
    if ($sourceOrphans.Count -gt 0) {
        Write-Host "  NOTE: source-level orphans (out of scope for this test): $($sourceOrphans -join ', ')"
    }

    # --- 1-2. Both variants are present for every paired stem ----------------
    foreach ($stem in $pairedStems) {
        Assert-True (Test-Path (Join-Path $hooksDir "$stem.ps1")) "hooks/$stem.ps1 installed"
        Assert-True (Test-Path (Join-Path $hooksDir "$stem.sh"))  "hooks/$stem.sh installed"
    }

    # --- 3. All installed .sh files use LF only ------------------------------
    $installedSh = @(Get-ChildItem -Path $hooksDir -Filter '*.sh' -File -ErrorAction SilentlyContinue)
    Assert-True ($installedSh.Count -ge $pairedStems.Count) "hooks/*.sh count >= paired stems count"

    $crlfOffenders = @()
    foreach ($f in $installedSh) {
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        if ($raw -match "`r`n") { $crlfOffenders += $f.Name }
    }
    Assert-True ($crlfOffenders.Count -eq 0) "all hooks/*.sh use LF-only line endings (offenders: $($crlfOffenders -join ', '))"

    # --- 4. All installed .sh files are UTF-8 without BOM --------------------
    $bomOffenders = @()
    foreach ($f in $installedSh) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bomOffenders += $f.Name
        }
    }
    Assert-True ($bomOffenders.Count -eq 0) "all hooks/*.sh are UTF-8 without BOM (offenders: $($bomOffenders -join ', '))"

    # --- 5. Supporting files -------------------------------------------------
    Assert-True (Test-Path (Join-Path $hooksDir 'lib'))             "hooks/lib/ directory present"
    Assert-True (Test-Path (Join-Path $hooksDir 'known-issues.json')) "hooks/known-issues.json present"

    # --- 6. Utility scripts: both variants -----------------------------------
    $ps1Scripts = @(Get-ChildItem -Path $scriptsDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
    $shScripts  = @(Get-ChildItem -Path $scriptsDir -Filter '*.sh'  -File -ErrorAction SilentlyContinue)
    Assert-True ($ps1Scripts.Count -gt 0) "scripts/*.ps1 present (found $($ps1Scripts.Count))"
    Assert-True ($shScripts.Count -gt 0)  "scripts/*.sh present (found $($shScripts.Count))"

    $scriptCrlfOffenders = @()
    foreach ($f in $shScripts) {
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        if ($raw -match "`r`n") { $scriptCrlfOffenders += $f.Name }
    }
    Assert-True ($scriptCrlfOffenders.Count -eq 0) "all scripts/*.sh use LF-only line endings (offenders: $($scriptCrlfOffenders -join ', '))"

} finally {
    # Restore parent env first so cleanup does not run against scratch
    $env:USERPROFILE = $origUserProfile
    $env:HOME        = $origHome

    if (Test-Path $scratch) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "================================================"
Write-Host "Results: $($script:PASS) passed, $($script:FAIL) failed"
Write-Host "================================================"

if ($script:FAIL -gt 0) {
    Write-Host "Failures:"
    foreach ($e in $script:ERRORS) { Write-Host "  - $e" }
    exit 1
}
exit 0
