#!/bin/bash
# Guard test for issue #422: the PostToolUse Edit|Write formatter hook
# (black/isort/prettier/clang-format/ktlint/gofmt/rustfmt one-liner) must
# be registered in exactly one file. The canonical owner is
# plugin/hooks/hooks.json.
#
# Run: bash tests/scripts/test-no-duplicate-formatter.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

# `black --quiet` is a stable substring of the formatter one-liner and
# does not appear in any other tracked hook.
PATTERN='black --quiet'
SCAN_TARGETS=(
    "plugin/hooks"
    "plugin-lite"
    ".claude"
    "project/.claude"
    "global"
    "enterprise"
)

EXISTING=()
for t in "${SCAN_TARGETS[@]}"; do
    [ -e "$t" ] && EXISTING+=("$t")
done

MATCHES=$(grep -rlF --include='*.json' "$PATTERN" "${EXISTING[@]}" 2>/dev/null || true)
COUNT=0
[ -n "$MATCHES" ] && COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')

if [ "$COUNT" -gt 1 ]; then
    echo "FAIL: PostToolUse formatter registered in $COUNT files (expected 1)"
    echo "$MATCHES" | sed 's/^/  - /'
    echo ""
    echo "Canonical owner: plugin/hooks/hooks.json. Remove duplicates."
    exit 1
fi

if [ "$COUNT" -eq 0 ]; then
    echo "FAIL: PostToolUse formatter not found in any tracked settings file"
    exit 1
fi

CANONICAL=$(echo "$MATCHES")
if [ "$CANONICAL" != "plugin/hooks/hooks.json" ]; then
    echo "FAIL: formatter registered in '$CANONICAL'; expected plugin/hooks/hooks.json"
    exit 1
fi

echo "PASS: formatter owned by $CANONICAL"
