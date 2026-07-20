#Requires -Version 7.0
# cleanup-workspace.ps1
# issue-work: resume reconciliation + safe cleanup (PUSHED -> ... -> CLEANED)
# ==========================================================================
# PowerShell parity port of scripts/cleanup-workspace.sh. Same functions, same
# behavior, same manifest transitions, same fail-safe cleanup gate, same
# injection seams (GIT_BIN / GH_BIN / CLEANUP_LEASE_DIRNAME / CLEANUP_RM), same
# 3-fail preservation policy, same credential redaction. See
# reference/workspace-lifecycle.md (the #840 sections) for the contract both
# scripts satisfy.
#
# NOTE (authoring-time caveat): pwsh was not available in the environment this
# port was written in, so it was produced by mirroring the bash-verified logic
# in cleanup-workspace.sh line-for-line rather than by running it. It has NOT
# been executed and is NOT wired into CI. Cross-platform regression coverage is
# tracked in issue #832, consistent with the existing PowerShell-parity notes
# for the triage (#829), workspace (#838), and agents (#839) stages in
# tests/issue-work/README.md.
#
# The script is both a sourceable library (dot-source it to get the functions
# below) and a CLI:
#   pwsh -File cleanup-workspace.ps1 --phase reconcile --repo-dir <dir> --manifest <path> [--pr <n>]
#   pwsh -File cleanup-workspace.ps1 --phase cleanup --run-root <dir> --repo-dir <dir> \
#        --manifest <path> --base <tmpbase> --issue <n> [--pr <n>] [--merge-commit <sha>]
# CLI flags intentionally mirror cleanup-workspace.sh's flags exactly so the two
# entry points are interchangeable from a caller's point of view.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit from git/gh is data here, not an error: cleanup-workspace.sh
# reads `rev-parse @{u}` failing as "no upstream", `merge-base --is-ancestor`
# failing as "not an ancestor", and `gh pr view` failing as "no such PR" -- all
# load-bearing refusals in the cleanup gate. A host that has enabled
# $PSNativeCommandUseErrorActionPreference would promote those exits to
# terminating errors under the 'Stop' preference above, turning a safety refusal
# into a crash, so the setting is pinned off for this script.
#
# Pinned at script scope rather than inside _cleanup_git / _cleanup_gh because
# most call sites invoke $script:GitBin / $script:GhBin directly; a
# wrapper-local guard would leave them unprotected.
$PSNativeCommandUseErrorActionPreference = $false

# Reuse the #838 manifest primitive (workspace_manifest_write/_read/_state,
# workspace_redact_credentials, WorkspaceMarkerFile). workspace.ps1 is quiet
# when dot-sourced.
$script:CleanupDir = Split-Path -Parent $PSCommandPath
. (Join-Path $script:CleanupDir 'workspace.ps1')

# Injection seams (overridable by tests and callers via environment variables,
# mirroring the bash GIT_BIN / GH_BIN / CLEANUP_* seams).
$script:GitBin = if ($env:GIT_BIN) { $env:GIT_BIN } else { 'git' }
$script:GhBin = if ($env:GH_BIN) { $env:GH_BIN } else { 'gh' }

# Lease directory basename. Matches agents.ps1's AgentsLeaseDirname so this stage
# can detect a still-held single-writer lease left behind by #839.
$script:CleanupLeaseDirname = if ($env:CLEANUP_LEASE_DIRNAME) { $env:CLEANUP_LEASE_DIRNAME } else { '.iw-writer.lease' }

# Delete seam. When empty, removal uses the internal guarded Remove-Item. Tests
# set it to a failing remover so the retry / 3-fail preservation policy is
# testable without a real un-removable directory.
$script:CleanupRm = if ($env:CLEANUP_RM) { $env:CLEANUP_RM } else { '' }

# Seconds to sleep between removal retries. A seam so tests can drive the retry
# loop instantly; real runs get a brief pause (the Windows file-lock analog).
$script:CleanupRetrySleep = if ($env:CLEANUP_RETRY_SLEEP) { [int]$env:CLEANUP_RETRY_SLEEP } else { 1 }

# Set by primitives on failure; consumed by callers to build a redacted reason
# without re-touching git's/gh's raw output.
$script:CleanupLastError = ''

# Lifecycle states this stage owns (strictly ordered).
$script:CleanupStatePushed = 'PUSHED'
$script:CleanupStatePrOpen = 'PR_OPEN'
$script:CleanupStateCiPending = 'CI_PENDING'
$script:CleanupStateMerged = 'MERGED'
$script:CleanupStateCleanupPending = 'CLEANUP_PENDING'
$script:CleanupStateCleaned = 'CLEANED'

# ── Low-level command wrappers ────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via
# $env:GIT_BIN.
#
# Native-command failure is surfaced via $LASTEXITCODE, never a thrown
# exception: $ErrorActionPreference is locally lowered to 'Continue' so a benign
# non-zero git exit (`rev-parse @{u}` on a branch with no upstream, or
# `merge-base --is-ancestor` reporting "not an ancestor") does NOT become a
# terminating error when the caller has enabled
# $PSNativeCommandUseErrorActionPreference under the script-scope 'Stop'
# preference. Both exits are load-bearing refusals in cleanup-workspace.sh, not
# errors. Mirrors _triage_gh in triage.ps1.
function _cleanup_git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    & $script:GitBin @GitArgs
}

# All gh access funnels through here so a fake gh can shadow it via $env:GH_BIN.
# Guarded for the same reason as _cleanup_git: `gh pr view` on a missing PR
# exits non-zero, and reconcile treats that as "no PR" rather than an error.
function _cleanup_gh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GhArgs)
    $ErrorActionPreference = 'Continue'
    & $script:GhBin @GhArgs
}

# ── Path normalization ────────────────────────────────────────────────

# Pure (filesystem-free) normalization of an already-absolute path: collapses
# "." and empty segments and resolves ".." lexically. Never touches disk, so it
# is safe for a path that does not (yet) exist. Mirrors agents.ps1's normalizer.
function _cleanup_normalize_pure {
    param([string]$InputPath)
    $result = ''
    foreach ($seg in ($InputPath -split '/')) {
        switch ($seg) {
            '' { continue }
            '.' { continue }
            '..' {
                $idx = $result.LastIndexOf('/')
                $result = if ($idx -ge 0) { $result.Substring(0, $idx) } else { '' }
            }
            default { $result = "$result/$seg" }
        }
    }
    if ([string]::IsNullOrEmpty($result)) { return '/' }
    return $result
}

# Resolve Path to an absolute, canonical path. For an existing directory this
# uses the resolved provider path (which also resolves symlinks/junctions, so a
# reparse point cannot cause a false path-prefix mismatch); for a non-existent
# path it makes the path absolute against the current directory and normalizes
# it lexically.
function _cleanup_realpath {
    param([AllowEmptyString()][string]$Path = '')
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $abs = $Path
    if ($abs -notmatch '^/') {
        $cwd = (Get-Location).Path.TrimEnd('/', '\')
        $abs = "$cwd/$abs"
    }
    return _cleanup_normalize_pure $abs
}

# True when the given path is a symlink / junction / reparse point.
function _cleanup_is_reparse_point {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

# ── Cleanup safety predicate ──────────────────────────────────────────

# cleanup_validate_path <candidate> <run_base> <expected_issue>
# The single gate that decides whether a candidate path may ever be handed to a
# remover. Refuses ($false + CleanupLastError) unless the candidate is
# unambiguously an issue-work run root created by #838 for the expected issue.
# See cleanup-workspace.sh for the full list of refusal conditions.
function cleanup_validate_path {
    param([AllowEmptyString()][string]$Candidate = '', [AllowEmptyString()][string]$RunBase = '', [AllowEmptyString()][string]$Issue = '')
    $script:CleanupLastError = ''

    if ([string]::IsNullOrEmpty($Candidate) -or [string]::IsNullOrEmpty($RunBase) -or [string]::IsNullOrEmpty($Issue)) {
        $script:CleanupLastError = 'empty candidate/base/issue'
        return $false
    }

    # Traversal attempt in the RAW candidate, before any canonicalization.
    if ($Candidate -like '*..*') {
        $script:CleanupLastError = "path traversal ('..') refused"
        return $false
    }

    # The final component must not itself be a symlink / junction (swap attack),
    # checked on the raw candidate before canonicalization would resolve it away.
    if (_cleanup_is_reparse_point $Candidate) {
        $script:CleanupLastError = 'candidate final component is a symlink/junction'
        return $false
    }

    # Basename must be an issue-work run root for the expected issue.
    $baseName = Split-Path -Leaf $Candidate
    if ($baseName -notlike "iw-$Issue-*") {
        $script:CleanupLastError = "basename does not match iw-$Issue-*"
        return $false
    }

    # Canonicalize BOTH so a /var -> /private/var (or a Windows reparse) cannot
    # desync them.
    $canonCandidate = _cleanup_realpath $Candidate
    if ([string]::IsNullOrEmpty($canonCandidate)) {
        $script:CleanupLastError = 'cannot canonicalize candidate'
        return $false
    }
    $canonBase = _cleanup_realpath $RunBase
    if ([string]::IsNullOrEmpty($canonBase)) {
        $script:CleanupLastError = 'cannot canonicalize run base'
        return $false
    }

    # Never the filesystem root.
    if ($canonCandidate -eq '/' -or $canonCandidate -match '^[A-Za-z]:[\\/]?$') {
        $script:CleanupLastError = 'refusing to remove the filesystem root'
        return $false
    }

    # Never the home directory. (Use a distinct name -- $HOME is a read-only
    # PowerShell automatic variable and must not be reassigned.)
    $userHome = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { '' }
    if (-not [string]::IsNullOrEmpty($userHome)) {
        $canonHome = _cleanup_realpath $userHome
        if ([string]::IsNullOrEmpty($canonHome)) { $canonHome = $userHome }
        if ($canonCandidate -eq $canonHome) {
            $script:CleanupLastError = 'refusing to remove the home directory'
            return $false
        }
    }

    # Must be STRICTLY under the base: <canonical_base>/<something>, never equal.
    if ($canonCandidate -eq $canonBase) {
        $script:CleanupLastError = 'candidate equals the run base'
        return $false
    }
    if (-not $canonCandidate.StartsWith("$canonBase/")) {
        $script:CleanupLastError = 'candidate is not strictly under the run base'
        return $false
    }

    # Marker must be present and name the expected issue.
    $marker = Join-Path $Candidate $script:WorkspaceMarkerFile
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
        $script:CleanupLastError = "run marker $script:WorkspaceMarkerFile missing"
        return $false
    }
    $markerHasIssue = Get-Content -LiteralPath $marker -ErrorAction SilentlyContinue |
        Where-Object { $_ -eq "issue=$Issue" } | Select-Object -First 1
    if (-not $markerHasIssue) {
        $script:CleanupLastError = "run marker does not name issue $Issue"
        return $false
    }

    return $true
}

# ── Preservation predicates ───────────────────────────────────────────

# cleanup_git_state_clean <repo_dir>
# Succeeds only when the working tree is completely clean (status --porcelain
# empty) AND there are no unmerged / conflict entries (ls-files -u empty).
function cleanup_git_state_clean {
    param([string]$RepoDir)
    $script:CleanupLastError = ''
    if ([string]::IsNullOrEmpty($RepoDir)) { $script:CleanupLastError = 'empty repo dir'; return $false }
    if (-not (Test-Path -LiteralPath $RepoDir -PathType Container)) { $script:CleanupLastError = 'repo dir does not exist'; return $false }

    $porcelain = & $script:GitBin -C $RepoDir status --porcelain 2>$null
    if (-not [string]::IsNullOrEmpty(($porcelain | Out-String).Trim())) {
        $script:CleanupLastError = 'working tree not clean (uncommitted or untracked changes)'
        return $false
    }
    $unmerged = & $script:GitBin -C $RepoDir ls-files -u 2>$null
    if (-not [string]::IsNullOrEmpty(($unmerged | Out-String).Trim())) {
        $script:CleanupLastError = 'unresolved merge conflicts present'
        return $false
    }
    return $true
}

# cleanup_remotely_recoverable <repo_dir> [<merge_commit>]
# Succeeds when the local HEAD is recoverable from a remote. Holds if ANY of:
#   (a) HEAD is contained in some remote-tracking ref;
#   (b) HEAD has an upstream and is not ahead of it;
#   (c) <merge_commit> is given and is an ancestor of origin/develop (the
#       squash-merge nuance).
# Fail-safe: none holding -> refuse (preserve).
function cleanup_remotely_recoverable {
    param([string]$RepoDir, [AllowEmptyString()][string]$MergeCommit = '')
    $script:CleanupLastError = ''
    if ([string]::IsNullOrEmpty($RepoDir)) { $script:CleanupLastError = 'empty repo dir'; return $false }

    # (a) HEAD is contained in some remote-tracking ref.
    $remoteContains = & $script:GitBin -C $RepoDir branch -r --contains HEAD 2>$null
    if (-not [string]::IsNullOrEmpty(($remoteContains | Out-String).Trim())) {
        return $true
    }

    # (b) HEAD has an upstream and is not ahead of it.
    & $script:GitBin -C $RepoDir rev-parse --abbrev-ref '@{u}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $ahead = (& $script:GitBin -C $RepoDir rev-list --count '@{u}..HEAD' 2>$null | Out-String).Trim()
        if ($ahead -eq '0') {
            return $true
        }
    }

    # (c) squash-merge: the merge commit landed on origin/develop.
    if (-not [string]::IsNullOrEmpty($MergeCommit)) {
        & $script:GitBin -C $RepoDir merge-base --is-ancestor $MergeCommit origin/develop 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }

    $script:CleanupLastError = 'local HEAD is not recoverable from any remote (unpushed work)'
    return $false
}

# cleanup_agents_terminated <run_root>
# Succeeds only when NO single-writer lease directory survives under <run_root>.
function cleanup_agents_terminated {
    param([string]$RunRoot)
    $script:CleanupLastError = ''
    if ([string]::IsNullOrEmpty($RunRoot)) { $script:CleanupLastError = 'empty run root'; return $false }

    $found = Get-ChildItem -LiteralPath $RunRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $script:CleanupLeaseDirname } | Select-Object -First 1
    if ($found) {
        $script:CleanupLastError = 'a writer lease is still held (agent not terminated)'
        return $false
    }
    return $true
}

# ── Manifest state transitions ────────────────────────────────────────

# Advance the manifest state from From to To, refusing if the current state is
# not exactly From. Mirrors agents.ps1's _agents_transition.
function _cleanup_transition {
    param([string]$Manifest, [string]$From, [string]$To)
    if ([string]::IsNullOrEmpty($Manifest) -or [string]::IsNullOrEmpty($From) -or [string]::IsNullOrEmpty($To)) { return $false }
    $current = workspace_manifest_state -Path $Manifest
    if ($current -ne $From) {
        $shown = if ([string]::IsNullOrEmpty($current)) { '<empty>' } else { $current }
        $script:CleanupLastError = "expected state $From but manifest is $shown"
        return $false
    }
    workspace_manifest_write -Path $Manifest -Key 'state' -Value $To | Out-Null
    return $true
}

# Thin advancing helpers along PUSHED -> ... -> CLEANED.
function cleanup_mark_pr_open         { param([string]$Manifest) return (_cleanup_transition -Manifest $Manifest -From $script:CleanupStatePushed        -To $script:CleanupStatePrOpen) }
function cleanup_mark_ci_pending      { param([string]$Manifest) return (_cleanup_transition -Manifest $Manifest -From $script:CleanupStatePrOpen        -To $script:CleanupStateCiPending) }
function cleanup_mark_merged          { param([string]$Manifest) return (_cleanup_transition -Manifest $Manifest -From $script:CleanupStateCiPending     -To $script:CleanupStateMerged) }
function cleanup_mark_cleanup_pending { param([string]$Manifest) return (_cleanup_transition -Manifest $Manifest -From $script:CleanupStateMerged        -To $script:CleanupStateCleanupPending) }
function cleanup_mark_cleaned         { param([string]$Manifest) return (_cleanup_transition -Manifest $Manifest -From $script:CleanupStateCleanupPending -To $script:CleanupStateCleaned) }

# ── Emit outcome JSON (redacted) ──────────────────────────────────────

function _cleanup_emit_reconciled {
    param([string]$Manifest, [string]$Branch, [string]$Head, [string]$State, [AllowEmptyString()][string]$PrState = '')
    $Branch = workspace_redact_credentials $Branch
    $Head = workspace_redact_credentials $Head
    $State = workspace_redact_credentials $State
    $PrState = workspace_redact_credentials $PrState
    $Manifest = workspace_redact_credentials $Manifest
    Write-Output ('{{"phase":"reconcile","state":"{0}","branch":"{1}","head":"{2}","pr_state":"{3}","manifest":"{4}"}}' `
        -f $State, $Branch, $Head, $PrState, $Manifest)
}

function _cleanup_emit_cleaned {
    param([string]$RunRoot, [string]$Manifest)
    $RunRoot = workspace_redact_credentials $RunRoot
    $Manifest = workspace_redact_credentials $Manifest
    Write-Output ('{{"state":"CLEANED","run_root":"{0}","manifest":"{1}"}}' -f $RunRoot, $Manifest)
}

function _cleanup_emit_preserve {
    param([AllowEmptyString()][string]$Reason = '', [AllowEmptyString()][string]$RunRoot = '')
    $Reason = workspace_redact_credentials $Reason
    $RunRoot = workspace_redact_credentials $RunRoot
    Write-Output ('{{"state":"PRESERVED","reason":"{0}","run_root":"{1}"}}' -f $Reason, $RunRoot)
}

function _cleanup_emit_error {
    param([AllowEmptyString()][string]$Reason = '')
    $Reason = workspace_redact_credentials $Reason
    Write-Output ('{{"state":"ERROR","reason":"{0}"}}' -f $Reason)
}

# ── Resume reconciliation ─────────────────────────────────────────────

# cleanup_reconcile <repo_dir> <manifest> [<pr_number>]
# Re-reads LIVE state and repairs the manifest, never trusting the stored state
# alone. Reality wins over the stored state. See cleanup-workspace.sh for the
# full derivation rules.
function cleanup_reconcile {
    param([string]$RepoDir, [string]$Manifest, [AllowEmptyString()][string]$PrNumber = '')
    $script:CleanupLastError = ''
    if ([string]::IsNullOrEmpty($RepoDir) -or [string]::IsNullOrEmpty($Manifest)) {
        _cleanup_emit_error 'missing required repo-dir/manifest'
        return 2
    }

    $branch = (& $script:GitBin -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    $head = (& $script:GitBin -C $RepoDir rev-parse HEAD 2>$null | Out-String).Trim()
    $remoteRef = ''
    if (-not [string]::IsNullOrEmpty($branch)) {
        $remoteRef = (& $script:GitBin -C $RepoDir ls-remote --heads origin $branch 2>$null | Out-String).Trim()
    }
    $storedState = workspace_manifest_state -Path $Manifest

    $prState = ''
    $prMerge = ''
    if (-not [string]::IsNullOrEmpty($PrNumber)) {
        $prState = (_cleanup_gh pr view $PrNumber --json state,mergedAt,mergeCommit,headRefName --jq '.state' 2>$null | Out-String).Trim()
        $prMerge = (_cleanup_gh pr view $PrNumber --json state,mergedAt,mergeCommit,headRefName --jq '.mergeCommit.oid' 2>$null | Out-String).Trim()
    }

    # Derive the reconciled state from reality, never from the stored state alone.
    $newState = ''
    if ($prState -eq 'MERGED') {
        if ($storedState -eq $script:CleanupStateCleanupPending -or $storedState -eq $script:CleanupStateCleaned) {
            $newState = $storedState
        } else {
            $newState = $script:CleanupStateMerged
        }
    } elseif (-not [string]::IsNullOrEmpty($remoteRef)) {
        if (-not [string]::IsNullOrEmpty($prState)) {
            if ($storedState -eq $script:CleanupStateCiPending) { $newState = $storedState } else { $newState = $script:CleanupStatePrOpen }
        } else {
            if ($storedState -eq $script:CleanupStatePrOpen -or $storedState -eq $script:CleanupStateCiPending) {
                $newState = $storedState
            } else {
                $newState = $script:CleanupStatePushed
            }
        }
    } else {
        $newState = $storedState
    }

    if (-not [string]::IsNullOrEmpty($branch))   { workspace_manifest_write -Path $Manifest -Key 'branch' -Value $branch | Out-Null }
    if (-not [string]::IsNullOrEmpty($head))     { workspace_manifest_write -Path $Manifest -Key 'head' -Value $head | Out-Null }
    if (-not [string]::IsNullOrEmpty($prMerge))  { workspace_manifest_write -Path $Manifest -Key 'merge_commit' -Value $prMerge | Out-Null }
    if (-not [string]::IsNullOrEmpty($newState)) { workspace_manifest_write -Path $Manifest -Key 'state' -Value $newState | Out-Null }

    $emitState = if ([string]::IsNullOrEmpty($newState)) { $storedState } else { $newState }
    _cleanup_emit_reconciled -Manifest $Manifest -Branch $branch -Head $head -State $emitState -PrState $prState
    return 0
}

# ── Gated removal ─────────────────────────────────────────────────────

# Remove the target via the CleanupRm seam when set, else the internal guarded
# Remove-Item. NEVER called on anything but a freshly re-validated run root.
# Returns $true on success.
function _cleanup_remove {
    param([string]$Target)
    if ([string]::IsNullOrEmpty($Target)) { return $false }
    if (-not [string]::IsNullOrEmpty($script:CleanupRm)) {
        & $script:CleanupRm $Target
        return ($LASTEXITCODE -eq 0)
    }
    try {
        Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Print, to stderr, a manual cleanup procedure naming the exact validated path.
function _cleanup_print_manual_procedure {
    param([string]$RunRoot)
    [Console]::Error.WriteLine('MANUAL CLEANUP REQUIRED')
    [Console]::Error.WriteLine('  Automated removal failed 3 times (3-fail rule); the workspace is preserved.')
    [Console]::Error.WriteLine('  Verify no process holds a file under the path below, then remove it by hand:')
    [Console]::Error.WriteLine("    Remove-Item -Recurse -Force -- '$RunRoot'")
}

# The gated delete: re-validate immediately before each removal (TOCTOU guard),
# retry at most 3 times on failure, and on 3 identical failures preserve and
# print the manual procedure (3-fail rule). On success emit CLEANED.
function _cleanup_gated_delete {
    param([string]$RunRoot, [string]$RunBase, [string]$Issue, [string]$Manifest)
    $attempt = 1
    $max = 3

    while ($attempt -le $max) {
        # TOCTOU guard: re-validate the exact path immediately before removal.
        if (-not (cleanup_validate_path -Candidate $RunRoot -RunBase $RunBase -Issue $Issue)) {
            _cleanup_emit_preserve "revalidation failed before removal: $script:CleanupLastError" $RunRoot
            return 1
        }

        $ok = _cleanup_remove $RunRoot
        if ($ok -and -not (Test-Path -LiteralPath $RunRoot)) {
            # If a manifest override lives OUTSIDE the (now-removed) run root,
            # persist the terminal state. When the manifest lived inside the run
            # root it is gone and the emitted JSON below is the only record.
            if (Test-Path -LiteralPath $Manifest) {
                _cleanup_transition -Manifest $Manifest -From $script:CleanupStateCleanupPending -To $script:CleanupStateCleaned | Out-Null
            }
            _cleanup_emit_cleaned -RunRoot $RunRoot -Manifest $Manifest
            return 0
        }

        $attempt++
        if ($attempt -le $max) { Start-Sleep -Seconds $script:CleanupRetrySleep }
    }

    # 3-fail rule: stop retrying, preserve, and print the manual procedure.
    _cleanup_print_manual_procedure $RunRoot
    _cleanup_emit_preserve "removal failed after $max attempts; workspace preserved" $RunRoot
    return 1
}

# ── Gated cleanup driver ──────────────────────────────────────────────

# cleanup_workspace <run_root> <repo_dir> <manifest> <run_base> <expected_issue>
#                   [<merge_commit>] [<pr_number>]
# The gated delete. ALL gates must hold, else PRESERVE. See cleanup-workspace.sh
# for the full gate list.
function cleanup_workspace {
    param(
        [string]$RunRoot, [string]$RepoDir, [string]$Manifest, [string]$RunBase, [string]$Issue,
        [AllowEmptyString()][string]$MergeCommit = '', [AllowEmptyString()][string]$PrNumber = ''
    )
    $script:CleanupLastError = ''

    if ([string]::IsNullOrEmpty($RunRoot) -or [string]::IsNullOrEmpty($RepoDir) -or [string]::IsNullOrEmpty($Manifest) -or
        [string]::IsNullOrEmpty($RunBase) -or [string]::IsNullOrEmpty($Issue)) {
        _cleanup_emit_preserve 'missing required run-root/repo-dir/manifest/base/issue' $RunRoot
        return 2
    }
    # PrNumber is accepted for signature parity with reconcile / the CLI but is
    # not consulted here: the MERGED gate is the coordinator's authority that the
    # PR merged.
    $null = $PrNumber

    # Gate 1: manifest state must be MERGED or CLEANUP_PENDING.
    $state = workspace_manifest_state -Path $Manifest
    if ($state -ne $script:CleanupStateMerged -and $state -ne $script:CleanupStateCleanupPending) {
        $shown = if ([string]::IsNullOrEmpty($state)) { '<empty>' } else { $state }
        _cleanup_emit_preserve "state is $shown; refusing cleanup before MERGED (PR incomplete or not merged)" $RunRoot
        return 1
    }

    # Gate 2: path safety.
    if (-not (cleanup_validate_path -Candidate $RunRoot -RunBase $RunBase -Issue $Issue)) {
        _cleanup_emit_preserve "path safety: $script:CleanupLastError" $RunRoot
        return 1
    }

    # Gate 3: git state clean (uncommitted work + unresolved conflicts).
    if (-not (cleanup_git_state_clean -RepoDir $RepoDir)) {
        _cleanup_emit_preserve "git state: $script:CleanupLastError" $RunRoot
        return 1
    }

    # Gate 4: work recoverable from a remote (no unpushed commits).
    if (-not (cleanup_remotely_recoverable -RepoDir $RepoDir -MergeCommit $MergeCommit)) {
        _cleanup_emit_preserve "recoverability: $script:CleanupLastError" $RunRoot
        return 1
    }

    # Gate 5: all agents terminated (no held lease).
    if (-not (cleanup_agents_terminated -RunRoot $RunRoot)) {
        _cleanup_emit_preserve "agents: $script:CleanupLastError" $RunRoot
        return 1
    }

    # Advance to CLEANUP_PENDING (skip if already there, e.g. a resumed run).
    if ($state -eq $script:CleanupStateMerged) {
        if (-not (_cleanup_transition -Manifest $Manifest -From $script:CleanupStateMerged -To $script:CleanupStateCleanupPending)) {
            _cleanup_emit_preserve "cannot advance to CLEANUP_PENDING: $script:CleanupLastError" $RunRoot
            return 1
        }
    }

    return (_cleanup_gated_delete -RunRoot $RunRoot -RunBase $RunBase -Issue $Issue -Manifest $Manifest)
}

# ── Driver ────────────────────────────────────────────────────────────
# run_cleanup -Phase reconcile|cleanup ...
function run_cleanup {
    param(
        [string]$Phase, [AllowEmptyString()][string]$RunRoot = '', [AllowEmptyString()][string]$RepoDir = '',
        [AllowEmptyString()][string]$Manifest = '', [AllowEmptyString()][string]$Base = '', [AllowEmptyString()][string]$Issue = '',
        [AllowEmptyString()][string]$MergeCommit = '', [AllowEmptyString()][string]$Pr = ''
    )
    switch ($Phase) {
        'reconcile' {
            return (cleanup_reconcile -RepoDir $RepoDir -Manifest $Manifest -PrNumber $Pr)
        }
        'cleanup' {
            return (cleanup_workspace -RunRoot $RunRoot -RepoDir $RepoDir -Manifest $Manifest -RunBase $Base -Issue $Issue -MergeCommit $MergeCommit -PrNumber $Pr)
        }
        default {
            $shown = if ([string]::IsNullOrEmpty($Phase)) { '<empty>' } else { $Phase }
            _cleanup_emit_error "unknown phase: $shown"
            return 2
        }
    }
}

# ── CLI entry ─────────────────────────────────────────────────────────

# Split a driver result into "emit on stdout" and "use as the exit code".
#
# run_cleanup writes its JSON to the success stream and then `return`s an int
# exit code -- but in PowerShell a `return` value also lands on the success
# stream, so the caller receives @(<json>, <int>) as one array. Passing that
# array straight to `exit` casts the whole array to int, which throws and takes
# the JSON down with it, so `pwsh -File cleanup-workspace.ps1 ...` printed
# nothing at all while cleanup-workspace.sh printed the phase JSON
# (issue #847 S2).
#
# This helper writes every non-int item straight to the console and returns the
# trailing int as the exit code, restoring parity with the bash CLI.
# Dot-sourced callers are unaffected -- they consume the driver's return value
# directly.
#
# The payload goes out via [Console]::Out rather than Write-Output on purpose:
# Write-Output would put it back on the success stream alongside the returned
# exit code, reproducing the very merge this helper exists to undo.
function Split-CleanupCliResult {
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

function Invoke-CleanupMain {
    param([string[]]$Arguments = @())
    $runRoot = ''; $repoDir = ''; $manifest = ''; $base = ''; $issue = ''; $phase = ''; $pr = ''; $mergeCommit = ''
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '--run-root' { $runRoot = $Arguments[$i + 1]; $i += 2 }
            '--repo-dir' { $repoDir = $Arguments[$i + 1]; $i += 2 }
            '--manifest' { $manifest = $Arguments[$i + 1]; $i += 2 }
            '--base' { $base = $Arguments[$i + 1]; $i += 2 }
            '--issue' { $issue = $Arguments[$i + 1]; $i += 2 }
            '--phase' { $phase = $Arguments[$i + 1]; $i += 2 }
            '--pr' { $pr = $Arguments[$i + 1]; $i += 2 }
            '--merge-commit' { $mergeCommit = $Arguments[$i + 1]; $i += 2 }
            default {
                Write-Error "unknown argument: $($Arguments[$i])"
                return 2
            }
        }
    }
    if (-not $phase) {
        Write-Error 'error: --phase <reconcile|cleanup> is required'
        return 2
    }
    return run_cleanup -Phase $phase -RunRoot $runRoot -RepoDir $repoDir -Manifest $manifest -Base $base -Issue $issue -MergeCommit $mergeCommit -Pr $pr
}

# Run as CLI only when executed directly; stay quiet when dot-sourced by tests
# (mirrors cleanup-workspace.sh's BASH_SOURCE guard).
if ($MyInvocation.InvocationName -ne '.') {
    exit (Split-CleanupCliResult (Invoke-CleanupMain -Arguments $args))
}
