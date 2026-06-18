#!/bin/bash
# test-doc-prompt-lockstep.sh
# Doc/prompt lockstep guard (issue #763).
#
# When the installer language prompt was collapsed from a two-prompt
# (Agent Conversation Language + Content Language) flow into a single
# 3-option Language Profile Preset (issue #757), several docs and inline
# comments kept describing the old flow and naming functions that no
# longer exist. This test pins the prompt source as the single source of
# truth and fails if any stale description or dead identifier creeps back
# into a tracked file.
#
# Two halves:
#   1. DENYLIST  — tokens that describe the removed two-prompt flow or name
#                  removed functions. None may appear in any tracked file
#                  (the test itself and CHANGELOG/history files excepted).
#   2. POSITIVE  — anchors that must remain in install-prompts.sh so the
#                  3-option preset prompt is not silently gutted.
#
# Run: bash tests/scripts/test-doc-prompt-lockstep.sh
# Exit: 0 on no drift, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

BASH_LIB="scripts/lib/install-prompts.sh"

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

# Files excluded from the denylist scan: this test (it lists the banned
# tokens verbatim) and changelog/history files (they record the removal
# and must keep the old names for posterity).
is_excluded() {
    case "$1" in
        tests/scripts/test-doc-prompt-lockstep.sh) return 0 ;;
        CHANGELOG.md) return 0 ;;
        */VERSION_HISTORY.md|VERSION_HISTORY.md) return 0 ;;
        *) return 1 ;;
    esac
}

echo "=== Doc/prompt lockstep test (#763) ==="
echo ""
echo "[1] Denylist — stale two-prompt descriptions and removed identifiers"

# Tokens that must not appear in any tracked file. Removed function names
# from the two-prompt era plus prose that describes the old flow.
DENYLIST=(
    'prompt_agent_language'
    'prompt_content_language'
    'Show-AgentLanguagePrompt'
    'Show-ContentLanguagePrompt'
    'two-option'
    '두 옵션'
    'Enter twice'
    'pressing Enter twice'
)

for token in "${DENYLIST[@]}"; do
    # git grep with -F (fixed string) over tracked files. Collect hits,
    # drop excluded files, and fail if anything remains.
    hits="$(git grep -lF -- "$token" 2>/dev/null || true)"
    offending=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! is_excluded "$f"; then
            offending="${offending:+$offending }$f"
        fi
    done <<EOF
$hits
EOF

    if [ -z "$offending" ]; then
        pass "denylist token absent: '$token'"
    else
        fail "denylist token present: '$token' in: $offending"
    fi
done

echo ""
echo "[2] Positive anchors — the 3-option preset prompt is intact"

# install-prompts.sh must still carry the preset header, all three option
# labels, and the default-3 selection line. These pin the live prompt so a
# regression that guts it back toward the old flow is caught here too.
POSITIVE=(
    'Select Language Profile Preset:'
    '1) English Unified'
    '2) Korean Unified'
    '3) Hybrid Mode'
    '[default: 3]'
)

for anchor in "${POSITIVE[@]}"; do
    if grep -qF -- "$anchor" "$BASH_LIB"; then
        pass "anchor present in $BASH_LIB: '$anchor'"
    else
        fail "anchor missing in $BASH_LIB: '$anchor'"
    fi
done

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
