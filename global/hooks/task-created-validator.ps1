#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# task-created-validator.ps1
# Validates task quality at creation time.
# Hook Type: TaskCreated (sync, blocking)
# Exit codes: 0 = approve, 2 = block (stderr message shown to model)
#
# Rules:
#   1. description must be >= 20 characters (after trim)
#   2. description must contain at least one "- [ ]" markdown checkbox

$json = Read-HookInput
if (-not $json) { exit 0 }

# Extract description from common TaskCreate field paths.
# $null = field missing (fail open), '' = explicitly empty (block).
$desc = $null
$hasField = $false
foreach ($getter in @(
    { $json.tool_input.description },
    { $json.description },
    { $json.task.description }
)) {
    try {
        $val = & $getter
        if ($null -ne $val) {
            $desc = [string]$val
            $hasField = $true
            break
        }
    } catch { }
}

if (-not $hasField) { exit 0 }

$trimmed = $desc.Trim()

# Rule 1: minimum length
if ($trimmed.Length -lt 20) {
    [Console]::Error.WriteLine("TaskCreated rejected: description must be at least 20 characters (got $($trimmed.Length)). Add scope, context, and acceptance criteria.")
    exit 2
}

# Rule 2: must contain at least one checkbox marker
if ($desc -notmatch '\- \[ \]') {
    [Console]::Error.WriteLine("TaskCreated rejected: description must contain at least one '- [ ]' checkbox marker for acceptance criteria.")
    exit 2
}

exit 0
