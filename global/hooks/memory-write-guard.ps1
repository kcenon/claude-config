#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# memory-write-guard.ps1
# Validates Claude Code Edit/Write tool calls targeting memory files BEFORE disk write.
# Hook Type: PreToolUse (Edit|Write)
# Exit codes: 0 (always - decision encoded in JSON response).
#
# Path gate: only acts when the resolved path is under
# "$HOME/.claude/memory-shared/memories/" and ends with ".md".
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

function Resolve-Path-Safe {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    try {
        if (Test-Path -LiteralPath $Path) {
            return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        } else {
            $parent = Split-Path -LiteralPath $Path -Parent
            $base   = Split-Path -LiteralPath $Path -Leaf
            if (-not [string]::IsNullOrEmpty($parent) -and (Test-Path -LiteralPath $parent)) {
                $resolvedParent = (Resolve-Path -LiteralPath $parent -ErrorAction Stop).Path
                return Join-Path $resolvedParent $base
            }
            return $Path
        }
    } catch {
        return $Path
    }
}

$home_dir   = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [System.Environment]::GetFolderPath('UserProfile') }
$memoryRoot = Join-Path (Join-Path $home_dir '.claude') 'memory-shared'
$memoryRoot = Join-Path $memoryRoot 'memories'

$resolved = Resolve-Path-Safe $filePath

# Path must be a .md file under the memory root.
$normalized     = $resolved -replace '\\','/'
$normalizedRoot = $memoryRoot -replace '\\','/'
if (-not ($normalized.StartsWith($normalizedRoot + '/', [System.StringComparison]::Ordinal) -and $normalized.EndsWith('.md', [System.StringComparison]::Ordinal))) {
    Write-Output (New-HookAllowResponse)
    exit 0
}

# MEMORY.md (auto-generated index) is exempt per validate.sh.
$leaf = Split-Path -LiteralPath $resolved -Leaf
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

# Bash interpreter required to run the validators.
$bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source
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
    if ($secretRc -eq 1) { $block = $true }

    if ($block) {
        $reason = "memory-write-guard rejected write to $leaf"
        if ($validateRc -eq 1 -or $validateRc -eq 2) {
            $reason = $reason + "`nvalidate.sh (exit $validateRc):`n" + $validateOut.TrimEnd()
        }
        if ($secretRc -eq 1) {
            $reason = $reason + "`nsecret-check.sh blocked write:`n" + $secretOut.TrimEnd()
        }
        Write-Output (New-HookDenyResponse -Reason $reason)
        exit 0
    }

    $feedback = ''
    if ($injectionRc -eq 3) {
        $feedback = "memory-write-guard: write allowed but injection-check flagged:`n" + $injectionOut.TrimEnd() + "`nReview before merge."
    } elseif ($validateRc -eq 3) {
        $feedback = "memory-write-guard: write allowed with semantic warnings:`n" + $validateOut.TrimEnd()
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
