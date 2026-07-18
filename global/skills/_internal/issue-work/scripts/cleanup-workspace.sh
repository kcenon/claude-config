#!/usr/bin/env bash
# issue-work: resume reconciliation + safe cleanup (PUSHED -> ... -> CLEANED)
# ==========================================================================
# Final workspace-lifecycle stage for the issue-work skill. Runs AFTER the
# coordinator has pushed a branch, opened a PR, and the CI gate + merge have
# completed. See reference/workspace-lifecycle.md (the #840 sections) for the
# contract (resume-reconciliation rule, the cleanup safety predicate, the
# preservation predicate, the remotely-recoverable rule incl. the squash-merge
# nuance, the 3-fail preservation policy, and the manifest keys this stage
# adds).
#
# This stage advances the manifest through
# PUSHED -> PR_OPEN -> CI_PENDING -> MERGED -> CLEANUP_PENDING -> CLEANED and
# reconciles resume state by re-reading reality rather than trusting the stored
# state. It reuses the #838 manifest primitive (workspace_manifest_write /
# _read / _state, workspace_redact_credentials) by sourcing workspace.sh (which
# stays quiet when sourced).
#
# CAPABILITY BOUNDARY: unlike agents.sh (a subagent), this stage runs as the
# COORDINATOR, so it MAY invoke the GitHub CLI (through the GH_BIN seam) to read
# PR state during reconciliation. It still funnels every git and gh call
# through a wrapper so tests can inject a fake binary. The only destructive
# operation it performs is the gated removal of a run root, and that path is
# guarded by a re-validated safety predicate on every attempt.
#
# The script is both a sourceable library (unit-testable functions) and a CLI
# (`run_cleanup`). Every git call funnels through _cleanup_git and every gh call
# through _cleanup_gh so tests can inject fakes via GIT_BIN / GH_BIN.
#
# Usage:
#   bash cleanup-workspace.sh --phase reconcile --repo-dir <dir> --manifest <path> [--pr <n>]
#   bash cleanup-workspace.sh --phase cleanup --run-root <dir> --repo-dir <dir> \
#        --manifest <path> --base <tmpbase> --issue <n> [--pr <n>] [--merge-commit <sha>]

set -uo pipefail

# Reuse the #838 manifest primitive (workspace_manifest_write/_read/_state,
# workspace_redact_credentials, _WORKSPACE_MARKER_FILE). workspace.sh is quiet
# when sourced.
_CLEANUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace.sh
. "${_CLEANUP_DIR}/workspace.sh"

# Injection seams (overridable by tests and callers).
GIT_BIN="${GIT_BIN:-git}"
GH_BIN="${GH_BIN:-gh}"

# Lease directory basename. Matches agents.sh's AGENTS_LEASE_DIRNAME so this
# stage can detect a still-held single-writer lease left behind by #839.
CLEANUP_LEASE_DIRNAME="${CLEANUP_LEASE_DIRNAME:-.iw-writer.lease}"

# Delete seam. When empty, removal uses the internal guarded `rm -rf`. Tests set
# it to a failing remover so the retry / 3-fail preservation policy is testable
# without needing a real un-removable directory.
CLEANUP_RM="${CLEANUP_RM:-}"

# Seconds to sleep between removal retries. A seam so tests can drive the retry
# loop instantly; real runs get a brief pause (the Windows file-lock analog).
CLEANUP_RETRY_SLEEP="${CLEANUP_RETRY_SLEEP:-1}"

# Set by primitives on failure; consumed by callers to build a redacted reason
# without re-touching git's/gh's raw output.
CLEANUP_LAST_ERROR=""

# Lifecycle states this stage owns (strictly ordered).
_CLEANUP_STATE_PUSHED="PUSHED"
_CLEANUP_STATE_PR_OPEN="PR_OPEN"
_CLEANUP_STATE_CI_PENDING="CI_PENDING"
_CLEANUP_STATE_MERGED="MERGED"
_CLEANUP_STATE_CLEANUP_PENDING="CLEANUP_PENDING"
_CLEANUP_STATE_CLEANED="CLEANED"

# ── Low-level command wrappers ────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via GIT_BIN.
_cleanup_git() {
    "$GIT_BIN" "$@"
}

# All gh access funnels through here so a fake gh can shadow it via GH_BIN.
_cleanup_gh() {
    "$GH_BIN" "$@"
}

# ── Path normalization ────────────────────────────────────────────────

# Pure (filesystem-free) normalization of an already-absolute path: collapses
# "." and empty segments and resolves ".." lexically. Never touches disk, so it
# is safe for a path that does not (yet) exist. Mirrors agents.sh's normalizer.
_cleanup_normalize_pure() {
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

# Resolve <path> to an absolute, canonical path. For an existing directory this
# uses cd+pwd -P (which also resolves symlinks, so the macOS /var -> /private/var
# symlink cannot cause a false path-prefix mismatch); for a non-existent path it
# makes the path absolute against $PWD and normalizes it lexically.
_cleanup_realpath() {
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
    _cleanup_normalize_pure "$path"
}

# ── Cleanup safety predicate ──────────────────────────────────────────

# cleanup_validate_path <candidate> <run_base> <expected_issue>
#
# The single gate that decides whether a candidate path may ever be handed to a
# remover. It refuses (non-zero + CLEANUP_LAST_ERROR) unless the candidate is
# unambiguously an issue-work run root created by #838 for the expected issue.
# Fail-safe: any doubt refuses. Refusal conditions:
#   * empty candidate/base/issue;
#   * the RAW candidate contains ".." (traversal attempt), checked before any
#     canonicalization so a resolved path can never launder a traversal;
#   * the candidate's final component is itself a symlink (swap attack);
#   * basename does not match iw-<expected_issue>-*;
#   * candidate canonicalizes to "/" (root) or to $HOME (home);
#   * candidate is not STRICTLY under the canonicalized run_base (must be
#     <canonical_base>/<something>, never the base itself);
#   * marker <candidate>/.iw-run-marker missing, or lacks a line
#     `issue=<expected_issue>`.
# Both candidate and run_base are canonicalized so the /var -> /private/var
# symlink does NOT cause a false mismatch.
cleanup_validate_path() {
    local candidate="${1:-}" run_base="${2:-}" issue="${3:-}"
    CLEANUP_LAST_ERROR=""

    if [ -z "$candidate" ] || [ -z "$run_base" ] || [ -z "$issue" ]; then
        CLEANUP_LAST_ERROR="empty candidate/base/issue"
        return 1
    fi

    # Traversal attempt in the RAW candidate, before any canonicalization.
    case "$candidate" in
        *..*)
            CLEANUP_LAST_ERROR="path traversal ('..') refused"
            return 1
            ;;
    esac

    # The final component must not itself be a symlink (swap attack). Checked on
    # the raw candidate before canonicalization would resolve it away.
    if [ -L "$candidate" ]; then
        CLEANUP_LAST_ERROR="candidate final component is a symlink"
        return 1
    fi

    # Basename must be an issue-work run root for the expected issue.
    local base_name
    base_name="$(basename -- "$candidate")"
    case "$base_name" in
        iw-"${issue}"-*) : ;;
        *)
            CLEANUP_LAST_ERROR="basename does not match iw-${issue}-*"
            return 1
            ;;
    esac

    # Canonicalize BOTH so a /var -> /private/var symlink cannot desync them.
    local canon_candidate canon_base
    canon_candidate="$(_cleanup_realpath "$candidate")" || {
        CLEANUP_LAST_ERROR="cannot canonicalize candidate"
        return 1
    }
    canon_base="$(_cleanup_realpath "$run_base")" || {
        CLEANUP_LAST_ERROR="cannot canonicalize run base"
        return 1
    }

    # Never the filesystem root.
    if [ "$canon_candidate" = "/" ]; then
        CLEANUP_LAST_ERROR="refusing to remove the filesystem root"
        return 1
    fi

    # Never the home directory.
    if [ -n "${HOME:-}" ]; then
        local canon_home
        canon_home="$(_cleanup_realpath "$HOME")" || canon_home="$HOME"
        if [ "$canon_candidate" = "$canon_home" ]; then
            CLEANUP_LAST_ERROR="refusing to remove the home directory"
            return 1
        fi
    fi

    # Must be STRICTLY under the base: <canonical_base>/<something>, never equal.
    case "$canon_candidate" in
        "$canon_base"/?*) : ;;
        *)
            CLEANUP_LAST_ERROR="candidate is not strictly under the run base"
            return 1
            ;;
    esac
    if [ "$canon_candidate" = "$canon_base" ]; then
        CLEANUP_LAST_ERROR="candidate equals the run base"
        return 1
    fi

    # Marker must be present and name the expected issue.
    local marker="${candidate%/}/${_WORKSPACE_MARKER_FILE}"
    if [ ! -f "$marker" ]; then
        CLEANUP_LAST_ERROR="run marker ${_WORKSPACE_MARKER_FILE} missing"
        return 1
    fi
    if ! grep -q "^issue=${issue}$" "$marker" 2>/dev/null; then
        CLEANUP_LAST_ERROR="run marker does not name issue ${issue}"
        return 1
    fi

    return 0
}

# ── Preservation predicates ───────────────────────────────────────────

# cleanup_git_state_clean <repo_dir>
# Succeeds only when the working tree is completely clean: no tracked
# modifications and no untracked files (`status --porcelain` empty) AND no
# unmerged / conflict entries (`ls-files -u` empty). This covers both
# uncommitted work and unresolved merge conflicts.
cleanup_git_state_clean() {
    local repo_dir="${1:-}" porcelain unmerged
    CLEANUP_LAST_ERROR=""
    [ -n "$repo_dir" ] || { CLEANUP_LAST_ERROR="empty repo dir"; return 1; }
    [ -d "$repo_dir" ] || { CLEANUP_LAST_ERROR="repo dir does not exist"; return 1; }

    porcelain="$(_cleanup_git -C "$repo_dir" status --porcelain 2>/dev/null)"
    if [ -n "$porcelain" ]; then
        CLEANUP_LAST_ERROR="working tree not clean (uncommitted or untracked changes)"
        return 1
    fi
    unmerged="$(_cleanup_git -C "$repo_dir" ls-files -u 2>/dev/null)"
    if [ -n "$unmerged" ]; then
        CLEANUP_LAST_ERROR="unresolved merge conflicts present"
        return 1
    fi
    return 0
}

# cleanup_remotely_recoverable <repo_dir> [<merge_commit>]
# Succeeds when the local HEAD is recoverable from a remote (so removing the
# checkout loses no work). It holds if ANY of:
#   (a) HEAD is contained in some remote-tracking ref;
#   (b) HEAD has an upstream and is not ahead of it (rev-list @{u}..HEAD == 0);
#   (c) <merge_commit> is given and is an ancestor of origin/develop -- the
#       squash-merge nuance: after a squash merge the local commits are NOT
#       ancestors of the merge commit, so the only way to prove the work landed
#       is that the merge commit itself is reachable from origin/develop.
# Fail-safe: if none hold, refuse (preserve) rather than risk losing unpushed
# work.
cleanup_remotely_recoverable() {
    local repo_dir="${1:-}" merge_commit="${2:-}"
    CLEANUP_LAST_ERROR=""
    [ -n "$repo_dir" ] || { CLEANUP_LAST_ERROR="empty repo dir"; return 1; }

    # (a) HEAD is contained in some remote-tracking ref.
    local remote_contains
    remote_contains="$(_cleanup_git -C "$repo_dir" branch -r --contains HEAD 2>/dev/null)"
    if [ -n "$remote_contains" ]; then
        return 0
    fi

    # (b) HEAD has an upstream and is not ahead of it.
    if _cleanup_git -C "$repo_dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        local ahead
        ahead="$(_cleanup_git -C "$repo_dir" rev-list --count '@{u}..HEAD' 2>/dev/null)"
        if [ "${ahead:-1}" = "0" ]; then
            return 0
        fi
    fi

    # (c) squash-merge: the merge commit landed on origin/develop.
    if [ -n "$merge_commit" ]; then
        if _cleanup_git -C "$repo_dir" merge-base --is-ancestor "$merge_commit" origin/develop 2>/dev/null; then
            return 0
        fi
    fi

    CLEANUP_LAST_ERROR="local HEAD is not recoverable from any remote (unpushed work)"
    return 1
}

# cleanup_agents_terminated <run_root>
# Succeeds only when NO single-writer lease directory survives anywhere under
# <run_root>. A surviving lease means a #839 writer is still (or was left)
# active, so cleanup must be deferred.
cleanup_agents_terminated() {
    local run_root="${1:-}" found
    CLEANUP_LAST_ERROR=""
    [ -n "$run_root" ] || { CLEANUP_LAST_ERROR="empty run root"; return 1; }

    found="$(find "$run_root" -type d -name "$CLEANUP_LEASE_DIRNAME" 2>/dev/null | head -n1)"
    if [ -n "$found" ]; then
        CLEANUP_LAST_ERROR="a writer lease is still held (agent not terminated)"
        return 1
    fi
    return 0
}

# ── Manifest state transitions ────────────────────────────────────────

# Advance the manifest state from <from> to <to>, refusing if the current state
# is not exactly <from>. Keeps this stage's lifecycle strictly ordered rather
# than allowing an out-of-order jump. Mirrors agents.sh's _agents_transition.
_cleanup_transition() {
    local manifest="${1:-}" from="${2:-}" to="${3:-}" current
    [ -n "$manifest" ] && [ -n "$from" ] && [ -n "$to" ] || return 2
    current="$(workspace_manifest_state "$manifest")"
    if [ "$current" != "$from" ]; then
        CLEANUP_LAST_ERROR="expected state ${from} but manifest is ${current:-<empty>}"
        return 1
    fi
    workspace_manifest_write "$manifest" state "$to"
}

# Thin advancing helpers along PUSHED -> ... -> CLEANED. Each refuses unless the
# manifest is currently at the exact predecessor state.
cleanup_mark_pr_open()         { _cleanup_transition "${1:-}" "$_CLEANUP_STATE_PUSHED"          "$_CLEANUP_STATE_PR_OPEN"; }
cleanup_mark_ci_pending()      { _cleanup_transition "${1:-}" "$_CLEANUP_STATE_PR_OPEN"         "$_CLEANUP_STATE_CI_PENDING"; }
cleanup_mark_merged()          { _cleanup_transition "${1:-}" "$_CLEANUP_STATE_CI_PENDING"      "$_CLEANUP_STATE_MERGED"; }
cleanup_mark_cleanup_pending() { _cleanup_transition "${1:-}" "$_CLEANUP_STATE_MERGED"          "$_CLEANUP_STATE_CLEANUP_PENDING"; }
cleanup_mark_cleaned()         { _cleanup_transition "${1:-}" "$_CLEANUP_STATE_CLEANUP_PENDING" "$_CLEANUP_STATE_CLEANED"; }

# ── Emit outcome JSON (redacted) ──────────────────────────────────────

_cleanup_emit_reconciled() {
    local manifest="$1" branch="$2" head="$3" state="$4" pr_state="$5"
    branch="$(workspace_redact_credentials "$branch")"
    head="$(workspace_redact_credentials "$head")"
    state="$(workspace_redact_credentials "$state")"
    pr_state="$(workspace_redact_credentials "$pr_state")"
    manifest="$(workspace_redact_credentials "$manifest")"
    printf '{"phase":"reconcile","state":"%s","branch":"%s","head":"%s","pr_state":"%s","manifest":"%s"}\n' \
        "$state" "$branch" "$head" "$pr_state" "$manifest"
}

_cleanup_emit_cleaned() {
    local run_root="$1" manifest="${2:-}"
    run_root="$(workspace_redact_credentials "$run_root")"
    manifest="$(workspace_redact_credentials "$manifest")"
    printf '{"state":"CLEANED","run_root":"%s","manifest":"%s"}\n' "$run_root" "$manifest"
}

_cleanup_emit_preserve() {
    local reason run_root
    reason="$(workspace_redact_credentials "${1:-}")"
    run_root="$(workspace_redact_credentials "${2:-}")"
    printf '{"state":"PRESERVED","reason":"%s","run_root":"%s"}\n' "$reason" "$run_root"
}

_cleanup_emit_error() {
    local reason
    reason="$(workspace_redact_credentials "${1:-}")"
    printf '{"state":"ERROR","reason":"%s"}\n' "$reason"
}

# ── Resume reconciliation ─────────────────────────────────────────────

# cleanup_reconcile <repo_dir> <manifest> [<pr_number>]
# Re-reads LIVE state and repairs the manifest, never trusting the stored state
# alone. Reads the current branch, HEAD sha, whether the remote branch exists,
# and (if a PR number is given) the PR state and merge commit via gh. Then
# writes branch/head/merge_commit and a `state` derived from reality:
#   * PR MERGED         -> MERGED (unless already CLEANUP_PENDING/CLEANED);
#   * else remote branch exists -> PR_OPEN if a non-merged PR exists, else
#     keep an in-flight CI_PENDING/PR_OPEN, otherwise PUSHED;
#   * else               -> leave the stored state untouched.
# Emits a single redacted JSON summary line. Reality wins over the stored state.
cleanup_reconcile() {
    local repo_dir="${1:-}" manifest="${2:-}" pr_number="${3:-}"
    CLEANUP_LAST_ERROR=""
    if [ -z "$repo_dir" ] || [ -z "$manifest" ]; then
        _cleanup_emit_error "missing required repo-dir/manifest"
        return 2
    fi

    local branch head remote_ref stored_state pr_state="" pr_merge="" new_state=""
    branch="$(_cleanup_git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    head="$(_cleanup_git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
    remote_ref=""
    if [ -n "$branch" ]; then
        remote_ref="$(_cleanup_git -C "$repo_dir" ls-remote --heads origin "$branch" 2>/dev/null)"
    fi
    stored_state="$(workspace_manifest_state "$manifest")"

    if [ -n "$pr_number" ]; then
        pr_state="$(_cleanup_gh pr view "$pr_number" --json state,mergedAt,mergeCommit,headRefName --jq '.state' 2>/dev/null)" || pr_state=""
        pr_merge="$(_cleanup_gh pr view "$pr_number" --json state,mergedAt,mergeCommit,headRefName --jq '.mergeCommit.oid' 2>/dev/null)" || pr_merge=""
    fi

    # Derive the reconciled state from reality, never from the stored state alone.
    if [ "$pr_state" = "MERGED" ]; then
        case "$stored_state" in
            "$_CLEANUP_STATE_CLEANUP_PENDING"|"$_CLEANUP_STATE_CLEANED") new_state="$stored_state" ;;
            *) new_state="$_CLEANUP_STATE_MERGED" ;;
        esac
    elif [ -n "$remote_ref" ]; then
        if [ -n "$pr_state" ]; then
            # A live, non-merged PR exists for the branch.
            case "$stored_state" in
                "$_CLEANUP_STATE_CI_PENDING") new_state="$stored_state" ;;
                *) new_state="$_CLEANUP_STATE_PR_OPEN" ;;
            esac
        else
            case "$stored_state" in
                "$_CLEANUP_STATE_PR_OPEN"|"$_CLEANUP_STATE_CI_PENDING") new_state="$stored_state" ;;
                *) new_state="$_CLEANUP_STATE_PUSHED" ;;
            esac
        fi
    else
        new_state="$stored_state"
    fi

    [ -n "$branch" ]   && workspace_manifest_write "$manifest" branch "$branch"
    [ -n "$head" ]     && workspace_manifest_write "$manifest" head "$head"
    [ -n "$pr_merge" ] && workspace_manifest_write "$manifest" merge_commit "$pr_merge"
    [ -n "$new_state" ] && workspace_manifest_write "$manifest" state "$new_state"

    _cleanup_emit_reconciled "$manifest" "$branch" "$head" "${new_state:-$stored_state}" "$pr_state"
    return 0
}

# ── Gated removal ─────────────────────────────────────────────────────

# Remove the target via the CLEANUP_RM seam when set, else the internal guarded
# `rm -rf`. NEVER called on anything but a freshly re-validated run root.
_cleanup_remove() {
    local target="${1:-}"
    [ -n "$target" ] || return 1
    if [ -n "$CLEANUP_RM" ]; then
        "$CLEANUP_RM" "$target"
        return $?
    fi
    rm -rf -- "$target"
}

# Print, to stderr, a manual cleanup procedure naming the exact validated path.
# Used when automated removal has failed the 3-fail cap and the workspace is
# preserved for a human to remove by hand.
_cleanup_print_manual_procedure() {
    local run_root="${1:-}"
    {
        echo "MANUAL CLEANUP REQUIRED"
        echo "  Automated removal failed 3 times (3-fail rule); the workspace is preserved."
        echo "  Verify no process holds a file under the path below, then remove it by hand:"
        echo "    rm -rf -- '${run_root}'"
    } >&2
}

# The gated delete: re-validate immediately before each removal (TOCTOU guard),
# retry at most 3 times on failure, and on 3 identical failures preserve and
# print the manual procedure (3-fail rule). On success emit CLEANED.
_cleanup_gated_delete() {
    local run_root="${1:-}" run_base="${2:-}" issue="${3:-}" manifest="${4:-}"
    local attempt=1 max=3 rc

    while [ "$attempt" -le "$max" ]; do
        # TOCTOU guard: re-validate the exact path immediately before removal so
        # a swap between the gate check and the delete cannot redirect it.
        if ! cleanup_validate_path "$run_root" "$run_base" "$issue"; then
            _cleanup_emit_preserve "revalidation failed before removal: ${CLEANUP_LAST_ERROR}" "$run_root"
            return 1
        fi

        _cleanup_remove "$run_root"
        rc=$?
        if [ "$rc" -eq 0 ] && [ ! -e "$run_root" ]; then
            # If a manifest override lives OUTSIDE the (now-removed) run root,
            # persist the terminal state. When the manifest lived inside the run
            # root it is gone and the emitted JSON below is the only record.
            if [ -f "$manifest" ]; then
                _cleanup_transition "$manifest" "$_CLEANUP_STATE_CLEANUP_PENDING" "$_CLEANUP_STATE_CLEANED" >/dev/null 2>&1 || true
            fi
            _cleanup_emit_cleaned "$run_root" "$manifest"
            return 0
        fi

        attempt=$((attempt + 1))
        [ "$attempt" -le "$max" ] && sleep "$CLEANUP_RETRY_SLEEP"
    done

    # 3-fail rule: stop retrying, preserve, and print the manual procedure.
    _cleanup_print_manual_procedure "$run_root"
    _cleanup_emit_preserve "removal failed after ${max} attempts; workspace preserved" "$run_root"
    return 1
}

# ── Gated cleanup driver ──────────────────────────────────────────────

# cleanup_workspace <run_root> <repo_dir> <manifest> <run_base> <expected_issue>
#                   [<merge_commit>] [<pr_number>]
# The gated delete. ALL gates must hold, else PRESERVE (report reason, no delete,
# non-zero):
#   1. manifest state is MERGED or CLEANUP_PENDING (PR merged + CI gate passed;
#      the coordinator only advances to MERGED after the merge, so an incomplete
#      / unmerged PR falls out of this gate);
#   2. cleanup_validate_path passes;
#   3. cleanup_git_state_clean passes (uncommitted work + unresolved conflicts);
#   4. cleanup_remotely_recoverable passes (unpushed commits);
#   5. cleanup_agents_terminated passes (live agents).
# If the gate passes: advance to CLEANUP_PENDING, then perform the gated delete.
cleanup_workspace() {
    local run_root="${1:-}" repo_dir="${2:-}" manifest="${3:-}" run_base="${4:-}" issue="${5:-}" merge_commit="${6:-}" pr_number="${7:-}"
    CLEANUP_LAST_ERROR=""

    if [ -z "$run_root" ] || [ -z "$repo_dir" ] || [ -z "$manifest" ] || [ -z "$run_base" ] || [ -z "$issue" ]; then
        _cleanup_emit_preserve "missing required run-root/repo-dir/manifest/base/issue" "$run_root"
        return 2
    fi
    # pr_number is accepted for signature parity with reconcile / the CLI but is
    # not consulted here: the MERGED gate is the coordinator's authority that the
    # PR merged. Reference it as a no-op so it is not an unused parameter.
    : "${pr_number:-}"

    # Gate 1: manifest state must be MERGED or CLEANUP_PENDING.
    local state
    state="$(workspace_manifest_state "$manifest")"
    case "$state" in
        "$_CLEANUP_STATE_MERGED"|"$_CLEANUP_STATE_CLEANUP_PENDING") : ;;
        *)
            _cleanup_emit_preserve "state is ${state:-<empty>}; refusing cleanup before MERGED (PR incomplete or not merged)" "$run_root"
            return 1
            ;;
    esac

    # Gate 2: path safety.
    if ! cleanup_validate_path "$run_root" "$run_base" "$issue"; then
        _cleanup_emit_preserve "path safety: ${CLEANUP_LAST_ERROR}" "$run_root"
        return 1
    fi

    # Gate 3: git state clean (uncommitted work + unresolved conflicts).
    if ! cleanup_git_state_clean "$repo_dir"; then
        _cleanup_emit_preserve "git state: ${CLEANUP_LAST_ERROR}" "$run_root"
        return 1
    fi

    # Gate 4: work recoverable from a remote (no unpushed commits).
    if ! cleanup_remotely_recoverable "$repo_dir" "$merge_commit"; then
        _cleanup_emit_preserve "recoverability: ${CLEANUP_LAST_ERROR}" "$run_root"
        return 1
    fi

    # Gate 5: all agents terminated (no held lease).
    if ! cleanup_agents_terminated "$run_root"; then
        _cleanup_emit_preserve "agents: ${CLEANUP_LAST_ERROR}" "$run_root"
        return 1
    fi

    # Advance to CLEANUP_PENDING (skip if already there, e.g. a resumed run).
    if [ "$state" = "$_CLEANUP_STATE_MERGED" ]; then
        if ! _cleanup_transition "$manifest" "$_CLEANUP_STATE_MERGED" "$_CLEANUP_STATE_CLEANUP_PENDING"; then
            _cleanup_emit_preserve "cannot advance to CLEANUP_PENDING: ${CLEANUP_LAST_ERROR}" "$run_root"
            return 1
        fi
    fi

    _cleanup_gated_delete "$run_root" "$run_base" "$issue" "$manifest"
}

# ── Driver ────────────────────────────────────────────────────────────
# run_cleanup <phase> <run_root> <repo_dir> <manifest> <base> <issue>
#             [<merge_commit>] [<pr_number>]
#
# phase=reconcile  re-read reality and repair the manifest (no delete).
# phase=cleanup    gated removal of the run root.
run_cleanup() {
    local phase="${1:-}" run_root="${2:-}" repo_dir="${3:-}" manifest="${4:-}" base="${5:-}" issue="${6:-}" merge_commit="${7:-}" pr="${8:-}"
    case "$phase" in
        reconcile)
            cleanup_reconcile "$repo_dir" "$manifest" "$pr"
            ;;
        cleanup)
            cleanup_workspace "$run_root" "$repo_dir" "$manifest" "$base" "$issue" "$merge_commit" "$pr"
            ;;
        *)
            _cleanup_emit_error "unknown phase: ${phase:-<empty>}"
            return 2
            ;;
    esac
}

# ── CLI entry ─────────────────────────────────────────────────────────
_cleanup_main() {
    local run_root="" repo_dir="" manifest="" base="" issue="" phase="" pr="" merge_commit=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --run-root) run_root="$2"; shift 2 ;;
            --repo-dir) repo_dir="$2"; shift 2 ;;
            --manifest) manifest="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --phase) phase="$2"; shift 2 ;;
            --pr) pr="$2"; shift 2 ;;
            --merge-commit) merge_commit="$2"; shift 2 ;;
            *) echo "unknown argument: $1" >&2; return 2 ;;
        esac
    done
    if [ -z "$phase" ]; then
        echo "error: --phase <reconcile|cleanup> is required" >&2
        return 2
    fi
    run_cleanup "$phase" "$run_root" "$repo_dir" "$manifest" "$base" "$issue" "$merge_commit" "$pr"
}

# Run as CLI only when executed directly; stay quiet when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _cleanup_main "$@"
fi
