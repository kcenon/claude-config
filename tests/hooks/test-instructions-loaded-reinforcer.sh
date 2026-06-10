#!/bin/bash
# Test suite for instructions-loaded-reinforcer.sh
# Run: bash tests/hooks/test-instructions-loaded-reinforcer.sh

HOOK="global/hooks/instructions-loaded-reinforcer.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_contains() {
    local needle="$1" label="$2"
    local result
    result=$(echo '{}' | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — needle '$needle' not found")
        echo "  FAIL: $label"
    fi
}

assert_valid_json() {
    local label="$1"
    local result
    result=$(echo '{}' | bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq empty >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    elif echo "$result" | python3 -m json.tool >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    elif echo "$result" | python -m json.tool >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — invalid JSON: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== instructions-loaded-reinforcer.sh tests ==="
echo ""

echo "[output structure]"
assert_valid_json "produces valid JSON"
assert_contains '"hookEventName"' "includes hookEventName field"
assert_contains '"InstructionsLoaded"' "event name is InstructionsLoaded"
assert_contains '"additionalContext"' "includes additionalContext field"

echo ""
echo "[policy content]"
assert_contains 'Conventional Commits' "mentions Conventional Commits"
assert_contains 'AI/Claude attribution\|attribution' "mentions attribution policy"
assert_contains 'develop' "mentions develop branch policy"

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

echo ""
echo "[digest constraints (issue #716)]"
CTX_FILE=$(mktemp)
echo '{}' | bash "$HOOK" 2>/dev/null | extract_ctx "$CTX_FILE"

if [ -s "$CTX_FILE" ]; then
    check 0 "additionalContext extracted"

    CTX_BYTES=$(wc -c < "$CTX_FILE")
    [ "$CTX_BYTES" -le 500 ]; check $? "payload is at most 500 bytes (got $CTX_BYTES)"

    CTX_LINES=$(awk 'END{print NR}' "$CTX_FILE")
    [ "$CTX_LINES" -le 10 ]; check $? "payload is at most 10 lines (got $CTX_LINES)"

    # No verbatim copy of commit-settings.md: these markers exist only in the
    # full policy file (and the old inline fallback), never in the digest.
    ! grep -q 'korean_plus_english' "$CTX_FILE"; check $? "no verbatim copy marker: korean_plus_english"
    ! grep -q 'commit-message-guard' "$CTX_FILE"; check $? "no verbatim copy marker: commit-message-guard"
    ! grep -q 'Enforced by' "$CTX_FILE"; check $? "no verbatim copy marker: Enforced by"

    # Four required digest items (issue #716 AC2).
    grep -qi 'No AI/Claude attribution' "$CTX_FILE"; check $? "item 1: attribution ban"
    grep -q 'CLAUDE_CONTENT_LANGUAGE' "$CTX_FILE" && grep -q 'commit-settings.md' "$CTX_FILE"
    check $? "item 2: content-language policy pointer"
    grep -q 'develop' "$CTX_FILE" && grep -q 'main' "$CTX_FILE" && grep -qi 'squash' "$CTX_FILE"
    check $? "item 3: protected branch rules"
    grep -q 'type(scope): description' "$CTX_FILE" && grep -q 'lowercase first char' "$CTX_FILE" && grep -q 'no trailing period' "$CTX_FILE"
    check $? "item 4: Conventional Commits format"
else
    check 1 "additionalContext extracted (jq/python unavailable or empty payload)"
fi

echo ""
echo "[sh/ps1 parity]"
PS1_HOOK="global/hooks/instructions-loaded-reinforcer.ps1"
if command -v pwsh >/dev/null 2>&1; then
    PS_CTX_FILE=$(mktemp)
    echo '{}' | pwsh -NoProfile -File "$PS1_HOOK" 2>/dev/null | extract_ctx "$PS_CTX_FILE"
    cmp -s "$CTX_FILE" "$PS_CTX_FILE"
    check $? "additionalContext is byte-equivalent between .sh and .ps1"
    rm -f "$PS_CTX_FILE"
else
    echo "  SKIP: pwsh not available"
fi
rm -f "$CTX_FILE"

echo ""
echo "[exit code]"
echo '{}' | bash "$HOOK" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: exit code is 0"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: exit code expected 0, got $RC")
    echo "  FAIL: exit code"
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
