#!/bin/bash
# test-bootstrap-atomic-deploy.sh
# Regression test for issue #798.
#
# Verifies that bootstrap.sh publishes ~/.claude/settings.json only after
# runtime hook deployment succeeds. A hook deployment failure must leave the
# previously installed settings.json untouched.
#
# Run: bash tests/scripts/test-bootstrap-atomic-deploy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

PASS=0
FAIL=0
ERRORS=()

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS+=("$1")
    echo "  FAIL: $1"
}

assert_true() {
    local label="$1"
    if eval "$2"; then
        pass "$label"
    else
        fail "$label"
    fi
}

make_fixture() {
    local fixture="$1"
    local lib
    mkdir -p "$fixture/global/hooks/lib" "$fixture/global/scripts" "$fixture/hooks/lib" "$fixture/scripts"
    cp "$REPO_ROOT/scripts/install-manifest.sh" "$fixture/scripts/install-manifest.sh"

    cat > "$fixture/global/settings.json" <<'JSON'
{
  "fixture": "bash"
}
JSON
    cat > "$fixture/global/hooks/example.sh" <<'SH'
#!/bin/sh
exit 0
SH
    for lib in tokenize-shell.sh path-utils.sh timeout-wrapper.sh rotate.sh; do
        cat > "$fixture/global/hooks/lib/$lib" <<'SH'
#!/bin/sh
return 0 2>/dev/null || exit 0
SH
    done
    for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
        cat > "$fixture/hooks/lib/$lib" <<'SH'
#!/bin/sh
return 0 2>/dev/null || exit 0
SH
    done
    cat > "$fixture/global/scripts/statusline-command.sh" <<'SH'
#!/bin/sh
echo statusline
SH
}

run_atomic_deploy() {
    local home_dir="$1" fixture="$2"
    env \
        HOME="$home_dir" \
        USERPROFILE="$home_dir" \
        INSTALL_DIR="$fixture" \
        AGENT_LANGUAGE=english \
        CONTENT_LANGUAGE=english \
        CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=atomic-deploy \
        bash "$BOOTSTRAP" >"$OUTPUT" 2>&1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-atomic.XXXXXX" 2>/dev/null || mktemp -d)"
OUTPUT="$WORK/bootstrap-atomic-bash.out"
trap 'rm -rf "$WORK"' EXIT

echo "=== Bootstrap atomic deploy test (bash, #798) ==="
echo ""

success_fixture="$WORK/success-fixture"
success_home="$WORK/success-home"
make_fixture "$success_fixture"
mkdir -p "$success_home"

if run_atomic_deploy "$success_home" "$success_fixture"; then
    pass "successful hook deployment exits 0"
else
    fail "successful hook deployment exits 0"
    sed 's/^/    /' "$OUTPUT"
fi

assert_true "settings.json published after successful hook deployment" \
    "grep -q '\"fixture\": \"bash\"' '$success_home/.claude/settings.json'"
assert_true "top-level hook deployed executable" \
    "[ -x '$success_home/.claude/hooks/example.sh' ]"
assert_true "hook lib deployed executable" \
    "[ -x '$success_home/.claude/hooks/lib/tokenize-shell.sh' ]"
assert_true "statusline utility script deployed executable" \
    "[ -x '$success_home/.claude/scripts/statusline-command.sh' ]"

failure_fixture="$WORK/failure-fixture"
failure_home="$WORK/failure-home"
make_fixture "$failure_fixture"
mkdir -p "$failure_home/.claude"
printf '%s\n' '{"sentinel":"keep"}' > "$failure_home/.claude/settings.json"
printf '%s\n' 'not a directory' > "$failure_home/.claude/hooks"

set +e
run_atomic_deploy "$failure_home" "$failure_fixture"
rc=$?

if [ "$rc" -ne 0 ]; then
    pass "failed hook deployment exits non-zero"
else
    fail "failed hook deployment exits non-zero"
fi

assert_true "existing settings.json preserved when hook deployment fails" \
    "grep -q '\"sentinel\":\"keep\"' '$failure_home/.claude/settings.json'"
assert_true "staged settings temp removed after hook deployment failure" \
    "! find '$failure_home/.claude' -maxdepth 1 -name '.settings.json.tmp.*' | grep -q ."

missing_lib_fixture="$WORK/missing-lib-fixture"
missing_lib_home="$WORK/missing-lib-home"
make_fixture "$missing_lib_fixture"
rm -f "$missing_lib_fixture/global/hooks/lib/tokenize-shell.sh"
mkdir -p "$missing_lib_home/.claude"
printf '%s\n' '{"sentinel":"missing-lib"}' > "$missing_lib_home/.claude/settings.json"

set +e
run_atomic_deploy "$missing_lib_home" "$missing_lib_fixture"
rc=$?

if [ "$rc" -ne 0 ]; then
    pass "missing required runtime lib exits non-zero"
else
    fail "missing required runtime lib exits non-zero"
fi

assert_true "existing settings.json preserved when required runtime lib is missing" \
    "grep -q '\"sentinel\":\"missing-lib\"' '$missing_lib_home/.claude/settings.json'"
assert_true "missing runtime lib failure reports blocked settings publication" \
    "grep -q 'settings.json을 변경하지 않았습니다' '$OUTPUT'"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

exit 0
