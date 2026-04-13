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

exit 0
