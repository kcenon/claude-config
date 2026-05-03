#!/bin/bash
# tests/safe-rm-rf.sh
# =====================================================================
# Unit tests for scripts/lib/safe-rm.sh (M1.3, see #566).
#
# Bats is not available in CI; this is a plain bash harness.
# Each test is a function returning non-zero on failure. The runner at
# the bottom collects results and exits with the failure count.
#
# Coverage (matches the issue acceptance criteria):
#   - relative path resolution
#   - symlink pointing outside the allow-listed prefix
#   - `..` traversal
#   - `$HOME` direct
#   - `/` direct
#   - allow-listed paths
#   - empty argument
#   - non-existent target (idempotent)
# =====================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/scripts/lib/safe-rm.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: helper not found at $HELPER" >&2
    exit 1
fi

# Test sandbox lives under /tmp/claude-config-* — itself an allow-listed
# prefix, which is convenient: positive tests that delete real fixtures
# can run inside the sandbox without tripping the guard.
SANDBOX="$(mktemp -d -t claude-config-tests.XXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0

# Run a single test: $1 = name, remaining args = command to evaluate.
# A test passes when the command's exit status matches the expectation.
run_test() {
    local name="$1"
    shift
    local expected_status="$1"
    shift
    # Run the test command in a subshell so failures don't kill the runner.
    local actual_status=0
    ( "$@" ) >/dev/null 2>&1 || actual_status=$?
    if [ "$actual_status" = "$expected_status" ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected exit $expected_status, got $actual_status)"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------
# Test cases. Each defines a clean sandbox state, sources the helper in
# a subshell, and calls safe_rm_rf with the target under test.
# ---------------------------------------------------------------------

# 1. Empty argument -> refused with exit 1.
test_empty_arg() {
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf ""
}

# 2. Non-existent target -> idempotent success (exit 0).
test_nonexistent() {
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf "/tmp/this-path-must-not-exist-$$"
}

# 3. Root path -> refused.
test_root_refused() {
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf "/"
}

# 4. $HOME direct -> refused (HOME itself is not in any prefix; only
#    $HOME/.claude/* and $HOME/claude_config_backup/* etc. are allowed).
test_home_refused() {
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf "$HOME"
}

# 5. Path outside allow-list (e.g. /etc) -> refused.
test_outside_refused() {
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf "/etc/hostname"
}

# 6. `..` traversal that escapes the allow-list -> refused after
#    realpath collapses the segments. The literal path is dressed up to
#    look like an allow-listed location, but `..` segments resolve it
#    back to a non-allow-listed parent.
test_dotdot_traversal_refused() {
    # Create a fixture in /tmp directly using a name that is NOT
    # /tmp/claude-* nor /tmp/claude-config-*, so resolving back to
    # the fixture root escapes the allow-list.
    local outside_root
    outside_root="$(mktemp -d -t safe-rm-outside.XXXXXX)"
    mkdir -p "$outside_root/.claude/inner"
    # shellcheck disable=SC1090
    source "$HELPER"
    local rc=0
    # Lexically contains /.claude/, but `../..` resolves to outside_root
    # itself (e.g. /tmp/safe-rm-outside.*) — not allow-listed.
    safe_rm_rf "$outside_root/.claude/inner/../.." || rc=$?
    rm -rf "$outside_root"
    return "$rc"
}

# 7. Symlink pointing outside the allow-list -> refused. The link itself
#    lives in an allow-listed prefix, but realpath -e follows it to /etc.
test_symlink_outside_refused() {
    local link="/tmp/claude-config-symlink-$$"
    rm -f "$link"
    ln -s "/etc" "$link"
    # shellcheck disable=SC1090
    source "$HELPER"
    local rc=0
    safe_rm_rf "$link" || rc=$?
    rm -f "$link"
    return "$rc"
}

# 8. Allow-listed path under /tmp/claude-config-* -> succeeds.
test_allowlisted_tmp_succeeds() {
    local fixture="$SANDBOX/positive-case"
    mkdir -p "$fixture/sub"
    touch "$fixture/sub/file"
    # shellcheck disable=SC1090
    source "$HELPER"
    safe_rm_rf "$fixture"
    [ ! -e "$fixture" ]
}

# 9. Relative path that resolves into an allow-listed prefix -> succeeds.
#    Verifies realpath promotion, not just literal prefix match.
test_relative_path_succeeds() {
    local fixture="$SANDBOX/relative-case"
    mkdir -p "$fixture/inner"
    # shellcheck disable=SC1090
    source "$HELPER"
    ( cd "$fixture" && safe_rm_rf "./inner" )
    [ ! -e "$fixture/inner" ]
}

# 10. Relative path that resolves OUTSIDE the allow-list -> refused.
test_relative_path_refused() {
    # shellcheck disable=SC1090
    source "$HELPER"
    ( cd /etc && safe_rm_rf "./hostname" )
}

# ---------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------
echo "Running safe_rm_rf tests..."
echo "Helper: $HELPER"
echo "Sandbox: $SANDBOX"
echo ""

run_test "empty argument refused"            1 test_empty_arg
run_test "non-existent target idempotent"    0 test_nonexistent
run_test "/ refused"                         1 test_root_refused
run_test "\$HOME refused"                    1 test_home_refused
run_test "outside allow-list refused"        1 test_outside_refused
run_test ".. traversal refused"              1 test_dotdot_traversal_refused
run_test "symlink to outside refused"        1 test_symlink_outside_refused
run_test "allow-listed path succeeds"        0 test_allowlisted_tmp_succeeds
run_test "relative path inside succeeds"     0 test_relative_path_succeeds
run_test "relative path outside refused"     1 test_relative_path_refused

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
