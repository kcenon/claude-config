#!/bin/bash
# Regression test for issue #959.
#
# Verifies that install_memory_sync() in scripts/install.sh runs the memory
# repo's scripts/install-hooks.sh when the clone has one, and warns instead of
# skipping silently when it does not. Scheduler activation is redirected to
# staging directories (LAUNCHD_TARGET_DIR / SYSTEMD_USER_DIR), so no real
# launchd or systemd state is touched.
#
# Run: bash tests/scripts/test-install-memory-sync-hooks.sh

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
        "$fixture/scripts/launchd" \
        "$fixture/scripts/systemd" \
        "$fixture/global/hooks/lib" \
        "$fixture/hooks/lib"

    cp "$REPO_ROOT/scripts/install.sh" "$fixture/scripts/install.sh"
    cp "$REPO_ROOT/scripts/install-manifest.sh" "$fixture/scripts/install-manifest.sh"
    cp "$REPO_ROOT/scripts/lib/install-prompts.sh" "$fixture/scripts/lib/install-prompts.sh"
    cp "$REPO_ROOT/scripts/launchd/com.kcenon.claude-memory-sync.plist" "$fixture/scripts/launchd/"
    cp "$REPO_ROOT/scripts/systemd/memory-sync.service" "$REPO_ROOT/scripts/systemd/memory-sync.timer" \
        "$fixture/scripts/systemd/"

    printf '%s\n' '{"fixture": "memory-sync"}' > "$fixture/global/settings.json"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$fixture/global/hooks/example.sh"
    for lib in tokenize-shell.sh timeout-wrapper.sh rotate.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$fixture/global/hooks/lib/$lib"
    done
    for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$fixture/hooks/lib/$lib"
    done
}

# make_memory_repo <bare_repo> <with_hooks:0|1>
# Creates a bare git repo whose default branch optionally carries an
# executable scripts/install-hooks.sh that drops a marker in .git/.
make_memory_repo() {
    local bare="$1" with_hooks="$2"
    local src="${bare%.git}-src"

    mkdir -p "$src/memories"
    : > "$src/memories/.gitkeep"
    if [ "$with_hooks" = "1" ]; then
        mkdir -p "$src/scripts"
        printf '%s\n' '#!/bin/sh' ': > .git/install-hooks-ran' > "$src/scripts/install-hooks.sh"
        chmod +x "$src/scripts/install-hooks.sh"
    fi
    git -C "$src" init -q
    git -C "$src" add -A
    git -C "$src" -c user.name=test -c user.email=test@example.com \
        -c commit.gpgsign=false commit -q -m "chore: seed"
    git clone -q --bare "$src" "$bare"
}

run_install() {
    local home_dir="$1" fixture="$2" fake_bin="$3" repo_url="$4"
    env \
        HOME="$home_dir" \
        USERPROFILE="$home_dir" \
        PATH="$fake_bin:$PATH" \
        AGENT_LANGUAGE=english \
        CONTENT_LANGUAGE=english \
        INSTALL_NPM=n \
        CLAUDE_MEMORY_REPO_URL="$repo_url" \
        LAUNCHD_TARGET_DIR="$home_dir/launchd-staging" \
        SYSTEMD_USER_DIR="$home_dir/systemd-staging" \
        bash "$fixture/scripts/install.sh" --type 1 --yes >"$OUTPUT" 2>&1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-memsync.XXXXXX" 2>/dev/null || mktemp -d)"
OUTPUT="$WORK/install-memsync.out"
trap 'rm -rf "$WORK"' EXIT
WARNING_TEXT='memory repo has no scripts/install-hooks.sh'

echo "=== install_memory_sync hook installer test (bash, #959) ==="
echo ""

fake_bin="$WORK/fake-bin"
make_fake_bin "$fake_bin"
fixture="$WORK/fixture"
make_fixture "$fixture"

echo "[Memory repo without scripts/install-hooks.sh]"
make_memory_repo "$WORK/mem-nohooks.git" 0
home_a="$WORK/home-nohooks"
mkdir -p "$home_a"
if run_install "$home_a" "$fixture" "$fake_bin" "$WORK/mem-nohooks.git"; then
    pass "install exits 0"
else
    fail "install exits 0"
    sed 's/^/    /' "$OUTPUT"
fi
assert_true "memory repo cloned" "[ -d '$home_a/.claude/memory-shared/.git' ]"
assert_true "missing hook installer is reported" "grep -q '$WARNING_TEXT' '$OUTPUT'"

echo ""
echo "[Memory repo with scripts/install-hooks.sh]"
make_memory_repo "$WORK/mem-hooks.git" 1
home_b="$WORK/home-hooks"
mkdir -p "$home_b"
if run_install "$home_b" "$fixture" "$fake_bin" "$WORK/mem-hooks.git"; then
    pass "install exits 0"
else
    fail "install exits 0"
    sed 's/^/    /' "$OUTPUT"
fi
assert_true "hook installer ran in the clone" "[ -f '$home_b/.claude/memory-shared/.git/install-hooks-ran' ]"
assert_true "no missing-installer warning" "! grep -q '$WARNING_TEXT' '$OUTPUT'"

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
