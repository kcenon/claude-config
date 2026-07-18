#!/usr/bin/env bash
# issue-work: subagent spawn contract + single-writer lease (READY -> AGENTS_RUNNING -> COMMITTED)
# ================================================================================================
# Subagent-orchestration stage for the issue-work skill. Runs AFTER workspace.sh
# reaches READY and BEFORE the coordinator commits. See
# reference/workspace-lifecycle.md for the contract (spawn-prompt fields, the
# coordinator-vs-agent capability split, the mkdir-based lease protocol, the
# worktree rule, and the manifest keys this stage adds).
#
# This stage implements only the READY -> AGENTS_RUNNING -> COMMITTED manifest
# transitions plus two orchestration primitives: a spawn-prompt builder and a
# single-writer lease. It reuses the #838 manifest primitive by sourcing
# workspace.sh (which stays quiet when sourced). Cleanup and resume
# (CLEANUP_PENDING/CLEANED) remain issue #840.
#
# CAPABILITY BOUNDARY: a subagent may only read/write within its write scope.
# The coordinator owns every GitHub mutation. Accordingly this script contains
# NO GitHub CLI invocation and never pushes to a remote -- the only git verb it
# runs is `git worktree` (add/remove), used solely for the concurrent-writes
# case. The test suite greps this file to enforce that boundary.
#
# The script is both a sourceable library (unit-testable functions) and a CLI
# (`run_agents`). Every git call funnels through _agents_git so tests can inject
# a fake git via GIT_BIN, though the reference test suite prefers a real
# temporary repository over a fake.
#
# Usage:
#   bash agents.sh --manifest <path> --phase start|commit [--owner <id>]

set -uo pipefail

# Reuse the #838 manifest primitive (workspace_manifest_write/_read/_state,
# workspace_redact_credentials). workspace.sh is quiet when sourced.
_AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace.sh
. "${_AGENTS_DIR}/workspace.sh"

# Injection seams (overridable by tests and callers).
GIT_BIN="${GIT_BIN:-git}"

# Lease directory basename. A release only ever removes a path whose final
# component equals this value (see agents_release_lease), so a caller-supplied
# path can never be mistaken for an arbitrary directory to delete.
AGENTS_LEASE_DIRNAME="${AGENTS_LEASE_DIRNAME:-.iw-writer.lease}"

# Marker file recorded inside a held lease directory naming its owner.
_AGENTS_LEASE_OWNER_FILE="owner"

# Lifecycle states this stage owns.
_AGENTS_STATE_READY="READY"
_AGENTS_STATE_RUNNING="AGENTS_RUNNING"
_AGENTS_STATE_COMMITTED="COMMITTED"

# Set by primitives on failure; consumed by run_agents to build a redacted
# reason without re-touching git's raw output.
AGENTS_LAST_ERROR=""

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via GIT_BIN.
# Only `git worktree` is ever passed in -- never a network verb.
_agents_git() {
    "$GIT_BIN" "$@"
}

# ── Path normalization ────────────────────────────────────────────────

# Pure (filesystem-free) normalization of an already-absolute path: collapses
# "." and empty segments and resolves ".." lexically. Never touches disk, so it
# is safe for a path that does not (yet) exist.
_agents_normalize_pure() {
    local input="$1" seg result="" IFS=/
    for seg in $input; do
        case "$seg" in
            ''|'.') continue ;;
            '..')   result="${result%/*}" ;;
            *)      result="${result}/${seg}" ;;
        esac
    done
    printf '%s' "${result:-/}"
}

# Resolve <path> to an absolute, normalized path. For an existing directory this
# uses cd+pwd -P (which also resolves symlinks); for a non-existent path it makes
# the path absolute against $PWD and normalizes it lexically. An absolute path is
# required by the spawn contract (agents_build_prompt embeds it verbatim).
agents_normalize_path() {
    local path="${1:-}"
    [ -n "$path" ] || return 1
    if [ -d "$path" ]; then
        (cd "$path" 2>/dev/null && pwd -P) || return 1
        return 0
    fi
    case "$path" in
        /*) : ;;
        *)  path="${PWD%/}/$path" ;;
    esac
    _agents_normalize_pure "$path"
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
#
# Usage: agents_build_prompt <repo_path> <issue> <branch> <baseline> <write_scope>
agents_build_prompt() {
    local repo_path="${1:-}" issue="${2:-}" branch="${3:-}" baseline="${4:-}" write_scope="${5:-}"
    local abs
    abs="$(agents_normalize_path "$repo_path")" || abs="$repo_path"
    cat <<EOF
You are an implementation subagent for issue #${issue}.

Repository (normalized absolute path): ${abs}
Active issue: #${issue}
Target branch: ${branch}
Baseline commit: ${baseline}

Write scope -- you may create or edit ONLY these paths:
${write_scope}

Ownership and prohibitions (the coordinator owns ALL git and GitHub mutations):
- You MUST NOT push any commit or branch to the remote.
- You MUST NOT invoke the GitHub CLI or any GitHub API mutation.
- You MUST NOT open, update, or merge a pull request (PR).
- You MUST NOT clean up, delete, or otherwise tear down the workspace.
- You may only read and write files within the write scope above.
- When in doubt, stop and defer the mutation to the coordinator.
EOF
}

# ── Single-writer lease (mkdir-atomic) ────────────────────────────────

# True only when <lease_path>'s final component equals AGENTS_LEASE_DIRNAME.
# This is the guard that keeps agents_release_lease from ever removing an
# arbitrary caller-supplied path.
_agents_valid_lease_path() {
    local lease_path="${1:-}"
    [ -n "$lease_path" ] || return 1
    [ "$(basename -- "$lease_path")" = "$AGENTS_LEASE_DIRNAME" ]
}

# Atomically acquire the single-writer lease at <lease_path> for <owner_id>.
# `mkdir` (without -p) is atomic on POSIX: exactly one caller can create the
# directory, so a second concurrent writer is refused with a non-zero return.
# Fail-safe: any error (bad path, parent-create failure, lease already held)
# returns non-zero -- when in doubt, refuse rather than admit a second writer.
agents_acquire_lease() {
    local lease_path="${1:-}" owner="${2:-}"
    [ -n "$lease_path" ] && [ -n "$owner" ] || return 2
    if ! _agents_valid_lease_path "$lease_path"; then
        AGENTS_LAST_ERROR="lease path must end in ${AGENTS_LEASE_DIRNAME}"
        return 2
    fi
    mkdir -p -- "$(dirname -- "$lease_path")" 2>/dev/null || return 1
    if ! mkdir -- "$lease_path" 2>/dev/null; then
        AGENTS_LAST_ERROR="lease already held"
        return 1
    fi
    printf '%s\n' "$owner" > "${lease_path}/${_AGENTS_LEASE_OWNER_FILE}"
    return 0
}

# Print the owner recorded in a held lease (empty + non-zero if none).
agents_lease_owner() {
    local lease_path="${1:-}" line=""
    [ -n "$lease_path" ] || return 1
    [ -f "${lease_path}/${_AGENTS_LEASE_OWNER_FILE}" ] || return 1
    IFS= read -r line < "${lease_path}/${_AGENTS_LEASE_OWNER_FILE}" || true
    printf '%s' "$line"
}

# Release the lease at <lease_path>, but only if <owner_id> currently holds it.
# Refuses (non-zero) for a non-owner, a missing lease, or a path that is not a
# lease directory. Removal is guarded: it deletes the known owner marker and
# then rmdirs the now-empty directory -- never a bare `rm -rf` on the input.
agents_release_lease() {
    local lease_path="${1:-}" owner="${2:-}" stored=""
    [ -n "$lease_path" ] && [ -n "$owner" ] || return 2
    if ! _agents_valid_lease_path "$lease_path"; then
        AGENTS_LAST_ERROR="refusing to release a non-lease path"
        return 2
    fi
    if [ ! -d "$lease_path" ]; then
        AGENTS_LAST_ERROR="no lease to release"
        return 1
    fi
    stored="$(agents_lease_owner "$lease_path")" || stored=""
    if [ "$stored" != "$owner" ]; then
        AGENTS_LAST_ERROR="lease held by another writer"
        return 1
    fi
    rm -f -- "${lease_path}/${_AGENTS_LEASE_OWNER_FILE}"
    rmdir -- "$lease_path" 2>/dev/null || return 1
    return 0
}

# ── Per-agent worktrees (concurrent-writes case ONLY) ─────────────────
# The DEFAULT concurrency control is the single-writer lease above on the
# shared checkout. Worktrees are used ONLY when agents must write concurrently;
# each MUST be removed afterward (agents_worktree_remove) so no orphan is left
# to block the #840 cleanup stage.

# Add a worktree at <worktree_path> on a NEW <branch>, rooted in <repo_dir>.
agents_worktree_add() {
    local repo_dir="${1:-}" worktree_path="${2:-}" branch="${3:-}" out rc
    [ -n "$repo_dir" ] && [ -n "$worktree_path" ] && [ -n "$branch" ] || return 2
    out="$(_agents_git -C "$repo_dir" worktree add -b "$branch" "$worktree_path" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        AGENTS_LAST_ERROR="$(workspace_redact_credentials "$out" | tail -n1)"
    fi
    return "$rc"
}

# Remove the worktree at <worktree_path> so it is not left orphaned.
agents_worktree_remove() {
    local repo_dir="${1:-}" worktree_path="${2:-}" out rc
    [ -n "$repo_dir" ] && [ -n "$worktree_path" ] || return 2
    out="$(_agents_git -C "$repo_dir" worktree remove "$worktree_path" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        AGENTS_LAST_ERROR="$(workspace_redact_credentials "$out" | tail -n1)"
    fi
    return "$rc"
}

# ── Manifest state transitions ────────────────────────────────────────

# Advance the manifest state from <from> to <to>, refusing if the current state
# is not exactly <from>. This keeps the lifecycle strictly ordered
# (READY -> AGENTS_RUNNING -> COMMITTED) rather than allowing an out-of-order jump.
_agents_transition() {
    local manifest="${1:-}" from="${2:-}" to="${3:-}" current
    [ -n "$manifest" ] && [ -n "$from" ] && [ -n "$to" ] || return 2
    current="$(workspace_manifest_state "$manifest")"
    if [ "$current" != "$from" ]; then
        AGENTS_LAST_ERROR="expected state ${from} but manifest is ${current:-<empty>}"
        return 1
    fi
    workspace_manifest_write "$manifest" state "$to"
}

# READY -> AGENTS_RUNNING. Records the lease owner when one is supplied.
agents_mark_running() {
    local manifest="${1:-}" owner="${2:-}"
    _agents_transition "$manifest" "$_AGENTS_STATE_READY" "$_AGENTS_STATE_RUNNING" || return $?
    [ -n "$owner" ] && workspace_manifest_write "$manifest" lease_owner "$owner"
    return 0
}

# AGENTS_RUNNING -> COMMITTED. The coordinator calls this after committing.
agents_mark_committed() {
    local manifest="${1:-}"
    _agents_transition "$manifest" "$_AGENTS_STATE_RUNNING" "$_AGENTS_STATE_COMMITTED"
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
_agents_emit() {
    local state="$1" manifest="$2"
    printf '{"state":"%s","manifest":"%s"}\n' "$state" "$manifest"
}

_agents_emit_error() {
    local reason
    reason="$(workspace_redact_credentials "${1:-}")"
    printf '{"state":"ERROR","reason":"%s"}\n' "$reason"
}

# ── Driver ──────────────────────────────────────────────────────────
# run_agents <manifest> <phase> [<owner_id>]
#
# phase=start   READY -> AGENTS_RUNNING (records lease_owner when owner given)
# phase=commit  AGENTS_RUNNING -> COMMITTED (the post-commit transition)
run_agents() {
    local manifest="${1:-}" phase="${2:-}" owner="${3:-}"
    if [ -z "$manifest" ] || [ -z "$phase" ]; then
        _agents_emit_error "missing required manifest/phase"
        return 2
    fi
    case "$phase" in
        start)
            if ! agents_mark_running "$manifest" "$owner"; then
                _agents_emit_error "${AGENTS_LAST_ERROR:-cannot enter AGENTS_RUNNING}"
                return 1
            fi
            _agents_emit "$_AGENTS_STATE_RUNNING" "$manifest"
            ;;
        commit)
            if ! agents_mark_committed "$manifest"; then
                _agents_emit_error "${AGENTS_LAST_ERROR:-cannot enter COMMITTED}"
                return 1
            fi
            _agents_emit "$_AGENTS_STATE_COMMITTED" "$manifest"
            ;;
        *)
            _agents_emit_error "unknown phase: $phase"
            return 2
            ;;
    esac
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────
_agents_main() {
    local manifest="" phase="" owner=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --manifest) manifest="$2"; shift 2 ;;
            --phase) phase="$2"; shift 2 ;;
            --owner) owner="$2"; shift 2 ;;
            *) echo "unknown argument: $1" >&2; return 2 ;;
        esac
    done
    if [ -z "$manifest" ] || [ -z "$phase" ]; then
        echo "error: --manifest <path> and --phase <start|commit> are required" >&2
        return 2
    fi
    run_agents "$manifest" "$phase" "$owner"
}

# Run as CLI only when executed directly; stay quiet when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _agents_main "$@"
fi
