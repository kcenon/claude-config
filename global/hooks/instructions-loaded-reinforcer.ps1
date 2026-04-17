#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# instructions-loaded-reinforcer.ps1
# Re-asserts critical policy after CLAUDE.md / .claude/rules/*.md loads.
# Hook Type: InstructionsLoaded (sync)
# Exit codes: 0 (always - context is delivered via JSON)

$policyText = $null
$candidates = @(
    (Join-Path $HOME '.claude' 'commit-settings.md')
)
if ($env:CLAUDE_HOME) {
    $candidates += (Join-Path $env:CLAUDE_HOME 'commit-settings.md')
}
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $policyText = Get-Content -LiteralPath $candidate -Raw
        break
    }
}

if (-not $policyText) {
    $policyText = @'
# Commit, Issue, and PR Settings

No AI/Claude attribution in commits, issues, or PRs.
All GitHub Issues and Pull Requests must be written in English.
'@
}

$reinforcement = @"
## Critical Policy Reinforcement (auto-injected after instruction load)

$policyText

## Branching

- Default working branch: ``develop``. Never push directly to ``main`` or ``develop``.
- Feature/fix PRs target ``develop``; release PRs target ``main``.
- Squash merge required.

## Commit Format

Conventional Commits: ``type(scope): description`` or ``type: description``.
Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, security.
Description: lowercase start, no trailing period, no emojis, no AI attribution.
"@

$response = @{
    hookSpecificOutput = @{
        hookEventName     = 'InstructionsLoaded'
        additionalContext = $reinforcement
    }
}
Write-Output ($response | ConvertTo-Json -Depth 3 -Compress)
exit 0
