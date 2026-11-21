#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# memory-write-guard.ps1
# Validates Claude Code Edit/Write tool calls targeting memory files BEFORE disk write.
# Hook Type: PreToolUse (Edit|Write)
# Exit codes: 0 (always - decision encoded in JSON response).
#
# Path gate: only acts when the resolved path is under
# "$HOME/.claude/memory-shared/memories/" and ends with ".md".
#
# Allow-path output (issue #715 audit): plain allows already emit the minimal
# allow JSON with no additionalContext; only warn-only validator findings and
# internal-failure diagnostics intentionally attach context. A validator that
# could not run is such a failure: it is named in the context (#1045).
#
# See memory-write-guard.sh for full design notes.

# ----- read input ------------------------------------------------------------

$json = Read-HookInput

# Empty stdin -> fail-open (let other guards / handlers decide).
if (-not $json) {
    Write-Output (New-HookAllowResponse)
    exit 0
}

$toolName = ''
$filePath = ''
try { $toolName = [string]$json.tool_name } catch {}
try { $filePath = [string]$json.tool_input.file_path } catch {}

# Only Edit and Write are guarded.
if ($toolName -ne 'Edit' -and $toolName -ne 'Write') {
    Write-Output (New-HookAllowResponse)
    exit 0
}

# Missing file_path -> fail-open with diagnostic.
if ([string]::IsNullOrEmpty($filePath)) {
    Write-Output (New-HookAllowResponse -AdditionalContext 'memory-write-guard: tool_input.file_path missing')
    exit 0
}

# ----- path gate (resolve, prefix check) ------------------------------------

$home_dir   = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [System.Environment]::GetFolderPath('UserProfile') }
$memoryRoot = Join-Path (Join-Path $home_dir '.claude') 'memory-shared'
$memoryRoot = Join-Path $memoryRoot 'memories'

# Both sides follow links, as in memory-write-guard.sh. A write that names the
# real target of a symlinked HOME, or reaches a real HOME through a link, would
# otherwise miss the gate and go unvalidated (#983).
$memoryRoot = Resolve-HookPath $memoryRoot
$resolved = Resolve-HookPath $filePath

# Path must be a .md file under the memory root.
$normalized     = $resolved -replace '\\','/'
$normalizedRoot = $memoryRoot -replace '\\','/'
if (-not ($normalized.StartsWith($normalizedRoot + '/', [System.StringComparison]::Ordinal) -and $normalized.EndsWith('.md', [System.StringComparison]::Ordinal))) {
    Write-Output (New-HookAllowResponse)
    exit 0
}

# MEMORY.md (auto-generated index) is exempt per validate.sh.
$leaf = [System.IO.Path]::GetFileName($resolved)
if ($leaf -eq 'MEMORY.md') {
    Write-Output (New-HookAllowResponse)
    exit 0
}

# ----- locate validators -----------------------------------------------------

function Find-Validator {
    param([string]$Name)
    $candidates = @(
        (Join-Path (Join-Path (Join-Path $home_dir '.claude') 'scripts') (Join-Path 'memory' $Name)),
        (Join-Path (Join-Path $home_dir '.claude') (Join-Path 'memory-scripts' $Name)),
        (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'scripts' (Join-Path 'memory' $Name)))))
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

$validateBin  = Find-Validator 'validate.sh'
$secretBin    = Find-Validator 'secret-check.sh'
$injectionBin = Find-Validator 'injection-check.sh'

if (-not $validateBin -or -not $secretBin -or -not $injectionBin) {
    Write-Output (New-HookAllowResponse -AdditionalContext 'memory-write-guard: validators not found; validation skipped')
    exit 0
}

# Bash interpreter required to run the validators. On Windows the first `bash`
# on PATH is not good enough: in a PowerShell process it is usually
# C:\Windows\System32\bash.exe, the WSL launcher, which cannot open a Windows
# path. Every validator then ended with 127 and the write was allowed without a
# note (#1045). Prefer the bash that ships with git, then any bash on PATH that
# is not a WSL launcher.
function Find-ValidatorBash {
    if (-not $IsWindows) {
        return (Get-Command bash -ErrorAction SilentlyContinue).Source
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and $git.Source) {
        $dir = Split-Path -Parent $git.Source
        foreach ($up in 1..3) {
            $dir = Split-Path -Parent $dir
            if (-not $dir) { break }
            foreach ($rel in 'bin\bash.exe', 'usr\bin\bash.exe') {
                $candidate = Join-Path $dir $rel
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }
    foreach ($c in @(Get-Command bash -All -ErrorAction SilentlyContinue)) {
        $src = [string]$c.Source
        if (-not $src) { continue }
        if ($env:SystemRoot -and $src.StartsWith($env:SystemRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($src -match '[\\/]WindowsApps[\\/]') { continue }
        return $src
    }
    return $null
}

$bashExe = Find-ValidatorBash
if (-not $bashExe) {
    Write-Output (New-HookAllowResponse -AdditionalContext 'memory-write-guard: bash not available; validation skipped')
    exit 0
}

# ----- build proposed content ------------------------------------------------

$tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + '.md')

try {
    switch ($toolName) {
        'Write' {
            $content = ''
            try { $content = [string]$json.tool_input.content } catch { $content = '' }
            [System.IO.File]::WriteAllText($tmp, $content)
        }
        'Edit' {
            $oldString  = ''
            $newString  = ''
            $replaceAll = $false
            try { $oldString  = [string]$json.tool_input.old_string } catch {}
            try { $newString  = [string]$json.tool_input.new_string } catch {}
            try { $replaceAll = [bool]$json.tool_input.replace_all }   catch {}

            $current = ''
            if (Test-Path -LiteralPath $resolved) {
                $current = [System.IO.File]::ReadAllText($resolved)
            }

            if ([string]::IsNullOrEmpty($oldString)) {
                $simulated = $current
            } elseif ($replaceAll) {
                # Literal substring replace for ALL occurrences.
                $simulated = $current.Replace($oldString, $newString)
            } else {
                # First occurrence only.
                $idx = $current.IndexOf($oldString, [System.StringComparison]::Ordinal)
                if ($idx -ge 0) {
                    $simulated = $current.Substring(0, $idx) + $newString + $current.Substring($idx + $oldString.Length)
                } else {
                    $simulated = $current
                }
            }
            [System.IO.File]::WriteAllText($tmp, $simulated)
        }
    }

    # ----- run validators ----------------------------------------------------

    $validateOut  = & $bashExe $validateBin  $tmp 2>&1 | Out-String
    $validateRc   = $LASTEXITCODE
    $secretOut    = & $bashExe $secretBin    $tmp 2>&1 | Out-String
    $secretRc     = $LASTEXITCODE
    $injectionOut = & $bashExe $injectionBin $tmp 2>&1 | Out-String
    $injectionRc  = $LASTEXITCODE

    # ----- decision ----------------------------------------------------------

    $block = $false
    if ($validateRc -eq 1 -or $validateRc -eq 2) { $block = $true }
    # Fail-closed on secret-check exit code 2 (OWNER_EMAILS not configured,
    # #618), mirroring memory-write-guard.sh lines 272-274.
    if ($secretRc -eq 1 -or $secretRc -eq 2) { $block = $true }

    # A validator that could not run is not one that passed. validate.sh answers
    # 0 to 3, secret-check.sh 0 to 2 and injection-check.sh 0 or 3; any other
    # code (126 or 127 from the interpreter, 64 for a usage error, a crash)
    # means that check did not happen. That is this guard's own failure, so the
    # write is allowed, as #521 prescribes, but never without saying so (#1045).
    $notRun = [System.Collections.Generic.List[string]]::new()
    if ($validateRc  -notin 0, 1, 2, 3) { $notRun.Add("validate.sh (exit $validateRc)") }
    if ($secretRc    -notin 0, 1, 2)    { $notRun.Add("secret-check.sh (exit $secretRc)") }
    if ($injectionRc -notin 0, 3)       { $notRun.Add("injection-check.sh (exit $injectionRc)") }
    $notRunNote = ''
    if ($notRun.Count -gt 0) {
        $notRunNote = 'memory-write-guard: validation incomplete, could not run ' + ($notRun -join ', ') + '; that check was skipped.'
    }

    if ($block) {
        $reason = "memory-write-guard rejected write to $leaf"
        if ($validateRc -eq 1 -or $validateRc -eq 2) {
            $reason = $reason + "`nvalidate.sh (exit $validateRc):`n" + $validateOut.TrimEnd()
        }
        if ($secretRc -eq 1) {
            $reason = $reason + "`nsecret-check.sh blocked write:`n" + $secretOut.TrimEnd()
        }
        if ($secretRc -eq 2) {
            $reason = $reason + "`nsecret-check.sh requires configuration (#618):`n" + $secretOut.TrimEnd()
        }
        if ($notRunNote) { $reason = $reason + "`n" + $notRunNote }
        Write-Output (New-HookDenyResponse -Reason $reason)
        exit 0
    }

    $feedback = $notRunNote
    $warning = ''
    if ($injectionRc -eq 3) {
        $warning = "memory-write-guard: write allowed but injection-check flagged:`n" + $injectionOut.TrimEnd() + "`nReview before merge."
    } elseif ($validateRc -eq 3) {
        $warning = "memory-write-guard: write allowed with semantic warnings:`n" + $validateOut.TrimEnd()
    }
    if ($warning) {
        $feedback = if ($feedback) { $feedback + "`n" + $warning } else { $warning }
    }

    if ([string]::IsNullOrEmpty($feedback)) {
        Write-Output (New-HookAllowResponse)
    } else {
        Write-Output (New-HookAllowResponse -AdditionalContext $feedback)
    }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
    }
}
