#Requires -Version 7.0

# pre-push — PowerShell hook to block direct pushes to protected branches
# Receives the remote name ($args[0]) and remote URL ($args[1]) from git.
# Reads lines from stdin: <local ref> <local sha> <remote ref> <remote sha>
#
# Protected branches: main, develop
# Bypass:  git push --no-verify (forbidden by global CLAUDE.md policy)
#
# Install: hooks/install-hooks.ps1 copies this to .git/hooks/pre-push

$ErrorActionPreference = 'Stop'

# Protected branch names
$ProtectedBranches = @('main', 'develop')

# Read push info from stdin
while ($line = [Console]::In.ReadLine()) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $parts = $line -split '\s+'
    if ($parts.Count -lt 3) { continue }

    $remoteRef = $parts[2]
    $remoteBranch = $remoteRef -replace '^refs/heads/', ''

    if ($remoteBranch -in $ProtectedBranches) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("pre-push hook: direct push to '$remoteBranch' is blocked.")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Protected branches ($($ProtectedBranches -join ', ')) require pull requests.")
        [Console]::Error.WriteLine("Use the following workflow instead:")
        [Console]::Error.WriteLine("  1. Push to a feature branch:  git push origin <feature-branch>")
        [Console]::Error.WriteLine("  2. Create a pull request to merge into '$remoteBranch'")
        [Console]::Error.WriteLine("  3. Merge via the pull request after review and CI checks")
        [Console]::Error.WriteLine("")
        exit 1
    }
}

# Opt-in preflight check. Set CLAUDE_PREFLIGHT=1 to reproduce CI checks locally
# before pushing. Skipped silently by default to preserve prior behaviour.
if ($env:CLAUDE_PREFLIGHT -eq '1') {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null) | Out-String
    $repoRoot = $repoRoot.Trim()
    if (-not $repoRoot) { $repoRoot = (Get-Location).Path }
    $preflight = Join-Path $repoRoot 'global/skills/_internal/preflight/scripts/run-all.sh'

    if (Test-Path $preflight) {
        [Console]::Error.WriteLine("pre-push: CLAUDE_PREFLIGHT=1 — running preflight checks")
        # run-all.sh is bash-only; assume Git Bash or WSL is available on PATH.
        $bash = (Get-Command bash -ErrorAction SilentlyContinue)
        if ($bash) {
            & $bash.Source $preflight
            if ($LASTEXITCODE -ne 0) {
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("pre-push: preflight failed — see the JSON report above for the failing check.")
                [Console]::Error.WriteLine("Re-run with CLAUDE_PREFLIGHT_VERBOSE=1 for full logs, or unset CLAUDE_PREFLIGHT")
                [Console]::Error.WriteLine("to bypass (the failure will surface on GitHub CI instead).")
                exit 1
            }
        } else {
            [Console]::Error.WriteLine("pre-push: CLAUDE_PREFLIGHT=1 but bash is not on PATH — skipping preflight.")
        }
    } else {
        [Console]::Error.WriteLine("pre-push: CLAUDE_PREFLIGHT=1 but $preflight is missing — skipping preflight.")
    }
}

exit 0
