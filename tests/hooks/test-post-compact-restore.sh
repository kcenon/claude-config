#!/bin/bash
# Test suite for post-compact-restore.sh
# Run: bash tests/hooks/test-post-compact-restore.sh
#
# Asserts the SessionStart(compact) restore contract (issue #720):
# the PostCompact event does not support hookSpecificOutput, so the hook
# must emit a SessionStart envelope with exactly the schema keys
# {hookSpecificOutput: {hookEventName, additionalContext}}, keep the
# digest small, stay silent for non-compact sources, and keep .sh/.ps1
# additionalContext byte-equivalent.

HOOK="global/hooks/post-compact-restore.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

COMPACT_INPUT='{"session_id":"test","hook_event_name":"SessionStart","source":"compact"}'
STARTUP_INPUT='{"session_id":"test","hook_event_name":"SessionStart","source":"startup"}'

check() {
    local rc="$1" label="$2"
    if [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label")
        echo "  FAIL: $label"
    fi
}

# Extract additionalContext (raw string, no trailing-newline mangling) from
# stdin JSON into a file. Prefers jq, falls back to python.
extract_ctx() {
    local outfile="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -j '.hookSpecificOutput.additionalContext' > "$outfile"
        return
    fi
    local pybin=""
    for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1; then pybin="$c"; break; fi
    done
    if [ -n "$pybin" ]; then
        "$pybin" -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' > "$outfile"
    else
        : > "$outfile"
    fi
}

echo "=== post-compact-restore.sh tests ==="
echo ""

echo "[output structure (source == compact)]"
RESULT=$(printf '%s' "$COMPACT_INPUT" | bash "$HOOK" 2>/dev/null)
RC=$?
check $RC "exit code is 0"

if command -v jq >/dev/null 2>&1; then
    printf '%s' "$RESULT" | jq empty >/dev/null 2>&1
elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$RESULT" | python3 -m json.tool >/dev/null 2>&1
else
    printf '%s' "$RESULT" | python -m json.tool >/dev/null 2>&1
fi
check $? "produces valid JSON"

printf '%s' "$RESULT" | grep -q '"hookEventName"'
check $? "includes hookEventName field"

printf '%s' "$RESULT" | grep -q '"SessionStart"'
check $? "event name is SessionStart"

! printf '%s' "$RESULT" | grep -q 'PostCompact'
check $? "no PostCompact string in output (unsupported event)"

printf '%s' "$RESULT" | grep -q '"additionalContext"'
check $? "includes additionalContext field"

echo ""
echo "[schema exactness (issue #720 AC4)]"
SCHEMA_RC=1
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$RESULT" | jq -e '
        (keys == ["hookSpecificOutput"]) and
        (.hookSpecificOutput | keys == ["additionalContext", "hookEventName"]) and
        (.hookSpecificOutput.hookEventName == "SessionStart") and
        (.hookSpecificOutput.additionalContext | type == "string" and length > 0)
    ' >/dev/null 2>&1
    SCHEMA_RC=$?
else
    PYBIN=""
    for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1; then PYBIN="$c"; break; fi
    done
    if [ -n "$PYBIN" ]; then
        printf '%s' "$RESULT" | "$PYBIN" -c '
import json, sys
d = json.load(sys.stdin)
assert sorted(d.keys()) == ["hookSpecificOutput"]
inner = d["hookSpecificOutput"]
assert sorted(inner.keys()) == ["additionalContext", "hookEventName"]
assert inner["hookEventName"] == "SessionStart"
assert isinstance(inner["additionalContext"], str) and inner["additionalContext"]
' >/dev/null 2>&1
        SCHEMA_RC=$?
    fi
fi
check $SCHEMA_RC "top-level keys are exactly {hookSpecificOutput} with exactly {hookEventName, additionalContext}"

echo ""
echo "[digest constraints (issue #720)]"
CTX_FILE=$(mktemp)
printf '%s' "$RESULT" | extract_ctx "$CTX_FILE"

if [ -s "$CTX_FILE" ]; then
    check 0 "additionalContext extracted"

    CTX_BYTES=$(wc -c < "$CTX_FILE")
    [ "$CTX_BYTES" -le 1000 ]; check $? "payload is at most 1000 bytes (got $CTX_BYTES)"

    CTX_LINES=$(awk 'END{print NR}' "$CTX_FILE")
    [ "$CTX_LINES" -le 12 ]; check $? "payload is at most 12 lines (got $CTX_LINES)"

    # No full-document re-injection: these markers exist only in the full
    # core/principles.md file (frontmatter, guardrail section), never in
    # the digest.
    ! grep -q 'alwaysApply' "$CTX_FILE"; check $? "no full-document marker: alwaysApply"
    ! grep -q 'Behavioral Guardrails' "$CTX_FILE"; check $? "no full-document marker: Behavioral Guardrails"

    # Digest items: the four core principles plus the self-check line.
    grep -q 'Think Before Acting' "$CTX_FILE"; check $? "principle 1: Think Before Acting"
    grep -q 'Minimize & Focus' "$CTX_FILE"; check $? "principle 2: Minimize & Focus"
    grep -q 'Surgical Precision' "$CTX_FILE"; check $? "principle 3: Surgical Precision"
    grep -q 'Verify & Iterate' "$CTX_FILE"; check $? "principle 4: Verify & Iterate"
    grep -q 'senior engineer' "$CTX_FILE"; check $? "self-check line present"
else
    check 1 "additionalContext extracted (jq/python unavailable or empty payload)"
fi

echo ""
echo "[source gating (defense in depth)]"
STARTUP_OUT=$(printf '%s' "$STARTUP_INPUT" | bash "$HOOK" 2>/dev/null)
STARTUP_RC=$?
[ "$STARTUP_RC" -eq 0 ]; check $? "source startup: exit code is 0"
[ -z "$STARTUP_OUT" ]; check $? "source startup: stdout is empty"

EMPTY_OUT=$(printf '' | bash "$HOOK" 2>/dev/null)
EMPTY_RC=$?
[ "$EMPTY_RC" -eq 0 ]; check $? "empty stdin: exit code is 0"
[ -z "$EMPTY_OUT" ]; check $? "empty stdin: stdout is empty"

NOSRC_OUT=$(printf '%s' '{}' | bash "$HOOK" 2>/dev/null)
NOSRC_RC=$?
[ "$NOSRC_RC" -eq 0 ] && [ -z "$NOSRC_OUT" ]
check $? "missing source field: silent exit 0"

echo ""
echo "[sh/ps1 parity]"
PS1_HOOK="global/hooks/post-compact-restore.ps1"
if command -v pwsh >/dev/null 2>&1; then
    PS_CTX_FILE=$(mktemp)
    printf '%s' "$COMPACT_INPUT" | pwsh -NoProfile -File "$PS1_HOOK" 2>/dev/null | extract_ctx "$PS_CTX_FILE"
    cmp -s "$CTX_FILE" "$PS_CTX_FILE"
    check $? "additionalContext is byte-equivalent between .sh and .ps1"

    PS_STARTUP_OUT=$(printf '%s' "$STARTUP_INPUT" | pwsh -NoProfile -File "$PS1_HOOK" 2>/dev/null)
    [ -z "$PS_STARTUP_OUT" ]; check $? "ps1 source startup: stdout is empty"
    rm -f "$PS_CTX_FILE"
else
    echo "  SKIP: pwsh not available"
fi
rm -f "$CTX_FILE"

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
