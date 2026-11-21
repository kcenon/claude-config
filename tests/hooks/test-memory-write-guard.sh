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
# Use a symlinked HOME to exercise macOS-style realpath normalization
# (/var/... -> /private/var/...), where the file path and memory root must be
# normalized before comparing.
TEST_HOME_REAL="$(mktemp -d -t mwg-home.XXXXXX)"
TEST_HOME="${TEST_HOME_REAL}.link"
# Git Bash for Windows copies where `ln -s` should link, and reports success.
# A copy is no stand-in for a link, and cleanup() left it behind (#1046).
ln -s "$TEST_HOME_REAL" "$TEST_HOME" 2>/dev/null || true
if [ ! -L "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME" 2>/dev/null || true
    TEST_HOME="$TEST_HOME_REAL"
fi
export HOME="$TEST_HOME"
MEM="$HOME/.claude/memory-shared/memories"
mkdir -p "$MEM"

# OWNER_EMAILS is required by secret-check.sh as of #618. Configure a test
# owner so the secret-detection paths can run; the test suite still uses
# validate.sh + secret-check.sh + injection-check.sh as the real chain.
export OWNER_EMAILS="test-owner@example.com"
export OWNER_GITHUB_HANDLE="test-owner"
export OWNER_HOME_USER="test-owner"

# Symlink validators to ${HOME}/.claude/scripts/memory/ so the hook's
# locator finds them regardless of the user's installed claude-config.
mkdir -p "$HOME/.claude/scripts/memory"
ln -sf "$(pwd)/scripts/memory/validate.sh"        "$HOME/.claude/scripts/memory/validate.sh"
ln -sf "$(pwd)/scripts/memory/secret-check.sh"    "$HOME/.claude/scripts/memory/secret-check.sh"
ln -sf "$(pwd)/scripts/memory/injection-check.sh" "$HOME/.claude/scripts/memory/injection-check.sh"

cleanup() {
    if [ "$TEST_HOME" != "$TEST_HOME_REAL" ]; then
        rm -f "$TEST_HOME" 2>/dev/null || true
    fi
    rm -rf "$TEST_HOME_REAL" 2>/dev/null || true
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

# Under Git Bash, an argument that looks like a path is rewritten to a Windows
# path before a native jq.exe sees it: /tmp/x became C:/.../Temp/x, which is
# outside the hook's memory root, so every memory case passed the path gate
# unvalidated (#1046). The two variables turn that rewriting off, for Git for
# Windows and for MSYS2; they mean nothing elsewhere.
build_payload() {
    # Use jq to safely encode tool_name + file_path + content as JSON.
    local tool="$1" fp="$2" content="$3"
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
        jq -n -c --arg tool "$tool" --arg fp "$fp" --arg content "$content" \
        '{tool_name:$tool,tool_input:{file_path:$fp,content:$content}}'
}

build_edit_payload() {
    local fp="$1" old="$2" new="$3" replace_all="${4:-false}"
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
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

NESTED_TYPE_BODY="---
name: Nested type memory
description: Auto-memory layout with type nested under metadata.
metadata:
  node_type: memory
  type: feedback
---

This is a body. **Why:** because auto-memory writes type under metadata. **How to apply:** accept the nested layout when validating memory writes.
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
echo "[Plain-pass silence -- issue #715]"
plain_sample=$(printf '%s' "$(build_payload Write /tmp/non-memory.txt 'hello')" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$plain_sample" | grep -q '"additionalContext"'; then
    FAIL=$((FAIL + 1)); ERRORS+=("FAIL: non-memory plain allow must not carry additionalContext -- got: $plain_sample"); echo "  FAIL: non-memory plain allow carries additionalContext"
else
    PASS=$((PASS + 1)); echo "  PASS: non-memory plain allow has no additionalContext"
fi
# Warn-only validator findings must keep their additionalContext feedback.
# Build this payload with pure-bash printf (not jq --arg / env): on
# MSYS/Git Bash, path-like arguments and env values handed to a native
# jq.exe get converted to Windows paths, which would dodge the hook's
# path gate. The body contains no quotes/backslashes, so escaping
# newlines is sufficient for valid JSON.
warn_payload=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' \
    "$MEM/feedback_strict_ctx.md" "${INJECTION_BODY//$'\n'/\\n}")
warn_sample=$(printf '%s' "$warn_payload" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$warn_sample" | grep -q '"additionalContext"'; then
    PASS=$((PASS + 1)); echo "  PASS: warn-only finding keeps additionalContext"
else
    FAIL=$((FAIL + 1)); ERRORS+=("FAIL: warn-only finding lost additionalContext -- got: $warn_sample"); echo "  FAIL: warn-only finding lost additionalContext"
fi

echo ""
echo "[Memory write decisions]"
assert_decision "$(build_payload Write "$MEM/feedback_clean.md" "$CLEAN_BODY")" 'allow' 'Clean memory write -> allow'
assert_decision "$(build_payload Write "$MEM/feedback_nested.md" "$NESTED_TYPE_BODY")" 'allow' 'Auto-memory metadata.type layout -> allow (#956)'
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
echo "[A jq that writes CR LF -- issue #1046]"
# A native Windows jq writes CR LF for every newline inside a value, and Git
# Bash drops the last one in a command substitution. A multi-line old_string
# then matched nothing in the file, so the hook validated the unchanged file.
# Where the jq on PATH does not write CR LF itself, a stand-in in front of it
# does, so the case runs on every platform; OSTYPE tells the hook that it runs
# under Git Bash.
CR=$'\r'
CRLF_JQ_PATH="$PATH"
if ! printf '%s' '"a\nb"' | jq -r . | grep -q "$CR"; then
    REAL_JQ="$(command -v jq)"
    mkdir -p "$TEST_HOME_REAL/crlf-jq"
    cat >"$TEST_HOME_REAL/crlf-jq/jq" <<SHIM_EOF
#!/bin/bash
set -o pipefail
"$REAL_JQ" "\$@" | awk 'NR > 1 { printf "\r\n" } { printf "%s", \$0 } END { if (NR) printf "\n" }'
SHIM_EOF
    chmod +x "$TEST_HOME_REAL/crlf-jq/jq"
    CRLF_JQ_PATH="$TEST_HOME_REAL/crlf-jq:$PATH"
fi
multiline_edit=$(build_edit_payload "$EDIT_FIXTURE" \
    "name: Edit target
description: An existing memory used to test edit-time validation." \
    "name: Edit target")
crlf_result=$(printf '%s' "$multiline_edit" | OSTYPE=msys PATH="$CRLF_JQ_PATH" bash "$HOOK" 2>/dev/null)
crlf_decision=$(decision_of "$crlf_result")
if [ "$crlf_decision" = "deny" ]; then
    PASS=$((PASS + 1)); echo "  PASS: Edit with a multi-line old_string removes a required field -> deny"
else
    FAIL=$((FAIL + 1)); ERRORS+=("FAIL: Edit with a multi-line old_string removes a required field -- expected deny, got $crlf_decision; raw=$crlf_result")
    echo "  FAIL: Edit with a multi-line old_string removes a required field (got $crlf_decision, expected deny)"
fi

echo ""
echo "[A validator that cannot run is reported, not passed (#1045)]"
# Stub validators in a HOME of their own. Each stub only exits with the code
# it is given: 127 is what a shell answers when it cannot run the script, 64
# is secret-check.sh's usage error. The payload is built with printf, as the
# warn-only case above, so that a native jq.exe never sees the path.
STUB_HOME="$(mktemp -d -t mwg-stub.XXXXXX)"
mkdir -p "$STUB_HOME/.claude/memory-shared/memories" "$STUB_HOME/.claude/scripts/memory"
set_stubs() {   # <validate rc> <secret-check rc> <injection-check rc>
    local pair
    for pair in "validate:$1" "secret-check:$2" "injection-check:$3"; do
        printf '#!/bin/bash\nexit %s\n' "${pair#*:}" > "$STUB_HOME/.claude/scripts/memory/${pair%%:*}.sh"
        chmod +x "$STUB_HOME/.claude/scripts/memory/${pair%%:*}.sh"
    done
}
stub_payload=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' \
    "$STUB_HOME/.claude/memory-shared/memories/feedback_stub.md" "${CLEAN_BODY//$'\n'/\\n}")
# stub_case <validate rc> <secret rc> <injection rc> <expected decision> <text the response must hold, or - for no note> <label>
stub_case() {
    local result decision ok=1
    set_stubs "$1" "$2" "$3"
    result=$(printf '%s' "$stub_payload" | HOME="$STUB_HOME" bash "$HOOK" 2>/dev/null)
    decision=$(decision_of "$result")
    [ "$decision" = "$4" ] || ok=0
    if [ "$5" = "-" ]; then
        if printf '%s' "$result" | grep -q '"additionalContext"'; then ok=0; fi
    elif ! printf '%s' "$result" | grep -qF "$5"; then
        ok=0
    fi
    if [ "$ok" -eq 1 ]; then
        PASS=$((PASS + 1)); echo "  PASS: $6"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $6 -- decision $decision, raw=$result"); echo "  FAIL: $6"
    fi
}
stub_case 127 0 0 allow 'validate.sh (exit 127)' 'validate.sh exits 127 -> allow that names the check that did not run'
stub_case 0 64 0 allow 'secret-check.sh (exit 64)' 'secret-check.sh exits 64 -> allow that names the check that did not run'
stub_case 127 1 0 deny 'validate.sh (exit 127)' 'a check that ran and blocks still denies, and the reason names the one that did not run'
stub_case 0 0 0 allow - 'all three ran clean -> plain allow with no note'
rm -rf "$STUB_HOME"

echo ""
echo "[Internal-failure fail-open]"
# Move validators away to simulate missing-validator condition.
MISSING_HOME="$(mktemp -d -t mwg-missing.XXXXXX)"
mkdir -p "$MISSING_HOME/.claude/memory-shared/memories"
HOME="$MISSING_HOME" assert_decision "$(HOME="$MISSING_HOME" MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n -c --arg fp "$MISSING_HOME/.claude/memory-shared/memories/feedback_test.md" --arg content "$CLEAN_BODY" '{tool_name:"Write",tool_input:{file_path:$fp,content:$content}}')" 'allow' 'Missing validators -> fail-open allow'
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
