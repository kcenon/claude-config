#!/bin/bash
# Test suite for scripts/migrate_halt_conditions.sh (A2, P1-b)
# Run: bash tests/scripts/test-migrate-halt-conditions.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
MIGRATOR="$ROOT_DIR/scripts/migrate_halt_conditions.sh"

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

write_skill_legacy() {
    local path="$1" cond="$2"
    cat > "$path" <<EOF
---
name: $(basename "$path" .md)
description: SKILL fixture for migrate_halt_conditions testing.
max_iterations: 3
halt_condition: "$cond"
on_halt: "report and exit"
loop_safe: true
---

content
EOF
}

write_skill_migrated() {
    local path="$1"
    cat > "$path" <<'EOF'
---
name: already-migrated
description: SKILL fixture already in array form.
max_iterations: 3
halt_conditions:
  - { type: success, expr: "all done" }
  - { type: limit,   expr: "3 retries" }
on_halt: "report and exit"
loop_safe: true
---

content
EOF
}

write_skill_neither() {
    local path="$1"
    cat > "$path" <<'EOF'
---
name: no-halt
description: SKILL fixture with neither halt_condition nor halt_conditions.
loop_safe: true
---

content
EOF
}

assert_contains() {
    local needle="$1" output="$2" label="$3"
    if echo "$output" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output did not contain '$needle'")
        echo "  FAIL: $label"
    fi
}

assert_not_contains() {
    local needle="$1" output="$2" label="$3"
    if echo "$output" | grep -Fq -- "$needle"; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output unexpectedly contained '$needle'")
        echo "  FAIL: $label"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    fi
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

echo "=== migrate_halt_conditions.sh tests ==="
echo ""

# ── Case 1: simple "X OR Y" → success/limit array ────────────
echo "[case 1: simple two-clause halt_condition]"
F1="$WORK/case1.md"
write_skill_legacy "$F1" "CI all-green and PR merged, OR 3 identical CI failures in a row"
out=$(bash "$MIGRATOR" "$F1" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 on legacy file"
assert_contains "halt_conditions:" "$out" "proposes array form"
assert_contains "type: success" "$out" "classifies success clause"
assert_contains "type: limit" "$out" "classifies limit clause"
assert_contains 'expr: "CI all-green and PR merged"' "$out" "trailing comma stripped"

# ── Case 2: three-clause with user signal ────────────────────
echo ""
echo "[case 2: three-clause with user signal]"
F2="$WORK/case2.md"
write_skill_legacy "$F2" "All checks pass, OR user aborts, OR 3 identical failures in a row"
out=$(bash "$MIGRATOR" "$F2" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 on three-clause"
assert_contains "type: success" "$out" "first clause classified success"
assert_contains "type: user" "$out" "user clause classified"
assert_contains "type: limit" "$out" "limit clause classified"

# ── Case 3: compound clause flagged for manual review ────────
echo ""
echo "[case 3: compound 'X AND Y' clause]"
F3="$WORK/case3.md"
write_skill_legacy "$F3" "Migration step succeeds AND verification passes, OR rollback triggered"
out=$(bash "$MIGRATOR" "$F3" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 on compound"
assert_contains "MANUAL REVIEW" "$out" "compound flagged for review"

# ── Case 4: already-migrated file → OK / exit 0 ──────────────
echo ""
echo "[case 4: already-migrated file is idempotent]"
F4="$WORK/case4.md"
write_skill_migrated "$F4"
out=$(bash "$MIGRATOR" "$F4" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 on already-migrated"
assert_contains "OK: already migrated" "$out" "reports already-migrated"
assert_not_contains "PROPOSED" "$out" "no proposal generated"

# ── Case 5: file with neither key → SKIP / exit 1 ────────────
echo ""
echo "[case 5: neither halt_condition nor halt_conditions]"
F5="$WORK/case5.md"
write_skill_neither "$F5"
out=$(bash "$MIGRATOR" "$F5" 2>&1); rc=$?
assert_exit 1 "$rc" "exit 1 when no halt key present"
assert_contains "SKIP" "$out" "reports SKIP for missing key"

# ── Case 6: --quiet suppresses ORIGINAL/PROPOSED labels ──────
echo ""
echo "[case 6: --quiet flag]"
F6="$WORK/case6.md"
write_skill_legacy "$F6" "All green, OR 3 retries"
out=$(bash "$MIGRATOR" --quiet "$F6" 2>&1); rc=$?
assert_exit 0 "$rc" "exit 0 with --quiet"
assert_not_contains "ORIGINAL:" "$out" "no ORIGINAL line"
assert_not_contains "PROPOSED:" "$out" "no PROPOSED line"

# ── Case 7: deterministic — same input twice yields same output
echo ""
echo "[case 7: deterministic dry-run output]"
F7="$WORK/case7.md"
write_skill_legacy "$F7" "Workflow run conclusion == success, OR failure maps to unknown error"
out1=$(bash "$MIGRATOR" "$F7" 2>&1)
out2=$(bash "$MIGRATOR" "$F7" 2>&1)
if [ "$out1" = "$out2" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: identical output on repeat invocation"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: dry-run not deterministic")
    echo "  FAIL: dry-run output differs between runs"
fi

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
