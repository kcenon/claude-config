#!/bin/bash
# Test suite for sensitive-file-guard.sh — historical bypass cases.
# Run: bash tests/hooks/test-sensitive-file-guard-bypass.sh
#
# Validates Issue #569: the 11 cases below previously bypassed the guard.
# After adopting resolve_path() normalization, lowercase basename matching,
# and an expanded pattern set, all 11 must now be BLOCKED (deny).

set -uo pipefail

HOOK="global/hooks/sensitive-file-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label - expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

assert_allow() {
    local input="$1" label="$2"
    local result
    result=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label - expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

# Some cases need a fixture file because shell printf cannot embed a NUL byte
# into a tool argument. assert_deny_from_file pipes the raw bytes from a file.
assert_deny_from_file() {
    local fixture="$1" label="$2"
    local result
    result=$(bash "$HOOK" < "$fixture" 2>/dev/null)
    if echo "$result" | grep -q '"deny"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label - expected deny, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== sensitive-file-guard.sh historical bypass tests (Issue #569) ==="
echo ""

echo "[Case 1: .ENV (uppercase) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":".ENV"}}' ".ENV uppercase"

echo ""
echo "[Case 2: .Env (mixed case) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":".Env"}}' ".Env mixed case"

echo ""
echo "[Case 3: /foo/.ENV (uppercase in path) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":"/foo/.ENV"}}' "/foo/.ENV uppercase in path"

echo ""
echo "[Case 4: .env (trailing space) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":".env "}}' ".env trailing space"

echo ""
echo "[Case 5: .env<NUL>.txt (NUL truncation) - was BYPASS]"
# Build the JSON payload via python because shell printf cannot embed
# a NUL byte into command arguments. After jq parses the JSON, the NUL
# either truncates the bash variable to ".env" or survives concatenated
# as ".env.txt"; both shapes match the .env|.env.* pattern set.
NUL_FIXTURE=$(mktemp -t sfg-nul.XXXXXX 2>/dev/null) || NUL_FIXTURE="/tmp/sfg-nul.$$"
trap 'rm -f "$NUL_FIXTURE"' EXIT
if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.stdout.buffer.write(b"{\"tool_input\":{\"file_path\":\".env\x00.txt\"}}")' > "$NUL_FIXTURE"
elif command -v python >/dev/null 2>&1; then
    python -c 'import sys; sys.stdout.write("{\"tool_input\":{\"file_path\":\".env\x00.txt\"}}")' > "$NUL_FIXTURE"
else
    # Fallback uses printf with octal NUL, which works on most platforms.
    printf '{"tool_input":{"file_path":".env\0.txt"}}' > "$NUL_FIXTURE"
fi
assert_deny_from_file "$NUL_FIXTURE" ".env<NUL>.txt NUL truncation"

echo ""
echo "[Case 6: ../.aws/credentials (traversal + AWS) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":"../.aws/credentials"}}' "../.aws/credentials traversal"

echo ""
echo "[Case 7: id_rsa (SSH key) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":"id_rsa"}}' "id_rsa SSH key"

echo ""
echo "[Case 8: .envrc (env extension variant) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":".envrc"}}' ".envrc env variant"

echo ""
echo "[Case 9: /Users/x/.ssh/id_ed25519 (SSH path) - was BYPASS]"
assert_deny '{"tool_input":{"file_path":"/Users/x/.ssh/id_ed25519"}}' "id_ed25519 SSH path"

echo ""
echo "[Case 10: .env (canonical baseline) - already BLOCKED]"
assert_deny '{"tool_input":{"file_path":".env"}}' ".env canonical"

echo ""
echo "[Case 11: secret.pem (canonical baseline) - already BLOCKED]"
assert_deny '{"tool_input":{"file_path":"secret.pem"}}' "secret.pem canonical"

echo ""
echo "[Negative tests - legitimate writes must NOT be blocked]"
assert_allow '{"tool_input":{"file_path":"package.json"}}' "package.json"
assert_allow '{"tool_input":{"file_path":"README.md"}}' "README.md"
assert_allow '{"tool_input":{"file_path":"src/main.ts"}}' "src/main.ts"

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
