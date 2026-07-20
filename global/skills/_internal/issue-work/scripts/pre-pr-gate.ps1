#Requires -Version 7.0
# pre-pr-gate.ps1
# issue-work: pre-PR readiness gate (git-state half)
# ==================================================
# PowerShell parity port of scripts/pre-pr-gate.sh. Same functions, same
# behavior, same develop-refresh / conflict / base-movement rules, same
# injection seams, and the same single-line JSON outcome schema (identical field
# order, attempts as an unquoted number). See reference/pre-pr-readiness.md for
# the full contract both scripts satisfy (outcome table, develop-refresh rules,
# conflict rule, base-movement retry rule, and the agent-side gap audit this
# script does not itself perform).
#
# NOTE (authoring-time caveat): pwsh was not available in the environment this
# port was written in, so it was produced by mirroring the bash-verified logic
# in pre-pr-gate.sh line-for-line rather than by running it. It has NOT been
# executed and is NOT wired into CI. Cross-platform runtime regression coverage
# is tracked in issue #847 under epic #832, consistent with the existing
# PowerShell-parity notes for the triage (#829), workspace (#838), and agents
# (#839) stages in tests/issue-work/README.md.
#
# This script owns only the mechanical, non-judgemental half of the gate:
#   1. Refuse to run against a dirty worktree (commit impl+docs first).
#   2. Fetch the remote base and fast-forward the LOCAL base branch only when it
#      is strictly behind the remote. If the local base is AHEAD or DIVERGED it
#      is left untouched and the gate blocks -- it never rewinds a base branch.
#   3. Integrate the refreshed base into the feature branch (rebase by default,
#      merge for shared branches). On ANY integration conflict it aborts the
#      rebase/merge -- leaving the feature branch exactly as it was -- and blocks.
#   4. Re-fetch after a clean integration; if the remote base moved, re-integrate
#      against the new base, capped at --max-base-moves re-integrations.
#
# The script is both a sourceable library (dot-source it to get the functions
# below, e.g. classify_base_relationship / run_pre_pr_gate) and a CLI:
#   pwsh -File pre-pr-gate.ps1 --repo <owner/name> --base <develop> --branch <feature>
#        [--remote origin] [--max-base-moves 3] [--integrate rebase|merge]
# CLI flags intentionally mirror pre-pr-gate.sh's flags exactly (rather than
# native PowerShell parameter binding) so the two entry points are
# interchangeable from a caller's point of view.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit from git is data here, not an error: pre-pr-gate.sh reads
# `merge-base --is-ancestor` failing as "not an ancestor" and a failed
# rebase/merge as a conflict outcome. A host that has enabled
# $PSNativeCommandUseErrorActionPreference would promote those exits to
# terminating errors under the 'Stop' preference above and lose the structured
# outcome, so the setting is pinned off for this script. _prepr_git also lowers
# $ErrorActionPreference locally, which keeps the wrapper correct even if this
# line is ever removed.
$PSNativeCommandUseErrorActionPreference = $false

# Injection seams (overridable by tests and callers via environment variables,
# mirroring the bash GIT_BIN seam). GIT_BIN is captured once at load time, as in
# the bash script; PREPR_REPO_DIR is read fresh on every git call (see
# _prepr_git) so a sourced unit test can aim a single helper at a temp repo.
$script:GitBin = if ($env:GIT_BIN) { $env:GIT_BIN } else { 'git' }

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via
# $env:GIT_BIN. Operations run inside ${PREPR_REPO_DIR:-.}; the default targets
# the current working directory (the feature-branch checkout in the real
# workflow), and a sourced unit test may set PREPR_REPO_DIR to aim a single
# helper at a temp repo.
#
# Native-command failure is surfaced via $LASTEXITCODE, never a thrown
# exception: $ErrorActionPreference is locally lowered to 'Continue' so that a
# benign non-zero git exit (e.g. `merge-base --is-ancestor` reporting "not an
# ancestor") does NOT become a terminating error under the script-scope 'Stop'
# preference -- whether it would depends on the pwsh minor version. git's stderr
# is redirected to null so a caller only ever sees git's stdout on the success
# stream.
function _prepr_git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $repoDir = if ($env:PREPR_REPO_DIR) { $env:PREPR_REPO_DIR } else { '.' }
    $ErrorActionPreference = 'Continue'
    & $script:GitBin -C $repoDir @GitArgs 2>$null
}

# Run a git command purely for its exit status, discarding stdout. Returns $true
# when git exited 0. Mirrors the bash `if _prepr_git ... >/dev/null 2>&1` idiom.
# $LASTEXITCODE is set by the native git inside _prepr_git and is not disturbed
# by the Out-Null cmdlet or the function return, so it is safe to read here.
function _prepr_git_ok {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    _prepr_git @GitArgs | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Run a git command and return its stdout as a single trimmed string ('' when
# git produced nothing or failed). Mirrors the bash `x="$(_prepr_git ... )"`
# command-substitution idiom, which likewise yields the empty string on failure.
function _prepr_git_line {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $out = _prepr_git @GitArgs
    if ($null -eq $out) { return '' }
    return (($out | Out-String).Trim())
}

# ── Base-movement test seam ──────────────────────────────────────────
# Command string run after every fetch, mirroring the bash env-var seam. It
# exists so a test can push a new commit to the bare remote between fetches and
# deterministically simulate the base moving under the gate. It is a no-op when
# unset and its failures are swallowed so a flaky hook never masks a real gate
# result. Mirrors the bash `eval` seam using Invoke-Expression.
function _prepr_run_hook {
    if ([string]::IsNullOrEmpty($env:PRE_PR_ON_FETCH)) { return }
    try {
        Invoke-Expression -Command $env:PRE_PR_ON_FETCH *> $null
    } catch {
        # A flaky hook must never mask a real gate result; swallow all failures.
    }
}

# ── Pure helper (unit-testable via PREPR_REPO_DIR ancestry) ──────────
# Classify how a local base sha relates to a remote base sha using commit
# ancestry, funneled through _prepr_git so it is fakeable / testable against a
# real throwaway repo. Returns exactly one of:
#   equal     the two shas are identical (no refresh needed)
#   behind    local is an ancestor of remote (safe fast-forward)
#   ahead     remote is an ancestor of local (local has unshared commits)
#   diverged  neither is an ancestor of the other (histories forked)
# Returns "unknown" only when an argument is empty (the bash returns nonzero in
# that case; the string is the contract the driver switches on, and "unknown"
# falls through to the diverged branch there exactly as bash's `diverged|*`
# does).
function classify_base_relationship {
    param(
        [AllowEmptyString()][string]$LocalSha = '',
        [AllowEmptyString()][string]$RemoteSha = ''
    )
    if ([string]::IsNullOrEmpty($LocalSha) -or [string]::IsNullOrEmpty($RemoteSha)) {
        return 'unknown'
    }
    if ($LocalSha -eq $RemoteSha) {
        return 'equal'
    }
    # `merge-base --is-ancestor` emits no stdout and signals via exit code only.
    _prepr_git merge-base --is-ancestor $LocalSha $RemoteSha | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return 'behind'
    }
    _prepr_git merge-base --is-ancestor $RemoteSha $LocalSha | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return 'ahead'
    }
    return 'diverged'
}

# ── Integration primitives ───────────────────────────────────────────
# Integrate the (already refreshed) base branch into the currently checked-out
# feature branch. Rebase is the private-branch default; merge is the shared-
# branch escape hatch. Returns $true on a clean integration and $false on a
# conflict (or an unknown mode, which the driver validates away up front) so the
# driver can distinguish a clean integration from a conflict.
function _prepr_integrate {
    param([string]$Mode, [string]$Base)
    switch ($Mode) {
        'rebase' { _prepr_git rebase $Base | Out-Null; return ($LASTEXITCODE -eq 0) }
        'merge'  { _prepr_git merge --no-edit $Base | Out-Null; return ($LASTEXITCODE -eq 0) }
        default  { return $false }
    }
}

# Abort an in-progress integration, restoring the feature branch to exactly the
# state it had before the integration attempt. Best-effort: its own exit code is
# ignored because the driver has already decided to block.
function _prepr_abort {
    param([string]$Mode)
    switch ($Mode) {
        'rebase' { _prepr_git rebase --abort | Out-Null }
        'merge'  { _prepr_git merge --abort | Out-Null }
    }
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
# Single stdout line. attempts is numeric (unquoted); every other field is a
# string. Field order is identical to pre-pr-gate.sh so a test can parse the two
# scripts' output interchangeably. Doubled {{ }} are literal braces for the -f
# operator, matching the workspace.ps1 emit idiom.
function _prepr_emit {
    param(
        [string]$Outcome,
        [string]$Reason,
        [AllowEmptyString()][string]$Base = '',
        [AllowEmptyString()][string]$RemoteSha = '',
        [AllowEmptyString()][string]$Before = '',
        [AllowEmptyString()][string]$After = '',
        [int]$Attempts = 0
    )
    Write-Output ('{{"outcome":"{0}","reason":"{1}","base":"{2}","remote_base_sha":"{3}","local_base_sha_before":"{4}","local_base_sha_after":"{5}","attempts":{6}}}' `
        -f $Outcome, $Reason, $Base, $RemoteSha, $Before, $After, $Attempts)
}

# ── Driver ───────────────────────────────────────────────────────────
# run_pre_pr_gate <repo> <base> <branch> [<remote>] [<max_base_moves>] [<integrate>]
#
# Repo             expected "owner/name" identity (reported, not re-verified here
#                  -- the workspace stage already verified origin identity).
# Base             the base branch to refresh and integrate from (e.g. develop).
# Branch           the feature branch to integrate the base into.
# Remote           remote to fetch the base from (default origin).
# MaxMoves         cap on re-integrations when the remote base keeps moving
#                  (default 3).
# Mode             rebase (default, private branch) or merge (shared branch).
#
# Parameters are declared positionally so the function can be called both by name
# and positionally (`run_pre_pr_gate o/n develop feat/x`), mirroring the bash
# positional contract the test suite exercises.
function run_pre_pr_gate {
    param(
        [string]$Repo = '',
        [string]$Base = '',
        [string]$Branch = '',
        [string]$Remote = 'origin',
        [int]$MaxMoves = 3,
        [string]$Mode = 'rebase'
    )

    if ([string]::IsNullOrEmpty($Repo) -or [string]::IsNullOrEmpty($Base) -or [string]::IsNullOrEmpty($Branch)) {
        _prepr_emit 'blocked' 'missing_args' $Base '' '' '' 0
        return 2
    }
    if ($Mode -ne 'rebase' -and $Mode -ne 'merge') {
        _prepr_emit 'blocked' 'bad_integrate_mode' $Base '' '' '' 0
        return 2
    }

    # Best-effort snapshot of the local base before any refresh, so a blocked
    # outcome can prove the base was not rewound.
    $localBefore = _prepr_git_line rev-parse $Base

    # 1. Clean-worktree precondition. Tracked staged/unstaged changes block the
    #    gate; untracked files (--untracked-files=no) do not, since they never
    #    impede a rebase.
    $dirty = _prepr_git_line status --porcelain --untracked-files=no
    if (-not [string]::IsNullOrEmpty($dirty)) {
        _prepr_emit 'blocked' 'dirty_worktree' $Base '' $localBefore $localBefore 0
        return 1
    }

    # Ensure we operate from the feature branch (defensive: the real workflow is
    # already on it). Everything after this integrates the base into HEAD.
    if (-not (_prepr_git_ok checkout $Branch)) {
        _prepr_emit 'blocked' 'checkout_failed' $Base '' $localBefore $localBefore 0
        return 1
    }

    # Initial fetch of the remote base.
    if (-not (_prepr_git_ok fetch $Remote $Base)) {
        _prepr_emit 'blocked' 'fetch_failed' $Base '' $localBefore $localBefore 0
        return 1
    }
    $rb = _prepr_git_line rev-parse FETCH_HEAD
    _prepr_run_hook

    $attempts = 0
    while ($true) {
        $attempts++

        # Refresh the LOCAL base branch against the freshly fetched remote sha.
        $lb = _prepr_git_line rev-parse $Base
        $rel = classify_base_relationship $lb $rb
        switch ($rel) {
            'equal' {
                # Local base already current; nothing to fast-forward.
            }
            'behind' {
                # Strictly behind -> a true fast-forward. Move the ref without a
                # checkout (we stay on the feature branch). Best-effort like the
                # bash update-ref, whose exit is ignored.
                _prepr_git update-ref "refs/heads/$Base" $rb | Out-Null
            }
            'ahead' {
                # Local base has commits the remote lacks; never rewind it.
                _prepr_emit 'blocked' 'base_ahead' $Base $rb $localBefore $lb $attempts
                return 1
            }
            default {
                # diverged (and the "unknown" fall-through) -> never reset.
                _prepr_emit 'blocked' 'base_diverged' $Base $rb $localBefore $lb $attempts
                return 1
            }
        }

        # Integrate the refreshed base into the feature branch.
        _prepr_git checkout $Branch | Out-Null
        if (-not (_prepr_integrate $Mode $Base)) {
            # A script cannot judge conflict ambiguity: abort and block.
            _prepr_abort $Mode
            $afterConf = _prepr_git_line rev-parse $Base
            _prepr_emit 'blocked' 'conflict' $Base $rb $localBefore $afterConf $attempts
            return 1
        }

        # Re-fetch to detect the remote base moving under us during the audit.
        if (-not (_prepr_git_ok fetch $Remote $Base)) {
            $afterFf = _prepr_git_line rev-parse $Base
            _prepr_emit 'blocked' 'fetch_failed' $Base $rb $localBefore $afterFf $attempts
            return 1
        }
        $rbNew = _prepr_git_line rev-parse FETCH_HEAD
        _prepr_run_hook

        if ($rbNew -eq $rb) {
            break  # base stable across two consecutive fetches -> ready.
        }
        $rb = $rbNew
        if ($attempts -ge $MaxMoves) {
            $afterUnstable = _prepr_git_line rev-parse $Base
            _prepr_emit 'blocked' 'base_unstable' $Base $rb $localBefore $afterUnstable $attempts
            return 1
        }
    }

    $localAfter = _prepr_git_line rev-parse $Base
    _prepr_emit 'ready' 'ready' $Base $rb $localBefore $localAfter $attempts
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────

# Split a driver result into "emit on stdout" and "use as the exit code".
#
# run_pre_pr_gate writes its JSON to the success stream and then `return`s an
# int exit code -- but in PowerShell a `return` value also lands on the success
# stream, so the caller receives @(<json>, <int>) as one array. Passing that
# array straight to `exit` casts the whole array to int, which throws and takes
# the JSON down with it, so `pwsh -File pre-pr-gate.ps1 ...` printed nothing at
# all while pre-pr-gate.sh printed the gate JSON (issue #847 S2).
#
# This helper writes every non-int item straight to the console and returns the
# trailing int as the exit code, restoring parity with the bash CLI.
# Dot-sourced callers are unaffected -- they consume the driver's return value
# directly.
#
# The payload goes out via [Console]::Out rather than Write-Output on purpose:
# Write-Output would put it back on the success stream alongside the returned
# exit code, reproducing the very merge this helper exists to undo.
function Split-PrePrGateCliResult {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Result)
    $items = @($Result)
    $code = 0
    if ($items.Count -gt 0 -and $items[-1] -is [int]) {
        $code = [int]$items[-1]
        # Note the explicit Count check: $items[0..($items.Count - 2)] would be
        # $items[0..-1] for a single-element array, and PowerShell reads -1 as
        # "last element", silently re-emitting the exit code as output.
        if ($items.Count -gt 1) {
            $items = $items[0..($items.Count - 2)]
        } else {
            $items = @()
        }
    }
    foreach ($item in $items) { [Console]::Out.WriteLine([string]$item) }
    return $code
}

# Mirrors pre-pr-gate.sh's _prepr_main: manual flag parsing over the argument
# array (not native parameter binding) so the CLI surface matches the bash one
# exactly. MaxMoves is left as a string here and coerced to [int] by
# run_pre_pr_gate's parameter binding, matching the bash string-then-numeric use.
function Invoke-PrePrGateMain {
    param([string[]]$Arguments = @())
    $repo = ''; $base = ''; $branch = ''; $remote = 'origin'; $maxMoves = '3'; $mode = 'rebase'
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '--repo' { $repo = $Arguments[$i + 1]; $i += 2 }
            '--base' { $base = $Arguments[$i + 1]; $i += 2 }
            '--branch' { $branch = $Arguments[$i + 1]; $i += 2 }
            '--remote' { $remote = $Arguments[$i + 1]; $i += 2 }
            '--max-base-moves' { $maxMoves = $Arguments[$i + 1]; $i += 2 }
            '--integrate' { $mode = $Arguments[$i + 1]; $i += 2 }
            default {
                Write-Error "unknown argument: $($Arguments[$i])"
                return 2
            }
        }
    }
    if (-not $repo -or -not $base -or -not $branch) {
        Write-Error 'error: --repo <owner/name>, --base <branch>, and --branch <feature> are required'
        return 2
    }
    return run_pre_pr_gate $repo $base $branch $remote $maxMoves $mode
}

# Run as CLI only when executed directly; stay quiet when dot-sourced by tests
# (mirrors pre-pr-gate.sh's BASH_SOURCE guard).
if ($MyInvocation.InvocationName -ne '.') {
    exit (Split-PrePrGateCliResult (Invoke-PrePrGateMain -Arguments $args))
}
