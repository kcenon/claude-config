#!/bin/bash
# Test suite for scripts/extract-doc-description.sh (#625).
#
# Run: bash tests/doc-index/test-extract-doc-description.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

SCRIPT="scripts/extract-doc-description.sh"
FIX="tests/doc-index/fixtures"
PASS=0
FAIL=0
ERRORS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected '$expected', got '$actual'")
        echo "  FAIL: $label"
    fi
}

assert_exit() {
    local label="$1" expected_rc="$2" actual_rc="$3"
    if (( actual_rc == expected_rc )); then
        ((PASS++))
        echo "  PASS: $label (rc=$actual_rc)"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected rc=$expected_rc, got rc=$actual_rc")
        echo "  FAIL: $label"
    fi
}

echo "=== extract-doc-description.sh tests (#625) ==="
echo ""

echo "[Plain prose document]"
out=$(bash "$SCRIPT" "$FIX/normal.md")
rc=$?
assert_exit "normal.md exits 0" 0 "$rc"
assert_eq "normal.md returns first prose paragraph" \
    "This is the first prose paragraph and should be returned as the description." \
    "$out"

echo ""
echo "[Document opening with HTML badges]"
out=$(bash "$SCRIPT" "$FIX/html-only.md")
rc=$?
assert_exit "html-only.md exits 0" 0 "$rc"
assert_eq "html-only.md strips tags and returns prose inside <strong>" \
    "Real description hidden inside an HTML strong tag" \
    "$out"

echo ""
echo "[Document with YAML frontmatter]"
out=$(bash "$SCRIPT" "$FIX/frontmatter-only.md")
rc=$?
assert_exit "frontmatter-only.md exits 0" 0 "$rc"
assert_eq "frontmatter-only.md skips frontmatter + heading and returns prose" \
    "The first prose line that the extractor should pick up." \
    "$out"

echo ""
echo "[Document with no prose body]"
out=$(bash "$SCRIPT" "$FIX/empty.md")
rc=$?
assert_exit "empty.md exits 1 (no description)" 1 "$rc"
assert_eq "empty.md emits empty stdout" "" "$out"

echo ""
echo "[Real READMEs (regression for the original bug)]"
out=$(bash "$SCRIPT" "README.ko.md")
rc=$?
assert_exit "README.ko.md exits 0" 0 "$rc"
case "$out" in
    '<p align'*)
        ((FAIL++))
        ERRORS+=("FAIL: README.ko.md returned the bug's HTML tag")
        echo "  FAIL: README.ko.md still returns HTML tag"
        ;;
    '')
        ((FAIL++))
        ERRORS+=("FAIL: README.ko.md returned empty")
        echo "  FAIL: README.ko.md returned empty"
        ;;
    *)
        ((PASS++))
        echo "  PASS: README.ko.md returns meaningful prose: $out"
        ;;
esac

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
