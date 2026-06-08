#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# traceability-guard.ps1
# Deterministic traceability cascade validator.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# PowerShell counterpart for the bash traceability-guard.sh. The shared
# validator (hooks/lib/validate-traceability.sh) is bash-only, so this
# script delegates to bash via WSL / Git Bash when available. When bash
# is missing the hook fails open and defers to the pre-push git hook.
#
# Scope: only fires for `gh pr create` invocations.
# Opt-in: silently allows when docs/.index/graph.yaml is absent.

# Read input from stdin
$json = Read-HookInput

# Empty input: allow (the pre-push hook is the terminal gate)
if (-not $json) {
    New-HookAllowResponse
    exit 0
}

# Extract command
$CMD = $null
try { $CMD = $json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }

# Scope: only validate gh pr create commands
if ($CMD -notmatch 'gh\s+pr\s+create') {
    New-HookAllowResponse
    exit 0
}

# Discover repo root
$repoRoot = (& git rev-parse --show-toplevel 2>$null) | Out-String
$repoRoot = $repoRoot.Trim()
if (-not $repoRoot) { $repoRoot = (Get-Location).Path }

# Opt-in gate: skip silently when graph.yaml is absent.
$graphYaml = Join-Path $repoRoot 'docs' '.index' 'graph.yaml'
if (-not (Test-Path $graphYaml)) {
    New-HookAllowResponse
    exit 0
}

# Locate the bash counterpart and delegate. The shared validator uses
# POSIX shell features (awk, sed, here-docs) that are inconvenient to
# port; instead we re-exec the canonical traceability-guard.sh. This
# keeps PowerShell users on the exact same enforcement logic.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    # Bash unavailable on PATH (rare on CI runners; possible on bare
    # Windows). Fail open - the pre-push.ps1 gate remains.
    New-HookAllowResponse
    exit 0
}

$bashGuard = Join-Path $PSScriptRoot 'traceability-guard.sh'
if (-not (Test-Path $bashGuard)) {
    # Companion script missing from this install. Fail open.
    New-HookAllowResponse
    exit 0
}

# Re-encode the JSON we already parsed so the bash script sees the same
# payload via stdin. This avoids losing the original raw string.
$payload = $json | ConvertTo-Json -Compress -Depth 10
$payload | & $bash.Source $bashGuard
exit 0
