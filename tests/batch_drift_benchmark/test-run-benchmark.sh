#!/bin/bash
# Test suite for tests/batch_drift_benchmark/run-benchmark.sh
# Run: bash tests/batch_drift_benchmark/test-run-benchmark.sh
#
# Covers dry-run, argument validation, and precondition errors. The live
# execution path (claude + gh) is exercised in #315, not here.

SCRIPT="tests/batch_drift_benchmark/run-benchmark.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

if [ ! -f "$SCRIPT" ]; then
    echo "ERROR: $SCRIPT not found"
    exit 1
fi

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected output to contain '$needle'")
        echo "  FAIL: $label (missing '$needle')"
    fi
}

assert_nonzero_exit() {
    local rc="$1" label="$2"
    if [ "$rc" -ne 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (rc=$rc)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected non-zero exit")
        echo "  FAIL: $label (expected non-zero exit)"
    fi
}

echo "=== run-benchmark.sh tests ==="
echo ""

echo "[--help]"
help_out=$(bash "$SCRIPT" --help 2>&1); help_rc=$?
if [ "$help_rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "  PASS: --help exits 0"; else FAIL=$((FAIL + 1)); echo "  FAIL: --help exits 0"; fi
assert_contains "$help_out" "run-benchmark.sh" "help mentions script name"
assert_contains "$help_out" "--strategy" "help documents --strategy"
assert_contains "$help_out" "subagent" "help mentions subagent strategy"
assert_contains "$help_out" "auto-restart" "help mentions auto-restart strategy"
assert_contains "$help_out" "orchestrator" "help mentions orchestrator strategy"

echo ""
echo "[argument validation]"
no_strategy_out=$(bash "$SCRIPT" --dry-run 2>&1); rc=$?
assert_nonzero_exit "$rc" "missing --strategy rejected"
assert_contains "$no_strategy_out" "strategy" "missing strategy error mentions strategy"

bash "$SCRIPT" --strategy foo --dry-run > /dev/null 2>&1; rc=$?
assert_nonzero_exit "$rc" "invalid --strategy rejected"

bash "$SCRIPT" --strategy subagent --items 0 --dry-run > /dev/null 2>&1; rc=$?
assert_nonzero_exit "$rc" "--items 0 rejected"

bash "$SCRIPT" --strategy subagent --items 201 --dry-run > /dev/null 2>&1; rc=$?
assert_nonzero_exit "$rc" "--items 201 rejected"

bash "$SCRIPT" --strategy subagent --items abc --dry-run > /dev/null 2>&1; rc=$?
assert_nonzero_exit "$rc" "--items abc rejected"

bash "$SCRIPT" --strategy subagent --no-such-flag --dry-run > /dev/null 2>&1; rc=$?
assert_nonzero_exit "$rc" "unknown flag rejected"

echo ""
echo "[--dry-run subagent]"
dry_sub=$(bash "$SCRIPT" --strategy subagent --items 30 --dry-run 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "  PASS: subagent dry-run exits 0"; else FAIL=$((FAIL + 1)); echo "  FAIL: subagent dry-run"; fi
assert_contains "$dry_sub" "[dry-run]" "dry-run tag present"
assert_contains "$dry_sub" "strategy:" "dry-run reports strategy"
assert_contains "$dry_sub" "subagent" "dry-run names subagent"
assert_contains "$dry_sub" "kcenon/batch-drift-scratch" "dry-run names scratch repo"
assert_contains "$dry_sub" "claude --print" "dry-run includes claude invocation"
assert_contains "$dry_sub" "/issue-work" "dry-run includes /issue-work command"
assert_contains "$dry_sub" "--limit 30" "dry-run passes --limit 30"
assert_contains "$dry_sub" "results/subagent-" "dry-run shows results path"

echo ""
echo "[--dry-run auto-restart]"
dry_ar=$(bash "$SCRIPT" --strategy auto-restart --items 15 --dry-run 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "  PASS: auto-restart dry-run exits 0"; else FAIL=$((FAIL + 1)); echo "  FAIL: auto-restart dry-run"; fi
assert_contains "$dry_ar" "--auto-restart" "dry-run shows --auto-restart flag"
assert_contains "$dry_ar" "while claude" "dry-run shows while loop wrapper"
assert_contains "$dry_ar" "--limit 15" "dry-run honors custom --items"

echo ""
echo "[--dry-run orchestrator]"
dry_orch=$(bash "$SCRIPT" --strategy orchestrator --dry-run 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "  PASS: orchestrator dry-run exits 0"; else FAIL=$((FAIL + 1)); echo "  FAIL: orchestrator dry-run"; fi
assert_contains "$dry_orch" "batch-issue-work.sh" "dry-run names external orchestrator"

echo ""
echo "[--reset in dry-run]"
dry_reset=$(bash "$SCRIPT" --strategy subagent --reset --dry-run 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS + 1)); echo "  PASS: --reset dry-run exits 0"; else FAIL=$((FAIL + 1)); echo "  FAIL: --reset dry-run"; fi
assert_contains "$dry_reset" "seed-scratch-repo.sh" "dry-run reports seeder invocation under --reset"

echo ""
echo "[invocation shape determinism — strategy cmd line only]"
# Timestamps naturally differ per run; extract just the invocation line.
extract_cmd() { printf '%s' "$1" | grep -F 'invocation:'; }
c1=$(extract_cmd "$(bash "$SCRIPT" --strategy subagent --dry-run 2>&1)")
c2=$(extract_cmd "$(bash "$SCRIPT" --strategy subagent --dry-run 2>&1)")
c3=$(extract_cmd "$(bash "$SCRIPT" --strategy subagent --dry-run 2>&1)")
if [ "$c1" = "$c2" ] && [ "$c2" = "$c3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: invocation line deterministic across 3 runs"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("non-deterministic invocation line")
    echo "  FAIL: invocation line differs across runs"
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
