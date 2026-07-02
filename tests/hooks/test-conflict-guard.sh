#!/bin/bash
# Test suite for conflict-guard.sh decision logic.
# conflict-guard inspects the CWD git state, so each assertion runs the hook
# with CWD set to a throwaway git repo whose state we manipulate.
# Run: bash tests/hooks/test-conflict-guard.sh

cd "$(dirname "$0")/../.." || exit 1
HOOK="$PWD/global/hooks/conflict-guard.sh"

PASS=0
FAIL=0
ERRORS=()

SCRATCH_ROOT="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$SCRATCH_ROOT/cg-test.XXXXXX" 2>/dev/null) || WORK="$SCRATCH_ROOT/cg-test.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Initialize a clean repo with one commit.
REPO="$WORK/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "seed" > seed.txt
    git add seed.txt
    git commit -qm "seed"
) || { echo "FATAL: could not init test repo"; exit 1; }

GITDIR="$REPO/.git"

# Run the hook with CWD = $REPO (where git state lives).
run_in_repo() {
    local input="$1"
    ( cd "$REPO" && printf '%s' "$input" | bash "$HOOK" 2>/dev/null )
}

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(run_in_repo "$input")
    if echo "$result" | grep -q '"deny"'; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label — expected deny, got: $result"); echo "  FAIL: $label"
    fi
}

assert_deny_contains() {
    local input="$1" needle="$2" label="$3"
    local result
    result=$(run_in_repo "$input")
    if echo "$result" | grep -q '"deny"' && echo "$result" | grep -Fq "$needle"; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label — expected deny containing '$needle', got: $result"); echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2"
    local result
    result=$(run_in_repo "$input")
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label — expected allow, got: $result"); echo "  FAIL: $label"
    fi
}

clean_state() {
    rm -f "$GITDIR/MERGE_HEAD" "$GITDIR/REBASE_HEAD" "$GITDIR/CHERRY_PICK_HEAD"
    ( cd "$REPO" && git checkout -q -- . 2>/dev/null; git clean -fdq 2>/dev/null )
}

echo "=== conflict-guard.sh tests ==="
echo ""

echo "[Fail-open]"
assert_allow '' "Empty input -> allow"
assert_allow '{"tool_input":{"command":"ls -la"}}' "non-git command -> allow (out of scope)"
assert_allow '{"tool_input":{"command":"git status"}}' "git status -> allow (out of scope)"

echo ""
echo "[Clean repo: in-scope commands allowed]"
clean_state
assert_allow '{"tool_input":{"command":"git merge feature"}}' "git merge on clean repo -> allow"
assert_allow '{"tool_input":{"command":"git rebase main"}}'   "git rebase on clean repo -> allow"

echo ""
echo "[Existing conflict state -> deny]"
clean_state
: > "$GITDIR/MERGE_HEAD"
assert_deny '{"tool_input":{"command":"git merge feature"}}' "merge with MERGE_HEAD present -> deny"
clean_state
: > "$GITDIR/REBASE_HEAD"
assert_deny '{"tool_input":{"command":"git rebase main"}}' "rebase with REBASE_HEAD present -> deny"
clean_state
: > "$GITDIR/CHERRY_PICK_HEAD"
assert_deny '{"tool_input":{"command":"git cherry-pick abc123"}}' "cherry-pick with CHERRY_PICK_HEAD present -> deny"

echo ""
echo "[Dirty working tree (tracked modifications) -> deny]"
clean_state
# Modify a tracked file so the porcelain status is a tracked change (' M'),
# not an untracked entry ('??').
echo "modified" >> "$REPO/seed.txt"
assert_deny '{"tool_input":{"command":"git merge feature"}}' "merge with tracked modification -> deny"
assert_deny_contains '{"tool_input":{"command":"git pull"}}' "git stash && git pull && git stash pop" "pull with tracked modification includes stash retry"

echo ""
echo "[Untracked-only working tree -> allow (#747)]"
clean_state
# A brand-new file that git is not tracking shows as '??' in porcelain.
# merge/rebase/cherry-pick/pull never silently clobber untracked files, so
# this must not block.
echo "scratch" > "$REPO/untracked.txt"
assert_allow '{"tool_input":{"command":"git pull"}}' "pull with untracked-only -> allow"
assert_allow '{"tool_input":{"command":"git merge feature"}}' "merge with untracked-only -> allow"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf '%s\n' "${ERRORS[@]}"
    exit 1
fi
exit 0
