#!/bin/bash
# Test suite for tests/batch_drift_benchmark/seed-scratch-repo.sh
# Run: bash tests/batch_drift_benchmark/test-seed-scratch-repo.sh
#
# Offline: only exercises --dry-run and --help paths; never calls gh.

SCRIPT="tests/batch_drift_benchmark/seed-scratch-repo.sh"
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

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — unexpected '$needle' in output")
        echo "  FAIL: $label (unexpected '$needle')"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    fi
}

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

echo "=== seed-scratch-repo.sh tests ==="
echo ""

echo "[--help]"
help_out=$(bash "$SCRIPT" --help 2>&1); help_rc=$?
assert_eq "$help_rc" "0" "--help exits 0"
assert_contains "$help_out" "seed-scratch-repo.sh" "help mentions script name"
assert_contains "$help_out" "--dry-run" "help documents --dry-run"
assert_contains "$help_out" "Idempotence" "help explains idempotence"
help_out_short=$(bash "$SCRIPT" -h 2>&1); help_short_rc=$?
assert_eq "$help_short_rc" "0" "-h exits 0"

echo ""
echo "[--dry-run]"
dry_out=$(bash "$SCRIPT" --dry-run 2>&1); dry_rc=$?
assert_eq "$dry_rc" "0" "--dry-run exits 0"
assert_contains "$dry_out" "[dry-run]" "dry-run tag present"
assert_contains "$dry_out" "kcenon/batch-drift-scratch" "dry-run names scratch repo"
assert_contains "$dry_out" "docs/file-01.md" "dry-run lists file-01"
assert_contains "$dry_out" "docs/file-30.md" "dry-run lists file-30"
assert_contains "$dry_out" "fix typo in docs/file-01.md" "dry-run lists issue-01 title"
assert_contains "$dry_out" "fix typo in docs/file-30.md" "dry-run lists issue-30 title"

put_count=$(printf '%s\n' "$dry_out" | grep -c 'PUT docs/file-')
assert_eq "$put_count" "30" "dry-run plans 30 PUT actions"

issue_count=$(printf '%s\n' "$dry_out" | grep -c 'issue: fix typo in docs/file-')
assert_eq "$issue_count" "30" "dry-run plans 30 issue creations"

echo ""
echo "[--dry-run is network-free]"
# Ensure dry-run doesn't invoke `gh` by verifying no API output patterns leak in
assert_not_contains "$dry_out" "HTTP/" "dry-run produces no HTTP output"
assert_not_contains "$dry_out" "X-GitHub" "dry-run produces no GitHub response headers"

echo ""
echo "[argument validation]"
bad_out=$(bash "$SCRIPT" --unknown-flag 2>&1); bad_rc=$?
if [ "$bad_rc" -eq 0 ]; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: unknown flag should exit non-zero")
    echo "  FAIL: unknown flag should exit non-zero"
else
    PASS=$((PASS + 1))
    echo "  PASS: unknown flag exits non-zero (rc=$bad_rc)"
fi
assert_contains "$bad_out" "unknown argument" "unknown flag reports error"

echo ""
echo "[determinism]"
d1=$(bash "$SCRIPT" --dry-run 2>&1)
d2=$(bash "$SCRIPT" --dry-run 2>&1)
d3=$(bash "$SCRIPT" --dry-run 2>&1)
if [ "$d1" = "$d2" ] && [ "$d2" = "$d3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: 3 dry-runs produce identical output"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: dry-run output non-deterministic")
    echo "  FAIL: 3 dry-runs differ"
fi

echo ""
echo "[file numbering]"
# Sample a middle number to verify zero-padding
assert_contains "$dry_out" "docs/file-15.md" "file-15 with zero pad"
# 30 should not have an extra leading zero
assert_contains "$dry_out" "docs/file-30.md" "file-30 two-digit"
# Should not produce file-31
assert_not_contains "$dry_out" "docs/file-31.md" "no file-31"
# Should not produce file-00
assert_not_contains "$dry_out" "docs/file-00.md" "no file-00"

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
