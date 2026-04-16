#!/bin/bash
# test-run-regression.sh
# Unit tests for run-regression.sh — validates argument parsing, dry-run
# output, threshold file loading, and assertion logic.
#
# All tests are offline: no gh, claude, or network calls.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGRESSION="$SCRIPT_DIR/run-regression.sh"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "  PASS: $1"; }
fail() { failed=$((failed + 1)); echo "  FAIL: $1"; }

assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

assert_contains() {
    if echo "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

assert_exit() {
    local expected="$1"; shift
    set +e
    "$@" >/dev/null 2>&1
    local rc=$?
    set -e
    if [ "$rc" -eq "$expected" ]; then
        pass "exit code $expected: ${*: -1}"
    else
        fail "expected exit $expected, got $rc: ${*: -1}"
    fi
}

# --- Create fixtures ---

# Valid threshold file
cat > "$FIXTURE_DIR/thresholds.json" <<'EOF'
{
  "language_violations": 0,
  "attribution_leaks": 0,
  "ci_gate_violations": 0,
  "missing_closes": 1,
  "commit_format_violations": 0
}
EOF

# Relaxed threshold file (for testing pass scenarios)
cat > "$FIXTURE_DIR/relaxed.json" <<'EOF'
{
  "language_violations": 10,
  "attribution_leaks": 5,
  "ci_gate_violations": 3,
  "missing_closes": 5,
  "commit_format_violations": 5
}
EOF

# Invalid JSON threshold file
echo "not json" > "$FIXTURE_DIR/bad.json"

echo "=== run-regression.sh tests ==="
echo ""

# --- Help tests ---
echo "[--help]"

out=$(bash "$REGRESSION" --help 2>&1)
assert_eq "$?" "0" "--help exits 0"
assert_contains "$out" "run-regression.sh" "help mentions script name"
assert_contains "$out" "--strategy" "help documents --strategy"
assert_contains "$out" "--threshold-file" "help documents --threshold-file"
assert_contains "$out" "--dry-run" "help documents --dry-run"
assert_contains "$out" "--skip-seed" "help documents --skip-seed"

out=$(bash "$REGRESSION" -h 2>&1)
assert_eq "$?" "0" "-h exits 0"

echo ""

# --- Argument validation ---
echo "[argument validation]"

assert_exit 2 bash "$REGRESSION" --strategy invalid --dry-run
assert_exit 2 bash "$REGRESSION" --items 0 --dry-run
assert_exit 2 bash "$REGRESSION" --items 201 --dry-run
assert_exit 2 bash "$REGRESSION" --items abc --dry-run
assert_exit 2 bash "$REGRESSION" --unknown-flag

out=$(bash "$REGRESSION" --strategy invalid --dry-run 2>&1 || true)
assert_contains "$out" "ERROR" "invalid strategy reports error"

echo ""

# --- Threshold file validation ---
echo "[threshold file validation]"

assert_exit 2 bash "$REGRESSION" --threshold-file /nonexistent/path --dry-run
assert_exit 2 bash "$REGRESSION" --threshold-file "$FIXTURE_DIR/bad.json" --dry-run

echo ""

# --- Dry-run output ---
echo "[dry-run]"

out=$(bash "$REGRESSION" --dry-run --threshold-file "$FIXTURE_DIR/thresholds.json" 2>&1)
assert_eq "$?" "0" "dry-run exits 0"
assert_contains "$out" "[dry-run]" "dry-run tag present"
assert_contains "$out" "subagent" "dry-run shows default strategy"
assert_contains "$out" "30" "dry-run shows default items"
assert_contains "$out" "language_violations" "dry-run shows language threshold"
assert_contains "$out" "attribution_leaks" "dry-run shows attribution threshold"
assert_contains "$out" "ci_gate_violations" "dry-run shows ci threshold"
assert_contains "$out" "missing_closes" "dry-run shows closes threshold"
assert_contains "$out" "commit_format_violations" "dry-run shows commit threshold"

echo ""

# --- Dry-run with custom parameters ---
echo "[dry-run custom params]"

out=$(bash "$REGRESSION" --dry-run --strategy auto-restart --items 15 \
    --threshold-file "$FIXTURE_DIR/relaxed.json" --skip-seed 2>&1)
assert_eq "$?" "0" "custom dry-run exits 0"
assert_contains "$out" "auto-restart" "dry-run shows custom strategy"
assert_contains "$out" "15" "dry-run shows custom items"
assert_contains "$out" "true" "dry-run shows skip-seed"

echo ""

# --- Dry-run all strategies ---
echo "[dry-run all strategies]"

for strat in subagent auto-restart orchestrator; do
    out=$(bash "$REGRESSION" --dry-run --strategy "$strat" \
        --threshold-file "$FIXTURE_DIR/thresholds.json" 2>&1)
    assert_eq "$?" "0" "$strat dry-run exits 0"
    assert_contains "$out" "$strat" "$strat dry-run names strategy"
done

echo ""

# --- Determinism ---
echo "[determinism]"

run1=$(bash "$REGRESSION" --dry-run --threshold-file "$FIXTURE_DIR/thresholds.json" 2>&1)
run2=$(bash "$REGRESSION" --dry-run --threshold-file "$FIXTURE_DIR/thresholds.json" 2>&1)
run3=$(bash "$REGRESSION" --dry-run --threshold-file "$FIXTURE_DIR/thresholds.json" 2>&1)
if [ "$run1" = "$run2" ] && [ "$run2" = "$run3" ]; then
    pass "3 dry-runs produce identical output"
else
    fail "dry-run output not deterministic"
fi

echo ""
echo "=== Results: $passed passed, $failed failed ==="
[ "$failed" -eq 0 ]
