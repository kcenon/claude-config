#!/usr/bin/env bash
# Guard for #1011: installed guidance must not contradict the gh invariant in
# global/CLAUDE.md, which says to wait for CI with `gh pr checks --watch` or
# `gh run watch`, one gh command per Bash call, never in a loop.
#
# Fails when a Markdown file under an installed tree (global/, project/,
# plugin/, plugin-lite/) forbids those watch commands, or points to the
# "Environment Workarounds" section that global/CLAUDE.md no longer has.
#
# Run: bash tests/scripts/test-ci-wait-guidance.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

FAIL=0

check() {
    local label="$1" pattern="$2" matches
    matches="$(git grep -n -i -E "$pattern" -- \
        'global/*.md' 'project/*.md' 'plugin/*.md' 'plugin-lite/*.md')"
    if [ -n "$matches" ]; then
        echo "FAIL: $label"
        printf '%s\n' "$matches" | sed 's/^/  /'
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
    fi
}

check "no line forbids waiting with gh run watch or gh pr checks --watch" \
    "(do not|don't|never)[^.]*(gh run watch|gh pr checks[^.]*--watch)"
check "no line calls gh run watch blocking" \
    "block(s|ing)?[^.]*gh run watch|gh run watch[^.]*block"
check "no pointer to the removed Environment Workarounds section" \
    "Environment Workarounds"

if [ "$FAIL" -ne 0 ]; then
    echo "test-ci-wait-guidance: $FAIL check(s) failed; see the gh invariant in global/CLAUDE.md"
    exit 1
fi
echo "test-ci-wait-guidance: all checks passed"
