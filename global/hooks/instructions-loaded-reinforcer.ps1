#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# instructions-loaded-reinforcer.ps1
# Re-asserts critical policy after CLAUDE.md / .claude/rules/*.md loads.
# Hook Type: InstructionsLoaded (sync)
# Exit codes: 0 (always - context is delivered via JSON)

# Fixed short digest (issue #716): the full commit-settings.md text already
# reaches context via the CLAUDE.md @import chain, so re-injecting it verbatim
# on every InstructionsLoaded event is pure duplication. Keep the payload to
# ~10 lines / ~500 bytes and never read policy file contents into it.
# Must stay byte-equivalent to the digest in instructions-loaded-reinforcer.sh.
$reinforcement = @'
## Critical Policy Reinforcement (digest)

- No AI/Claude attribution in commits, issues, or PRs.
- Issue/PR/commit prose: follow the CLAUDE_CONTENT_LANGUAGE policy (see commit-settings.md).
- Branches: work branches from develop; never push directly to main or develop; squash merge only.
- Commits: Conventional Commits `type(scope): description`; lowercase first char, no trailing period.
'@

$reinforcement = ($reinforcement -replace "`r`n", "`n").TrimEnd("`n")

$response = @{
    hookSpecificOutput = @{
        hookEventName     = 'InstructionsLoaded'
        additionalContext = $reinforcement
    }
}
Write-Output ($response | ConvertTo-Json -Depth 3 -Compress)
exit 0
