#!/bin/bash
# Test suite for post-task-checkpoint.sh
# Run: bash tests/hooks/test-post-task-checkpoint.sh

HOOK_SRC="global/hooks/post-task-checkpoint.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

HOOK_ABS="$(pwd)/$HOOK_SRC"

# Prepare an isolated fixture git repo for each test case.
make_fixture_repo() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/ptc-fixture.XXXXXX")
    (
        cd "$dir" || exit 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test"
        git config commit.gpgsign false
        echo "seed" > seed.txt
        git add seed.txt
        git -c core.hooksPath=/dev/null commit -q --no-verify -m "seed: initial"
    )
    echo "$dir"
}

commit_count() {
    git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0
}

latest_subject() {
    git -C "$1" log -1 --pretty=%s 2>/dev/null || echo ""
}

assert_count_delta() {
    local dir="$1" before="$2" expected_delta="$3" label="$4"
    local after actual_delta
    after=$(commit_count "$dir")
    actual_delta=$((after - before))
    if [ "$actual_delta" -eq "$expected_delta" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (commits +$actual_delta)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected +$expected_delta commit(s), got +$actual_delta")
        echo "  FAIL: $label (expected +$expected_delta, got +$actual_delta)"
    fi
}

assert_subject_contains() {
    local dir="$1" needle="$2" label="$3"
    local subj
    subj=$(latest_subject "$dir")
    if echo "$subj" | grep -q "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — latest subject '$subj' missing '$needle'")
        echo "  FAIL: $label (subject='$subj')"
    fi
}

assert_exit() {
    local input="$1" expected="$2" label="$3" dir="$4"
    local actual
    (
        cd "$dir" || exit 1
        printf '%s' "$input" | bash "$HOOK_ABS" >/dev/null 2>&1
    )
    actual=$?
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $actual)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected exit $expected, got $actual")
        echo "  FAIL: $label (expected $expected, got $actual)"
    fi
}

run_hook() {
    local input="$1" dir="$2"
    (
        cd "$dir" || exit 1
        printf '%s' "$input" | bash "$HOOK_ABS" >/dev/null 2>&1
    )
}

echo "=== post-task-checkpoint.sh tests ==="
echo ""

# ---- 1. Task tool with changes → commits ----
echo "[Task tool with dirty tree → checkpoint commit created]"
REPO1=$(make_fixture_repo)
BEFORE=$(commit_count "$REPO1")
echo "agent work" > "$REPO1/new-file.txt"
INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"researcher"}}'
run_hook "$INPUT" "$REPO1"
assert_count_delta "$REPO1" "$BEFORE" 1 "Task tool + dirty tree → +1 commit"
assert_subject_contains "$REPO1" "wip(agent): researcher checkpoint" "commit subject includes agent name"
rm -rf "$REPO1"
echo ""

# ---- 2. Agent tool with changes → commits ----
echo "[Agent tool with dirty tree → checkpoint commit created]"
REPO2=$(make_fixture_repo)
BEFORE=$(commit_count "$REPO2")
echo "more work" > "$REPO2/another.txt"
INPUT='{"tool_name":"Agent","tool_input":{"name":"coder"}}'
run_hook "$INPUT" "$REPO2"
assert_count_delta "$REPO2" "$BEFORE" 1 "Agent tool + dirty tree → +1 commit"
assert_subject_contains "$REPO2" "wip(agent): coder checkpoint" "commit subject uses fallback name field"
rm -rf "$REPO2"
echo ""

# ---- 3. Non-matching tool → no-op ----
echo "[non-matching tool → no-op]"
REPO3=$(make_fixture_repo)
BEFORE=$(commit_count "$REPO3")
echo "stray" > "$REPO3/stray.txt"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"stray.txt"}}'
run_hook "$INPUT" "$REPO3"
assert_count_delta "$REPO3" "$BEFORE" 0 "Edit tool → no commit"
rm -rf "$REPO3"
echo ""

# ---- 4. Clean tree → no-op ----
echo "[clean tree → no-op]"
REPO4=$(make_fixture_repo)
BEFORE=$(commit_count "$REPO4")
INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"explorer"}}'
run_hook "$INPUT" "$REPO4"
assert_count_delta "$REPO4" "$BEFORE" 0 "Task on clean tree → no commit (hook skips)"
rm -rf "$REPO4"
echo ""

# ---- 5. Outside git worktree → no-op, exit 0 ----
echo "[outside git worktree → no-op, exit 0]"
NON_REPO=$(mktemp -d "${TMPDIR:-/tmp}/ptc-nonrepo.XXXXXX")
INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"x"}}'
assert_exit "$INPUT" 0 "non-git directory → exit 0" "$NON_REPO"
rm -rf "$NON_REPO"
echo ""

# ---- 6. Malformed stdin → fail-open ----
echo "[malformed stdin → fail-open]"
REPO6=$(make_fixture_repo)
assert_exit "not json"  0 "garbage stdin → exit 0"       "$REPO6"
assert_exit ""          0 "empty stdin → exit 0"         "$REPO6"
assert_exit "{}"        0 "empty object → exit 0"        "$REPO6"
assert_exit '{"tool_name":' 0 "truncated JSON → exit 0"  "$REPO6"
rm -rf "$REPO6"
echo ""

# ---- 7. Agent-name sanitization ----
echo "[agent name sanitization]"
REPO7=$(make_fixture_repo)
echo "work" > "$REPO7/x.txt"
# Inject weird chars; only [A-Za-z0-9_-] survive.
INPUT='{"tool_name":"Task","tool_input":{"subagent_type":"my agent/name; rm -rf"}}'
run_hook "$INPUT" "$REPO7"
assert_subject_contains "$REPO7" "myagentname" "weird chars stripped from agent name"
rm -rf "$REPO7"
echo ""

# ---- 8. Overwrite protection scenario ----
# Simulates the original bug: two sequential agents touch the same file.
# Without the hook, agent-B's write clobbers agent-A's write.
# With the hook, agent-A's change lands in a checkpoint commit BEFORE
# agent-B runs — so agent-B sees agent-A's work in git history.
echo "[overwrite protection — two sequential agents]"
REPO8=$(make_fixture_repo)
echo "agent-A output" > "$REPO8/shared.txt"
run_hook '{"tool_name":"Task","tool_input":{"subagent_type":"agent-A"}}' "$REPO8"
# Agent-B now overwrites shared.txt
echo "agent-B output" > "$REPO8/shared.txt"
run_hook '{"tool_name":"Task","tool_input":{"subagent_type":"agent-B"}}' "$REPO8"

# History must contain both checkpoints.
LOG=$(git -C "$REPO8" log --pretty=%s)
if echo "$LOG" | grep -q "agent-A checkpoint" && echo "$LOG" | grep -q "agent-B checkpoint"; then
    PASS=$((PASS + 1))
    echo "  PASS: both agent checkpoints present in history"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: sequential agent checkpoints not both in history: $LOG")
    echo "  FAIL: sequential checkpoints missing — log: $LOG"
fi
# Agent-A's output must be recoverable from history even though agent-B
# overwrote the working tree.
CONTENT_AT_A=$(git -C "$REPO8" show HEAD~1:shared.txt 2>/dev/null)
if [ "$CONTENT_AT_A" = "agent-A output" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: agent-A output recoverable from HEAD~1 (overwrite survived)"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: agent-A output lost — HEAD~1 shared.txt = '$CONTENT_AT_A'")
    echo "  FAIL: agent-A output lost — HEAD~1 shared.txt = '$CONTENT_AT_A'"
fi
rm -rf "$REPO8"
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
