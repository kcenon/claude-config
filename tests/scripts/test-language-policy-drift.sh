#!/bin/bash
# test-language-policy-drift.sh
# Drift regression for issue #411.
#
# For each rule document shipped with a .md.tmpl twin, this test verifies:
#
#   1. The canonical .md file equals the .tmpl file rendered with the
#      "english" policy phrase. If someone edits the .md without updating
#      the .tmpl (or vice versa), the installer would overwrite the doc
#      with a stale phrase on any non-english policy - this catches that.
#
#   2. For all three policies (english, korean_plus_english, any), the
#      rendered output contains the expected phrase. Policy values that
#      cannot be rendered deterministically fail the test.
#
# Run: bash tests/scripts/test-language-policy-drift.sh
# Exit: 0 on all-pass, 1 on any drift or rendering failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Files under coverage — (canonical .md, .tmpl) pairs
TEMPLATE_PAIRS=(
    "$REPO_ROOT/global/commit-settings.md|$REPO_ROOT/global/commit-settings.md.tmpl"
    "$REPO_ROOT/project/.claude/rules/core/communication.md|$REPO_ROOT/project/.claude/rules/core/communication.md.tmpl"
    "$REPO_ROOT/project/.claude/rules/workflow/git-commit-format.md|$REPO_ROOT/project/.claude/rules/workflow/git-commit-format.md.tmpl"
)

# policy → phrase table (must match installer tables)
declare -A PHRASE
PHRASE[english]="English"
PHRASE[korean_plus_english]="English or Korean"
PHRASE[any]="any language"

PASS=0
FAIL=0

render() {
    local tmpl="$1" phrase="$2"
    sed "s|{{CONTENT_LANGUAGE_POLICY}}|${phrase}|g" "$tmpl"
}

echo "=== Content-language policy drift test (#411) ==="
echo ""

for pair in "${TEMPLATE_PAIRS[@]}"; do
    md="${pair%%|*}"
    tmpl="${pair##*|}"
    name="$(basename "$md")"

    echo "[${name}]"

    if [ ! -f "$md" ]; then
        echo "  FAIL: canonical .md missing: $md"
        FAIL=$((FAIL + 1))
        continue
    fi
    if [ ! -f "$tmpl" ]; then
        echo "  FAIL: .tmpl missing: $tmpl"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Check 1: canonical .md equals .tmpl rendered with english phrase.
    # Line-ending insensitive (repo has mixed CRLF/LF; on Windows clones all
    # files roundtrip through CRLF via Git autocrlf).
    if diff -q <(render "$tmpl" "${PHRASE[english]}" | tr -d '\r') <(tr -d '\r' < "$md") >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: canonical .md matches .tmpl rendered with english phrase"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: canonical .md drifted from .tmpl (english render)"
        echo "  --- diff (canonical vs rendered, LF-normalized) ---"
        diff <(render "$tmpl" "${PHRASE[english]}" | tr -d '\r') <(tr -d '\r' < "$md") | head -20 | sed 's/^/      /'
        echo "  ---------------------------------------------------"
    fi

    # Check 2: each policy produces output containing its phrase
    for policy in english korean_plus_english any; do
        phrase="${PHRASE[$policy]}"
        if render "$tmpl" "$phrase" | grep -qF "$phrase"; then
            PASS=$((PASS + 1))
            echo "  PASS: ${policy} render contains '${phrase}'"
        else
            FAIL=$((FAIL + 1))
            echo "  FAIL: ${policy} render missing phrase '${phrase}'"
        fi
    done

    echo ""
done

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
