#!/bin/bash
# Test suite for bash-sensitive-read-guard.sh
# Run: bash tests/hooks/test-bash-sensitive-read-guard.sh

HOOK="global/hooks/bash-sensitive-read-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Use a scratch fixture dir so tests are independent of the developer's $HOME.
SCRATCH_ROOT="${TMPDIR:-/tmp}"
FIXTURE_DIR=$(mktemp -d "$SCRATCH_ROOT/bsrg-test.XXXXXX" 2>/dev/null) \
    || FIXTURE_DIR="$SCRATCH_ROOT/bsrg-test.$$"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Pipe a fixture file into the hook. Using a file (rather than echo) avoids
# shell-channel re-interpretation of backslash escapes in commands like
# `find ... -exec cat {} \;`.
make_fixture() {
    local cmd="$1"
    local out="$FIXTURE_DIR/in.json"
    # jq -n produces correctly-escaped JSON regardless of the command shape.
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg cmd "$cmd" '{tool_name:"Bash", tool_input:{command:$cmd}}' > "$out"
    else
        # Fallback: rely on the caller having already escaped backslashes/quotes.
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

echo "=== bash-sensitive-read-guard.sh tests ==="
echo ""

echo "[Fail-open on missing input]"
assert_allow '' "Empty command → allow (fail-open; dangerous-command-guard owns parse-failure)"

echo ""
echo "[deny — direct read of sensitive paths]"
assert_deny "cat .env" "cat .env"
assert_deny "cat ./config/.env.production" "nested .env.production"
assert_deny "head -n 5 .env" "head .env"
assert_deny "tail -f .env.local" "tail .env.local"
assert_deny "grep AWS_SECRET .env" "grep .env"
assert_deny 'cat ~/.ssh/id_rsa' "cat ~/.ssh/id_rsa"
assert_deny 'cat ~/.ssh/my_key_ed25519' "ssh ed25519 key"
assert_deny 'cat ~/.aws/credentials' "AWS credentials file"
assert_deny 'cat /etc/shadow' "/etc/shadow"
assert_deny 'cat secrets/db.yml' "secrets/ directory"
assert_deny 'cat config/credentials/aws.json' "credentials/ directory"
assert_deny 'cat certs/server.pem' "*.pem extension"
assert_deny 'cat keys/private.key' "*.key extension"

echo ""
echo "[deny — case-insensitive variants (macOS/Windows bypass guard)]"
assert_deny "cat .ENV" "uppercase .ENV"
assert_deny "cat ./config/.Env.Production" "mixed-case .Env.Production"
assert_deny 'cat ~/.NETRC' "uppercase .NETRC"
assert_deny 'cat ~/.AWS/credentials' "uppercase .AWS directory"
assert_deny 'cat ~/.SSH/ID_RSA' "uppercase .SSH/ID_RSA"

echo ""
echo "[deny — wrapper bypasses]"
assert_deny 'sudo cat /etc/shadow' "sudo wrapper"
assert_deny 'env DEBUG=1 cat .env' "env wrapper"
assert_deny 'nice cat .env' "nice wrapper"

echo ""
echo "[deny — chained commands]"
assert_deny 'echo start && cat .env' "&& chain"
assert_deny 'cat README.md; cat .env' "; chain"
assert_deny 'true | cat .env' "pipe receiver"

echo ""
echo "[deny — find -exec cat]"
assert_deny 'find / -name .env -exec cat {} \;' "find -exec cat sensitive"
assert_deny 'find . -name id_rsa' "find -name id_rsa (search target itself)"

echo ""
echo "[allow — non-sensitive reads]"
assert_allow "cat README.md" "README.md"
assert_allow "cat src/main.py" "src/main.py"
assert_allow "cat package.json" "package.json"
assert_allow 'head -n 10 docs/guide.md' "docs/guide.md"
assert_allow 'grep TODO src/' "grep TODO in src/"
assert_allow 'find . -name "*.md"' "find non-sensitive"

echo ""
echo "[allow — sensitive token inside non-read context]"
assert_allow 'echo "do not commit .env"' "echo about .env (not a read)"
assert_allow 'echo cat .env' "echo cat .env (echo, not cat)"
assert_allow 'git status' "git status"
assert_allow 'ls -la' "ls -la"

echo ""
echo "[allow — env file templates (issue #866, file-channel parity)]"
assert_allow 'cat .env.example' "cat .env.example"
assert_allow 'cat /app/.env.sample' "cat /app/.env.sample (path-prefixed form)"
assert_allow 'cat .env.template' "cat .env.template"
assert_allow 'cat .env.example.local' "cat .env.example.local (suffixed example)"
assert_allow 'grep API_URL .env.example' "grep in .env.example"

echo ""
echo "[deny — template allow-list must not widen the bypass surface (#866)]"
# A literal glob reaching the hook unexpanded must never satisfy the
# allow-list — `.env.*` would otherwise read every env file in a directory.
assert_deny 'cat .env.*' "glob .env.* (not an allow-list entry)"
assert_deny 'cat .env.example*' "glob .env.example* (no dot before wildcard)"
assert_deny 'cat .env.examplexyz' ".env.examplexyz (not .env.example)"
# Only .env.example carries a dotted-suffix arm, mirroring the file channel.
assert_deny 'cat .env.sample.local' ".env.sample.local (no suffix arm for sample)"
# The template arm falls through, so later directory checks still apply.
assert_deny 'cat secrets/.env.example' "template under secrets/ still denied"
assert_deny 'cat .env.example && cat .env' "template does not launder a chained .env read"

echo ""
echo "[deny — unexpanded glob bracketing the env token (issue #867)]"
# The hook sees the command before the shell expands it. A wildcard adjacent
# to `.env` matches no literal deny arm, so the raw pattern must be caught by
# its de-globbed remainder or it would read every env file in the directory.
assert_deny 'cat *.env*' "double-wildcard env glob (the reported bypass)"
assert_deny 'cat .env*' "trailing glob after .env"
assert_deny 'cat *.env' "leading glob before .env"
assert_deny 'cat .env?' "single-char glob after .env"
assert_deny 'grep SECRET *.env*' "grep double-wildcard env glob"
assert_deny 'head config/*.env*' "path-prefixed double-wildcard env glob"

echo ""
echo "[allow — env-mentioning globs that cannot expand to a .env file (#867 precision)]"
# The de-glob check keys on the .env class specifically, so a wildcard that
# does not bracket a dotted-env token stays allowed and does not over-deny.
assert_allow 'cat env*' "env* -- no leading dot, not the .env class"
assert_allow 'cat *.md' "wildcard over markdown"
assert_allow 'cat environment.txt' "environment.txt -- env substring, no wildcard, no .env"

echo ""
echo "[edge — symlink to sensitive (Red Team Vector F)]"
# Plant an actual .env so realpath has a target to resolve to. The hook's
# resolve_path follows the symlink, so the deny pattern fires on the real
# path even though the surface argument is `safe.txt`. /etc/shadow is
# unreliable for this test (absent on macOS), so we use a fixture .env.
TARGET_ENV="$FIXTURE_DIR/.env"
echo "SECRET=x" > "$TARGET_ENV"
LINK="$FIXTURE_DIR/safe.txt"
ln -sf "$TARGET_ENV" "$LINK" 2>/dev/null || true
if [ -L "$LINK" ]; then
    assert_deny "cat $LINK" "symlink to .env → deny (resolves through realpath)"
fi

echo ""
echo "[edge — cp source side]"
assert_deny 'cp .env /tmp/exfil' "cp .env (source side denied)"
assert_allow 'cp README.md /tmp/copy.md' "cp README.md (non-sensitive source)"

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
