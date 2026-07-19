#!/usr/bin/env bash
# Test suite for global/skills/_internal/issue-work/scripts/pre-pr-gate.sh
# Run: bash tests/issue-work/test-pre-pr-gate.sh
#
# Drives the pre-PR readiness gate (git-state half) against REAL local bare git
# repositories -- no fake git shim is needed for the mechanics, because the gate
# never calls gh and driving real git exercises the actual fetch / fast-forward
# / rebase / merge codepaths instead of a stand-in. The classifier unit test
# points the sourced helper at a throwaway repo via the PREPR_REPO_DIR seam.
#
# AC -> test mapping (see reference/pre-pr-readiness.md):
#   AC1  clean-worktree precondition -> dirty tree -> blocked/dirty_worktree
#   AC2  develop refresh (advance)   -> behind -> local base ff'd -> ready;
#                                       current -> ready with no reset
#   AC3  develop refresh (guard)     -> ahead -> blocked/base_ahead (not reset);
#                                       diverged -> blocked/base_diverged (not reset)
#   AC4  integration                 -> clean rebase replays feature commits ->
#                                       ready; merge mode also integrates -> ready
#   AC5  conflict                    -> any conflict aborts -> blocked/conflict,
#                                       feature HEAD unchanged, worktree clean
#   AC6  base-movement retry         -> repeated movement -> blocked/base_unstable
#                                       after --max-base-moves attempts, reported
#   UNIT classify_base_relationship  -> equal/behind/ahead/diverged/unknown

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
GATE="$ROOT_DIR/global/skills/_internal/issue-work/scripts/pre-pr-gate.sh"

PASS=0
FAIL=0
ERRORS=()

# Explicit template (rather than a bare `mktemp -d`) so this suite is stable
# under sandboxes that restrict the OS default temp directory but expose
# $TMPDIR, as well as under plain CI runners where $TMPDIR is unset.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iw-pre-pr-test.XXXXXX")"
# Canonicalize (resolve symlinks + collapse //) so paths baked into the
# PRE_PR_ON_FETCH hook match what git sees on macOS, whose default $TMPDIR
# (/var/folders/...) is a symlink to /private/var/...
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

assert_not_contains() {
    local needle="$1" hay="$2" label="$3"
    if printf '%s' "$hay" | grep -Fq -- "$needle"; then
        bad "$label -- '$needle' unexpectedly present"
    else
        ok "$label"
    fi
}

jfield() {  # jfield <json> <field>
    printf '%s' "$1" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],""))' "$2" 2>/dev/null
}

# Builds a bare "remote" under $WORK/remote seeded with one commit on a
# "develop" branch, plus a "seed" working clone used to advance the remote
# during a scenario. Prints "<remote-path>|<seed-path>".
make_remote() {  # make_remote <name>
    local name="$1" remote seed
    remote="$WORK/remote/${name}.git"
    seed="$WORK/seed-${name}"
    mkdir -p "$(dirname "$remote")"
    git init --bare -q "$remote"
    git init -q -b develop "$seed"
    git -C "$seed" config user.email "test@example.com"
    git -C "$seed" config user.name "test"
    echo "base" > "$seed/file.txt"
    git -C "$seed" add file.txt
    git -C "$seed" commit -q -m "seed commit" >/dev/null
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q origin develop
    printf '%s|%s' "$remote" "$seed"
}

# Clones <remote>'s develop into <dest>, sets a test identity, and creates a
# feature branch <branch> carrying one commit on <feat_file>. Prints <dest>.
make_feature_clone() {  # make_feature_clone <remote> <dest> <branch> <feat_file>
    local remote="$1" dest="$2" branch="$3" feat_file="$4"
    git clone -q --branch develop --single-branch "$remote" "$dest"
    git -C "$dest" config user.email "test@example.com"
    git -C "$dest" config user.name "test"
    git -C "$dest" checkout -q -b "$branch"
    echo "feature work" > "$dest/$feat_file"
    git -C "$dest" add "$feat_file"
    git -C "$dest" commit -q -m "feature commit"
    printf '%s' "$dest"
}

# Advance the remote develop by one non-conflicting commit via the seed clone.
# Prints the new remote develop sha.
advance_remote() {  # advance_remote <seed> <file> <content>
    local seed="$1" file="$2" content="$3"
    git -C "$seed" checkout -q develop
    echo "$content" >> "$seed/$file"
    git -C "$seed" add "$file"
    git -C "$seed" commit -q -m "remote advance"
    git -C "$seed" push -q origin develop
    git -C "$seed" rev-parse develop
}

# Run the gate CLI from inside <repo> so PREPR_REPO_DIR defaults to that
# checkout. Extra args are forwarded. Prints the JSON stdout line.
run_gate() {  # run_gate <repo> [gate args...]
    local repo="$1"; shift
    ( cd "$repo" && bash "$GATE" "$@" )
}

echo "=== pre-pr-gate.sh UNIT: classify_base_relationship ==="
# shellcheck disable=SC1090
source "$GATE"
cls_repo="$WORK/classify-repo"
git init -q -b main "$cls_repo"
git -C "$cls_repo" config user.email "test@example.com"
git -C "$cls_repo" config user.name "test"
echo a > "$cls_repo/f.txt"; git -C "$cls_repo" add f.txt; git -C "$cls_repo" commit -q -m A
SHA_A="$(git -C "$cls_repo" rev-parse HEAD)"
echo b >> "$cls_repo/f.txt"; git -C "$cls_repo" add f.txt; git -C "$cls_repo" commit -q -m B
SHA_B="$(git -C "$cls_repo" rev-parse HEAD)"
git -C "$cls_repo" checkout -q -b fork "$SHA_A"
echo c > "$cls_repo/g.txt"; git -C "$cls_repo" add g.txt; git -C "$cls_repo" commit -q -m C
SHA_C="$(git -C "$cls_repo" rev-parse HEAD)"

assert_eq "equal"    "$(PREPR_REPO_DIR="$cls_repo" classify_base_relationship "$SHA_A" "$SHA_A")" "UNIT identical shas -> equal"
assert_eq "behind"   "$(PREPR_REPO_DIR="$cls_repo" classify_base_relationship "$SHA_A" "$SHA_B")" "UNIT local ancestor of remote -> behind"
assert_eq "ahead"    "$(PREPR_REPO_DIR="$cls_repo" classify_base_relationship "$SHA_B" "$SHA_A")" "UNIT remote ancestor of local -> ahead"
assert_eq "diverged" "$(PREPR_REPO_DIR="$cls_repo" classify_base_relationship "$SHA_B" "$SHA_C")" "UNIT forked histories -> diverged"
cls_unknown="$(PREPR_REPO_DIR="$cls_repo" classify_base_relationship "" "$SHA_A")"
assert_eq "unknown"  "$cls_unknown" "UNIT empty argument -> unknown"

echo ""
echo "=== AC1: dirty worktree is refused before any fetch ==="
IFS='|' read -r rem1 seed1 <<< "$(make_remote ac1)"
repo1="$(make_feature_clone "$rem1" "$WORK/repo1" feat/x feature.txt)"
dev1_before="$(git -C "$repo1" rev-parse develop)"
echo "uncommitted" >> "$repo1/file.txt"   # tracked, uncommitted -> dirty
out1="$(run_gate "$repo1" --repo o/ac1 --base develop --branch feat/x)"
assert_eq "blocked" "$(jfield "$out1" outcome)" "AC1 outcome=blocked on a dirty worktree"
assert_eq "dirty_worktree" "$(jfield "$out1" reason)" "AC1 reason=dirty_worktree"
assert_eq "0" "$(jfield "$out1" attempts)" "AC1 no integration attempted (attempts=0)"
assert_eq "$dev1_before" "$(git -C "$repo1" rev-parse develop)" "AC1 local base untouched by a refused run"

echo ""
echo "=== AC2: behind base -> local base fast-forwarded -> ready ==="
IFS='|' read -r rem2 seed2 <<< "$(make_remote ac2)"
repo2="$(make_feature_clone "$rem2" "$WORK/repo2" feat/x feature.txt)"
dev2_before="$(git -C "$repo2" rev-parse develop)"
remote2_sha="$(advance_remote "$seed2" churn.txt one)"   # remote develop moves ahead
out2="$(run_gate "$repo2" --repo o/ac2 --base develop --branch feat/x)"
assert_eq "ready" "$(jfield "$out2" outcome)" "AC2 outcome=ready when strictly behind"
assert_eq "$remote2_sha" "$(jfield "$out2" remote_base_sha)" "AC2 remote_base_sha is the fetched remote head"
assert_eq "$dev2_before" "$(jfield "$out2" local_base_sha_before)" "AC2 local_base_sha_before is the pre-refresh sha"
assert_eq "$remote2_sha" "$(jfield "$out2" local_base_sha_after)" "AC2 local base fast-forwarded to the remote head"
assert_eq "$remote2_sha" "$(git -C "$repo2" rev-parse develop)" "AC2 the on-disk local base branch was fast-forwarded"
# The feature commits are replayed onto the refreshed base.
assert_eq "1" "$(test -f "$repo2/feature.txt" && echo 1 || echo 0)" "AC2 feature file survives the rebase"
assert_eq "1" "$(test -f "$repo2/churn.txt" && echo 1 || echo 0)" "AC2 refreshed base content is present after the rebase"

echo ""
echo "=== AC2: base already current -> ready with no reset ==="
IFS='|' read -r rem2b seed2b <<< "$(make_remote ac2b)"
repo2b="$(make_feature_clone "$rem2b" "$WORK/repo2b" feat/x feature.txt)"
dev2b_before="$(git -C "$repo2b" rev-parse develop)"
out2b="$(run_gate "$repo2b" --repo o/ac2b --base develop --branch feat/x)"
assert_eq "ready" "$(jfield "$out2b" outcome)" "AC2 outcome=ready when base is already current"
assert_eq "$dev2b_before" "$(jfield "$out2b" local_base_sha_before)" "AC2 current-base before sha recorded"
assert_eq "$dev2b_before" "$(jfield "$out2b" local_base_sha_after)" "AC2 current base is not moved"

echo ""
echo "=== AC3: local base AHEAD -> blocked/base_ahead, base not reset ==="
IFS='|' read -r rem3 seed3 <<< "$(make_remote ac3)"
git clone -q --branch develop --single-branch "$rem3" "$WORK/repo3"
repo3="$WORK/repo3"
git -C "$repo3" config user.email "test@example.com"; git -C "$repo3" config user.name "test"
# Put an unshared commit on the LOCAL develop, then branch the feature from it.
git -C "$repo3" checkout -q develop
echo "local-only" >> "$repo3/file.txt"; git -C "$repo3" add file.txt; git -C "$repo3" commit -q -m "local ahead"
dev3_before="$(git -C "$repo3" rev-parse develop)"
git -C "$repo3" checkout -q -b feat/x
out3="$(run_gate "$repo3" --repo o/ac3 --base develop --branch feat/x)"
assert_eq "blocked" "$(jfield "$out3" outcome)" "AC3 outcome=blocked when local base is ahead"
assert_eq "base_ahead" "$(jfield "$out3" reason)" "AC3 reason=base_ahead"
assert_eq "$dev3_before" "$(jfield "$out3" local_base_sha_after)" "AC3 local_base_sha_after unchanged (not reset)"
assert_eq "$dev3_before" "$(git -C "$repo3" rev-parse develop)" "AC3 the on-disk local base was not rewound"

echo ""
echo "=== AC3: local base DIVERGED -> blocked/base_diverged, base not reset ==="
IFS='|' read -r rem4 seed4 <<< "$(make_remote ac4)"
git clone -q --branch develop --single-branch "$rem4" "$WORK/repo4"
repo4="$WORK/repo4"
git -C "$repo4" config user.email "test@example.com"; git -C "$repo4" config user.name "test"
git -C "$repo4" checkout -q develop
echo "local-side" >> "$repo4/local.txt"; git -C "$repo4" add local.txt; git -C "$repo4" commit -q -m "local diverge"
dev4_before="$(git -C "$repo4" rev-parse develop)"
git -C "$repo4" checkout -q -b feat/x
advance_remote "$seed4" remote.txt other >/dev/null   # remote diverges independently
out4="$(run_gate "$repo4" --repo o/ac4 --base develop --branch feat/x)"
assert_eq "blocked" "$(jfield "$out4" outcome)" "AC3 outcome=blocked when histories diverge"
assert_eq "base_diverged" "$(jfield "$out4" reason)" "AC3 reason=base_diverged"
assert_eq "$dev4_before" "$(jfield "$out4" local_base_sha_after)" "AC3 diverged local base not reset"
assert_eq "$dev4_before" "$(git -C "$repo4" rev-parse develop)" "AC3 the on-disk diverged base was not rewound"

echo ""
echo "=== AC4: clean rebase replays feature commits onto refreshed base ==="
# Same mechanics as AC2 ready, asserted from the integration angle: the feature
# commit sha changes (replayed) while its content and the new base coexist.
IFS='|' read -r rem5 seed5 <<< "$(make_remote ac5)"
repo5="$(make_feature_clone "$rem5" "$WORK/repo5" feat/x feature.txt)"
feat5_before="$(git -C "$repo5" rev-parse HEAD)"
advance_remote "$seed5" churn.txt two >/dev/null
out5="$(run_gate "$repo5" --repo o/ac5 --base develop --branch feat/x)"
assert_eq "ready" "$(jfield "$out5" outcome)" "AC4 clean integration -> ready"
feat5_after="$(git -C "$repo5" rev-parse HEAD)"
if [ "$feat5_before" != "$feat5_after" ]; then ok "AC4 feature commit was replayed (HEAD sha changed)"; else
    bad "AC4 feature commit should have been replayed onto the refreshed base"; fi
assert_eq "1" "$(git -C "$repo5" merge-base --is-ancestor develop HEAD && echo 1 || echo 0)" "AC4 refreshed base is an ancestor of the feature HEAD"

echo ""
echo "=== AC4: merge mode integrates the base -> ready ==="
IFS='|' read -r rem6 seed6 <<< "$(make_remote ac6)"
repo6="$(make_feature_clone "$rem6" "$WORK/repo6" feat/x feature.txt)"
advance_remote "$seed6" churn.txt three >/dev/null
out6="$(run_gate "$repo6" --repo o/ac6 --base develop --branch feat/x --integrate merge)"
assert_eq "ready" "$(jfield "$out6" outcome)" "AC4 merge-mode integration -> ready"
assert_eq "1" "$(git -C "$repo6" rev-list --merges -1 HEAD | wc -l | tr -d ' ')" "AC4 merge mode created a merge commit"

echo ""
echo "=== AC5: integration conflict -> abort -> blocked/conflict, feature untouched ==="
IFS='|' read -r rem7 seed7 <<< "$(make_remote ac7)"
git clone -q --branch develop --single-branch "$rem7" "$WORK/repo7"
repo7="$WORK/repo7"
git -C "$repo7" config user.email "test@example.com"; git -C "$repo7" config user.name "test"
git -C "$repo7" checkout -q -b feat/x
echo "OURS" > "$repo7/file.txt"; git -C "$repo7" add file.txt; git -C "$repo7" commit -q -m "feature edits shared file"
feat7_before="$(git -C "$repo7" rev-parse HEAD)"
# Remote edits the same line differently -> rebase will conflict.
git -C "$seed7" checkout -q develop
echo "THEIRS" > "$seed7/file.txt"; git -C "$seed7" add file.txt; git -C "$seed7" commit -q -m "remote edits shared file"
git -C "$seed7" push -q origin develop
out7="$(run_gate "$repo7" --repo o/ac7 --base develop --branch feat/x)"
assert_eq "blocked" "$(jfield "$out7" outcome)" "AC5 outcome=blocked on an integration conflict"
assert_eq "conflict" "$(jfield "$out7" reason)" "AC5 reason=conflict"
assert_eq "$feat7_before" "$(git -C "$repo7" rev-parse HEAD)" "AC5 feature branch HEAD is unchanged (rebase aborted)"
assert_eq "" "$(git -C "$repo7" status --porcelain)" "AC5 worktree is clean after the abort (no conflict markers left)"
assert_eq "feat/x" "$(git -C "$repo7" rev-parse --abbrev-ref HEAD)" "AC5 still on the feature branch after the abort"

echo ""
echo "=== AC6: repeated base movement -> blocked/base_unstable after N attempts ==="
IFS='|' read -r rem8 seed8 <<< "$(make_remote ac8)"
repo8="$(make_feature_clone "$rem8" "$WORK/repo8" feat/x feature.txt)"
counter="$WORK/ac8-counter"
echo 0 > "$counter"
# After every fetch, push a fresh non-conflicting commit so the base never
# stabilizes. Absolute paths are baked in so the hook works from any cwd.
hook="c=\$(cat '$counter'); c=\$((c+1)); echo \$c > '$counter'; echo churn\$c >> '$seed8/churn.txt'; git -C '$seed8' add -A; git -C '$seed8' commit -q -m churn\$c; git -C '$seed8' push -q origin develop"
out8="$(cd "$repo8" && PRE_PR_ON_FETCH="$hook" bash "$GATE" --repo o/ac8 --base develop --branch feat/x)"
assert_eq "blocked" "$(jfield "$out8" outcome)" "AC6 outcome=blocked when the base never stabilizes"
assert_eq "base_unstable" "$(jfield "$out8" reason)" "AC6 reason=base_unstable"
assert_eq "3" "$(jfield "$out8" attempts)" "AC6 attempts caps at the default --max-base-moves (3)"
# A smaller cap is honored and reported.
echo 0 > "$counter"
out8b="$(cd "$repo8" && PRE_PR_ON_FETCH="$hook" bash "$GATE" --repo o/ac8 --base develop --branch feat/x --max-base-moves 2)"
assert_eq "base_unstable" "$(jfield "$out8b" reason)" "AC6 reason=base_unstable with a smaller cap"
assert_eq "2" "$(jfield "$out8b" attempts)" "AC6 attempts honors an explicit --max-base-moves 2"

echo ""
echo "=== Missing required args -> blocked/missing_args, returns 2 ==="
# The JSON contract for a missing argument lives in the driver, exercised via
# the function sourced above (the CLI wrapper prints a usage hint to stderr and
# returns 2 without JSON, mirroring workspace.sh). The missing-arg check returns
# before any git call, so PREPR_REPO_DIR is irrelevant here.
out9="$(run_pre_pr_gate o/n develop "")"   # empty branch
rc9=$?
assert_eq "blocked" "$(jfield "$out9" outcome)" "missing branch -> blocked"
assert_eq "missing_args" "$(jfield "$out9" reason)" "missing branch -> reason=missing_args"
assert_eq "2" "$rc9" "missing required arg returns 2"

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
