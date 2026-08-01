#!/usr/bin/env bash
# Test suite for global/skills/_internal/issue-work/scripts/agents.sh
# Run: bash tests/issue-work/test-agents.sh
#
# Drives the subagent spawn-contract + single-writer-lease stage
# (READY -> AGENTS_RUNNING -> COMMITTED) against a real local git repository --
# no fake gh/git shim is needed because this stage never calls gh, and driving
# real git exercises the actual worktree add/remove codepaths instead of a
# stand-in. Sourcing agents.sh also loads workspace.sh, so the #838 manifest
# primitive (workspace_manifest_*) is available for assertions.
#
# AC -> test mapping (see reference/workspace-lifecycle.md, #839 sections):
#   AC1  path normalization      -> a relative path resolves to an absolute path
#   AC2  spawn-prompt contract    -> prompt carries every required field + the
#                                    full prohibition clause
#   AC3  lease mutual exclusion   -> one writer at a time; re-acquire after release
#   AC4  lease fail-safe          -> non-owner release refused; missing lease fails cleanly
#   AC5  per-agent worktree        -> add then remove leaves no orphan
#   AC6  state transitions         -> READY -> AGENTS_RUNNING -> COMMITTED
#   AC7  capability guard          -> script performs no gh call and no remote push

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
AGENTS="$ROOT_DIR/global/skills/_internal/issue-work/scripts/agents.sh"

PASS=0
FAIL=0
ERRORS=()

# Explicit template (rather than a bare `mktemp -d`) so this suite is stable
# under sandboxes that restrict the OS default temp directory but expose
# $TMPDIR, as well as under plain CI runners where $TMPDIR is unset.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iw-agents-test.XXXXXX")"
# Resolve symlinks + collapse // so derived paths match `git worktree list`
# output on macOS, whose default $TMPDIR (/var/folders/...) is a symlink to
# /private/var/... that git canonicalizes. pwd -P matches git's own resolution.
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then ok "$label"; else
        bad "$label -- expected '$expected', got '$actual'"; fi
}

assert_contains() {
    local needle="$1" hay="$2" label="$3"
    if printf '%s' "$hay" | grep -Fq -- "$needle"; then ok "$label"; else
        bad "$label -- '$needle' not in output"; fi
}

# Builds a real (non-bare) repository with one commit on a "develop" branch and
# prints its path. Worktree tests operate directly on this checkout.
make_repo() {  # make_repo <name>
    local name="$1" repo
    repo="$WORK/repos/$name"
    mkdir -p "$repo"
    git init -q -b develop "$repo"
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "test"
    echo "content" > "$repo/file.txt"
    git -C "$repo" add file.txt
    git -C "$repo" commit -q -m "seed commit" >/dev/null
    printf '%s' "$repo"
}

echo "=== agents.sh unit + scenario tests ==="
# shellcheck disable=SC1090
source "$AGENTS"

# Low-entropy, clearly-fake owner ids assembled at runtime. No credential is
# needed for any lease/worktree/transition test; these are opaque identity
# strings, never tokens, and carry no secret-scanner-shaped prefix.
OWNER_A="agent-a-$$"
OWNER_B="agent-b-$$"

echo ""
echo "=== AC1: path normalization -- a relative path resolves to an absolute path ==="
norm_dir="$WORK/norm/sub"
mkdir -p "$norm_dir"
rel_out="$(cd "$WORK/norm" && agents_normalize_path "sub")"
case "$rel_out" in
    /*) ok "AC1 relative existing dir resolves to an absolute path" ;;
    *)  bad "AC1 relative path did not resolve to an absolute path -- got '$rel_out'" ;;
esac
assert_contains "/norm/sub" "$rel_out" "AC1 normalized path retains the resolved directory"
# Pure (non-existent) path is still made absolute and lexically collapsed.
pure_out="$(cd "$WORK/norm" && agents_normalize_path "a/b/../c")"
case "$pure_out" in
    /*) ok "AC1 non-existent relative path is made absolute" ;;
    *)  bad "AC1 non-existent relative path not absolute -- got '$pure_out'" ;;
esac
assert_contains "/a/c" "$pure_out" "AC1 '..' is collapsed lexically"
if agents_normalize_path ""; then bad "AC1 empty input must fail"; else
    ok "AC1 empty input fails"; fi

echo ""
echo "=== AC2: spawn-prompt contract carries every required field ==="
prompt_repo="$WORK/repos/promptrepo"
mkdir -p "$prompt_repo"
abs_repo="$(agents_normalize_path "$prompt_repo")"
scope_text="scripts/agents.sh, tests/issue-work/test-agents.sh"
prompt="$(agents_build_prompt "$prompt_repo" 839 feat/issue-839-subagent-spawn-lease deadbeefcafe "$scope_text")"
assert_contains "$abs_repo" "$prompt" "AC2 prompt contains the normalized absolute repo path"
assert_contains "#839" "$prompt" "AC2 prompt contains the active issue number"
assert_contains "feat/issue-839-subagent-spawn-lease" "$prompt" "AC2 prompt contains the target branch"
assert_contains "deadbeefcafe" "$prompt" "AC2 prompt contains the baseline commit"
assert_contains "$scope_text" "$prompt" "AC2 prompt contains the explicit write scope"
# Prohibition clause: each ban must be present.
assert_contains "push any commit" "$prompt" "AC2 prohibition forbids pushing to the remote"
assert_contains "GitHub CLI" "$prompt" "AC2 prohibition forbids the GitHub CLI"
assert_contains "pull request (PR)" "$prompt" "AC2 prohibition forbids opening/merging a PR"
assert_contains "merge a pull request" "$prompt" "AC2 prohibition forbids merging a PR"
assert_contains "clean up" "$prompt" "AC2 prohibition forbids workspace cleanup"
assert_contains "coordinator owns ALL git and GitHub mutations" "$prompt" "AC2 prompt states coordinator ownership"

echo ""
echo "=== AC3: lease mutual exclusion -- one writer at a time ==="
lease="$WORK/checkout/$AGENTS_LEASE_DIRNAME"
if agents_acquire_lease "$lease" "$OWNER_A"; then ok "AC3 first writer acquires the lease"; else
    bad "AC3 first acquire should succeed"; fi
assert_eq "$OWNER_A" "$(agents_lease_owner "$lease")" "AC3 lease records the owning writer"
if agents_acquire_lease "$lease" "$OWNER_B"; then
    bad "AC3 a second writer must be refused while the lease is held"; else
    ok "AC3 second writer is refused while the lease is held"; fi
assert_eq "$OWNER_A" "$(agents_lease_owner "$lease")" "AC3 held lease still owned by the first writer"
if agents_release_lease "$lease" "$OWNER_A"; then ok "AC3 owner releases the lease"; else
    bad "AC3 owner release should succeed"; fi
if [ -d "$lease" ]; then bad "AC3 lease directory must be gone after release"; else
    ok "AC3 lease directory removed on release"; fi
if agents_acquire_lease "$lease" "$OWNER_B"; then ok "AC3 lease is re-acquirable after release"; else
    bad "AC3 re-acquire after release should succeed"; fi
# Clean up for later independence.
agents_release_lease "$lease" "$OWNER_B" >/dev/null 2>&1 || true

echo ""
echo "=== AC4: lease fail-safe -- non-owner release refused; missing lease fails cleanly ==="
lease2="$WORK/checkout2/$AGENTS_LEASE_DIRNAME"
agents_acquire_lease "$lease2" "$OWNER_A" >/dev/null 2>&1
if agents_release_lease "$lease2" "$OWNER_B"; then
    bad "AC4 a non-owner must not be able to release the lease"; else
    ok "AC4 non-owner release is refused"; fi
if [ -d "$lease2" ]; then ok "AC4 lease survives a refused non-owner release"; else
    bad "AC4 lease must survive a refused non-owner release"; fi
agents_release_lease "$lease2" "$OWNER_A" >/dev/null 2>&1 || true
# Releasing a non-existent lease fails cleanly (non-zero, no crash).
if agents_release_lease "$WORK/nope/$AGENTS_LEASE_DIRNAME" "$OWNER_A"; then
    bad "AC4 releasing a non-existent lease must fail"; else
    ok "AC4 releasing a non-existent lease fails cleanly"; fi
# A path that is not a lease directory is refused outright (guarded removal).
if agents_release_lease "$WORK/not-a-lease-dir" "$OWNER_A"; then
    bad "AC4 releasing a non-lease path must be refused"; else
    ok "AC4 non-lease path is refused (guarded removal)"; fi

echo ""
echo "=== AC5: per-agent worktree add then remove leaves no orphan ==="
wt_repo="$(make_repo wtrepo)"
wt_path="$WORK/worktrees/agent1"
if agents_worktree_add "$wt_repo" "$wt_path" "feat/agent1-work"; then ok "AC5 worktree add succeeds"; else
    bad "AC5 worktree add should succeed -- ${AGENTS_LAST_ERROR:-}"; fi
if [ -d "$wt_path" ]; then ok "AC5 worktree directory exists after add"; else
    bad "AC5 worktree directory should exist after add"; fi
assert_contains "$wt_path" "$(git -C "$wt_repo" worktree list)" "AC5 git lists the added worktree"
if agents_worktree_remove "$wt_repo" "$wt_path"; then ok "AC5 worktree remove succeeds"; else
    bad "AC5 worktree remove should succeed -- ${AGENTS_LAST_ERROR:-}"; fi
if [ -d "$wt_path" ]; then bad "AC5 worktree directory must be gone after remove"; else
    ok "AC5 worktree directory removed"; fi
assert_eq "" "$(git -C "$wt_repo" worktree list | grep -F "$wt_path" || true)" "AC5 removed worktree is not orphaned in git worktree list"

echo ""
echo "=== AC6: state transitions READY -> AGENTS_RUNNING -> COMMITTED ==="
manifest="$WORK/manifest"
workspace_manifest_write "$manifest" state READY
out_start="$(run_agents "$manifest" start "$OWNER_A")"
assert_contains "\"state\":\"AGENTS_RUNNING\"" "$out_start" "AC6 start phase emits AGENTS_RUNNING"
assert_eq "AGENTS_RUNNING" "$(workspace_manifest_state "$manifest")" "AC6 manifest advances to AGENTS_RUNNING"
assert_eq "$OWNER_A" "$(workspace_manifest_read "$manifest" lease_owner)" "AC6 start records the lease owner"
out_commit="$(run_agents "$manifest" commit)"
assert_contains "\"state\":\"COMMITTED\"" "$out_commit" "AC6 commit phase emits COMMITTED"
assert_eq "COMMITTED" "$(workspace_manifest_state "$manifest")" "AC6 manifest advances to COMMITTED"
# Out-of-order transition is refused (fail-safe on strict ordering).
manifest_bad="$WORK/manifest-bad"
workspace_manifest_write "$manifest_bad" state READY
if run_agents "$manifest_bad" commit >/dev/null 2>&1; then
    bad "AC6 commit from READY (skipping AGENTS_RUNNING) must be refused"; else
    ok "AC6 out-of-order transition is refused"; fi
assert_eq "READY" "$(workspace_manifest_state "$manifest_bad")" "AC6 refused transition leaves state unchanged"

echo ""
echo "=== AC7: capability guard -- script performs no gh call and no remote push ==="
# The agent must never perform a GitHub mutation. Assert the script contains no
# remote push and no GitHub-CLI invocation. The gh check uses a word boundary so
# ordinary words ending in 'gh' (e.g. 'through') never register as a false match.
if grep -Fq 'git push' "$AGENTS"; then
    bad "AC7 agents.sh must not contain 'git push'"; else
    ok "AC7 agents.sh performs no remote push"; fi
if grep -Eq '(^|[^[:alnum:]_])gh ' "$AGENTS"; then
    bad "AC7 agents.sh must not invoke the GitHub CLI (gh)"; else
    ok "AC7 agents.sh performs no gh call"; fi
if grep -Fq 'GH_BIN' "$AGENTS"; then
    bad "AC7 agents.sh must not wire a gh injection seam"; else
    ok "AC7 agents.sh has no gh injection seam"; fi

echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for e in "${ERRORS[@]}"; do echo "  $e"; done
    exit 1
fi
exit 0
