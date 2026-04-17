#!/bin/bash
# Test suite for markdown-anchor-validator.sh
# Covers bugs A-D documented in issue #339.
# Run: bash tests/hooks/test-markdown-anchor-validator.sh

set -u
HOOK="global/hooks/markdown-anchor-validator.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available on PATH; validator tests require jq"
    exit 0
fi

# Each fixture case runs the hook in a temp dir with a single markdown file
# under docs/ so the validator picks it up (it searches docs/*.md).
run_hook_against_fixture() {
    local fixture="$1"
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/docs"
    cp "tests/markdown-anchor-validator/fixtures/$fixture" "$tmpdir/docs/$fixture"
    local hook_abs
    hook_abs="$(pwd)/$HOOK"
    (cd "$tmpdir" && echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null)
    local rc=$?
    rm -rf "$tmpdir"
    return $rc
}

run_hook_capture() {
    local fixture="$1"
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/docs"
    cp "tests/markdown-anchor-validator/fixtures/$fixture" "$tmpdir/docs/$fixture"
    local hook_abs
    hook_abs="$(pwd)/$HOOK"
    (cd "$tmpdir" && echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null)
    rm -rf "$tmpdir"
}

assert_deny_fixture() {
    local fixture="$1" label="$2"
    local out
    out=$(run_hook_capture "$fixture")
    if echo "$out" | grep -q '"deny"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected deny, got: $out")
        echo "  FAIL: $label"
    fi
}

assert_allow_fixture() {
    local fixture="$1" label="$2"
    local out
    out=$(run_hook_capture "$fixture")
    if echo "$out" | grep -q '"allow"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected allow, got: $out")
        echo "  FAIL: $label"
    fi
}

assert_valid_json() {
    local fixture="$1" label="$2"
    local out
    out=$(run_hook_capture "$fixture")
    if echo "$out" | jq empty 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — output is not valid JSON: $out")
        echo "  FAIL: $label"
    fi
}

echo "=== markdown-anchor-validator.sh tests ==="
echo ""

echo "[Bug A: 7+ hashes are not headings]"
assert_deny_fixture "bug-a-excessive-hashes.md" "ref to ####### line → deny (broken anchor)"

echo ""
echo "[Bug B: inline code spans are not live references]"
assert_allow_fixture "bug-b-inline-code.md" "\`[a](#x)\` inside backticks → allow"

echo ""
echo "[Bug C: JSON output remains well-formed with backslash in anchor]"
assert_valid_json "bug-c-backslash.md" "anchor with backslash → valid JSON"

echo ""
echo "[Baseline: no false positives on well-formed markdown]"
assert_allow_fixture "baseline-valid.md" "valid intra-file refs → allow"

echo ""
echo "[Non-commit commands pass through]"
# These don't need a fixture — they exit before reading any markdown.
result=$(echo '{"tool_input":{"command":"ls -la"}}' | bash "$HOOK" 2>/dev/null)
if echo "$result" | grep -q '"allow"'; then
    PASS=$((PASS + 1)); echo "  PASS: ls -la → allow"
else
    FAIL=$((FAIL + 1)); echo "  FAIL: ls -la — got: $result"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
fi
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ]
