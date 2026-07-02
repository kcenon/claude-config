#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# push-target-guard.ps1
# Blocks git pushes that bypass the two-layer defense (issue #782):
#   1. `git push --no-verify ...`  - defeats the terminal-side pre-push hook.
#   2. Direct push to a protected branch (main / master / develop), whether the
#      target is explicit (`git push origin main`, `... HEAD:main`) or the
#      resolved upstream of the current branch (`git push` while on main).
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
#
# `git push -n` / `--dry-run` is intentionally NOT treated as --no-verify and
# not blocked on target: it performs no real push (verifier note, #782).
# PowerShell mirror of push-target-guard.sh.

# Read input from stdin
$json = Read-HookInput

# Fail-closed: deny if stdin is empty or missing
if (-not $json) {
    New-HookDenyResponse -Reason 'Failed to parse hook input — denying for safety (fail-closed)'
    exit 0
}

# Extract command
$CMD = $null
try { $CMD = $json.tool_input.command } catch {}
if (-not $CMD) { $CMD = $env:CLAUDE_TOOL_INPUT }

# Scope gate: only inspect `git push` commands
if ($CMD -notmatch 'git\s+push') {
    New-HookAllowResponse
    exit 0
}

# Strip quoted substrings so a flag-looking token inside a quoted argument
# cannot false-trigger the flag checks below.
$dequoted = $CMD -replace '"[^"]*"', '' -replace "'[^']*'", ''

# Check A: --no-verify defeats the pre-push hook
if ($dequoted -match '(?:^|\s)--no-verify(?:\s|$)') {
    New-HookDenyResponse -Reason 'git push --no-verify is blocked: it bypasses the pre-push hook, the terminal-side half of the two-layer protected-branch defense. Push without --no-verify.'
    exit 0
}

# Dry-run is harmless: skip the protected-target check (issue #782)
$dryRun = $dequoted -match '(?:^|\s)(?:-n|--dry-run)(?:\s|$)'

if (-not $dryRun) {
    # Isolate the `git push` arguments, stopping at the first shell operator.
    $pm = [regex]::Match($dequoted, 'git\s+push\s*(.*)')
    $pushArgs = if ($pm.Success) { $pm.Groups[1].Value } else { '' }
    $pushArgs = @($pushArgs -split '&&|;|\|')[0]

    # Positional (non-flag) args: [remote] [refspec].
    $tokens = @($pushArgs -split '\s+' | Where-Object { $_ -ne '' })
    $positionals = @($tokens | Where-Object { $_ -notmatch '^-' })

    $dst = ''
    if ($positionals.Count -ge 2) {
        # `src:dst` -> dst; a bare `branch` -> branch.
        $dst = @($positionals[1] -split ':')[-1]
    } else {
        # No refspec: bare `git push` targets the current branch's upstream
        # when one exists. Resolve that destination first, then fall back to the
        # current branch for repos without an upstream.
        $upstream = $null
        try { $upstream = (& git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null) } catch {}
        if ($upstream) {
            $upstreamText = "$upstream".Trim()
            $dst = @($upstreamText -split '/', 2)[-1]
        }
        else {
            try { $dst = (& git rev-parse --abbrev-ref HEAD 2>$null) } catch {}
        }
        if ($dst) { $dst = ("$dst").Trim() }
    }

    # Normalize: strip a leading '+' (force refspec) and a refs/heads/ prefix.
    $dst = $dst -replace '^\+', '' -replace '^refs/heads/', ''

    if ($dst -eq 'main' -or $dst -eq 'master' -or $dst -eq 'develop') {
        New-HookDenyResponse -Reason "Direct push to protected branch '$dst' is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main). If you must, push from a work branch instead."
        exit 0
    }
}

New-HookAllowResponse
exit 0
