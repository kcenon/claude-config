#!/usr/bin/env bash
# issue-work: workspace lifecycle (CLAIMED -> CLONING -> READY)
# ================================================================
# Isolated-workspace stage for the issue-work skill. Runs AFTER triage.sh
# returns "proceed" and BEFORE any subagent is spawned or branch/PR is
# created. See reference/workspace-lifecycle.md for the contract (full
# lifecycle state list, run-root layout, marker format, manifest schema,
# identity-verification rule, credential-redaction rule).
#
# This stage implements only CLAIMED -> CLONING -> READY plus the manifest
# primitive. Agent spawn (AGENTS_RUNNING/COMMITTED) is issue #839; cleanup and
# resume (CLEANUP_PENDING/CLEANED) are issue #840.
#
# The script is both a sourceable library (unit-testable functions) and a CLI
# (`run_workspace`). Every git call goes through _workspace_git so tests can
# inject a fake git via GIT_BIN, though the reference test suite prefers a
# real temporary bare repository over a fake.
#
# Usage:
#   bash workspace.sh --repo <owner/name> --base <tmpbase> --issue <n>
#                      [--clone-url <url>] [--manifest <path>]

set -uo pipefail

# Injection seams (overridable by tests and callers).
GIT_BIN="${GIT_BIN:-git}"

# Marker filename dropped into the run root once claimed. Its presence (and
# the issue= line inside it) lets a resumed session confirm a given run root
# belongs to a specific issue before reusing or cleaning it up.
_WORKSPACE_MARKER_FILE=".iw-run-marker"

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it.
_workspace_git() {
    "$GIT_BIN" "$@"
}

# ── Pure helpers (unit-testable without git) ──────────────────────────

# Strip credentials from a URL/string so `https://user:token@host/...`
# becomes `https://host/...`. Handles any `<userinfo>@` segment immediately
# following a `<scheme>://`, which covers the `x-access-token:<token>@` form
# used by gh/CI credential helpers. Matches anywhere in the input (not just
# at the start), so a credential embedded mid-sentence in a git error message
# ("fatal: unable to access 'https://user:token@host/...'") is also redacted.
# Never fails on plain (non-URL) input -- it is a no-op when no scheme://
# userinfo@ pattern is present.
workspace_redact_credentials() {
    local input="${1:-}"
    printf '%s' "$input" \
        | sed -E 's#([A-Za-z][A-Za-z0-9+.-]*://)[^/@[:space:]]*@#\1#g'
}

# Compute a unique run-root path under the given temp base, using a short
# issue-scoped name: "<base>/iw-<issue>-<suffix>". The suffix comes from the
# WORKSPACE_RUN_SUFFIX injection seam when set (tests use this for
# determinism); otherwise it falls back to a timestamp+pid combination so
# concurrent real runs do not collide.
workspace_run_root() {
    local base="$1" issue="$2" suffix
    suffix="${WORKSPACE_RUN_SUFFIX:-$(_workspace_default_suffix)}"
    printf '%s/iw-%s-%s\n' "${base%/}" "$issue" "$suffix"
}

_workspace_default_suffix() {
    local ts
    ts="$(date +%s 2>/dev/null || echo 0)"
    printf '%s%s' "$ts" "$$"
}

# Reduce a (already-redacted) git remote URL to its trailing "owner/name"
# path component. Host-agnostic by design: strips a "<scheme>://<host>/"
# prefix or an SSH-shorthand "<user>@<host>:" prefix (or neither, for a bare
# local path used by tests), then takes the final two "/"-separated
# segments. This accepts both "https://github.com/owner/name(.git)" and
# "git@github.com:owner/name(.git)" as specified, while remaining usable
# against GitHub Enterprise hosts and local test doubles.
_workspace_owner_name_from_origin() {
    local url="${1:-}" cleaned no_scheme path owner name
    [ -n "$url" ] || return 1
    cleaned="${url%.git}"
    if [ "$cleaned" != "${cleaned#*://}" ]; then
        no_scheme="${cleaned#*://}"
        path="${no_scheme#*/}"
    elif [ "$cleaned" != "${cleaned#*:}" ]; then
        path="${cleaned#*:}"
    else
        path="$cleaned"
    fi
    path="${path%/}"
    name="${path##*/}"
    owner="${path%/*}"
    owner="${owner##*/}"
    [ -n "$owner" ] && [ -n "$name" ] || return 1
    printf '%s/%s' "$owner" "$name"
}

# Read the origin remote of <repo_dir>, redact it, and succeed only when it
# resolves to the expected "owner/name". Rejects on mismatch, a missing
# origin, or an empty expected value.
workspace_verify_identity() {
    local repo_dir="$1" expected="${2:-}" origin actual
    [ -n "$repo_dir" ] && [ -n "$expected" ] || return 1
    origin="$(_workspace_git -C "$repo_dir" remote get-url origin 2>/dev/null)" || return 1
    [ -n "$origin" ] || return 1
    origin="$(workspace_redact_credentials "$origin")"
    actual="$(_workspace_owner_name_from_origin "$origin")" || return 1
    [ -n "$actual" ] || return 1
    [ "$actual" = "$expected" ]
}

# Atomically update a single `key=value` line in a portable line-based
# manifest (no jq dependency; readable by bash and PowerShell alike). Writes
# to "<path>.tmp.$$" then `mv`s into place so a reader never observes a
# partially-written file. The value is always passed through
# workspace_redact_credentials before being written, so a URL-shaped value
# can never land in the manifest with embedded credentials.
workspace_manifest_write() {
    local path="${1:-}" key="${2:-}" value="${3:-}" dir tmp
    [ -n "$path" ] && [ -n "$key" ] || return 1
    value="$(workspace_redact_credentials "$value")"
    dir="$(dirname -- "$path")"
    [ -d "$dir" ] || mkdir -p -- "$dir" 2>/dev/null || return 1
    tmp="${path}.tmp.$$"
    if [ -f "$path" ]; then
        grep -v -E "^${key}=" "$path" 2>/dev/null > "$tmp" || true
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv -f -- "$tmp" "$path"
}

# Print the value for <key> in the manifest ("" if the manifest or key is
# absent). When a key was written more than once, the last write wins.
workspace_manifest_read() {
    local path="${1:-}" key="${2:-}"
    [ -f "$path" ] || { printf ''; return 0; }
    grep -E "^${key}=" "$path" 2>/dev/null | tail -n1 | sed -E "s/^${key}=//"
}

# Convenience accessor for the current `state=` value.
workspace_manifest_state() {
    workspace_manifest_read "$1" state
}

# ── Marker ──────────────────────────────────────────────────────────
# Writes the run marker into <run_root> and prints its path. Content is a
# tiny key=value block (reuses the manifest line format) whose issue= line
# is the field a resumed session checks before trusting the run root.
_workspace_write_marker() {
    local run_root="$1" issue="$2" path created
    path="${run_root%/}/${_WORKSPACE_MARKER_FILE}"
    created="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf 'issue=%s\ncreated=%s\n' "$issue" "$created" > "$path"
    printf '%s' "$path"
}

# ── Clone ───────────────────────────────────────────────────────────
# Clones <url>'s <branch> into <dest>. Shallowable via the WORKSPACE_CLONE_DEPTH
# seam (adds --depth when set); never recurses submodules. All git output is
# captured (never streamed to stdout/stderr) and, on failure, redacted into
# WORKSPACE_LAST_ERROR so a caller can report a reason without ever risking a
# credential leak through git's own error text.
WORKSPACE_LAST_ERROR=""
_workspace_clone() {
    local url="$1" branch="$2" dest="$3" out rc
    local depth_args=()
    if [ -n "${WORKSPACE_CLONE_DEPTH:-}" ]; then
        depth_args=(--depth "$WORKSPACE_CLONE_DEPTH")
    fi
    out="$(_workspace_git clone --branch "$branch" --single-branch \
        --no-recurse-submodules "${depth_args[@]}" "$url" "$dest" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        WORKSPACE_LAST_ERROR="$(workspace_redact_credentials "$out" | tail -n1)"
    fi
    return "$rc"
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
_workspace_emit_ready() {
    local run_root="$1" repo_dir="$2" baseline="$3" manifest="$4" marker="$5"
    printf '{"state":"READY","run_root":"%s","repo_dir":"%s","baseline":"%s","manifest":"%s","marker":"%s"}\n' \
        "$run_root" "$repo_dir" "$baseline" "$manifest" "$marker"
}

_workspace_emit_rejected() {
    local run_root="$1" repo_dir="$2" manifest="$3" marker="$4" reason="$5"
    reason="$(workspace_redact_credentials "$reason")"
    printf '{"state":"REJECTED","reason":"%s","run_root":"%s","repo_dir":"%s","manifest":"%s","marker":"%s"}\n' \
        "$reason" "$run_root" "$repo_dir" "$manifest" "$marker"
}

# ── Driver ──────────────────────────────────────────────────────────
# run_workspace <repo> <base> <issue> [<clone_url>] [<manifest_path>]
#
# repo   expected "owner/name" identity, also used to derive the default
#        clone URL when <clone_url> is omitted.
# base   temp base directory the run root is created under.
# issue  issue number; scopes the run-root name and is recorded in the marker.
run_workspace() {
    local repo="${1:-}" base="${2:-}" issue="${3:-}" clone_url="${4:-}" manifest_override="${5:-}"

    if [ -z "$repo" ] || [ -z "$base" ] || [ -z "$issue" ]; then
        _workspace_emit_rejected "" "" "" "" "missing required repo/base/issue"
        return 2
    fi

    local run_root; run_root="$(workspace_run_root "$base" "$issue")"
    if ! mkdir -p -- "$run_root" 2>/dev/null; then
        _workspace_emit_rejected "$run_root" "" "" "" "failed to create run root"
        return 1
    fi

    local marker; marker="$(_workspace_write_marker "$run_root" "$issue")"
    local manifest="${manifest_override:-${run_root%/}/manifest}"

    workspace_manifest_write "$manifest" issue "$issue"
    workspace_manifest_write "$manifest" repo "$repo"
    workspace_manifest_write "$manifest" run_root "$run_root"
    workspace_manifest_write "$manifest" marker "$marker"
    workspace_manifest_write "$manifest" state CLAIMED

    # Enter CLONING before the clone actually starts, so a crash mid-clone
    # leaves the manifest correctly reflecting the in-progress phase rather
    # than the stale CLAIMED state.
    workspace_manifest_write "$manifest" state CLONING
    local repo_dir="${run_root%/}/repo"
    local url="${clone_url:-https://github.com/${repo}.git}"
    if ! _workspace_clone "$url" develop "$repo_dir"; then
        workspace_manifest_write "$manifest" state REJECTED
        _workspace_emit_rejected "$run_root" "$repo_dir" "$manifest" "$marker" \
            "clone failed: ${WORKSPACE_LAST_ERROR:-unknown error}"
        return 1
    fi

    local baseline
    baseline="$(_workspace_git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"

    if ! workspace_verify_identity "$repo_dir" "$repo"; then
        workspace_manifest_write "$manifest" state REJECTED
        _workspace_emit_rejected "$run_root" "$repo_dir" "$manifest" "$marker" \
            "origin identity does not match expected repo ${repo}"
        return 1
    fi

    workspace_manifest_write "$manifest" repo_dir "$repo_dir"
    workspace_manifest_write "$manifest" baseline "$baseline"
    workspace_manifest_write "$manifest" state READY

    _workspace_emit_ready "$run_root" "$repo_dir" "$baseline" "$manifest" "$marker"
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────
_workspace_main() {
    local repo="" base="" issue="" clone_url="" manifest=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --clone-url) clone_url="$2"; shift 2 ;;
            --manifest) manifest="$2"; shift 2 ;;
            *) echo "unknown argument: $1" >&2; return 2 ;;
        esac
    done
    if [ -z "$repo" ] || [ -z "$base" ] || [ -z "$issue" ]; then
        echo "error: --repo <owner/name>, --base <tmpbase>, and --issue <n> are required" >&2
        return 2
    fi
    run_workspace "$repo" "$base" "$issue" "$clone_url" "$manifest"
}

# Run as CLI only when executed directly; stay quiet when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _workspace_main "$@"
fi
