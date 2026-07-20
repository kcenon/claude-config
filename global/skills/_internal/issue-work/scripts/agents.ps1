#Requires -Version 7.0
# agents.ps1
# issue-work: subagent spawn contract + single-writer lease (READY -> AGENTS_RUNNING -> COMMITTED)
# ================================================================================================
# PowerShell parity port of scripts/agents.sh. Same functions, same behavior,
# same manifest transitions, same fail-safe lease semantics, same injection
# seams, same capability boundary (NO GitHub CLI, NO remote push -- the only git
# verb is `git worktree`). See reference/workspace-lifecycle.md for the contract
# both scripts satisfy.
#
# Runtime-verified by tests/issue-work/test-agents.ps1, which drives the same
# scenarios as the bash suite and runs in CI alongside it (#847).
#
# The script is both a sourceable library (dot-source it to get the functions
# below) and a CLI:
#   pwsh -File agents.ps1 --manifest <path> --phase start|commit [--owner <id>]
# CLI flags intentionally mirror agents.sh's flags exactly so the two entry
# points are interchangeable from a caller's point of view.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit from git is data here, not an error: agents.sh reads a failed
# `worktree add` / `worktree remove` as a plain "false". A host that has enabled
# $PSNativeCommandUseErrorActionPreference would promote those exits to
# terminating errors under the 'Stop' preference above, so the setting is pinned
# off for this script.
#
# Pinned at script scope rather than inside _agents_git because the worktree
# add/remove call sites invoke $script:GitBin directly; a wrapper-local guard
# would leave them unprotected.
$PSNativeCommandUseErrorActionPreference = $false

# Reuse the #838 manifest primitive (workspace_manifest_write/_read/_state,
# workspace_redact_credentials). workspace.ps1 is quiet when dot-sourced.
$script:AgentsDir = Split-Path -Parent $PSCommandPath
. (Join-Path $script:AgentsDir 'workspace.ps1')

# Injection seams (overridable by tests and callers via environment variables,
# mirroring the bash GIT_BIN seam).
$script:GitBin = if ($env:GIT_BIN) { $env:GIT_BIN } else { 'git' }

# Lease directory basename. A release only ever removes a path whose final
# component equals this value (see agents_release_lease), so a caller-supplied
# path can never be mistaken for an arbitrary directory to delete.
$script:AgentsLeaseDirname = if ($env:AGENTS_LEASE_DIRNAME) { $env:AGENTS_LEASE_DIRNAME } else { '.iw-writer.lease' }

# Marker file recorded inside a held lease directory naming its owner.
$script:AgentsLeaseOwnerFile = 'owner'

# Lifecycle states this stage owns.
$script:AgentsStateReady = 'READY'
$script:AgentsStateRunning = 'AGENTS_RUNNING'
$script:AgentsStateCommitted = 'COMMITTED'

# Set by primitives on failure; consumed by run_agents to build a redacted
# reason without re-touching git's raw output.
$script:AgentsLastError = ''

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via
# $env:GIT_BIN. Only `git worktree` is ever passed in -- never a network verb.
#
# Native-command failure is surfaced via $LASTEXITCODE, never a thrown
# exception: $ErrorActionPreference is locally lowered to 'Continue' so a benign
# non-zero git exit (a `worktree add` onto an existing path, or a `worktree
# remove` of an already-removed tree) does NOT become a terminating error when
# the caller has enabled $PSNativeCommandUseErrorActionPreference under the
# script-scope 'Stop' preference. agents.sh treats those exits as a normal
# "false". Mirrors _triage_gh in triage.ps1.
function _agents_git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    & $script:GitBin @GitArgs
}

# ── Path normalization ────────────────────────────────────────────────

# Pure (filesystem-free) normalization of an already-absolute path: collapses
# "." and empty segments and resolves ".." lexically. Never touches disk, so it
# is safe for a path that does not (yet) exist.
function _agents_normalize_pure {
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

# Resolve Path to an absolute, normalized path. For an existing directory this
# uses the resolved provider path (which also resolves symlinks); for a
# non-existent path it makes the path absolute against the current directory and
# normalizes it lexically. An absolute path is required by the spawn contract
# (agents_build_prompt embeds it verbatim).
function agents_normalize_path {
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
    return _agents_normalize_pure $abs
}

# ── Spawn-prompt contract ──────────────────────────────────────────────

# Build the subagent spawn prompt. The output ALWAYS contains every field the
# contract requires so a coordinator can never spawn an under-specified agent:
#   * a normalized absolute repo path   (agents_normalize_path)
#   * the active issue number
#   * the target branch
#   * the baseline commit sha
#   * an explicit write scope (the only paths the agent may touch)
#   * an ownership/prohibition clause forbidding remote pushes, the GitHub CLI,
#     opening/merging pull requests, and workspace cleanup
#
# The prohibition prose is worded to convey each ban WITHOUT embedding a literal
# remote-push or bare GitHub-CLI command token, so the capability-guard test can
# still assert this file performs no such command.
function agents_build_prompt {
    param(
        [string]$RepoPath,
        [string]$Issue,
        [string]$Branch,
        [string]$Baseline,
        [AllowEmptyString()][string]$WriteScope = ''
    )
    $abs = agents_normalize_path $RepoPath
    if ([string]::IsNullOrEmpty($abs)) { $abs = $RepoPath }
    return @"
You are an implementation subagent for issue #$Issue.

Repository (normalized absolute path): $abs
Active issue: #$Issue
Target branch: $Branch
Baseline commit: $Baseline

Write scope -- you may create or edit ONLY these paths:
$WriteScope

Ownership and prohibitions (the coordinator owns ALL git and GitHub mutations):
- You MUST NOT push any commit or branch to the remote.
- You MUST NOT invoke the GitHub CLI or any GitHub API mutation.
- You MUST NOT open, update, or merge a pull request (PR).
- You MUST NOT clean up, delete, or otherwise tear down the workspace.
- You may only read and write files within the write scope above.
- When in doubt, stop and defer the mutation to the coordinator.
"@
}

# ── Single-writer lease (mkdir-atomic) ────────────────────────────────

# True only when LeasePath's final component equals AgentsLeaseDirname. This is
# the guard that keeps agents_release_lease from ever removing an arbitrary
# caller-supplied path.
function _agents_valid_lease_path {
    param([AllowEmptyString()][string]$LeasePath = '')
    if ([string]::IsNullOrEmpty($LeasePath)) { return $false }
    return ((Split-Path -Leaf $LeasePath) -eq $script:AgentsLeaseDirname)
}

# Atomically acquire the single-writer lease at LeasePath for OwnerId. Directory
# creation is the atomic primitive: exactly one caller can create the directory,
# so a second concurrent writer is refused with $false. Fail-safe: any error
# (bad path, parent-create failure, lease already held) returns $false -- when
# in doubt, refuse rather than admit a second writer.
function agents_acquire_lease {
    param([string]$LeasePath, [string]$OwnerId)
    if ([string]::IsNullOrEmpty($LeasePath) -or [string]::IsNullOrEmpty($OwnerId)) { return $false }
    if (-not (_agents_valid_lease_path $LeasePath)) {
        $script:AgentsLastError = "lease path must end in $script:AgentsLeaseDirname"
        return $false
    }
    if (Test-Path -LiteralPath $LeasePath) {
        $script:AgentsLastError = 'lease already held'
        return $false
    }
    try {
        # -Force here creates parent directories; the prior Test-Path is the
        # held-lease guard. New-Item throws if a race lost the create, which the
        # catch turns into the fail-safe refusal.
        New-Item -ItemType Directory -Path $LeasePath -ErrorAction Stop | Out-Null
    } catch {
        $script:AgentsLastError = 'lease already held'
        return $false
    }
    Set-Content -LiteralPath (Join-Path $LeasePath $script:AgentsLeaseOwnerFile) -Value $OwnerId
    return $true
}

# Return the owner recorded in a held lease ($null if none).
function agents_lease_owner {
    param([string]$LeasePath)
    if ([string]::IsNullOrEmpty($LeasePath)) { return $null }
    $ownerFile = Join-Path $LeasePath $script:AgentsLeaseOwnerFile
    if (-not (Test-Path -LiteralPath $ownerFile)) { return $null }
    return (Get-Content -LiteralPath $ownerFile -First 1)
}

# Release the lease at LeasePath, but only if OwnerId currently holds it.
# Refuses ($false) for a non-owner, a missing lease, or a path that is not a
# lease directory. Removal is guarded: it deletes the known owner marker and
# then removes the now-empty directory -- never a recursive delete of the input.
function agents_release_lease {
    param([string]$LeasePath, [string]$OwnerId)
    if ([string]::IsNullOrEmpty($LeasePath) -or [string]::IsNullOrEmpty($OwnerId)) { return $false }
    if (-not (_agents_valid_lease_path $LeasePath)) {
        $script:AgentsLastError = 'refusing to release a non-lease path'
        return $false
    }
    if (-not (Test-Path -LiteralPath $LeasePath -PathType Container)) {
        $script:AgentsLastError = 'no lease to release'
        return $false
    }
    $stored = agents_lease_owner $LeasePath
    if ($stored -ne $OwnerId) {
        $script:AgentsLastError = 'lease held by another writer'
        return $false
    }
    $ownerFile = Join-Path $LeasePath $script:AgentsLeaseOwnerFile
    Remove-Item -LiteralPath $ownerFile -ErrorAction SilentlyContinue
    try {
        Remove-Item -LiteralPath $LeasePath -ErrorAction Stop
    } catch {
        return $false
    }
    return $true
}

# ── Per-agent worktrees (concurrent-writes case ONLY) ─────────────────
# The DEFAULT concurrency control is the single-writer lease above on the
# shared checkout. Worktrees are used ONLY when agents must write concurrently;
# each MUST be removed afterward (agents_worktree_remove) so no orphan is left
# to block the #840 cleanup stage.

# Add a worktree at WorktreePath on a NEW Branch, rooted in RepoDir.
function agents_worktree_add {
    param([string]$RepoDir, [string]$WorktreePath, [string]$Branch)
    if ([string]::IsNullOrEmpty($RepoDir) -or [string]::IsNullOrEmpty($WorktreePath) -or [string]::IsNullOrEmpty($Branch)) { return $false }
    $out = & $script:GitBin -C $RepoDir worktree add -b $Branch $WorktreePath 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $joined = ($out | Out-String)
        $redacted = workspace_redact_credentials $joined
        $lastLine = ($redacted -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
        $script:AgentsLastError = if ($lastLine) { $lastLine } else { 'unknown error' }
    }
    return ($rc -eq 0)
}

# Remove the worktree at WorktreePath so it is not left orphaned.
function agents_worktree_remove {
    param([string]$RepoDir, [string]$WorktreePath)
    if ([string]::IsNullOrEmpty($RepoDir) -or [string]::IsNullOrEmpty($WorktreePath)) { return $false }
    $out = & $script:GitBin -C $RepoDir worktree remove $WorktreePath 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $joined = ($out | Out-String)
        $redacted = workspace_redact_credentials $joined
        $lastLine = ($redacted -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
        $script:AgentsLastError = if ($lastLine) { $lastLine } else { 'unknown error' }
    }
    return ($rc -eq 0)
}

# ── Manifest state transitions ────────────────────────────────────────

# Advance the manifest state from From to To, refusing if the current state is
# not exactly From. This keeps the lifecycle strictly ordered
# (READY -> AGENTS_RUNNING -> COMMITTED) rather than allowing an out-of-order jump.
function _agents_transition {
    param([string]$Manifest, [string]$From, [string]$To)
    if ([string]::IsNullOrEmpty($Manifest) -or [string]::IsNullOrEmpty($From) -or [string]::IsNullOrEmpty($To)) { return $false }
    $current = workspace_manifest_state -Path $Manifest
    if ($current -ne $From) {
        $shown = if ([string]::IsNullOrEmpty($current)) { '<empty>' } else { $current }
        $script:AgentsLastError = "expected state $From but manifest is $shown"
        return $false
    }
    workspace_manifest_write -Path $Manifest -Key 'state' -Value $To | Out-Null
    return $true
}

# READY -> AGENTS_RUNNING. Records the lease owner when one is supplied.
function agents_mark_running {
    param([string]$Manifest, [AllowEmptyString()][string]$OwnerId = '')
    if (-not (_agents_transition -Manifest $Manifest -From $script:AgentsStateReady -To $script:AgentsStateRunning)) { return $false }
    if (-not [string]::IsNullOrEmpty($OwnerId)) {
        workspace_manifest_write -Path $Manifest -Key 'lease_owner' -Value $OwnerId | Out-Null
    }
    return $true
}

# AGENTS_RUNNING -> COMMITTED. The coordinator calls this after committing.
function agents_mark_committed {
    param([string]$Manifest)
    return (_agents_transition -Manifest $Manifest -From $script:AgentsStateRunning -To $script:AgentsStateCommitted)
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
function _agents_emit {
    param([string]$State, [string]$Manifest)
    Write-Output ('{{"state":"{0}","manifest":"{1}"}}' -f $State, $Manifest)
}

function _agents_emit_error {
    param([AllowEmptyString()][string]$Reason = '')
    $Reason = workspace_redact_credentials $Reason
    Write-Output ('{{"state":"ERROR","reason":"{0}"}}' -f $Reason)
}

# ── Driver ──────────────────────────────────────────────────────────
# run_agents -Manifest <path> -Phase start|commit [-OwnerId <id>]
#
# Phase=start   READY -> AGENTS_RUNNING (records lease_owner when owner given)
# Phase=commit  AGENTS_RUNNING -> COMMITTED (the post-commit transition)
function run_agents {
    param([string]$Manifest, [string]$Phase, [AllowEmptyString()][string]$OwnerId = '')
    if ([string]::IsNullOrEmpty($Manifest) -or [string]::IsNullOrEmpty($Phase)) {
        _agents_emit_error 'missing required manifest/phase'
        return 2
    }
    switch ($Phase) {
        'start' {
            if (-not (agents_mark_running -Manifest $Manifest -OwnerId $OwnerId)) {
                $reason = if ($script:AgentsLastError) { $script:AgentsLastError } else { 'cannot enter AGENTS_RUNNING' }
                _agents_emit_error $reason
                return 1
            }
            _agents_emit $script:AgentsStateRunning $Manifest
            return 0
        }
        'commit' {
            if (-not (agents_mark_committed -Manifest $Manifest)) {
                $reason = if ($script:AgentsLastError) { $script:AgentsLastError } else { 'cannot enter COMMITTED' }
                _agents_emit_error $reason
                return 1
            }
            _agents_emit $script:AgentsStateCommitted $Manifest
            return 0
        }
        default {
            _agents_emit_error "unknown phase: $Phase"
            return 2
        }
    }
}

# ── CLI entry ────────────────────────────────────────────────────────

# Split a driver result into "emit on stdout" and "use as the exit code".
#
# run_agents writes its JSON to the success stream and then `return`s an int
# exit code -- but in PowerShell a `return` value also lands on the success
# stream, so the caller receives @(<json>, <int>) as one array. Passing that
# array straight to `exit` casts the whole array to int, which throws and takes
# the JSON down with it, so `pwsh -File agents.ps1 ...` printed nothing at all
# while agents.sh printed the phase JSON (issue #847 S2).
#
# This helper writes every non-int item straight to the console and returns the
# trailing int as the exit code, restoring parity with the bash CLI.
# Dot-sourced callers are unaffected -- they consume the driver's return value
# directly.
#
# The payload goes out via [Console]::Out rather than Write-Output on purpose:
# Write-Output would put it back on the success stream alongside the returned
# exit code, reproducing the very merge this helper exists to undo.
function Split-AgentsCliResult {
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

function Invoke-AgentsMain {
    param([string[]]$Arguments = @())
    $manifest = ''; $phase = ''; $owner = ''
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '--manifest' { $manifest = $Arguments[$i + 1]; $i += 2 }
            '--phase' { $phase = $Arguments[$i + 1]; $i += 2 }
            '--owner' { $owner = $Arguments[$i + 1]; $i += 2 }
            default {
                Write-Error "unknown argument: $($Arguments[$i])"
                return 2
            }
        }
    }
    if (-not $manifest -or -not $phase) {
        Write-Error 'error: --manifest <path> and --phase <start|commit> are required'
        return 2
    }
    return run_agents -Manifest $manifest -Phase $phase -OwnerId $owner
}

# Run as CLI only when executed directly; stay quiet when dot-sourced by tests
# (mirrors agents.sh's BASH_SOURCE guard).
if ($MyInvocation.InvocationName -ne '.') {
    exit (Split-AgentsCliResult (Invoke-AgentsMain -Arguments $args))
}
