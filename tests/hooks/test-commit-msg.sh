#!/bin/bash
# Test suite for hooks/commit-msg (git hook) and hooks/lib/validate-commit-message.sh
# Run: bash tests/hooks/test-commit-msg.sh

HOOK="hooks/commit-msg"
VALIDATOR_LIB="hooks/lib/validate-commit-message.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Verify scripts exist
if [ ! -f "$HOOK" ]; then
    echo "ERROR: $HOOK not found"
    exit 1
fi
if [ ! -f "$VALIDATOR_LIB" ]; then
    echo "ERROR: $VALIDATOR_LIB not found"
    exit 1
fi

# Helper: create a temp commit message file and run the hook
run_hook() {
    local msg="$1"
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s\n' "$msg" > "$tmpfile"
    bash "$HOOK" "$tmpfile" 2>&1
    local rc=$?
    rm -f "$tmpfile"
    return $rc
}

assert_accept() {
    local msg="$1" label="$2"
    if run_hook "$msg" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected accept (exit 0)")
        echo "  FAIL: $label"
    fi
}

assert_reject() {
    local msg="$1" label="$2"
    if run_hook "$msg" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected reject (exit 1)")
        echo "  FAIL: $label"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    fi
}

echo "=== commit-msg hook tests ==="
echo ""

echo "[valid conventional commits]"
assert_accept "feat: add new feature" "feat: basic"
assert_accept "fix(auth): handle null token" "fix(scope): with scope"
assert_accept "docs(readme): update installation steps" "docs(readme): docs type"
assert_accept "security: patch credential leak" "security: security type"
assert_accept "refactor: simplify config loader" "refactor: refactor type"
assert_accept "chore: update dependencies" "chore: chore type"
assert_accept "test(unit): add parser tests" "test(scope): test type"
assert_accept "build: upgrade cmake to 3.28" "build: build type"
assert_accept "ci: add shellcheck workflow" "ci: ci type"
assert_accept "perf: optimize hot loop" "perf: perf type"
assert_accept "style: fix indentation" "style: style type"

echo ""
echo "[format violations]"
assert_reject "added new feature" "no type prefix"
assert_reject "feat add new feature" "missing colon"
assert_reject "wip: some stuff" "invalid type 'wip'"
assert_reject "feat(BadScope): desc" "uppercase scope"
assert_reject "update: things" "invalid type 'update'"

echo ""
echo "[description rules]"
assert_reject "feat: Added new feature" "uppercase first char"
assert_reject "fix: resolve issue." "trailing period"

echo ""
echo "[AI attribution]"
assert_reject "feat: add claude integration" "claude keyword"
assert_reject "fix: anthropic API fallback" "anthropic keyword"
assert_reject "fix: ai-assisted refactor" "ai-assisted"
assert_reject "feat: add feature generated with claude code" "generated with"

echo ""
echo "[emoji detection]"
EMOJI_PARTY=$(printf '\xf0\x9f\x8e\x89')
assert_reject "feat: ${EMOJI_PARTY} party hat" "emoji party face"

echo ""
echo "[edge cases]"
assert_accept "" "empty message (git rejects separately)"
assert_accept "# This is a comment" "comment-only message"

echo ""
echo "[git comment stripping]"
# Simulate a message file with git comments
TMPFILE=$(mktemp)
printf 'feat: add feature\n# Please enter the commit message\n# Changes:\n#   modified: file.txt\n' > "$TMPFILE"
if bash "$HOOK" "$TMPFILE" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: message with git comments accepted"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: message with git comments — expected accept")
    echo "  FAIL: message with git comments"
fi
rm -f "$TMPFILE"

echo ""
echo "[shared lib direct test]"
# shellcheck source=../../hooks/lib/validate-commit-message.sh
. "$VALIDATOR_LIB"

if validate_commit_message "feat: direct lib call" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: validate_commit_message direct call — valid"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: direct lib call valid message — expected 0")
    echo "  FAIL: validate_commit_message direct call — valid"
fi

if validate_commit_message "bad message" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: direct lib call invalid message — expected 1")
    echo "  FAIL: validate_commit_message direct call — invalid"
else
    PASS=$((PASS + 1))
    echo "  PASS: validate_commit_message direct call — invalid"
fi

echo ""
echo "[determinism — 3 identical runs]"
TMPFILE=$(mktemp)
printf 'feat: deterministic check\n' > "$TMPFILE"
R1=$(bash "$HOOK" "$TMPFILE" 2>&1; echo "RC=$?")
R2=$(bash "$HOOK" "$TMPFILE" 2>&1; echo "RC=$?")
R3=$(bash "$HOOK" "$TMPFILE" 2>&1; echo "RC=$?")
rm -f "$TMPFILE"
if [ "$R1" = "$R2" ] && [ "$R2" = "$R3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: 3 runs produced identical output"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: non-deterministic output across runs")
    echo "  FAIL: 3 runs differed"
fi

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
