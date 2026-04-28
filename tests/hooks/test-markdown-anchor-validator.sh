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

# Each fixture case runs the hook against a real (tiny) git repo with the
# fixture staged. The hook now collects files via `git diff --cached`, so
# the fixture must be staged for the validator to see it.
#
# $1: fixture filename under tests/markdown-anchor-validator/fixtures/
# $2: optional staged path inside the temp repo (default: docs/<fixture>)
run_hook_capture() {
    local fixture="$1"
    local fixture_dest="${2:-docs/$fixture}"
    local root_abs hook_abs tmpdir
    root_abs="$(pwd)"
    hook_abs="${root_abs}/${HOOK}"
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir" && \
        git init -q && \
        git config user.email "ci@example.com" && \
        git config user.name "CI" && \
        mkdir -p "$(dirname "$fixture_dest")" && \
        cp "${root_abs}/tests/markdown-anchor-validator/fixtures/${fixture}" "${fixture_dest}" && \
        git add -A && \
        echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null
    )
    rm -rf "$tmpdir"
}

# $3 (optional): staged path inside the temp repo. Forwarded to
# run_hook_capture; defaults to docs/<fixture>.
assert_deny_fixture() {
    local fixture="$1" label="$2" dest="${3:-}"
    local out
    out=$(run_hook_capture "$fixture" "$dest")
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
    local fixture="$1" label="$2" dest="${3:-}"
    local out
    out=$(run_hook_capture "$fixture" "$dest")
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
    local fixture="$1" label="$2" dest="${3:-}"
    local out
    out=$(run_hook_capture "$fixture" "$dest")
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
echo "[Parity: staged .md outside docs/ is also checked]"
# The bash hook previously scanned only docs/*.md and silently skipped
# top-level files (HOOKS.md, README.md, etc.), while the PowerShell
# variant already used `git diff --cached` and caught them. Stage a
# fixture with a known-broken anchor at the repo root; the bash hook
# must now reach it and deny.
assert_deny_fixture "bug-a-excessive-hashes.md" \
    "root-level .md with broken anchor → deny" \
    "top-level.md"

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
