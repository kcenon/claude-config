# Sync canonical workflow reference files to mirror locations.
# Canonical: project/.claude/rules/workflow/
# Mirrors:   project/.claude/skills/project-workflow/reference/
#            plugin/skills/project-workflow/reference/
#
# See docs/CUSTOM_EXTENSIONS.md for the SSOT design rationale.
#
# Usage: pwsh scripts/sync_references.ps1

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

$Canonical = 'project/.claude/rules/workflow'
$Mirrors = @(
    'project/.claude/skills/project-workflow/reference',
    'plugin/skills/project-workflow/reference'
)
$Files = @(
    'git-commit-format.md',
    'github-issue-5w1h.md',
    'github-pr-5w1h.md',
    'performance-analysis.md'
)

$missing = 0
foreach ($file in $Files) {
    $src = Join-Path $RootDir $Canonical | Join-Path -ChildPath $file
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Error "canonical file missing: $Canonical/$file"
        $missing = 1
    }
}
if ($missing -ne 0) { exit 1 }

foreach ($mirror in $Mirrors) {
    $mirrorPath = Join-Path $RootDir $mirror
    if (-not (Test-Path -LiteralPath $mirrorPath -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $mirrorPath | Out-Null
    }
    foreach ($file in $Files) {
        $src = Join-Path $RootDir $Canonical | Join-Path -ChildPath $file
        $dst = Join-Path $mirrorPath $file
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "synced: $Canonical/$file -> $mirror/$file"
    }
}

Write-Host "sync_references: done ($($Files.Count) files x $($Mirrors.Count) mirrors)"
