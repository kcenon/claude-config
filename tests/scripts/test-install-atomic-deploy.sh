#!/bin/bash
# Regression test for issue #813.
#
# Verifies that scripts/install.sh publishes ~/.claude/settings.json only after
# runtime hook deployment succeeds. A hook deployment failure must leave the
# previously installed settings.json untouched.
#
# Run: bash tests/scripts/test-install-atomic-deploy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

make_fake_bin() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/claude" <<'SH'
#!/bin/sh
echo "claude test"
SH
    chmod +x "$dir/claude"
}

make_fixture() {
    local fixture="$1"
    local lib

    mkdir -p \
        "$fixture/scripts/lib" \
        "$fixture/global/hooks/lib" \
        "$fixture/hooks/lib"

    cp "$REPO_ROOT/scripts/install.sh" "$fixture/scripts/install.sh"
    cp "$REPO_ROOT/scripts/install-manifest.sh" "$fixture/scripts/install-manifest.sh"
    cp "$REPO_ROOT/scripts/lib/install-prompts.sh" "$fixture/scripts/lib/install-prompts.sh"

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
}

run_install() {
    local home_dir="$1" fixture="$2" fake_bin="$3"
    env \
        HOME="$home_dir" \
        USERPROFILE="$home_dir" \
        PATH="$fake_bin:$PATH" \
        AGENT_LANGUAGE=english \
        CONTENT_LANGUAGE=english \
        INSTALL_NPM=n \
        bash "$fixture/scripts/install.sh" --type 1 --yes >"$OUTPUT" 2>&1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-atomic.XXXXXX" 2>/dev/null || mktemp -d)"
OUTPUT="$WORK/install-atomic-bash.out"
trap 'rm -rf "$WORK"' EXIT

echo "=== Clone installer atomic deploy test (bash, #813) ==="
echo ""

fake_bin="$WORK/fake-bin"
make_fake_bin "$fake_bin"

success_fixture="$WORK/success-fixture"
success_home="$WORK/success-home"
make_fixture "$success_fixture"
mkdir -p "$success_home"

if run_install "$success_home" "$success_fixture" "$fake_bin"; then
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
assert_true "shared validator lib deployed executable" \
    "[ -x '$success_home/.claude/hooks/lib/validate-traceability.sh' ]"
if command -v jq >/dev/null 2>&1; then
    assert_true "staged settings receive agent language update" \
        "[ \"\$(jq -r '.language' '$success_home/.claude/settings.json')\" = 'english' ]"
fi

failure_fixture="$WORK/failure-fixture"
failure_home="$WORK/failure-home"
make_fixture "$failure_fixture"
mkdir -p "$failure_home/.claude"
printf '%s\n' '{"sentinel":"keep"}' > "$failure_home/.claude/settings.json"
printf '%s\n' 'not a directory' > "$failure_home/.claude/hooks"

set +e
run_install "$failure_home" "$failure_fixture" "$fake_bin"
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
assert_true "hook deployment failure reports blocked settings publication" \
    "grep -q 'settings.json을 변경하지 않았습니다' '$OUTPUT'"

missing_lib_fixture="$WORK/missing-lib-fixture"
missing_lib_home="$WORK/missing-lib-home"
make_fixture "$missing_lib_fixture"
rm -f "$missing_lib_fixture/global/hooks/lib/tokenize-shell.sh"
mkdir -p "$missing_lib_home/.claude"
printf '%s\n' '{"sentinel":"missing-lib"}' > "$missing_lib_home/.claude/settings.json"

set +e
run_install "$missing_lib_home" "$missing_lib_fixture" "$fake_bin"
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
