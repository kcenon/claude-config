#!/bin/bash
# Test suite for memory-write-guard.sh
# Run: bash tests/hooks/test-memory-write-guard.sh
#
# Validates the path gate, validation flow, and decision logic of the
# memory-write-guard PreToolUse hook (issue #521).

set -u

HOOK="global/hooks/memory-write-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Establish a test memory tree under HOME so the hook's path gate triggers.
TEST_HOME="$(mktemp -d -t mwg-home.XXXXXX)"
export HOME="$TEST_HOME"
MEM="$HOME/.claude/memory-shared/memories"
mkdir -p "$MEM"

# Symlink validators to ${HOME}/.claude/scripts/memory/ so the hook's
# locator finds them regardless of the user's installed claude-config.
mkdir -p "$HOME/.claude/scripts/memory"
ln -sf "$(pwd)/scripts/memory/validate.sh"        "$HOME/.claude/scripts/memory/validate.sh"
ln -sf "$(pwd)/scripts/memory/secret-check.sh"    "$HOME/.claude/scripts/memory/secret-check.sh"
ln -sf "$(pwd)/scripts/memory/injection-check.sh" "$HOME/.claude/scripts/memory/injection-check.sh"

cleanup() {
    rm -rf "$TEST_HOME" 2>/dev/null || true
}
trap cleanup EXIT

# ----- helpers ---------------------------------------------------------------

decision_of() {
    # Print the permissionDecision field from the hook's JSON output.
    printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('hookSpecificOutput',{}).get('permissionDecision',''))" 2>/dev/null
}

assert_decision() {
    local input="$1" expected="$2" label="$3"
    local result decision
    result=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)
    decision=$(decision_of "$result")
    if [ "$decision" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected $expected, got $decision; raw=$result")
        echo "  FAIL: $label (got $decision, expected $expected)"
    fi
}

build_payload() {
    # Use jq to safely encode tool_name + file_path + content as JSON.
    local tool="$1" fp="$2" content="$3"
    jq -n -c --arg tool "$tool" --arg fp "$fp" --arg content "$content" \
        '{tool_name:$tool,tool_input:{file_path:$fp,content:$content}}'
}

build_edit_payload() {
    local fp="$1" old="$2" new="$3" replace_all="${4:-false}"
    jq -n -c --arg fp "$fp" --arg old "$old" --arg new "$new" --argjson r "$replace_all" \
        '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:$old,new_string:$new,replace_all:$r}}'
}

CLEAN_BODY="---
name: Clean memory
description: A clean test fixture.
type: feedback
---

This is a body. **Why:** because we need a clean test fixture incident reference. **How to apply:** use this exact pattern when validating new feedback memories.
"

SECRET_BODY="---
name: Bad memory
description: Has a leaked AWS key.
type: feedback
---

body body body body body. **Why:** test reason. **How to apply:** key is AKIAIOSFODNN7EXAMPLE oh no.
"

INJECTION_BODY="---
name: Strict rule
description: Multiple absolute commands.
type: feedback
---

You must always commit messages. Never skip CI. Always run tests because incident #142 happened. From now on we always test. **Why:** safety. **How to apply:** read the rules.
"

# ----- tests -----------------------------------------------------------------

echo "=== memory-write-guard.sh tests ==="
echo ""

echo "[Pass-through]"
assert_decision '' 'allow' 'Empty stdin -> allow (fail-open)'
assert_decision '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' 'allow' 'Read tool -> allow (only Edit/Write guarded)'
assert_decision '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 'allow' 'Bash tool -> allow'
assert_decision "$(build_payload Write /tmp/non-memory.txt 'hello')" 'allow' 'Non-memory path -> allow (fast pass)'
assert_decision "$(build_payload Write "$MEM/MEMORY.md" 'index')" 'allow' 'MEMORY.md -> allow (exempt)'
assert_decision '{"tool_name":"Write","tool_input":{"content":"x"}}' 'allow' 'Missing file_path -> allow (fail-open)'

echo ""
echo "[Memory write decisions]"
assert_decision "$(build_payload Write "$MEM/feedback_clean.md" "$CLEAN_BODY")" 'allow' 'Clean memory write -> allow'
assert_decision "$(build_payload Write "$MEM/feedback_leak.md" "$SECRET_BODY")" 'deny'  'Secret in memory -> deny'
assert_decision "$(build_payload Write "$MEM/feedback_strict.md" "$INJECTION_BODY")" 'allow' 'Injection density -> allow with feedback (warn-only)'

echo ""
echo "[Edit simulation]"
EDIT_FIXTURE="$MEM/feedback_edit_target.md"
cat > "$EDIT_FIXTURE" <<EDITEOF
---
name: Edit target
description: An existing memory used to test edit-time validation.
type: feedback
---

Original body. **Why:** because we set it up. **How to apply:** read the original.
EDITEOF
assert_decision "$(build_edit_payload "$EDIT_FIXTURE" 'Original body' 'Updated body')" 'allow' 'Clean Edit -> allow'
assert_decision "$(build_edit_payload "$EDIT_FIXTURE" 'Original body.' 'AKIAIOSFODNN7EXAMPLE leaked.')" 'deny' 'Edit injects secret -> deny'
assert_decision "$(build_edit_payload "$EDIT_FIXTURE" 'the' 'AKIAIOSFODNN7EXAMPLE' 'true')" 'deny' 'Edit replace_all injects secret -> deny'

echo ""
echo "[Internal-failure fail-open]"
# Move validators away to simulate missing-validator condition.
MISSING_HOME="$(mktemp -d -t mwg-missing.XXXXXX)"
mkdir -p "$MISSING_HOME/.claude/memory-shared/memories"
HOME="$MISSING_HOME" assert_decision "$(HOME="$MISSING_HOME" jq -n -c --arg fp "$MISSING_HOME/.claude/memory-shared/memories/feedback_test.md" --arg content "$CLEAN_BODY" '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" 'allow' 'Missing validators -> fail-open allow'
rm -rf "$MISSING_HOME"

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "Errors:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    echo ""
fi

echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
