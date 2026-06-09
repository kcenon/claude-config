#!/bin/bash
# Test suite for tests/sonar-fix/fixtures/ (#639).
#
# Verifies that every whitelisted SonarQube rule has a before/after
# fixture pair on disk AND that those fixtures match, byte-for-byte,
# the Before/After code blocks in the corresponding Pattern entry of
# global/skills/_internal/sonar-fix/reference/auto-fixable-rules.md.
#
# This prevents silent drift where someone edits the Pattern entry
# without updating the fixture (or vice versa). The automated fix
# engine that will eventually consume these fixtures relies on the
# Pattern entry being the single source of truth.
#
# Run: bash tests/sonar-fix/test-fixtures.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

RULES_DOC="global/skills/_internal/sonar-fix/reference/auto-fixable-rules.md"
FIX="tests/sonar-fix/fixtures"
PASS=0
FAIL=0
ERRORS=()

# rule_id:ext pairs. When a new whitelisted rule is codified, append
# its row here AND drop the matching fixture files into $FIX/.
RULES=(
    "S1481:py"
    "S1128:py"
    "S1854:py"
    "S1192:py"
    "S125:py"
    "S1116:c"
)

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label")
        ERRORS+=("  expected (from $RULES_DOC):")
        while IFS= read -r line; do ERRORS+=("    | $line"); done <<< "$expected"
        ERRORS+=("  actual (from fixture):")
        while IFS= read -r line; do ERRORS+=("    | $line"); done <<< "$actual"
        echo "  FAIL: $label"
    fi
}

# Extract the contents of the first fenced code block under a heading
# (`### Before` or `### After`) inside a specific rule's Pattern entry.
#
# Args:
#   $1 — rule id (e.g. S1481)
#   $2 — heading (Before or After)
extract_block() {
    local rule="$1" heading="$2"
    awk -v r="$rule" -v h="$heading" '
        BEGIN { in_rule = 0; in_heading = 0; in_fence = 0 }
        /^## / {
            in_rule = ($0 ~ ("^## " r " "))
            in_heading = 0
            in_fence = 0
            next
        }
        in_rule && /^### / {
            in_heading = ($0 == ("### " h))
            in_fence = 0
            next
        }
        in_rule && in_heading && /^```/ {
            if (in_fence == 0) { in_fence = 1; next }
            else { in_fence = 0; in_heading = 0; exit }
        }
        in_rule && in_heading && in_fence { print }
    ' "$RULES_DOC"
}

echo "=== sonar-fix fixture parity tests (#639) ==="
echo ""

for entry in "${RULES[@]}"; do
    rule="${entry%%:*}"
    ext="${entry##*:}"

    echo "[$rule]"

    before_fixture="$FIX/${rule}_before.${ext}"
    after_fixture="$FIX/${rule}_after.${ext}"

    if [[ ! -f "$before_fixture" ]]; then
        ((FAIL++))
        ERRORS+=("FAIL: $before_fixture missing")
        echo "  FAIL: before fixture missing"
        continue
    fi
    if [[ ! -f "$after_fixture" ]]; then
        ((FAIL++))
        ERRORS+=("FAIL: $after_fixture missing")
        echo "  FAIL: after fixture missing"
        continue
    fi

    before_doc=$(extract_block "$rule" "Before")
    after_doc=$(extract_block "$rule" "After")

    if [[ -z "$before_doc" ]]; then
        ((FAIL++))
        ERRORS+=("FAIL: $rule Before block missing in $RULES_DOC")
        echo "  FAIL: Before block missing in doc"
        continue
    fi
    if [[ -z "$after_doc" ]]; then
        ((FAIL++))
        ERRORS+=("FAIL: $rule After block missing in $RULES_DOC")
        echo "  FAIL: After block missing in doc"
        continue
    fi

    before_actual=$(cat "$before_fixture")
    after_actual=$(cat "$after_fixture")

    assert_eq "$rule before fixture matches doc" "$before_doc" "$before_actual"
    assert_eq "$rule after fixture matches doc"  "$after_doc"  "$after_actual"
done

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if (( FAIL > 0 )); then
    echo ""
    echo "=== Errors ==="
    for err in "${ERRORS[@]}"; do
        echo "$err"
    done
    exit 1
fi

exit 0
