#!/usr/bin/env bash
# Test suite for global/skills/_internal/issue-work/scripts/workspace.sh
# Run: bash tests/issue-work/test-workspace.sh
#
# Drives the workspace lifecycle stage (CLAIMED -> CLONING -> READY) against
# a real local bare git repository -- no fake gh/git shim is needed because
# this stage never calls gh, and driving real git exercises the actual clone
# and remote-identity codepaths instead of a stand-in.
#
# AC -> test mapping (see reference/workspace-lifecycle.md):
#   AC1  run root layout       -> under temp base, uniquely named, valid marker
#   AC2  clone -> READY        -> develop clone reaches READY with correct baseline sha
#   AC3  identity mismatch     -> REJECTED, never reaches READY
#   AC4  credential redaction  -> manifest and stdout never contain a token
#   AC5  manifest atomicity    -> key=value round-trips via read; no tmp leftovers
#   UNIT pure-function coverage -> redact / verify_identity / manifest write+read

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
WORKSPACE="$ROOT_DIR/global/skills/_internal/issue-work/scripts/workspace.sh"

PASS=0
FAIL=0
ERRORS=()

# Explicit template (rather than a bare `mktemp -d`) so this suite is stable
# under sandboxes that restrict the OS default temp directory but expose
# $TMPDIR, as well as under plain CI runners where $TMPDIR is unset.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iw-workspace-test.XXXXXX")"
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

# Builds a bare "remote" laid out as <owner>/<name>.git under $WORK/remote,
# seeds it with one commit on a "develop" branch, and prints the bare repo
# path (used as --clone-url so the origin recorded after cloning reduces to
# "<owner>/<name>", matching workspace_verify_identity's expectations).
make_remote() {  # make_remote <owner> <name>
    local owner="$1" name="$2" remote seed
    remote="$WORK/remote/${owner}/${name}.git"
    mkdir -p "$(dirname "$remote")"
    git init --bare -q "$remote"
    seed="$WORK/seed-${owner}-${name}"
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

echo "=== workspace.sh unit tests (pure functions) ==="
# shellcheck disable=SC1090
source "$WORKSPACE"

# --- Fake credential material (secret-scanner-safe) --------------------
# Redaction is structural (it strips a "scheme://<userinfo>@" span), so the
# placeholder value is irrelevant to what is tested. We use a low-entropy,
# clearly-fake secret with NO real token prefix and assemble credential URLs
# from it, so no complete "scheme://user:secret@host" literal (or token-shaped
# string) is ever committed to source. This satisfies the no-secrets-in-source
# policy and keeps secret scanners (e.g. GitGuardian) quiet.
FAKE_SECRET="placeholder-not-a-real-secret"
FAKE_USERINFO="x-access-token:${FAKE_SECRET}"

# workspace_redact_credentials.
r1="$(workspace_redact_credentials "https://${FAKE_USERINFO}@github.com/owner/name.git")"
assert_eq "https://github.com/owner/name.git" "$r1" "redact strips x-access-token userinfo"
r2="$(workspace_redact_credentials "fatal: unable to access 'https://${FAKE_USERINFO}@host/owner/name.git/': could not resolve")"
assert_not_contains "$FAKE_SECRET" "$r2" "redact strips creds embedded mid-message"
assert_contains "https://host/owner/name.git" "$r2" "redact preserves the scheme and path"
r3="$(workspace_redact_credentials 'plain text, no url here')"
assert_eq "plain text, no url here" "$r3" "redact is a no-op on non-URL input"
r4="$(workspace_redact_credentials 'git@github.com:owner/name.git')"
assert_eq "git@github.com:owner/name.git" "$r4" "redact leaves SSH shorthand untouched (no embedded secret)"

# workspace_run_root.
rr1="$(WORKSPACE_RUN_SUFFIX=abc123 workspace_run_root "$WORK/base" 838)"
assert_eq "$WORK/base/iw-838-abc123" "$rr1" "run_root composes base/iw-<issue>-<suffix>"
rr2="$(WORKSPACE_RUN_SUFFIX=xyz789 workspace_run_root "$WORK/base" 838)"
if [ "$rr1" != "$rr2" ]; then ok "run_root differs when the suffix seam differs"; else
    bad "run_root should differ for a different suffix"; fi

# workspace_manifest_write / workspace_manifest_read round trip + atomicity.
mpath="$WORK/unit-manifest"
workspace_manifest_write "$mpath" state CLAIMED
assert_eq "CLAIMED" "$(workspace_manifest_read "$mpath" state)" "manifest round-trips a fresh key"
workspace_manifest_write "$mpath" state CLONING
assert_eq "CLONING" "$(workspace_manifest_state "$mpath")" "manifest_state reflects the latest write"
assert_eq "1" "$(grep -c '^state=' "$mpath")" "manifest update replaces the key rather than duplicating it"
leftover="$(find "$WORK" -maxdepth 1 -name 'unit-manifest.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$leftover" "manifest write leaves no .tmp.\$\$ file behind"
assert_eq "" "$(workspace_manifest_read "$mpath" nonexistent_key)" "manifest_read is empty for an absent key"

# workspace_manifest_write redacts a credential-bearing value before it ever
# touches disk (AC4, targeted at the manifest half of the guarantee).
workspace_manifest_write "$mpath" origin_seen "https://${FAKE_USERINFO}@github.com/o/n.git"
assert_not_contains "$FAKE_SECRET" "$(cat "$mpath")" "manifest never stores a raw credential"
assert_eq "https://github.com/o/n.git" "$(workspace_manifest_read "$mpath" origin_seen)" "manifest stores the redacted form"

# workspace_verify_identity.
id_repo="$WORK/id-repo"
git init -q "$id_repo"
git -C "$id_repo" remote add origin "https://github.com/acme/widgets.git"
if workspace_verify_identity "$id_repo" "acme/widgets"; then ok "verify_identity accepts a matching https origin"; else
    bad "verify_identity should accept a matching https origin"; fi
if workspace_verify_identity "$id_repo" "someone/else"; then bad "verify_identity must reject a mismatched owner/name"; else
    ok "verify_identity rejects a mismatched owner/name"; fi

git -C "$id_repo" remote set-url origin "git@github.com:acme/widgets.git"
if workspace_verify_identity "$id_repo" "acme/widgets"; then ok "verify_identity accepts a matching SSH-shorthand origin"; else
    bad "verify_identity should accept a matching SSH-shorthand origin"; fi

no_origin_repo="$WORK/no-origin-repo"
git init -q "$no_origin_repo"
if workspace_verify_identity "$no_origin_repo" "acme/widgets"; then bad "verify_identity must reject a repo with no origin"; else
    ok "verify_identity rejects a repo with no origin"; fi

if workspace_verify_identity "$id_repo" ""; then bad "verify_identity must reject an empty expected value"; else
    ok "verify_identity rejects an empty expected value"; fi

echo ""
echo "=== AC1: run root under temp base, uniquely named, valid marker ==="
base1="$WORK/base1"
mkdir -p "$base1"
remote1="$(make_remote acme widgets)"
out1="$(WORKSPACE_RUN_SUFFIX=run1 bash "$WORKSPACE" --repo acme/widgets --base "$base1" --issue 838 --clone-url "$remote1")"
run_root1="$(jfield "$out1" run_root)"
assert_contains "$base1/iw-838-run1" "$run_root1" "AC1 run root is under the temp base with the expected name"
assert_eq "1" "$(find "$run_root1" -maxdepth 1 -name '.iw-run-marker' | wc -l | tr -d ' ')" "AC1 marker file exists in the run root"
assert_contains "issue=838" "$(cat "$run_root1/.iw-run-marker")" "AC1 marker content includes the issue number"

out1b="$(WORKSPACE_RUN_SUFFIX=run1b bash "$WORKSPACE" --repo acme/widgets --base "$base1" --issue 838 --clone-url "$remote1")"
run_root1b="$(jfield "$out1b" run_root)"
if [ "$run_root1" != "$run_root1b" ]; then ok "AC1 two runs for the same issue get uniquely named run roots"; else
    bad "AC1 run roots should differ across runs"; fi

echo ""
echo "=== AC2: clone from develop reaches READY with correct baseline sha ==="
base2="$WORK/base2"
mkdir -p "$base2"
remote2="$(make_remote acme gadgets)"
expected_sha="$(git -C "$WORK/seed-acme-gadgets" rev-parse develop)"
out2="$(WORKSPACE_RUN_SUFFIX=run2 bash "$WORKSPACE" --repo acme/gadgets --base "$base2" --issue 900 --clone-url "$remote2")"
assert_eq "READY" "$(jfield "$out2" state)" "AC2 outcome=READY"
assert_eq "$expected_sha" "$(jfield "$out2" baseline)" "AC2 baseline matches the seeded develop HEAD"
repo_dir2="$(jfield "$out2" repo_dir)"
assert_eq "1" "$(test -f "$repo_dir2/file.txt" && echo 1 || echo 0)" "AC2 clone actually checked out the working tree"
manifest2="$(jfield "$out2" manifest)"
assert_eq "READY" "$(workspace_manifest_state "$manifest2")" "AC2 manifest state reaches READY"
assert_eq "$expected_sha" "$(workspace_manifest_read "$manifest2" baseline)" "AC2 manifest records the baseline"

echo ""
echo "=== AC3: identity/origin mismatch is REJECTED, never reaches READY ==="
base3="$WORK/base3"
mkdir -p "$base3"
remote3="$(make_remote other owner)"
out3="$(WORKSPACE_RUN_SUFFIX=run3 bash "$WORKSPACE" --repo acme/mismatch --base "$base3" --issue 901 --clone-url "$remote3")"
assert_eq "REJECTED" "$(jfield "$out3" state)" "AC3 outcome=REJECTED on identity mismatch"
assert_contains "acme/mismatch" "$(jfield "$out3" reason)" "AC3 reason names the expected repo"
manifest3="$(jfield "$out3" manifest)"
assert_eq "REJECTED" "$(workspace_manifest_state "$manifest3")" "AC3 manifest never advances to READY"
assert_not_contains "READY" "$out3" "AC3 stdout JSON never claims READY"

echo ""
echo "=== AC4: credentials never appear in stdout or the manifest ==="
base4="$WORK/base4"
mkdir -p "$base4"
remote4="$(make_remote acme secure)"
token="$FAKE_SECRET"
out4="$(WORKSPACE_RUN_SUFFIX=run4 bash "$WORKSPACE" --repo acme/secure --base "$base4" --issue 902 \
    --clone-url "$remote4" --manifest "$base4/iw-902-run4/manifest")"
assert_eq "READY" "$(jfield "$out4" state)" "AC4 baseline run reaches READY (sanity precondition)"
assert_not_contains "$token" "$out4" "AC4 stdout never contains the fake token"
assert_not_contains "$token" "$(cat "$base4/iw-902-run4/manifest")" "AC4 manifest never contains the fake token"
# The token above never entered the run at all (defense-in-depth baseline);
# the manifest_write unit test earlier already proves a credential-bearing
# value handed directly to the manifest primitive is redacted before write.

# AC4b: exercise the real clone-failure redaction path (_workspace_clone's
# WORKSPACE_LAST_ERROR handling) without any network access, by shadowing
# git with a local shim (via the GIT_BIN seam) whose "clone" subcommand
# fails and echoes a credential-bearing URL to stderr, mimicking what a real
# git failure against an authenticated remote looks like.
fake_git="$WORK/fake-git-clone-fail"
cat > "$fake_git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "clone" ]; then
    echo "fatal: unable to access 'https://${FAKE_USERINFO}@github.com/acme/failing.git/': Could not resolve host" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$fake_git"
base4b="$WORK/base4b"
mkdir -p "$base4b"
out4b="$(GIT_BIN="$fake_git" WORKSPACE_RUN_SUFFIX=run4b bash "$WORKSPACE" --repo acme/failing --base "$base4b" \
    --issue 903 --clone-url "https://${FAKE_USERINFO}@github.com/acme/failing.git")"
assert_eq "REJECTED" "$(jfield "$out4b" state)" "AC4b clone failure yields REJECTED"
assert_contains "clone failed" "$(jfield "$out4b" reason)" "AC4b reason names the clone failure"
assert_not_contains "$FAKE_SECRET" "$out4b" "AC4b stdout never contains git's own credential-bearing error"
manifest4b="$WORK/base4b/iw-903-run4b/manifest"
assert_not_contains "$FAKE_SECRET" "$(cat "$manifest4b" 2>/dev/null)" "AC4b manifest never contains git's own credential-bearing error"

echo ""
echo "=== AC5: manifest updates are atomic and key=value round-trips ==="
manifest5="$WORK/atomic-manifest"
workspace_manifest_write "$manifest5" a 1
workspace_manifest_write "$manifest5" b 2
workspace_manifest_write "$manifest5" a 3
assert_eq "3" "$(workspace_manifest_read "$manifest5" a)" "AC5 later write for the same key wins"
assert_eq "2" "$(workspace_manifest_read "$manifest5" b)" "AC5 unrelated key is preserved across updates"
assert_eq "2" "$(grep -c '=' "$manifest5")" "AC5 manifest has exactly one line per key"

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
