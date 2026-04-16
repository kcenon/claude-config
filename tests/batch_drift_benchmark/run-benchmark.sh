#!/bin/bash
# run-benchmark.sh
# Run /issue-work in batch mode under one Tier 2 isolation strategy,
# capture per-item PR/commit data, and delegate aggregation to
# aggregate-results.sh.
#
# This script is the operator-facing entry point for benchmark execution
# (epic #287, issue #310, sub-issue #314). It is NOT auto-executed by CI
# or by /issue-work; an operator runs it against kcenon/batch-drift-scratch
# after bootstrapping the scratch repo via seed-scratch-repo.sh.
#
# The three strategies under test and their invocation shapes are:
#   subagent     — `claude --print '/issue-work <repo> --limit N --no-confirm'`
#   auto-restart — `while claude --auto-restart --print '...'; do :; done`
#   orchestrator — scripts/batch-issue-work.sh <repo> N
#
# Dry-run mode prints the planned invocation and target paths without
# calling claude or gh.
#
# Exit codes:
#   0  success (or dry-run)
#   1  invalid argument / precondition failure
#   2  tool missing (gh, jq, claude)

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCHMARK_DIR/../.." && pwd)"
EXTRACTORS="$BENCHMARK_DIR/extractors.sh"
AGGREGATOR="$BENCHMARK_DIR/aggregate-results.sh"
SEEDER="$BENCHMARK_DIR/seed-scratch-repo.sh"
EXTERNAL_ORCHESTRATOR="$REPO_ROOT/scripts/batch-issue-work.sh"

SCRATCH_REPO="kcenon/batch-drift-scratch"
STRATEGY=""
ITEMS=30
RESET=false
DRY_RUN=false

usage() {
    cat <<'EOF'
run-benchmark.sh --strategy <subagent|auto-restart|orchestrator> [options]

Runs one Tier 2 strategy against the kcenon/batch-drift-scratch corpus,
captures per-item PR data, and emits aggregated results JSON.

Options:
  --strategy <name>   required: subagent | auto-restart | orchestrator
  --items N           number of items to process (default 30)
  --reset             run seed-scratch-repo.sh before the batch
  --dry-run           print the plan; do not invoke claude, gh, or seeder
  --help, -h          show this help and exit

Output:
  tests/batch_drift_benchmark/results/<strategy>-<utc-ts>.json
  tests/batch_drift_benchmark/logs/<strategy>-<utc-ts>.log
  tests/batch_drift_benchmark/logs/<strategy>-<utc-ts>-raw/NN-<pr>.json

Prerequisites for a live run (not needed for --dry-run):
  - gh authenticated against kcenon/batch-drift-scratch
  - claude CLI on PATH
  - jq on PATH
  - kcenon/batch-drift-scratch bootstrapped via seed-scratch-repo.sh
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strategy) STRATEGY="$2"; shift 2 ;;
        --strategy=*) STRATEGY="${1#*=}"; shift ;;
        --items) ITEMS="$2"; shift 2 ;;
        --items=*) ITEMS="${1#*=}"; shift ;;
        --reset) RESET=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; echo "Run with --help." >&2; exit 1 ;;
    esac
done

if [ -z "$STRATEGY" ]; then
    echo "ERROR: --strategy required" >&2
    exit 1
fi

case "$STRATEGY" in
    subagent|auto-restart|orchestrator) ;;
    *) echo "ERROR: --strategy must be one of: subagent, auto-restart, orchestrator (got: $STRATEGY)" >&2; exit 1 ;;
esac

if ! [[ "$ITEMS" =~ ^[0-9]+$ ]] || [ "$ITEMS" -lt 1 ] || [ "$ITEMS" -gt 200 ]; then
    echo "ERROR: --items must be an integer in [1, 200] (got: $ITEMS)" >&2
    exit 1
fi

# Precondition: extractor + aggregator + seeder must exist
for dep in "$EXTRACTORS" "$AGGREGATOR" "$SEEDER"; do
    if [ ! -f "$dep" ]; then
        echo "ERROR: required file missing: $dep" >&2
        exit 1
    fi
done

if [ "$STRATEGY" = "orchestrator" ] && [ ! -x "$EXTERNAL_ORCHESTRATOR" ]; then
    echo "ERROR: external orchestrator missing or not executable: $EXTERNAL_ORCHESTRATOR" >&2
    exit 1
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)
RESULTS_DIR="$BENCHMARK_DIR/results"
LOGS_DIR="$BENCHMARK_DIR/logs"
RAW_DIR="$LOGS_DIR/${STRATEGY}-${TS}-raw"
LOG_FILE="$LOGS_DIR/${STRATEGY}-${TS}.log"
RESULTS_FILE="$RESULTS_DIR/${STRATEGY}-${TS}.json"

case "$STRATEGY" in
    subagent)
        STRATEGY_CMD="claude --print '/issue-work $SCRATCH_REPO --limit $ITEMS --no-confirm'"
        ;;
    auto-restart)
        STRATEGY_CMD="while claude --auto-restart --print '/issue-work $SCRATCH_REPO --limit $ITEMS --no-confirm'; do :; done"
        ;;
    orchestrator)
        STRATEGY_CMD="$EXTERNAL_ORCHESTRATOR $SCRATCH_REPO $ITEMS"
        ;;
esac

if $DRY_RUN; then
    echo "[dry-run] strategy:     $STRATEGY"
    echo "[dry-run] items:        $ITEMS"
    echo "[dry-run] reset:        $RESET"
    echo "[dry-run] scratch repo: $SCRATCH_REPO"
    echo "[dry-run] invocation:   $STRATEGY_CMD"
    echo "[dry-run] raw dir:      $RAW_DIR"
    echo "[dry-run] log file:     $LOG_FILE"
    echo "[dry-run] results file: $RESULTS_FILE"
    if $RESET; then
        echo "[dry-run] would call:   $SEEDER"
    fi
    echo "[dry-run] would capture per-item PR JSON from gh after batch completes"
    echo "[dry-run] would delegate aggregation to: $AGGREGATOR"
    exit 0
fi

# === Live execution path ===

for tool in gh jq claude; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool missing on PATH: $tool" >&2
        exit 2
    fi
done

if ! gh api user --jq '.login' >/dev/null 2>&1; then
    echo "ERROR: gh not authenticated (gh api user failed)" >&2
    exit 2
fi

mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$RAW_DIR"

if $RESET; then
    echo "==> resetting scratch repo"
    bash "$SEEDER"
fi

echo "==> capturing baseline PR list"
BEFORE_PRS=$(gh pr list --repo "$SCRATCH_REPO" --state all --limit 500 \
    --json number -q '[.[].number] | sort' | jq -c .)

STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "==> invoking strategy: $STRATEGY"
echo "    command: $STRATEGY_CMD"

set +e
bash -c "$STRATEGY_CMD" >"$LOG_FILE" 2>&1
STRATEGY_RC=$?
set -e

COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "==> strategy exited rc=$STRATEGY_RC (non-zero OK — per-item failures do not abort aggregation)"

echo "==> diffing PR list to identify items"
AFTER_PRS=$(gh pr list --repo "$SCRATCH_REPO" --state all --limit 500 \
    --json number -q '[.[].number] | sort' | jq -c .)

NEW_PRS=$(jq -n --argjson a "$BEFORE_PRS" --argjson b "$AFTER_PRS" '$b - $a | sort')

idx=0
while read -r pr_num; do
    [ -z "$pr_num" ] && continue
    idx=$((idx + 1))
    nn=$(printf '%02d' "$idx")

    # Per-item failure survival: record null signals if capture fails
    raw_file="$RAW_DIR/${nn}-${pr_num}.json"
    if ! pr_data=$(gh pr view "$pr_num" --repo "$SCRATCH_REPO" \
        --json number,body,mergedAt,statusCheckRollup,commits 2>/dev/null); then
        jq -n --argjson pr "$pr_num" \
            '{issue_number: 0, pr_number: $pr, pr_body: "", pr_json: {}, commit_messages: "", capture_error: true}' \
            > "$raw_file"
        echo "    item $nn (PR #$pr_num): capture FAILED — recorded null"
        continue
    fi

    pr_body=$(printf '%s' "$pr_data" | jq -r '.body // ""')
    pr_json=$(printf '%s' "$pr_data" | jq -c '{mergedAt: .mergedAt, statusCheckRollup: .statusCheckRollup}')
    commits=$(printf '%s' "$pr_data" | jq -r '[.commits[]?.messageHeadline // empty] | join("\n")')

    # Grep the PR body for "Closes #N" to recover the issue number (best-effort)
    issue_num=$(printf '%s' "$pr_body" | grep -oiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' \
        | head -1 | grep -oE '[0-9]+' || echo 0)

    jq -n \
        --argjson issue "$issue_num" \
        --argjson pr "$pr_num" \
        --arg body "$pr_body" \
        --argjson prj "$pr_json" \
        --arg commits "$commits" \
        '{issue_number: $issue, pr_number: $pr, pr_body: $body, pr_json: $prj, commit_messages: $commits}' \
        > "$raw_file"
    echo "    item $nn (PR #$pr_num): captured"
done <<< "$NEW_PRS"

echo "==> aggregating $idx items"
bash "$AGGREGATOR" \
    --strategy "$STRATEGY" \
    --started-at "$STARTED_AT" \
    --completed-at "$COMPLETED_AT" \
    "$RAW_DIR" > "$RESULTS_FILE"

echo ""
echo "==> benchmark complete"
echo "    results: $RESULTS_FILE"
echo "    log:     $LOG_FILE"
echo "    raw:     $RAW_DIR"
