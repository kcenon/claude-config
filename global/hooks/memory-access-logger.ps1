#Requires -Version 7.0
$ErrorActionPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# memory-access-logger.ps1
# Logs Claude Code Read tool calls targeting memory files (path only).
# Hook Type: PostToolUse (Read)
# Exit codes: 0 (always — passive logger; failure must NOT affect tool flow).
#
# Path gate: only logs when the resolved path is under
#   "$HOME/.claude/memory-shared/memories/".
# Log file: $HOME/.claude/logs/memory-access.log
# Log line: "<ISO8601 UTC timestamp> <session_id> read <relative-path>"
# Rotation: lazy; > 1 MiB OR file's calendar month != current month.
#
# See memory-access-logger.sh for full design notes.

function Exit-Silent { exit 0 }

# ----- read input ------------------------------------------------------------

$json = Read-HookInput
if (-not $json) { Exit-Silent }

$toolName  = ''
$filePath  = ''
$sessionId = ''
try { $toolName  = [string]$json.tool_name } catch {}
try { $filePath  = [string]$json.tool_input.file_path } catch {}
try { $sessionId = [string]$json.session_id } catch {}

if ($toolName -ne 'Read') { Exit-Silent }
if ([string]::IsNullOrEmpty($filePath)) { Exit-Silent }
if ([string]::IsNullOrEmpty($sessionId)) { $sessionId = 'unknown' }

# ----- helpers ---------------------------------------------------------------

function Resolve-Path-Safe {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    try {
        if (Test-Path -LiteralPath $Path) {
            return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        }
        $parent = Split-Path -LiteralPath $Path -Parent
        $base   = Split-Path -LiteralPath $Path -Leaf
        if (-not [string]::IsNullOrEmpty($parent) -and (Test-Path -LiteralPath $parent)) {
            $resolvedParent = (Resolve-Path -LiteralPath $parent -ErrorAction Stop).Path
            return Join-Path $resolvedParent $base
        }
        return $Path
    } catch {
        return $Path
    }
}

# ----- path gate -------------------------------------------------------------

$home_dir   = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { [System.Environment]::GetFolderPath('UserProfile') }
$sharedRoot = Join-Path (Join-Path $home_dir '.claude') 'memory-shared'
$memoryRoot = Join-Path $sharedRoot 'memories'

$resolved = Resolve-Path-Safe $filePath

$normalized      = ($resolved -replace '\\','/')
$normalizedRoot  = ($memoryRoot -replace '\\','/')
$normalizedShare = ($sharedRoot -replace '\\','/')

# Strict prefix match: must be under memories/ specifically (excludes the
# top-level memory-shared/MEMORY.md auto-generated index).
if (-not $normalized.StartsWith($normalizedRoot + '/', [System.StringComparison]::Ordinal)) {
    Exit-Silent
}

$relative = $normalized.Substring($normalizedShare.Length + 1)

# ----- log file path + rotation ---------------------------------------------

$logDir  = Join-Path (Join-Path $home_dir '.claude') 'logs'
$logFile = Join-Path $logDir 'memory-access.log'

try {
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
} catch { Exit-Silent }

function Invoke-Maybe-Rotate {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return }
    try {
        $info = Get-Item -LiteralPath $File -ErrorAction Stop
        $size = $info.Length
        $fileMonth    = $info.LastWriteTimeUtc.ToString('yyyy-MM')
        $currentMonth = [DateTime]::UtcNow.ToString('yyyy-MM')
        $oneMib       = 1MB
        $rotate       = ($size -gt $oneMib) -or ($fileMonth -ne $currentMonth)
        if (-not $rotate) { return }

        $stamp  = if ($fileMonth) { $fileMonth } else { $currentMonth }
        $target = "$File.$stamp"
        if (Test-Path -LiteralPath $target) {
            $n = 1
            while (Test-Path -LiteralPath "$target.$n") { $n++ }
            $target = "$target.$n"
        }
        Move-Item -LiteralPath $File -Destination $target -Force -ErrorAction Stop
        New-Item -ItemType File -Path $File -Force | Out-Null
    } catch {
        # Rotation failure is non-fatal.
    }
}

Invoke-Maybe-Rotate -File $logFile

# ----- write log entry -------------------------------------------------------

$timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
# Sanitize tab/newline characters in path so the line stays single-record.
$safeRelative = ($relative -replace "[\t\r\n]", ' ')
$line = "$timestamp $sessionId read $safeRelative"

try {
    Add-Content -LiteralPath $logFile -Value $line -ErrorAction Stop
} catch {
    # Silent: logger must never affect tool flow.
}

Exit-Silent
