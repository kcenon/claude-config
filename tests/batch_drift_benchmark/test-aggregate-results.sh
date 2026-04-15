#!/bin/bash
# Test suite for tests/batch_drift_benchmark/aggregate-results.sh
# Run: bash tests/batch_drift_benchmark/test-aggregate-results.sh

SCRIPT="tests/batch_drift_benchmark/aggregate-results.sh"
CLEAN_DIR="tests/batch_drift_benchmark/fixtures/aggregator-clean"
DRIFTED_DIR="tests/batch_drift_benchmark/fixtures/aggregator-drifted"

PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

for p in "$SCRIPT" "$CLEAN_DIR" "$DRIFTED_DIR"; do
    if [ ! -e "$p" ]; then
        echo "ERROR: $p not found"
        exit 1
    fi
done

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected '$expected', got '$actual'")
        echo "  FAIL: $label (expected '$expected', got '$actual')"
    fi
}

run_aggregator() {
    local dir="$1"
    bash "$SCRIPT" \
        --strategy subagent \
        --started-at "2026-04-15T10:00:00Z" \
        --completed-at "2026-04-15T11:00:00Z" \
        "$dir"
}

echo "=== aggregate-results.sh tests ==="
echo ""

echo "[flag parsing]"
help_out=$(bash "$SCRIPT" --help 2>&1); help_rc=$?
assert_eq "$help_rc" "0" "--help exits 0"
if printf '%s' "$help_out" | grep -Fq "aggregate-results.sh"; then
    PASS=$((PASS + 1)); echo "  PASS: help mentions script name"
else
    FAIL=$((FAIL + 1)); ERRORS+=("help missing script name"); echo "  FAIL: help missing script name"
fi

missing_strategy=$(bash "$SCRIPT" --started-at x --completed-at y "$CLEAN_DIR" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then PASS=$((PASS + 1)); echo "  PASS: missing --strategy rejected"; else FAIL=$((FAIL + 1)); echo "  FAIL: missing --strategy should fail"; fi

bad_dir_out=$(bash "$SCRIPT" --strategy s --started-at x --completed-at y /no/such/path 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then PASS=$((PASS + 1)); echo "  PASS: non-existent raw dir rejected"; else FAIL=$((FAIL + 1)); echo "  FAIL: bad dir should fail"; fi

echo ""
echo "[aggregation — clean batch (5 items)]"
CLEAN=$(run_aggregator "$CLEAN_DIR")
CLEAN_RC=$?
assert_eq "$CLEAN_RC" "0" "clean run exits 0"
assert_eq "$(echo "$CLEAN" | jq -r '.strategy')" "subagent" "strategy field"
assert_eq "$(echo "$CLEAN" | jq -r '.started_at')" "2026-04-15T10:00:00Z" "started_at field"
assert_eq "$(echo "$CLEAN" | jq -r '.completed_at')" "2026-04-15T11:00:00Z" "completed_at field"
assert_eq "$(echo "$CLEAN" | jq -r '.items | length')" "5" "5 items"
assert_eq "$(echo "$CLEAN" | jq -r '.items[0].index')" "1" "first item index=1"
assert_eq "$(echo "$CLEAN" | jq -r '.items[4].index')" "5" "last item index=5"
assert_eq "$(echo "$CLEAN" | jq -r '.items[0].pr')" "101" "first item pr=101"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_1_to_5.language_violations')" "0" "clean items_1_to_5 language=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_1_to_5.attribution_leaks')" "0" "clean items_1_to_5 attribution=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_1_to_5.ci_gate_violations')" "0" "clean items_1_to_5 ci_gate=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_1_to_5.missing_closes')" "0" "clean items_1_to_5 closes=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_1_to_5.commit_format_violations')" "0" "clean items_1_to_5 commit_format=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_6_to_30.language_violations')" "0" "clean items_6_to_30 language=0"
assert_eq "$(echo "$CLEAN" | jq -r '.summary.items_6_to_30.attribution_leaks')" "0" "clean items_6_to_30 attribution=0"

echo ""
echo "[aggregation — drifted batch (6 items, drift at item 6)]"
DRIFTED=$(run_aggregator "$DRIFTED_DIR")
DRIFTED_RC=$?
assert_eq "$DRIFTED_RC" "0" "drifted run exits 0"
assert_eq "$(echo "$DRIFTED" | jq -r '.items | length')" "6" "6 items"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[0].language_violations')" "0" "item 1 language=0"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[5].language_violations')" "4" "item 6 language=4 (4 hangul)"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[5].attribution_leaks')" "1" "item 6 attribution=1 (AI-assisted)"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[5].ci_gate_violations')" "1" "item 6 ci_gate=1 (merged with FAILURE)"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[5].missing_closes')" "1" "item 6 missing_closes=1"
assert_eq "$(echo "$DRIFTED" | jq -r '.items[5].commit_format_violations')" "1" "item 6 commit_format=1"

echo ""
echo "[bucketing — drift isolated to items_6_to_30]"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_1_to_5.language_violations')" "0" "items_1_to_5 bucket clean (lang)"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_1_to_5.attribution_leaks')" "0" "items_1_to_5 bucket clean (attr)"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_1_to_5.ci_gate_violations')" "0" "items_1_to_5 bucket clean (ci)"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_1_to_5.missing_closes')" "0" "items_1_to_5 bucket clean (closes)"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_1_to_5.commit_format_violations')" "0" "items_1_to_5 bucket clean (commit)"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_6_to_30.language_violations')" "4" "items_6_to_30 bucket lang=4"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_6_to_30.attribution_leaks')" "1" "items_6_to_30 bucket attr=1"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_6_to_30.ci_gate_violations')" "1" "items_6_to_30 bucket ci=1"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_6_to_30.missing_closes')" "1" "items_6_to_30 bucket closes=1"
assert_eq "$(echo "$DRIFTED" | jq -r '.summary.items_6_to_30.commit_format_violations')" "1" "items_6_to_30 bucket commit=1"

echo ""
echo "[output shape]"
required_keys=$(echo "$DRIFTED" | jq -r 'keys | sort | join(",")')
assert_eq "$required_keys" "completed_at,items,started_at,strategy,summary" "top-level keys present"
item_keys=$(echo "$DRIFTED" | jq -r '.items[0] | keys | sort | join(",")')
assert_eq "$item_keys" "attribution_leaks,ci_gate_violations,commit_format_violations,index,issue,language_violations,missing_closes,pr" "item keys present"

echo ""
echo "[determinism]"
D1=$(run_aggregator "$DRIFTED_DIR")
D2=$(run_aggregator "$DRIFTED_DIR")
D3=$(run_aggregator "$DRIFTED_DIR")
if [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: 3 aggregations produce identical JSON"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("non-deterministic aggregation output")
    echo "  FAIL: 3 aggregations differ"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
