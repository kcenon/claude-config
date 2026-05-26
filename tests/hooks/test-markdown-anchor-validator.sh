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

# Cross-file scenario runner: stages one fixture as $1 (placed at docs/$1
# by default), while ALSO copying a sidecar fixture next to it on disk
# WITHOUT staging it. This is the exact pattern that exposes the
# cross-file resolution false positive — the inter-file ref's target
# exists in the working tree but is not in `git diff --cached`.
#
# $1: staged fixture filename
# $2: sidecar fixture filename (copied next to staged file but unstaged)
# $3: optional staged-path override (default: docs/$1)
# $4: optional sidecar-path override (default: docs/$2)
run_cross_file_hook_capture() {
    local staged_fixture="$1"
    local sidecar_fixture="$2"
    local staged_dest="${3:-docs/$staged_fixture}"
    local sidecar_dest="${4:-docs/$sidecar_fixture}"
    local root_abs hook_abs tmpdir
    root_abs="$(pwd)"
    hook_abs="${root_abs}/${HOOK}"
    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir" && \
        git init -q && \
        git config user.email "ci@example.com" && \
        git config user.name "CI" && \
        mkdir -p "$(dirname "$staged_dest")" "$(dirname "$sidecar_dest")" && \
        cp "${root_abs}/tests/markdown-anchor-validator/fixtures/${staged_fixture}" "${staged_dest}" && \
        cp "${root_abs}/tests/markdown-anchor-validator/fixtures/${sidecar_fixture}" "${sidecar_dest}" && \
        git add -- "${staged_dest}" && \
        echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null
    )
    rm -rf "$tmpdir"
}

assert_cross_file_allow() {
    local staged="$1" sidecar="$2" label="$3"
    local out
    out=$(run_cross_file_hook_capture "$staged" "$sidecar")
    if echo "$out" | grep -q '"allow"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected allow, got: $out")
        echo "  FAIL: $label"
    fi
}

assert_cross_file_deny() {
    local staged="$1" sidecar="$2" label="$3"
    local out
    out=$(run_cross_file_hook_capture "$staged" "$sidecar")
    if echo "$out" | grep -q '"deny"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected deny, got: $out")
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
echo "[Cross-file resolution: unstaged target with valid anchor → allow]"
# Regression target for issue #646. Staged file references an anchor in a
# sibling file that exists on disk but is NOT staged. Before the fix, the
# anchor registry (built from staged files only) missed the target's
# headings and the hook denied the commit. After the fix, the validator
# lazy-parses the unstaged sibling and recognizes the anchor.
assert_cross_file_allow \
    "cross-file-source.md" \
    "cross-file-target.md" \
    "unstaged target heading → allow"

echo ""
echo "[Cross-file resolution: existing file but missing anchor → deny]"
# Negative case authored inline — the fixture itself would have a broken
# inter-file reference and would fail the hook on its own commit, so we
# materialize the file inside the temp repo at test time.
root_abs="$(pwd)"
hook_abs="${root_abs}/${HOOK}"
tmpdir=$(mktemp -d)
out=$(
    cd "$tmpdir" && \
    git init -q && \
    git config user.email "ci@example.com" && \
    git config user.name "CI" && \
    mkdir -p docs && \
    cp "${root_abs}/tests/markdown-anchor-validator/fixtures/cross-file-target.md" docs/cross-file-target.md && \
    cat > docs/source.md <<'MDFILE'
# Source with missing anchor

[missing](cross-file-target.md#definitely-missing-heading)
MDFILE
    git add docs/source.md && \
    echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null
)
rm -rf "$tmpdir"
if echo "$out" | grep -q '"deny"'; then
    PASS=$((PASS + 1)); echo "  PASS: unstaged target missing the requested anchor → deny"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: missing anchor inline case — expected deny, got: $out")
    echo "  FAIL: unstaged target missing the requested anchor → deny"
fi

echo ""
echo "[Cross-file resolution: target file does not exist → deny]"
# No sidecar — the referenced file is absent on disk. Lazy resolution
# must produce an empty anchor set and the validator must deny.
tmpdir=$(mktemp -d)
out=$(
    cd "$tmpdir" && \
    git init -q && \
    git config user.email "ci@example.com" && \
    git config user.name "CI" && \
    mkdir -p docs && \
    cat > docs/source.md <<'MDFILE'
# Source with missing file

[missing](no-such-file.md#whatever)
MDFILE
    git add docs/source.md && \
    echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$hook_abs" 2>/dev/null
)
rm -rf "$tmpdir"
if echo "$out" | grep -q '"deny"'; then
    PASS=$((PASS + 1)); echo "  PASS: missing referenced file → deny"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: missing referenced file — expected deny, got: $out")
    echo "  FAIL: missing referenced file → deny"
fi

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
