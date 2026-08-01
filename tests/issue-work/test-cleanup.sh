#!/usr/bin/env bash
# Test suite for global/skills/_internal/issue-work/scripts/cleanup-workspace.sh
# Run: bash tests/issue-work/test-cleanup.sh
#
# Drives the resume-reconciliation + safe-cleanup stage
# (PUSHED -> ... -> MERGED -> CLEANUP_PENDING -> CLEANED) against a real local
# bare git repository plus a fake gh (fake-gh.sh) for the PR-state reads that
# reconciliation performs. Sourcing cleanup-workspace.sh also loads
# workspace.sh, so the #838 manifest primitive (workspace_manifest_*) is
# available for assertions.
#
# AC -> test mapping (see reference/workspace-lifecycle.md, #840 sections):
#   AC1  cleanup safety predicate  -> traversal / symlink / basename / marker /
#                                     base / root / home are each REFUSED
#   AC2  git-state gate            -> tracked change / untracked / conflict REFUSED
#   AC3  remotely-recoverable      -> unpushed REFUSED; pushed OK; squash-merge OK
#   AC4  agents-terminated gate    -> a surviving .iw-writer.lease REFUSED
#   AC5  resume reconciliation      -> a MERGED PR repairs state to MERGED even
#                                     when the manifest stored PR_OPEN
#   AC6  3-fail preservation        -> failing remover retries exactly 3x, run
#                                     root survives, manifest not CLEANED, a
#                                     manual-procedure message names the path
#   AC7  happy path                 -> MERGED + clean + recoverable + no agents +
#                                     valid path emits CLEANED, run root removed
#   AC8  credential redaction       -> a git error carrying a fake token never
#                                     appears in output or the manifest

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
CLEANUP="$ROOT_DIR/global/skills/_internal/issue-work/scripts/cleanup-workspace.sh"
FAKE_SRC="$ROOT_DIR/tests/issue-work/fake-gh.sh"

PASS=0
FAIL=0
ERRORS=()

# Explicit template (rather than a bare `mktemp -d`) so this suite is stable
# under sandboxes that restrict the OS default temp directory but expose
# $TMPDIR, as well as under plain CI runners where $TMPDIR is unset.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iw-cleanup-test.XXXXXX")"
# Resolve symlinks + collapse // so derived paths match git's and realpath's own
# canonicalization on macOS, whose default $TMPDIR (/var/folders/...) is a
# symlink to /private/var/... The path-prefix / marker / TOCTOU checks compare
# canonicalized paths, so $WORK must be canonical too or every comparison would
# spuriously mismatch. Canonicalize -- never weaken the assertions.
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# A committed gh shadow (fake-gh.sh is tracked mode 644) copied to an executable
# path lets cleanup-workspace.sh call "$GH_BIN" directly via the GH_BIN seam.
FAKE_GH="$WORK/gh"
cp "$FAKE_SRC" "$FAKE_GH"
chmod +x "$FAKE_GH"

# Fast, deterministic retry loop: skip the real inter-retry sleep.
export CLEANUP_RETRY_SLEEP=0

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

# --- Fake credential material (secret-scanner-safe) --------------------
# A low-entropy, clearly-fake secret with NO real token prefix. Credential URLs
# are assembled from it at runtime, so no complete "scheme://user:secret@host"
# literal is ever committed to source (GitGuardian scans history).
FAKE_SECRET="placeholder-not-a-real-secret"
FAKE_USERINFO="x-access-token:${FAKE_SECRET}"

# Builds a bare "remote" under $WORK/remote seeded with one commit on a
# "develop" branch, and prints the bare repo path.
make_remote() {  # make_remote <name>
    local name="$1" remote seed
    remote="$WORK/remote/${name}.git"
    mkdir -p "$(dirname "$remote")"
    git init --bare -q "$remote"
    seed="$WORK/seed-${name}"
    git init -q -b develop "$seed"
    git -C "$seed" config user.email "test@example.com"
    git -C "$seed" config user.name "test"
    echo "content" > "$seed/file.txt"
    git -C "$seed" add file.txt
    git -C "$seed" commit -q -m "seed commit" >/dev/null
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q origin develop
    printf '%s' "$remote"
}

# Clones a remote into <dest> tracking develop, sets a test identity, prints dest.
clone_repo() {  # clone_repo <remote> <dest>
    local remote="$1" dest="$2"
    git clone -q --branch develop --single-branch "$remote" "$dest"
    git -C "$dest" config user.email "test@example.com"
    git -C "$dest" config user.name "test"
    printf '%s' "$dest"
}

# Materializes a valid run root under <base> for the given issue: creates the
# run root, a valid .iw-run-marker, a clone at <run_root>/repo, and a manifest.
# Prints the run root path.
make_run_root() {  # make_run_root <base> <issue> <suffix> <remote>
    local base="$1" issue="$2" suffix="$3" remote="$4" run_root marker
    run_root="$base/iw-${issue}-${suffix}"
    mkdir -p "$run_root"
    marker="$run_root/.iw-run-marker"
    printf 'issue=%s\ncreated=%s\n' "$issue" "2026-07-18T00:00:00Z" > "$marker"
    clone_repo "$remote" "$run_root/repo" >/dev/null
    workspace_manifest_write "$run_root/manifest" issue "$issue"
    workspace_manifest_write "$run_root/manifest" run_root "$run_root"
    printf '%s' "$run_root"
}

echo "=== cleanup-workspace.sh unit + scenario tests ==="
# shellcheck disable=SC1090
source "$CLEANUP"

BASE="$WORK/base"
mkdir -p "$BASE"
REMOTE="$(make_remote acme)"

echo ""
echo "=== AC1: cleanup safety predicate -- each unsafe candidate is REFUSED ==="
# A genuinely valid run root, used as the positive control.
valid_root="$(make_run_root "$BASE" 840 valid "$REMOTE")"
if cleanup_validate_path "$valid_root" "$BASE" 840; then
    ok "AC1 a valid run root passes the safety predicate"; else
    bad "AC1 a valid run root should pass -- ${CLEANUP_LAST_ERROR:-}"; fi

if cleanup_validate_path "" "$BASE" 840; then bad "AC1 empty candidate must be refused"; else
    ok "AC1 empty candidate refused"; fi
if cleanup_validate_path "/" "$BASE" 840; then bad "AC1 filesystem root must be refused"; else
    ok "AC1 filesystem root refused"; fi
if cleanup_validate_path "$HOME" "$BASE" 840; then bad "AC1 home directory must be refused"; else
    ok "AC1 home directory refused"; fi
# The base itself: give the base an iw-840-* name + marker so it clears the
# basename/marker gates, proving the strictly-under-base guard is what refuses it.
base_named="$WORK/iw-840-baseonly"
mkdir -p "$base_named"
printf 'issue=840\n' > "$base_named/.iw-run-marker"
if cleanup_validate_path "$base_named" "$base_named" 840; then
    bad "AC1 the base itself must be refused (never strictly under itself)"; else
    ok "AC1 the base itself refused"; fi
# Traversal in the raw candidate.
if cleanup_validate_path "$BASE/../iw-840-x" "$BASE" 840; then
    bad "AC1 a '..' traversal must be refused"; else
    ok "AC1 '..' traversal refused"; fi
# Basename does not match iw-840-*.
wrong_name="$BASE/notarun-840"
mkdir -p "$wrong_name"
printf 'issue=840\n' > "$wrong_name/.iw-run-marker"
if cleanup_validate_path "$wrong_name" "$BASE" 840; then
    bad "AC1 a basename not matching iw-840-* must be refused"; else
    ok "AC1 basename not matching iw-840-* refused"; fi
# Missing marker.
no_marker="$BASE/iw-840-nomarker"
mkdir -p "$no_marker"
if cleanup_validate_path "$no_marker" "$BASE" 840; then
    bad "AC1 a run root missing its marker must be refused"; else
    ok "AC1 missing marker refused"; fi
# Marker names the wrong issue.
wrong_issue="$BASE/iw-840-wrongissue"
mkdir -p "$wrong_issue"
printf 'issue=999\n' > "$wrong_issue/.iw-run-marker"
if cleanup_validate_path "$wrong_issue" "$BASE" 840; then
    bad "AC1 a marker naming a different issue must be refused"; else
    ok "AC1 marker naming the wrong issue refused"; fi
# Symlinked run root (swap attack): the final component is itself a symlink.
sym_root="$BASE/iw-840-symlink"
ln -s "$valid_root" "$sym_root"
if cleanup_validate_path "$sym_root" "$BASE" 840; then
    bad "AC1 a symlinked run root must be refused (swap attack)"; else
    ok "AC1 symlinked run root refused"; fi

echo ""
echo "=== AC2: git-state gate -- dirty tree or unresolved conflict is REFUSED ==="
gs_root="$(make_run_root "$BASE" 840 gitstate "$REMOTE")"
gs_repo="$gs_root/repo"
if cleanup_git_state_clean "$gs_repo"; then ok "AC2 a fresh clone is clean"; else
    bad "AC2 a fresh clone should be clean -- ${CLEANUP_LAST_ERROR:-}"; fi
# Tracked modification.
echo "changed" >> "$gs_repo/file.txt"
if cleanup_git_state_clean "$gs_repo"; then bad "AC2 a tracked modification must be refused"; else
    ok "AC2 tracked modification refused"; fi
git -C "$gs_repo" checkout -q -- file.txt
# Untracked file.
echo "new" > "$gs_repo/untracked.txt"
if cleanup_git_state_clean "$gs_repo"; then bad "AC2 an untracked file must be refused"; else
    ok "AC2 untracked file refused"; fi
rm -f "$gs_repo/untracked.txt"
if cleanup_git_state_clean "$gs_repo"; then ok "AC2 tree is clean again after reverting"; else
    bad "AC2 tree should be clean after reverting -- ${CLEANUP_LAST_ERROR:-}"; fi
# Unresolved conflict: stage conflicting index entries directly.
cf_repo="$WORK/conflict-repo"
git init -q -b develop "$cf_repo"
git -C "$cf_repo" config user.email "test@example.com"
git -C "$cf_repo" config user.name "test"
echo base > "$cf_repo/c.txt"; git -C "$cf_repo" add c.txt; git -C "$cf_repo" commit -q -m base
git -C "$cf_repo" checkout -q -b other
echo theirs > "$cf_repo/c.txt"; git -C "$cf_repo" add c.txt; git -C "$cf_repo" commit -q -m theirs
git -C "$cf_repo" checkout -q develop
echo ours > "$cf_repo/c.txt"; git -C "$cf_repo" add c.txt; git -C "$cf_repo" commit -q -m ours
git -C "$cf_repo" merge other >/dev/null 2>&1 || true
if cleanup_git_state_clean "$cf_repo"; then bad "AC2 an unresolved conflict must be refused"; else
    ok "AC2 unresolved conflict refused"; fi

echo ""
echo "=== AC3: remotely-recoverable -- unpushed REFUSED; pushed OK; squash-merge OK ==="
# Pushed HEAD: a fresh clone's HEAD == origin/develop, contained in a remote ref.
rc_root="$(make_run_root "$BASE" 840 recover "$REMOTE")"
rc_repo="$rc_root/repo"
if cleanup_remotely_recoverable "$rc_repo"; then ok "AC3 pushed HEAD is recoverable"; else
    bad "AC3 pushed HEAD should be recoverable -- ${CLEANUP_LAST_ERROR:-}"; fi
# Unpushed commit on top of develop.
echo "local work" >> "$rc_repo/file.txt"
git -C "$rc_repo" add file.txt
git -C "$rc_repo" commit -q -m "unpushed local work"
if cleanup_remotely_recoverable "$rc_repo"; then
    bad "AC3 an unpushed commit must be refused"; else
    ok "AC3 unpushed commit refused"; fi
# Squash-merge: local feature commit is NOT an ancestor of the merge commit, but
# the merge commit landed on origin/develop, so (c) deems it recoverable.
sq_remote="$(make_remote squash)"
sq_repo="$WORK/squash-repo"
clone_repo "$sq_remote" "$sq_repo" >/dev/null
git -C "$sq_repo" checkout -q -b feat/issue-840-x
echo "feature" >> "$sq_repo/file.txt"
git -C "$sq_repo" add file.txt
git -C "$sq_repo" commit -q -m "feature work (never pushed as-is)"
# Advance origin/develop with a separate 'merge' commit via the seed clone.
git -C "$WORK/seed-squash" checkout -q develop
echo "merged squashed change" >> "$WORK/seed-squash/file.txt"
git -C "$WORK/seed-squash" add file.txt
git -C "$WORK/seed-squash" commit -q -m "squash merge of #840"
git -C "$WORK/seed-squash" push -q origin develop
merge_commit="$(git -C "$WORK/seed-squash" rev-parse HEAD)"
git -C "$sq_repo" fetch -q origin
if cleanup_remotely_recoverable "$sq_repo"; then
    bad "AC3 without the merge commit the feature work looks unrecoverable"; else
    ok "AC3 feature branch alone is not recoverable (precondition)"; fi
if cleanup_remotely_recoverable "$sq_repo" "$merge_commit"; then
    ok "AC3 squash-merge is recoverable via the merge commit on origin/develop"; else
    bad "AC3 squash-merge should be recoverable -- ${CLEANUP_LAST_ERROR:-}"; fi

echo ""
echo "=== AC4: agents-terminated -- a surviving lease is REFUSED ==="
ag_root="$(make_run_root "$BASE" 840 agents "$REMOTE")"
if cleanup_agents_terminated "$ag_root"; then ok "AC4 no lease -> agents terminated"; else
    bad "AC4 a fresh run root should have no lease -- ${CLEANUP_LAST_ERROR:-}"; fi
mkdir -p "$ag_root/repo/.iw-writer.lease"
if cleanup_agents_terminated "$ag_root"; then
    bad "AC4 a surviving .iw-writer.lease must be refused"; else
    ok "AC4 surviving lease refused"; fi
rmdir "$ag_root/repo/.iw-writer.lease"

echo ""
echo "=== AC5: resume reconciliation -- a MERGED PR wins over a stored PR_OPEN ==="
# Exported so the fake-gh.sh child process (spawned inside cleanup_reconcile via
# the GH_BIN seam) sees it; an inline assignment before a shell *function* call
# is not exported to grandchild processes.
export FAKE_GH_DIR="$WORK/fakegh"
mkdir -p "$FAKE_GH_DIR"
rec_root="$(make_run_root "$BASE" 840 reconcile "$REMOTE")"
rec_repo="$rec_root/repo"
rec_manifest="$rec_root/manifest"
# Stored state deliberately stale: PR_OPEN even though the PR has since merged.
workspace_manifest_write "$rec_manifest" state PR_OPEN
mc="$(git -C "$rec_repo" rev-parse HEAD)"
cat > "$FAKE_GH_DIR/pr-view-77.json" <<EOF
{"state":"MERGED","mergedAt":"2026-07-18T01:00:00Z","mergeCommit":{"oid":"${mc}"},"headRefName":"feat/issue-840-x"}
EOF
rec_out="$(GH_BIN="$FAKE_GH" FAKE_GH_DIR="$FAKE_GH_DIR" cleanup_reconcile "$rec_repo" "$rec_manifest" 77)"
assert_contains '"state":"MERGED"' "$rec_out" "AC5 reconcile emits MERGED (reality wins over stored PR_OPEN)"
assert_eq "MERGED" "$(workspace_manifest_state "$rec_manifest")" "AC5 manifest repaired to MERGED"
assert_eq "$mc" "$(workspace_manifest_read "$rec_manifest" merge_commit)" "AC5 reconcile records the merge commit"
assert_eq "$mc" "$(workspace_manifest_read "$rec_manifest" head)" "AC5 reconcile records the live HEAD"

echo ""
echo "=== AC6: 3-fail preservation -- failing remover retries 3x, then preserves ==="
fail_root="$(make_run_root "$BASE" 840 threefail "$REMOTE")"
fail_repo="$fail_root/repo"
fail_manifest="$fail_root/manifest"
workspace_manifest_write "$fail_manifest" state MERGED
# A remover that always fails and counts its invocations.
fail_rm="$WORK/failing-rm.sh"
rm_count="$WORK/rm-count"
: > "$rm_count"
cat > "$fail_rm" <<EOF
#!/usr/bin/env bash
echo x >> "$rm_count"
exit 1
EOF
chmod +x "$fail_rm"
mc_fail="$(git -C "$fail_repo" rev-parse HEAD)"
fail_out="$(CLEANUP_RM="$fail_rm" cleanup_workspace "$fail_root" "$fail_repo" "$fail_manifest" "$BASE" 840 "$mc_fail" 2>&1)"
attempts="$(wc -l < "$rm_count" | tr -d ' ')"
assert_eq "3" "$attempts" "AC6 the failing remover is retried exactly 3 times (retry cap honored)"
if [ -d "$fail_root" ]; then ok "AC6 the run root survives a failed cleanup"; else
    bad "AC6 the run root must survive a failed cleanup"; fi
assert_contains "PRESERVED" "$fail_out" "AC6 outcome is PRESERVED"
assert_contains "MANUAL CLEANUP REQUIRED" "$fail_out" "AC6 a manual-procedure message is printed"
assert_contains "$fail_root" "$fail_out" "AC6 the manual procedure names the exact validated path"
if [ "$(workspace_manifest_state "$fail_manifest")" = "CLEANED" ]; then
    bad "AC6 the manifest must not read CLEANED after a failed cleanup"; else
    ok "AC6 manifest is not CLEANED after a failed cleanup"; fi

echo ""
echo "=== AC7: happy path -- MERGED + clean + recoverable + no agents removes root ==="
happy_root="$(make_run_root "$BASE" 840 happy "$REMOTE")"
happy_repo="$happy_root/repo"
happy_manifest="$happy_root/manifest"
# Use a manifest override OUTSIDE the run root so the terminal state survives the
# removal and can be asserted (the in-root manifest would be gone).
happy_ext_manifest="$WORK/happy-ext-manifest"
workspace_manifest_write "$happy_ext_manifest" state MERGED
happy_mc="$(git -C "$happy_repo" rev-parse HEAD)"
happy_out="$(cleanup_workspace "$happy_root" "$happy_repo" "$happy_ext_manifest" "$BASE" 840 "$happy_mc")"
assert_contains '"state":"CLEANED"' "$happy_out" "AC7 happy path emits CLEANED"
if [ -e "$happy_root" ]; then bad "AC7 the run root must be removed on the happy path"; else
    ok "AC7 run root removed on the happy path"; fi
assert_eq "CLEANED" "$(workspace_manifest_state "$happy_ext_manifest")" "AC7 external manifest persists CLEANED"

# Guard: cleanup before MERGED is refused (incomplete PR preservation case).
early_root="$(make_run_root "$BASE" 840 early "$REMOTE")"
workspace_manifest_write "$early_root/manifest" state PR_OPEN
early_out="$(cleanup_workspace "$early_root" "$early_root/repo" "$early_root/manifest" "$BASE" 840)"
assert_contains "PRESERVED" "$early_out" "AC7 cleanup before MERGED is refused"
if [ -d "$early_root" ]; then ok "AC7 the run root survives a pre-MERGED cleanup attempt"; else
    bad "AC7 the run root must survive a pre-MERGED cleanup attempt"; fi

echo ""
echo "=== AC8: credential redaction -- a git error carrying a fake token is scrubbed ==="
# A git shim whose branch lookup emits a credential-bearing URL, mimicking a
# credential leaking through git output. reconcile writes/emits branch + head;
# both must be redacted before they reach stdout or the manifest.
tok_git="$WORK/fake-git-token.sh"
cat > "$tok_git" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *"rev-parse --abbrev-ref HEAD"*) echo "https://${FAKE_USERINFO}@github.com/acme/x.git" ;;
    *"rev-parse HEAD"*)              echo "deadbeefcafe" ;;
    *)                               exit 0 ;;
esac
EOF
chmod +x "$tok_git"
tok_manifest="$WORK/token-manifest"
workspace_manifest_write "$tok_manifest" state PUSHED
tok_out="$(GIT_BIN="$tok_git" cleanup_reconcile "$WORK" "$tok_manifest")"
assert_not_contains "$FAKE_SECRET" "$tok_out" "AC8 reconcile stdout never contains the fake token"
assert_not_contains "$FAKE_SECRET" "$(cat "$tok_manifest")" "AC8 the manifest never contains the fake token"

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
