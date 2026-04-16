# Verify mirror reference files match the canonical copy.
# Exits with 2 if any mirror drifts from canonical; 0 otherwise.
#
# Canonical: project/.claude/rules/workflow/
# Mirrors:   project/.claude/skills/project-workflow/reference/
#            plugin/skills/project-workflow/reference/
#
# Usage: pwsh scripts/check_references.ps1

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

$drift = 0
foreach ($file in $Files) {
    $src = Join-Path $RootDir $Canonical | Join-Path -ChildPath $file
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "FAIL: canonical missing: $Canonical/$file" -ForegroundColor Red
        $drift = 1
        continue
    }
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    foreach ($mirror in $Mirrors) {
        $dst = Join-Path $RootDir $mirror | Join-Path -ChildPath $file
        if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) {
            Write-Host "FAIL: mirror missing: $mirror/$file" -ForegroundColor Red
            $drift = 1
            continue
        }
        $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            Write-Host "FAIL: drift detected: $mirror/$file" -ForegroundColor Red
            $drift = 1
        }
    }
}

if ($drift -eq 0) {
    Write-Host "check_references: OK (all $($Files.Count) files match across $($Mirrors.Count) mirrors)"
    exit 0
}

Write-Host ""
Write-Host "check_references: drift detected. Run scripts/sync_references.ps1 to regenerate mirrors." -ForegroundColor Yellow
exit 2
