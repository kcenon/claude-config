#!/usr/bin/env bash
# issue-work: pre-PR readiness gate (git-state half)
# ==================================================
# Deterministic git-state gate for the issue-work skill. Runs AFTER the
# implementation and documentation have been committed to the feature branch
# and BEFORE the branch is pushed or a PR is opened. See
# reference/pre-pr-readiness.md for the full contract (outcome table, the
# develop-refresh rules, the conflict rule, the base-movement retry rule, and
# the agent-side documentation-to-issue gap-audit procedure this script does
# not itself perform).
#
# This script owns only the mechanical, non-judgemental half of the gate:
#   1. Refuse to run against a dirty worktree (commit impl+docs first).
#   2. Fetch the remote base and fast-forward the LOCAL base branch only when it
#      is strictly behind the remote. If the local base is AHEAD or DIVERGED it
#      is left untouched and the gate blocks -- it never rewinds a base branch.
#   3. Integrate the refreshed base into the feature branch (rebase by default,
#      merge for shared branches). On ANY integration conflict it aborts the
#      rebase/merge -- leaving the feature branch exactly as it was -- and
#      blocks, because a script cannot judge whether a conflict is semantically
#      unambiguous. The agent-side procedure in the reference doc owns that call.
#   4. Re-fetch after a clean integration; if the remote base moved, re-integrate
#      against the new base, capped at --max-base-moves re-integrations.
#
# It emits a single JSON object on stdout and never touches the network beyond
# the injected git (GIT_BIN), so tests drive it against a local bare remote.
#
# The script is both a sourceable library (unit-testable functions such as
# classify_base_relationship) and a CLI (run_pre_pr_gate). Every git call goes
# through _prepr_git so a fake git can shadow it via GIT_BIN; the git operations
# target ${PREPR_REPO_DIR:-.} so the CLI runs against the current working
# directory (the feature-branch checkout) while a sourced unit test can point a
# single function at a throwaway repository.
#
# Usage:
#   bash pre-pr-gate.sh --repo <owner/name> --base <develop> --branch <feature>
#                       [--remote origin] [--max-base-moves 3]
#                       [--integrate rebase|merge]

set -uo pipefail

# Injection seams (overridable by tests and callers).
GIT_BIN="${GIT_BIN:-git}"

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it. Operations
# run inside ${PREPR_REPO_DIR:-.}; the default targets the current working
# directory (the feature-branch checkout in the real workflow), and a sourced
# unit test may set PREPR_REPO_DIR to aim a single helper at a temp repo.
_prepr_git() {
    "$GIT_BIN" -C "${PREPR_REPO_DIR:-.}" "$@"
}

# ── Base-movement test seam ──────────────────────────────────────────
# Command string run after every fetch, mirroring workspace.sh's env-var seam
# style. It exists so a test can push a new commit to the bare remote between
# fetches and deterministically simulate the base moving under the gate. It is
# a no-op when unset and its failures are swallowed so a flaky hook never masks
# a real gate result.
_prepr_run_hook() {
    [ -n "${PRE_PR_ON_FETCH:-}" ] || return 0
    ( eval "$PRE_PR_ON_FETCH" ) >/dev/null 2>&1 || true
}

# ── Pure helper (unit-testable via GIT_BIN ancestry) ─────────────────
# Classify how a local base sha relates to a remote base sha using commit
# ancestry, funneled through _prepr_git so it is fakeable / testable against a
# real throwaway repo. Prints exactly one of:
#   equal     the two shas are identical (no refresh needed)
#   behind    local is an ancestor of remote (safe fast-forward)
#   ahead     remote is an ancestor of local (local has unshared commits)
#   diverged  neither is an ancestor of the other (histories forked)
# Returns 1 (printing "unknown") only when an argument is empty.
classify_base_relationship() {
    local local_sha="${1:-}" remote_sha="${2:-}"
    if [ -z "$local_sha" ] || [ -z "$remote_sha" ]; then
        printf 'unknown\n'
        return 1
    fi
    if [ "$local_sha" = "$remote_sha" ]; then
        printf 'equal\n'
        return 0
    fi
    if _prepr_git merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
        printf 'behind\n'
        return 0
    fi
    if _prepr_git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
        printf 'ahead\n'
        return 0
    fi
    printf 'diverged\n'
    return 0
}

# ── Integration primitives ───────────────────────────────────────────
# Integrate the (already refreshed) base branch into the currently checked-out
# feature branch. Rebase is the private-branch default; merge is the shared-
# branch escape hatch. Returns the underlying git exit code so the driver can
# distinguish a clean integration from a conflict.
_prepr_integrate() {
    local mode="$1" base="$2"
    case "$mode" in
        rebase) _prepr_git rebase "$base" ;;
        merge)  _prepr_git merge --no-edit "$base" ;;
        *)      return 2 ;;
    esac
}

# Abort an in-progress integration, restoring the feature branch to exactly the
# state it had before the integration attempt. Best-effort: its own exit code is
# ignored because the driver has already decided to block.
_prepr_abort() {
    local mode="$1"
    case "$mode" in
        rebase) _prepr_git rebase --abort >/dev/null 2>&1 || true ;;
        merge)  _prepr_git merge --abort  >/dev/null 2>&1 || true ;;
    esac
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
# Single stdout line. attempts is numeric (unquoted); every other field is a
# string. Keys are stable so a test can parse them with jfield.
_prepr_emit() {
    local outcome="$1" reason="$2" base="$3" remote_sha="$4" before="$5" after="$6" attempts="$7"
    printf '{"outcome":"%s","reason":"%s","base":"%s","remote_base_sha":"%s","local_base_sha_before":"%s","local_base_sha_after":"%s","attempts":%s}\n' \
        "$outcome" "$reason" "$base" "$remote_sha" "$before" "$after" "$attempts"
}

# ── Driver ───────────────────────────────────────────────────────────
# run_pre_pr_gate <repo> <base> <branch> [<remote>] [<max_base_moves>] [<integrate>]
#
# repo             expected "owner/name" identity (reported, not re-verified here
#                  -- the workspace stage already verified origin identity).
# base             the base branch to refresh and integrate from (e.g. develop).
# branch           the feature branch to integrate the base into.
# remote           remote to fetch the base from (default origin).
# max_base_moves   cap on re-integrations when the remote base keeps moving
#                  (default 3).
# integrate        rebase (default, private branch) or merge (shared branch).
run_pre_pr_gate() {
    local repo="${1:-}" base="${2:-}" branch="${3:-}"
    local remote="${4:-origin}" max_moves="${5:-3}" mode="${6:-rebase}"

    if [ -z "$repo" ] || [ -z "$base" ] || [ -z "$branch" ]; then
        _prepr_emit blocked missing_args "$base" "" "" "" 0
        return 2
    fi
    case "$mode" in
        rebase|merge) : ;;
        *)
            _prepr_emit blocked bad_integrate_mode "$base" "" "" "" 0
            return 2
            ;;
    esac

    # Best-effort snapshot of the local base before any refresh, so a blocked
    # outcome can prove the base was not rewound.
    local local_before
    local_before="$(_prepr_git rev-parse "$base" 2>/dev/null)"

    # 1. Clean-worktree precondition. Tracked staged/unstaged changes block the
    #    gate; untracked files (-uno) do not, since they never impede a rebase.
    local dirty
    dirty="$(_prepr_git status --porcelain --untracked-files=no 2>/dev/null)"
    if [ -n "$dirty" ]; then
        _prepr_emit blocked dirty_worktree "$base" "" "$local_before" "$local_before" 0
        return 1
    fi

    # Ensure we operate from the feature branch (defensive: the real workflow is
    # already on it). Everything after this integrates the base into HEAD.
    if ! _prepr_git checkout "$branch" >/dev/null 2>&1; then
        _prepr_emit blocked checkout_failed "$base" "" "$local_before" "$local_before" 0
        return 1
    fi

    # Initial fetch of the remote base.
    if ! _prepr_git fetch "$remote" "$base" >/dev/null 2>&1; then
        _prepr_emit blocked fetch_failed "$base" "" "$local_before" "$local_before" 0
        return 1
    fi
    local rb
    rb="$(_prepr_git rev-parse FETCH_HEAD 2>/dev/null)"
    _prepr_run_hook

    local attempts=0
    while : ; do
        attempts=$((attempts + 1))

        # Refresh the LOCAL base branch against the freshly fetched remote sha.
        local lb rel
        lb="$(_prepr_git rev-parse "$base" 2>/dev/null)"
        rel="$(classify_base_relationship "$lb" "$rb")"
        case "$rel" in
            equal)
                : # local base already current; nothing to fast-forward.
                ;;
            behind)
                # Strictly behind -> a true fast-forward. Move the ref without a
                # checkout (we stay on the feature branch).
                _prepr_git update-ref "refs/heads/${base}" "$rb" >/dev/null 2>&1
                ;;
            ahead)
                # Local base has commits the remote lacks; never rewind it.
                _prepr_emit blocked base_ahead "$base" "$rb" "$local_before" "$lb" "$attempts"
                return 1
                ;;
            diverged|*)
                _prepr_emit blocked base_diverged "$base" "$rb" "$local_before" "$lb" "$attempts"
                return 1
                ;;
        esac

        # Integrate the refreshed base into the feature branch.
        _prepr_git checkout "$branch" >/dev/null 2>&1
        if ! _prepr_integrate "$mode" "$base" >/dev/null 2>&1; then
            # A script cannot judge conflict ambiguity: abort and block.
            _prepr_abort "$mode"
            local after_conf
            after_conf="$(_prepr_git rev-parse "$base" 2>/dev/null)"
            _prepr_emit blocked conflict "$base" "$rb" "$local_before" "$after_conf" "$attempts"
            return 1
        fi

        # Re-fetch to detect the remote base moving under us during the audit.
        if ! _prepr_git fetch "$remote" "$base" >/dev/null 2>&1; then
            local after_ff
            after_ff="$(_prepr_git rev-parse "$base" 2>/dev/null)"
            _prepr_emit blocked fetch_failed "$base" "$rb" "$local_before" "$after_ff" "$attempts"
            return 1
        fi
        local rb_new
        rb_new="$(_prepr_git rev-parse FETCH_HEAD 2>/dev/null)"
        _prepr_run_hook

        if [ "$rb_new" = "$rb" ]; then
            break # base stable across two consecutive fetches -> ready.
        fi
        rb="$rb_new"
        if [ "$attempts" -ge "$max_moves" ]; then
            local after_unstable
            after_unstable="$(_prepr_git rev-parse "$base" 2>/dev/null)"
            _prepr_emit blocked base_unstable "$base" "$rb" "$local_before" "$after_unstable" "$attempts"
            return 1
        fi
    done

    local local_after
    local_after="$(_prepr_git rev-parse "$base" 2>/dev/null)"
    _prepr_emit ready ready "$base" "$rb" "$local_before" "$local_after" "$attempts"
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────
_prepr_main() {
    local repo="" base="" branch="" remote="origin" max_moves="3" mode="rebase"
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --branch) branch="$2"; shift 2 ;;
            --remote) remote="$2"; shift 2 ;;
            --max-base-moves) max_moves="$2"; shift 2 ;;
            --integrate) mode="$2"; shift 2 ;;
            *) echo "unknown argument: $1" >&2; return 2 ;;
        esac
    done
    if [ -z "$repo" ] || [ -z "$base" ] || [ -z "$branch" ]; then
        echo "error: --repo <owner/name>, --base <branch>, and --branch <feature> are required" >&2
        return 2
    fi
    run_pre_pr_gate "$repo" "$base" "$branch" "$remote" "$max_moves" "$mode"
}

# Run as CLI only when executed directly; stay quiet when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _prepr_main "$@"
fi
