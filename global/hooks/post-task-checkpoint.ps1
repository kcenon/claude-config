#!/usr/bin/env pwsh
# Post Task/Agent Checkpoint Hook (Windows)
# =========================================
# Windows twin of post-task-checkpoint.sh. Same contract:
#   - Runs after a PostToolUse event for Task|Agent
#   - Auto-commits working-tree changes so a later sub-agent cannot
#     clobber a prior agent's output
#   - Always fail-open (exit 0); never block the workflow

$ErrorActionPreference = 'SilentlyContinue'

# Read stdin (may be empty).
$inputJson = ''
try {
    $inputJson = [Console]::In.ReadToEnd()
} catch {
    exit 0
}

# Parse JSON; fail-open on malformed input.
$data = $null
if ($inputJson) {
    try {
        $data = $inputJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        exit 0
    }
}

# Only checkpoint after Task or Agent tool calls.
$toolName = ''
if ($data -and $data.PSObject.Properties['tool_name']) {
    $toolName = [string]$data.tool_name
}
if ($toolName -ne 'Task' -and $toolName -ne 'Agent') {
    exit 0
}

# Must be inside a git worktree.
& git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { exit 0 }

# Skip when the tree is clean.
& git diff --quiet 2>$null
$diffClean = ($LASTEXITCODE -eq 0)
& git diff --cached --quiet 2>$null
$cacheClean = ($LASTEXITCODE -eq 0)
$untracked = & git ls-files --others --exclude-standard 2>$null
if ($diffClean -and $cacheClean -and [string]::IsNullOrWhiteSpace($untracked)) {
    exit 0
}

# Extract agent name; prefer subagent_type, fall back to name.
$agent = 'agent'
if ($data -and $data.PSObject.Properties['tool_input'] -and $data.tool_input) {
    if ($data.tool_input.PSObject.Properties['subagent_type'] -and $data.tool_input.subagent_type) {
        $agent = [string]$data.tool_input.subagent_type
    } elseif ($data.tool_input.PSObject.Properties['name'] -and $data.tool_input.name) {
        $agent = [string]$data.tool_input.name
    }
}

# Sanitize: alphanumerics, dash, underscore only; clip to 64 chars.
$agent = ($agent -replace '[^A-Za-z0-9_-]', '')
if ([string]::IsNullOrEmpty($agent)) { $agent = 'agent' }
if ($agent.Length -gt 64) { $agent = $agent.Substring(0, 64) }

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Stage and commit. Suppress all output; fail-open on any error.
try {
    & git add -A 2>$null | Out-Null
    & git commit -m "wip(agent): $agent checkpoint $ts" --no-verify --allow-empty 2>$null | Out-Null
} catch { }

exit 0
