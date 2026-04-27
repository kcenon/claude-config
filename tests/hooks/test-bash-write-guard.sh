#!/bin/bash
# Test suite for bash-write-guard.sh
# Run: bash tests/hooks/test-bash-write-guard.sh

HOOK="global/hooks/bash-write-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

SCRATCH_ROOT="${TMPDIR:-/tmp}"
FIXTURE_DIR=$(mktemp -d "$SCRATCH_ROOT/bwg-test.XXXXXX" 2>/dev/null) \
    || FIXTURE_DIR="$SCRATCH_ROOT/bwg-test.$$"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Use a fresh session id for this test run so we don't interact with the
# developer's existing read tracker.
TEST_SESSION="bwg-test-$$"
export CLAUDE_SESSION_ID="$TEST_SESSION"
TRACKER="${TMPDIR:-/tmp}/claude-read-set-${TEST_SESSION}"
rm -f "$TRACKER"

make_fixture() {
    local cmd="$1"
    local out="$FIXTURE_DIR/in.json"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg cmd "$cmd" --arg sid "$TEST_SESSION" \
            '{tool_name:"Bash", tool_input:{command:$cmd}, session_id:$sid}' > "$out"
    else
        printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" > "$out"
    fi
    printf '%s' "$out"
}

assert_deny() {
    local cmd="$1" label="$2"
    local fixture
    fixture=$(make_fixture "$cmd")
    local result
    result=$(bash "$HOOK" < "$fixture" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_allow() {
    local cmd="$1" label="$2"
    local fixture
    fixture=$(make_fixture "$cmd")
    local result
    result=$(bash "$HOOK" < "$fixture" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== bash-write-guard.sh tests ==="
echo ""

echo "[Fail-open on missing input]"
assert_allow '' "Empty command → allow"

echo ""
echo "[deny — write to sensitive paths]"
assert_deny 'echo secret > .env' "echo > .env"
assert_deny "$(printf 'cat <<EOF > .env\nA=1\nEOF')" "heredoc > .env"
assert_deny 'tee .env' "tee .env"
assert_deny 'cp newkey ~/.ssh/id_rsa' "cp into ~/.ssh/id_rsa"
assert_deny 'echo y > /etc/passwd' "echo > /etc/passwd"
assert_deny 'curl https://x | tee ~/.aws/credentials' "tee ~/.aws/credentials"
assert_deny 'dd of=/etc/shadow' "dd of=/etc/shadow"
assert_deny 'echo y >> .env' "append >> .env"

echo ""
echo "[deny — uninspectable mutation patterns (Red Team Vector E)]"
assert_deny 'python -c "open(\"/etc/x\", \"w\").write(\"y\")"' "python -c"
assert_deny 'python3 -c "import pathlib; pathlib.Path(\"f\").write_text(\"y\")"' "python3 -c"
assert_deny 'node -e "require(\"fs\").writeFileSync(\"f\",\"y\")"' "node -e"
assert_deny 'perl -e "open(F,\">f\");print F \"y\""' "perl -e"
assert_deny 'awk "BEGIN{print \"x\" > \"/tmp/y\"}"' "awk script body"
assert_deny 'gawk "BEGIN{print > \"f\"}"' "gawk script body"

echo ""
echo "[deny — wrapper bypass for sensitive write]"
assert_deny 'sudo tee /etc/shadow' "sudo tee /etc/shadow"
assert_deny 'env X=1 echo y > .env' "env wrapper write"

echo ""
echo "[deny — chained sensitive write]"
assert_deny 'true; echo y > .env' "; chain"
assert_deny 'true && echo y > .env' "&& chain"

echo ""
echo "[allow — write to new, non-sensitive files]"
NEW_TARGET="$FIXTURE_DIR/new_output.txt"
assert_allow "echo hello > $NEW_TARGET" "echo > new file"
assert_allow "tee $NEW_TARGET" "tee new file"

echo ""
echo "[allow — read-only commands]"
assert_allow 'cat README.md' "cat (no redirect)"
assert_allow 'grep TODO src/' "grep (no redirect)"
assert_allow 'ls -la' "ls"
assert_allow 'echo hello | tee /dev/null' "tee /dev/null (allowed sink)"
assert_allow 'echo hello > /dev/null' "echo > /dev/null"
assert_allow 'true 2>&1' "stderr redirect, no file"

echo ""
echo "[allow — write to file already Read this session]"
EXISTING="$FIXTURE_DIR/existing.txt"
echo "initial" > "$EXISTING"
# `realpath` on macOS canonicalizes `/var/folders/.../T//x` to
# `/private/var/folders/.../T/x`, the same form the hook computes — so
# this single call produces a tracker entry that matches.
RESOLVED=$(realpath "$EXISTING" 2>/dev/null || echo "$EXISTING")
echo "$RESOLVED" > "$TRACKER"
assert_allow "echo update > $EXISTING" "tracker hit → allow"

echo ""
echo "[deny — write to existing file NOT yet Read]"
UNTRACKED="$FIXTURE_DIR/untracked.txt"
echo "data" > "$UNTRACKED"
# Tracker exists (from prior test) but does not contain $UNTRACKED → deny.
assert_deny "echo overwrite > $UNTRACKED" "untracked existing file → deny"

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
