#!/usr/bin/env bash
# Test suite for global/skills/_internal/issue-work/scripts/triage.sh
# Run: bash tests/issue-work/test-triage.sh
#
# Drives the triage state machine end-to-end against a fake gh (fake-gh.sh) and
# exercises every issue #829 acceptance criterion plus the verification matrix.
#
# AC -> test mapping (see reference/triage-state-machine.md):
#   AC1  oversized + no children + plan          -> creates children + 1 summary, decomposed
#   AC2  oversized parent + eligible open child  -> selects child, no decompose comment, proceed
#   AC3  documented unchanged blocker            -> no additional comment on rerun
#   AC4  changed blocker                         -> exactly one updated comment
#   AC5  new human info before blocked decision  -> re-evaluated, flips blocked->proceed
#   AC6  partial child creation                  -> rerun creates only the missing child
#   AC7  claim race                              -> advances to the next eligible child
#   AC8  only-closed children                    -> completion audit (skipped), not a closed pick
#   AC9  blocked/decomposed do no repo work      -> no assign/create on blocked, terminal outcomes
#   VER  batch reporting                         -> decomposition is not a merge success (doc guard)
#   VER  cyclic relationships                    -> visited guard terminates the traversal
#   VER  max depth                               -> depth guard yields failed, not an infinite loop

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
TRIAGE="$ROOT_DIR/global/skills/_internal/issue-work/scripts/triage.sh"
FAKE_SRC="$ROOT_DIR/tests/issue-work/fake-gh.sh"
BATCH_MODE_DOC="$ROOT_DIR/global/skills/_internal/issue-work/reference/batch-mode.md"

PASS=0
FAIL=0
ERRORS=()

WORK="$(mktemp -d)"
# A committed gh shadow lets triage.sh call "$GH_BIN" directly.
GHBIN="$WORK/gh"
cp "$FAKE_SRC" "$GHBIN"
chmod +x "$GHBIN"
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

# Fresh fixture directory for one scenario.
newfix() {
    local d; d="$(mktemp -d "$WORK/fix.XXXXXX")"
    printf 'me' > "$d/user"
    printf '' > "$d/mutations.log"
    printf '%s' "$d"
}

# Run the triage CLI against a fixture, print the final JSON line.
run() {
    local fix="$1"; shift
    GH_BIN="$GHBIN" FAKE_GH_DIR="$fix" TRIAGE_CURRENT_USER="me" \
        bash "$TRIAGE" --repo test/repo "$@" 2>/dev/null | grep -E '^\{' | tail -n1
}

jfield() {  # jfield <json> <field>
    printf '%s' "$1" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],""))' "$2" 2>/dev/null
}

count_log() {  # count_log <fixture> <verb>
    grep -c "^$2 " "$1/mutations.log" 2>/dev/null | tr -d ' '
}

issue_json() {  # issue_json <num> <state> <labels-json> <assignees-json> <body>
    printf '{"number":%s,"title":"issue %s","state":"%s","body":"%s","labels":%s,"assignees":%s,"createdAt":"2026-01-01T00:00:00Z"}' \
        "$1" "$1" "$2" "$5" "$3" "$4"
}

echo "=== triage.sh unit tests (pure functions) ==="
# shellcheck disable=SC1090
source "$TRIAGE"

# triage_hash: deterministic and input-sensitive.
h1="$(printf 'abc' | triage_hash)"; h2="$(printf 'abc' | triage_hash)"
h3="$(printf 'abd' | triage_hash)"
assert_eq "$h1" "$h2" "triage_hash is deterministic"
if [ "$h1" != "$h3" ]; then ok "triage_hash differs on different input"; else
    bad "triage_hash collided on different input"; fi

# triage_extract_blockers.
blk="$(triage_extract_blockers 'text Blocked by #12 and Depends on #7 more')"
assert_eq "$(printf '7\n12')" "$blk" "triage_extract_blockers finds both refs, sorted"
assert_eq "" "$(triage_extract_blockers 'no refs here')" "triage_extract_blockers empty when none"

# triage_priority_rank.
assert_eq "0" "$(triage_priority_rank 'priority/critical,type/bug')" "rank critical=0"
assert_eq "2" "$(triage_priority_rank 'priority/medium')" "rank medium=2"
assert_eq "4" "$(triage_priority_rank 'type/bug')" "rank unlabeled=4"

# triage_is_eligible truth table.
if triage_is_eligible OPEN false false false false; then ok "eligible when all clear"; else
    bad "eligible-all-clear should pass"; fi
if triage_is_eligible CLOSED false false false false; then bad "closed must be ineligible"; else
    ok "closed is ineligible"; fi
if triage_is_eligible OPEN true false false false; then bad "blocked must be ineligible"; else
    ok "blocked is ineligible"; fi
if triage_is_eligible OPEN false true false false; then bad "assigned-other must be ineligible"; else
    ok "assigned-other is ineligible"; fi
if triage_is_eligible OPEN false false true false; then bad "active-PR must be ineligible"; else
    ok "active-PR is ineligible"; fi
if triage_is_eligible OPEN false false false true; then bad "visited must be ineligible"; else
    ok "visited is ineligible"; fi

# triage_comment_marker matchers.
raw='body text <!-- triage-fingerprint: blocked:abc123 --> tail'
if triage_comment_marker_matches "$raw" blocked abc123; then ok "marker matches equal fingerprint"; else
    bad "marker should match equal fingerprint"; fi
if triage_comment_marker_matches "$raw" blocked zzz999; then bad "marker must not match differing fingerprint"; else
    ok "marker rejects differing fingerprint"; fi
if triage_comment_marker_present "$raw" blocked; then ok "marker presence detected"; else
    bad "marker presence should be detected"; fi
if triage_comment_marker_present "$raw" decompose; then bad "absent kind should not be present"; else
    ok "absent marker kind reported absent"; fi

echo ""
echo "=== AC1: oversized + no children + plan -> decomposed (create + 1 summary) ==="
fix="$(newfix)"
issue_json 1 OPEN '[{"name":"size/XL"}]' '[]' 'Big epic' > "$fix/issue-1.json"
printf '[]' > "$fix/children-1.json"
printf 'child alpha\nchild beta\n' > "$fix/plan.txt"
out="$(run "$fix" --issue 1 --plan-file "$fix/plan.txt")"
assert_eq "decomposed" "$(jfield "$out" outcome)" "AC1 outcome=decomposed"
assert_eq "2" "$(count_log "$fix" CREATE)" "AC1 created 2 children"
assert_eq "1" "$(count_log "$fix" COMMENT)" "AC1 posted exactly one parent summary"
assert_eq "0" "$(count_log "$fix" ASSIGN)" "AC1 made no assignment (no code work)"

echo ""
echo "=== AC2: oversized parent + eligible open child -> proceed on child ==="
fix="$(newfix)"
issue_json 10 OPEN '[{"name":"size/XL"}]' '[]' 'Parent epic' > "$fix/issue-10.json"
issue_json 11 OPEN '[{"name":"size/S"}]' '[]' 'Child work' > "$fix/issue-11.json"
printf '[{"number":11,"title":"Child work","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]' > "$fix/children-10.json"
out="$(run "$fix" --issue 10)"
assert_eq "proceed" "$(jfield "$out" outcome)" "AC2 outcome=proceed"
assert_eq "11" "$(jfield "$out" active)" "AC2 active=child #11"
assert_eq "0" "$(count_log "$fix" CREATE)" "AC2 created no children"
assert_eq "0" "$(count_log "$fix" COMMENT)" "AC2 posted no decomposition comment"

echo ""
echo "=== AC3: documented unchanged blocker -> no extra comment on rerun ==="
fix="$(newfix)"
issue_json 20 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21' > "$fix/issue-20.json"
issue_json 21 OPEN '[]' '[]' 'dependency' > "$fix/issue-21.json"
out="$(run "$fix" --issue 20)"
assert_eq "blocked" "$(jfield "$out" outcome)" "AC3 first run outcome=blocked"
assert_eq "1" "$(count_log "$fix" COMMENT)" "AC3 first run posts one blocked comment"
out2="$(run "$fix" --issue 20)"   # rerun, blocker unchanged, marker now present
assert_eq "blocked" "$(jfield "$out2" outcome)" "AC3 rerun still blocked"
assert_eq "1" "$(count_log "$fix" COMMENT)" "AC3 rerun posts no additional comment"

echo ""
echo "=== AC4: changed blocker -> exactly one updated comment ==="
fix="$(newfix)"
issue_json 30 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21' > "$fix/issue-30.json"
issue_json 21 OPEN '[]' '[]' 'dep one' > "$fix/issue-21.json"
run "$fix" --issue 30 >/dev/null                        # run1: posts comment fp1
assert_eq "1" "$(count_log "$fix" COMMENT)" "AC4 first run posts one comment"
issue_json 30 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21 Depends on #22' > "$fix/issue-30.json"
issue_json 22 OPEN '[]' '[]' 'dep two' > "$fix/issue-22.json"
out="$(run "$fix" --issue 30)"                          # run2: blocker set changed -> fp2
assert_eq "blocked" "$(jfield "$out" outcome)" "AC4 rerun outcome=blocked"
assert_eq "2" "$(count_log "$fix" COMMENT)" "AC4 changed blocker adds exactly one comment"

echo ""
echo "=== AC5: new human info evaluated before keeping blocked -> flips to proceed ==="
fix="$(newfix)"
issue_json 40 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #41' > "$fix/issue-40.json"
issue_json 41 OPEN '[]' '[]' 'dependency' > "$fix/issue-41.json"
out="$(run "$fix" --issue 40)"
assert_eq "blocked" "$(jfield "$out" outcome)" "AC5 initially blocked"
issue_json 41 CLOSED '[]' '[]' 'dependency resolved' > "$fix/issue-41.json"   # human resolves blocker
out2="$(run "$fix" --issue 40)"
assert_eq "proceed" "$(jfield "$out2" outcome)" "AC5 fresh blocker state flips to proceed"
assert_eq "40" "$(jfield "$out2" active)" "AC5 proceeds on the unblocked issue"

echo ""
echo "=== AC6: partial child creation -> rerun creates only the missing child ==="
fix="$(newfix)"
issue_json 50 OPEN '[{"name":"size/XL"}]' '[]' 'Epic' > "$fix/issue-50.json"
printf '[{"number":51,"title":"child alpha","state":"OPEN","labels":[],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]' > "$fix/children-50.json"
printf 'child alpha\nchild beta\n' > "$fix/plan.txt"
out="$(run "$fix" --issue 50 --plan-file "$fix/plan.txt")"
assert_eq "decomposed" "$(jfield "$out" outcome)" "AC6 outcome=decomposed"
assert_eq "1" "$(count_log "$fix" CREATE)" "AC6 creates only the missing child"
assert_contains "child beta" "$(cat "$fix/mutations.log")" "AC6 creates the beta child specifically"

echo ""
echo "=== AC7: claim race -> advance to the next eligible child ==="
fix="$(newfix)"
issue_json 60 OPEN '[{"name":"size/XL"}]' '[]' 'Parent' > "$fix/issue-60.json"
issue_json 61 OPEN '[{"name":"size/S"}]' '[]' 'first child' > "$fix/issue-61.json"
# Post-claim swap: #61 turns out assigned to someone else (race lost).
issue_json 61 OPEN '[{"name":"size/S"}]' '[{"login":"other"}]' 'first child' > "$fix/issue-61.postclaim.json"
issue_json 62 OPEN '[{"name":"size/S"}]' '[]' 'second child' > "$fix/issue-62.json"
printf '[{"number":61,"title":"first child","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"},{"number":62,"title":"second child","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]' > "$fix/children-60.json"
out="$(run "$fix" --issue 60)"
assert_eq "proceed" "$(jfield "$out" outcome)" "AC7 recovers to proceed"
assert_eq "62" "$(jfield "$out" active)" "AC7 advances to the second child after losing the race"

echo ""
echo "=== AC8: only-closed children -> completion audit (skipped), not a closed pick ==="
fix="$(newfix)"
issue_json 70 OPEN '[{"name":"size/XL"}]' '[]' 'Parent all done' > "$fix/issue-70.json"
printf '[{"number":71,"title":"done a","state":"CLOSED","labels":[],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"},{"number":72,"title":"done b","state":"CLOSED","labels":[],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]' > "$fix/children-70.json"
out="$(run "$fix" --issue 70)"
assert_eq "skipped" "$(jfield "$out" outcome)" "AC8 outcome=skipped"
assert_contains "completion audit" "$(jfield "$out" reason)" "AC8 reason names the completion audit"
assert_eq "0" "$(count_log "$fix" ASSIGN)" "AC8 never claims a closed child"

echo ""
echo "=== AC9: blocked/decomposed perform no repository work ==="
fix="$(newfix)"
issue_json 80 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #81' > "$fix/issue-80.json"
issue_json 81 OPEN '[]' '[]' 'dep' > "$fix/issue-81.json"
out="$(run "$fix" --issue 80)"
assert_eq "blocked" "$(jfield "$out" outcome)" "AC9 blocked terminal"
assert_eq "0" "$(count_log "$fix" ASSIGN)" "AC9 blocked makes no assignment"
assert_eq "0" "$(count_log "$fix" CREATE)" "AC9 blocked creates no branch/child"

echo ""
echo "=== VER: cyclic relationship terminates via visited guard ==="
fix="$(newfix)"
issue_json 90 OPEN '[{"name":"size/XL"}]' '[]' 'A' > "$fix/issue-90.json"
issue_json 91 OPEN '[{"name":"size/XL"}]' '[]' 'B' > "$fix/issue-91.json"
# 90 -> 91 -> 90 cycle.
printf '[{"number":91,"title":"B","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]' > "$fix/children-90.json"
printf '[{"number":90,"title":"A","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-01T00:00:00Z"}]' > "$fix/children-91.json"
out="$(run "$fix" --issue 90)"
cyc_outcome="$(jfield "$out" outcome)"
if [ "$cyc_outcome" = "skipped" ] || [ "$cyc_outcome" = "failed" ]; then
    ok "VER cycle terminates with a terminal outcome ($cyc_outcome)"
else
    bad "VER cycle should terminate, got '$cyc_outcome'"
fi

echo ""
echo "=== VER: max-depth guard yields failed, not an infinite descent ==="
fix="$(newfix)"
# Chain 100 -> 101 -> 102 -> 103, each oversized with one deeper child.
for n in 100 101 102 103; do
    issue_json "$n" OPEN '[{"name":"size/XL"}]' '[]' "node $n" > "$fix/issue-$n.json"
done
printf '[{"number":101,"title":"n101","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]' > "$fix/children-100.json"
printf '[{"number":102,"title":"n102","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]' > "$fix/children-101.json"
printf '[{"number":103,"title":"n103","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-04T00:00:00Z"}]' > "$fix/children-102.json"
printf '[]' > "$fix/children-103.json"
out="$(run "$fix" --issue 100 --max-depth 2)"
assert_eq "failed" "$(jfield "$out" outcome)" "VER max-depth guard yields failed"
assert_contains "MAX_CHILD_DEPTH" "$(jfield "$out" reason)" "VER failure names the depth guard"

echo ""
echo "=== VER: batch reporting does not treat decomposition as a merge success ==="
if grep -Fq "only \`Merged\` items count as successes" "$BATCH_MODE_DOC"; then
    ok "VER batch-mode doc asserts only merged items are successes"
else
    bad "VER batch-mode doc missing the merge-success accounting guard"
fi

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
