#!/bin/bash
# run-regression.sh
# Behavioral regression test for batch drift (epic #287, issue #311).
#
# Runs a full batch under a Tier 2 isolation strategy against the scratch
# repo, then asserts that drift signal counts stay within configurable
# thresholds. Returns non-zero if any threshold is exceeded.
#
# This script is the CI-facing entry point. The nightly GitHub Actions
# workflow calls it; operators can also run it locally.
#
# Prerequisites (live mode only):
#   - gh CLI authenticated with write access to scratch repo
#   - claude CLI on PATH
#   - jq on PATH
#   - Scratch repo accessible (created by seed script if missing)
#
# Exit codes:
#   0  all thresholds passed (or dry-run)
#   1  one or more thresholds exceeded
#   2  precondition failure / missing tool
#   3  benchmark execution failed

set -euo pipefail

REGRESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$REGRESSION_DIR/../batch_drift_benchmark"
SEEDER="$BENCHMARK_DIR/seed-scratch-repo.sh"
RUNNER="$BENCHMARK_DIR/run-benchmark.sh"

STRATEGY="subagent"
ITEMS=30
THRESHOLD_FILE="$REGRESSION_DIR/thresholds.json"
DRY_RUN=false
SKIP_SEED=false

usage() {
    cat <<'EOF'
run-regression.sh [options]

Run a batch drift regression test: seed scratch repo, execute a Tier 2
strategy, aggregate results, and assert thresholds.

Options:
  --strategy <name>        Tier 2 strategy (default: subagent)
                           Values: subagent | auto-restart | orchestrator
  --items N                Number of batch items (default: 30)
  --threshold-file <path>  JSON threshold file (default: thresholds.json)
  --skip-seed              Skip scratch repo seeding (use existing state)
  --dry-run                Validate inputs and print plan without execution
  --help, -h               Show this help and exit

Thresholds file format (all fields are max allowed counts for items 6-30):
  {
    "language_violations": 0,
    "attribution_leaks": 0,
    "ci_gate_violations": 0,
    "missing_closes": 1,
    "commit_format_violations": 0
  }

Exit codes:
  0  pass (or dry-run)
  1  threshold exceeded
  2  precondition failure
  3  benchmark execution failed
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strategy) STRATEGY="$2"; shift 2 ;;
        --strategy=*) STRATEGY="${1#*=}"; shift ;;
        --items) ITEMS="$2"; shift 2 ;;
        --items=*) ITEMS="${1#*=}"; shift ;;
        --threshold-file) THRESHOLD_FILE="$2"; shift 2 ;;
        --threshold-file=*) THRESHOLD_FILE="${1#*=}"; shift ;;
        --skip-seed) SKIP_SEED=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$STRATEGY" in
    subagent|auto-restart|orchestrator) ;;
    *) echo "ERROR: --strategy must be one of: subagent, auto-restart, orchestrator (got: $STRATEGY)" >&2; exit 2 ;;
esac

if ! [[ "$ITEMS" =~ ^[0-9]+$ ]] || [ "$ITEMS" -lt 1 ] || [ "$ITEMS" -gt 200 ]; then
    echo "ERROR: --items must be an integer in [1, 200] (got: $ITEMS)" >&2
    exit 2
fi

if [ ! -f "$THRESHOLD_FILE" ]; then
    echo "ERROR: threshold file not found: $THRESHOLD_FILE" >&2
    exit 2
fi

if ! jq empty "$THRESHOLD_FILE" 2>/dev/null; then
    echo "ERROR: threshold file is not valid JSON: $THRESHOLD_FILE" >&2
    exit 2
fi

for dep in "$SEEDER" "$RUNNER"; do
    if [ ! -f "$dep" ]; then
        echo "ERROR: required script missing: $dep" >&2
        exit 2
    fi
done

T_LANG=$(jq -r '.language_violations // 0' "$THRESHOLD_FILE")
T_ATTR=$(jq -r '.attribution_leaks // 0' "$THRESHOLD_FILE")
T_CI=$(jq -r '.ci_gate_violations // 0' "$THRESHOLD_FILE")
T_CLOSES=$(jq -r '.missing_closes // 1' "$THRESHOLD_FILE")
T_COMMIT=$(jq -r '.commit_format_violations // 0' "$THRESHOLD_FILE")

if $DRY_RUN; then
    echo "[dry-run] strategy:       $STRATEGY"
    echo "[dry-run] items:          $ITEMS"
    echo "[dry-run] skip-seed:      $SKIP_SEED"
    echo "[dry-run] threshold file: $THRESHOLD_FILE"
    echo "[dry-run] thresholds:"
    echo "[dry-run]   language_violations:      <= $T_LANG"
    echo "[dry-run]   attribution_leaks:        <= $T_ATTR"
    echo "[dry-run]   ci_gate_violations:       <= $T_CI"
    echo "[dry-run]   missing_closes:           <= $T_CLOSES"
    echo "[dry-run]   commit_format_violations: <= $T_COMMIT"
    echo "[dry-run] would call: $SEEDER"
    echo "[dry-run] would call: $RUNNER --strategy $STRATEGY --items $ITEMS --reset"
    echo "[dry-run] would assert thresholds against items_6_to_30 bucket"
    exit 0
fi

# === Live execution ===

for tool in gh jq claude; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not on PATH: $tool" >&2
        exit 2
    fi
done

echo "=== Batch Drift Regression Test ==="
echo "    strategy: $STRATEGY"
echo "    items:    $ITEMS"
echo "    date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

if ! $SKIP_SEED; then
    echo "==> Phase 1: Seeding scratch repo"
    if ! bash "$SEEDER"; then
        echo "ERROR: scratch repo seeding failed" >&2
        exit 3
    fi
else
    echo "==> Phase 1: Seeding SKIPPED (--skip-seed)"
fi

echo ""
echo "==> Phase 2: Running benchmark (strategy=$STRATEGY, items=$ITEMS)"

RESET_FLAG=""
if ! $SKIP_SEED; then
    RESET_FLAG="--reset"
fi

if ! bash "$RUNNER" --strategy "$STRATEGY" --items "$ITEMS" $RESET_FLAG; then
    echo "WARNING: benchmark runner exited non-zero (per-item failures may exist)" >&2
fi

echo ""
echo "==> Phase 3: Locating results"

RESULTS_DIR="$BENCHMARK_DIR/results"
LATEST_RESULT=$(ls -t "$RESULTS_DIR"/${STRATEGY}-*.json 2>/dev/null | head -1)

if [ -z "$LATEST_RESULT" ] || [ ! -f "$LATEST_RESULT" ]; then
    echo "ERROR: no result file found for strategy '$STRATEGY' in $RESULTS_DIR" >&2
    exit 3
fi

echo "    result file: $LATEST_RESULT"

echo ""
echo "==> Phase 4: Asserting thresholds"

BUCKET="items_6_to_30"
if [ "$ITEMS" -le 5 ]; then
    BUCKET="items_1_to_5"
fi

A_LANG=$(jq -r ".summary.${BUCKET}.language_violations // 0" "$LATEST_RESULT")
A_ATTR=$(jq -r ".summary.${BUCKET}.attribution_leaks // 0" "$LATEST_RESULT")
A_CI=$(jq -r ".summary.${BUCKET}.ci_gate_violations // 0" "$LATEST_RESULT")
A_CLOSES=$(jq -r ".summary.${BUCKET}.missing_closes // 0" "$LATEST_RESULT")
A_COMMIT=$(jq -r ".summary.${BUCKET}.commit_format_violations // 0" "$LATEST_RESULT")

FAILED=0
check_threshold() {
    local name="$1" actual="$2" max="$3"
    if [ "$actual" -gt "$max" ]; then
        echo "    FAIL: $name = $actual (threshold: <= $max)"
        FAILED=1
    else
        echo "    PASS: $name = $actual (threshold: <= $max)"
    fi
}

check_threshold "language_violations" "$A_LANG" "$T_LANG"
check_threshold "attribution_leaks" "$A_ATTR" "$T_ATTR"
check_threshold "ci_gate_violations" "$A_CI" "$T_CI"
check_threshold "missing_closes" "$A_CLOSES" "$T_CLOSES"
check_threshold "commit_format_violations" "$A_COMMIT" "$T_COMMIT"

echo ""

# Emit machine-readable summary (consumed by CI artifact upload)
SUMMARY_FILE="$REGRESSION_DIR/last-run-summary.json"
jq -n \
    --arg strategy "$STRATEGY" \
    --argjson items "$ITEMS" \
    --arg bucket "$BUCKET" \
    --arg result_file "$LATEST_RESULT" \
    --argjson a_lang "$A_LANG" --argjson t_lang "$T_LANG" \
    --argjson a_attr "$A_ATTR" --argjson t_attr "$T_ATTR" \
    --argjson a_ci "$A_CI" --argjson t_ci "$T_CI" \
    --argjson a_closes "$A_CLOSES" --argjson t_closes "$T_CLOSES" \
    --argjson a_commit "$A_COMMIT" --argjson t_commit "$T_COMMIT" \
    --argjson passed "$([ $FAILED -eq 0 ] && echo true || echo false)" \
    '{
        strategy: $strategy,
        items: $items,
        bucket: $bucket,
        result_file: $result_file,
        passed: $passed,
        signals: {
            language_violations:      { actual: $a_lang, threshold: $t_lang, passed: ($a_lang <= $t_lang) },
            attribution_leaks:        { actual: $a_attr, threshold: $t_attr, passed: ($a_attr <= $t_attr) },
            ci_gate_violations:       { actual: $a_ci,   threshold: $t_ci,   passed: ($a_ci   <= $t_ci)   },
            missing_closes:           { actual: $a_closes, threshold: $t_closes, passed: ($a_closes <= $t_closes) },
            commit_format_violations: { actual: $a_commit, threshold: $t_commit, passed: ($a_commit <= $t_commit) }
        }
    }' > "$SUMMARY_FILE"

if [ $FAILED -eq 0 ]; then
    echo "=== REGRESSION TEST PASSED ==="
    exit 0
else
    echo "=== REGRESSION TEST FAILED ==="
    echo "    See $SUMMARY_FILE for details."
    exit 1
fi
