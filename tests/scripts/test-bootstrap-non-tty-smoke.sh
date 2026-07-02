#!/bin/bash
# test-bootstrap-non-tty-smoke.sh
# Smoke test for issue #797.
#
# The test feeds the real bootstrap.sh body to bash on stdin, matching the
# advertised `curl ... | bash` shape. It uses
# CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=prompt-resolution, a test-only early exit
# that runs after bootstrap argument/prompt resolution and before dependency
# checks, network access, cloning, or installation.
#
# Run: bash tests/scripts/test-bootstrap-non-tty-smoke.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-non-tty.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

PASS=0
FAIL=0

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label"
        echo "    expected:"
        printf '%s\n' "$expected" | sed 's/^/      /'
        echo "    actual:"
        printf '%s\n' "$actual" | sed 's/^/      /'
    fi
}

run_piped_bootstrap() {
    cat "$BOOTSTRAP" | env \
        -u INSTALL_TYPE \
        -u FORCE_MODE \
        -u PROJECT_DIR \
        -u INSTALL_CLAUDE \
        -u INSTALL_NPM \
        -u OVERWRITE \
        -u EDIT_NOW \
        HOME="$TEST_HOME" \
        USERPROFILE="$TEST_HOME" \
        CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=prompt-resolution \
        "$@" 2>&1
}

echo "=== Bootstrap non-tty smoke test (#797) ==="
echo ""

output="$(run_piped_bootstrap INSTALL_TYPE=3 bash)"
check_eq "piped INSTALL_TYPE=3 overrides non-tty default" \
    $'FORCE_MODE=0\nINSTALL_TYPE=3\nSTDIN_TTY=0' "$output"

output="$(run_piped_bootstrap bash -s -- --yes)"
check_eq "--yes resolves the documented bootstrap default without prompting" \
    $'FORCE_MODE=1\nINSTALL_TYPE=1\nSTDIN_TTY=0' "$output"

output="$(run_piped_bootstrap bash -s -- --type 3 --yes)"
check_eq "--type 3 combines with --yes in piped mode" \
    $'FORCE_MODE=1\nINSTALL_TYPE=3\nSTDIN_TTY=0' "$output"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
