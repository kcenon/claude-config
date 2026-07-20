#!/bin/bash
# Test suite for sensitive-file-guard.sh
# Run: bash tests/hooks/test-sensitive-file-guard.sh

HOOK="global/hooks/sensitive-file-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

assert_deny() {
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
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
    local input="$1" label="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== sensitive-file-guard.sh tests ==="
echo ""

echo "[Fail-closed]"
assert_deny '' "Empty input → deny"
assert_deny 'INVALID_JSON' "Malformed JSON → deny"
assert_allow '{}' "Missing tool_input → allow (valid JSON, no file)"

echo ""
echo "[.env patterns]"
assert_deny '{"tool_input":{"file_path":"/app/.env"}}' ".env → deny"
assert_deny '{"tool_input":{"file_path":"/app/.env.local"}}' ".env.local → deny"
assert_deny '{"tool_input":{"file_path":"/app/.env.production"}}' ".env.production → deny"
assert_deny '{"tool_input":{"file_path":"/app/.env.development"}}' ".env.development → deny"
assert_deny '{"tool_input":{"file_path":"config/.env"}}' "nested .env → deny"
assert_deny '{"tool_input":{"file_path":"/app/.env.backup.20260101"}}' ".env.backup.<ts> → deny"

echo ""
echo "[.env template allow-list (issue #582)]"
assert_allow '{"tool_input":{"file_path":"/app/.env.example"}}' ".env.example → allow"
assert_allow '{"tool_input":{"file_path":"/app/.env.example.local"}}' ".env.example.local → allow"
assert_allow '{"tool_input":{"file_path":"/app/.env.sample"}}' ".env.sample → allow"
assert_allow '{"tool_input":{"file_path":"/app/.env.template"}}' ".env.template → allow"
assert_allow '{"tool_input":{"file_path":"config/.env.example"}}' "nested .env.example → allow"
assert_allow '{"tool_input":{"file_path":"/app/.ENV.EXAMPLE"}}' "case-insensitive .env.example → allow"

echo ""
echo "[Path normalization + direnv parity (issue #856)]"
assert_deny '{"tool_input":{"file_path":".envrc"}}' ".envrc → deny (direnv config)"
assert_deny '{"tool_input":{"file_path":"/app/.envrc"}}' "path-qualified .envrc → deny"
assert_deny '{"tool_input":{"file_path":"/app/.env "}}' ".env with trailing space → deny"
assert_deny '{"tool_input":{"file_path":"keys/secret.key "}}' "secret.key with trailing space → deny"
assert_deny '{"tool_input":{"file_path":"~/.env"}}' "tilde ~/.env → deny"
assert_deny '{"tool_input":{"file_path":"~/.envrc"}}' "tilde ~/.envrc → deny"
# The allow-list is matched against the normalized basename too, so templates
# must survive the same tilde/whitespace handling that the deny paths apply.
assert_allow '{"tool_input":{"file_path":"~/.env.example"}}' "tilde ~/.env.example → allow"
assert_allow '{"tool_input":{"file_path":"/app/.env.template "}}' ".env.template with trailing space → allow"

echo ""
echo "[Certificate/key patterns]"
assert_deny '{"tool_input":{"file_path":"certs/server.pem"}}' ".pem → deny"
assert_deny '{"tool_input":{"file_path":"keys/private.key"}}' ".key → deny"
assert_deny '{"tool_input":{"file_path":"auth/cert.p12"}}' ".p12 → deny"
assert_deny '{"tool_input":{"file_path":"auth/cert.pfx"}}' ".pfx → deny"

echo ""
echo "[Sensitive directories]"
assert_deny '{"tool_input":{"file_path":"config/secrets/db.yml"}}' "secrets/ → deny"
assert_deny '{"tool_input":{"file_path":"config/credentials/aws.json"}}' "credentials/ → deny"
assert_deny '{"tool_input":{"file_path":"config/passwords/list.txt"}}' "passwords/ → deny"

echo ""
echo "[Allowed system paths]"
assert_allow '{"tool_input":{"file_path":"/private/tmp/claude_test"}}' "/private/tmp → allow (macOS system)"

echo ""
echo "[Allowed files]"
assert_allow '{"tool_input":{"file_path":"src/main.py"}}' "main.py → allow"
assert_allow '{"tool_input":{"file_path":"src/environment.ts"}}' "environment.ts → allow"
assert_allow '{"tool_input":{"file_path":"src/config.json"}}' "config.json → allow"
assert_allow '{"tool_input":{"file_path":"README.md"}}' "README.md → allow"
assert_allow '{"tool_input":{"file_path":"package.json"}}' "package.json → allow"

echo ""
echo "[Edge cases]"
assert_allow '{"tool_input":{"file_path":""}}' "Empty file path → allow"
assert_allow '{"tool_input":{}}' "No file_path field → allow"

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
