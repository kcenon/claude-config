#!/bin/bash
# Hook test runner
# Run: bash tests/hooks/test-runner.sh
# Runs all test-*.sh scripts in this directory and reports results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

echo "========================================="
echo "  Hook Test Suite"
echo "========================================="
echo ""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    # Skip self
    [ "$(basename "$test_file")" = "test-runner.sh" ] && continue
    suite_name=$(basename "$test_file" .sh | sed 's/^test-//')

    echo "--- $suite_name ---"
    if output=$(bash "$test_file" 2>&1); then
        # Extract pass/fail counts from last line
        pass=$(echo "$output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || echo 0)
        fail=$(echo "$output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || echo 0)
        TOTAL_PASS=$((TOTAL_PASS + pass))
        TOTAL_FAIL=$((TOTAL_FAIL + fail))
        echo "$output" | tail -1
    else
        pass=$(echo "$output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || echo 0)
        fail=$(echo "$output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || echo 0)
        TOTAL_PASS=$((TOTAL_PASS + pass))
        TOTAL_FAIL=$((TOTAL_FAIL + fail))
        FAILED_SUITES+=("$suite_name")
        echo "$output" | tail -1
    fi
    echo ""
done

echo "========================================="
echo "  Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo "========================================="

if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
    echo ""
    echo "Failed suites:"
    for s in "${FAILED_SUITES[@]}"; do
        echo "  - $s"
    done
    exit 1
fi

exit 0
