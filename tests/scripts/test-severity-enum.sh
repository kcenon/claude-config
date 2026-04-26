#!/bin/bash
# Test suite for severity / finding_levels schema additions (C1, P2-a)
# Run: bash tests/scripts/test-severity-enum.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
LINTER="$ROOT_DIR/scripts/spec_lint.py"

PASS=0
FAIL=0
ERRORS=()

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH" >&2
    exit 0
fi
if ! "$PYTHON" -c "import yaml, jsonschema" >/dev/null 2>&1; then
    echo "SKIP: missing PyYAML or jsonschema" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

write_skill() {
    local path="$1" extra="$2"
    cat > "$path" <<EOF
---
name: $(basename "$path" .md)
description: SKILL fixture for severity-enum testing covering both severity (single) and finding_levels (array) keys with valid and invalid values.
$extra
---

content
EOF
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $actual)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected exit $expected, got $actual")
        echo "  FAIL: $label"
    fi
}

run_lint() {
    "$PYTHON" "$LINTER" --mode skill --quiet "$1"
}

echo "=== severity / finding_levels schema tests ==="
echo ""

# ── Positive: severity S1 / S2 / S3 accepted ─────────────────
for tier in S1 S2 S3; do
    lower="$(echo "$tier" | tr '[:upper:]' '[:lower:]')"
    f="$WORK/sev-$lower.md"
    write_skill "$f" "severity: $tier"
    echo "[case: severity=$tier accepted]"
    run_lint "$f"; rc=$?
    assert_exit 0 "$rc" "severity=$tier -> exit 0"
done

# ── Positive: finding_levels arrays accepted ─────────────────
echo ""
echo "[case: finding_levels=[S1] accepted]"
write_skill "$WORK/fl-one.md" "finding_levels: [S1]"
run_lint "$WORK/fl-one.md"; rc=$?
assert_exit 0 "$rc" "finding_levels [S1] -> exit 0"

echo ""
echo "[case: finding_levels=[S1, S2, S3] accepted]"
write_skill "$WORK/fl-all.md" "finding_levels: [S1, S2, S3]"
run_lint "$WORK/fl-all.md"; rc=$?
assert_exit 0 "$rc" "finding_levels all tiers -> exit 0"

# ── Positive: both keys together ─────────────────────────────
echo ""
echo "[case: severity + finding_levels combined]"
write_skill "$WORK/combined.md" $'severity: S2\nfinding_levels: [S1, S2]'
run_lint "$WORK/combined.md"; rc=$?
assert_exit 0 "$rc" "severity=S2 + finding_levels=[S1,S2] -> exit 0"

# ── Negative: invalid severity values ────────────────────────
i=0
for bad in S0 S4 s1 high HIGH critical; do
    i=$((i + 1))
    f="$WORK/bad-sev-$i.md"
    write_skill "$f" "severity: $bad"
    echo ""
    echo "[case: severity=$bad rejected]"
    out=$(run_lint "$f" 2>&1); rc=$?
    assert_exit 1 "$rc" "severity=$bad -> exit 1"
    if echo "$out" | grep -Fq "severity"; then
        PASS=$((PASS + 1))
        echo "  PASS: rejection cited the severity field"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: severity=$bad rejection did not mention severity field; output: $out")
        echo "  FAIL: rejection did not cite severity field"
    fi
done

# ── Negative: empty finding_levels array ─────────────────────
echo ""
echo "[case: finding_levels=[] rejected]"
write_skill "$WORK/fl-empty.md" "finding_levels: []"
run_lint "$WORK/fl-empty.md"; rc=$?
assert_exit 1 "$rc" "finding_levels [] -> exit 1"

# ── Negative: invalid entry inside finding_levels ────────────
echo ""
echo "[case: finding_levels=[S0] rejected]"
write_skill "$WORK/fl-bad.md" "finding_levels: [S0]"
run_lint "$WORK/fl-bad.md"; rc=$?
assert_exit 1 "$rc" "finding_levels [S0] -> exit 1"

echo ""
echo "[case: finding_levels=[S1, s2] rejected (lowercase)]"
write_skill "$WORK/fl-mixed.md" "finding_levels: [S1, s2]"
run_lint "$WORK/fl-mixed.md"; rc=$?
assert_exit 1 "$rc" "finding_levels mixed-case -> exit 1"

# ── Negative: duplicates inside finding_levels ───────────────
echo ""
echo "[case: finding_levels=[S1, S1] rejected (uniqueItems)]"
write_skill "$WORK/fl-dup.md" "finding_levels: [S1, S1]"
run_lint "$WORK/fl-dup.md"; rc=$?
assert_exit 1 "$rc" "finding_levels duplicates -> exit 1"

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do echo "  $e"; done
    exit 1
fi
exit 0
