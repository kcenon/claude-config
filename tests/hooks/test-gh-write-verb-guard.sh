#!/bin/bash
# Test suite: gh-write-verb-guard.sh — golden corpus runner
# Run: bash tests/hooks/test-gh-write-verb-guard.sh
#
# Iterates over JSON fixtures under tests/hooks/fixtures/ghwvg-corpus/{deny,allow,edge}
# and asserts that each one produces the expected permission decision.
#
# Outcome is encoded by directory:
#   deny/  → must yield "permissionDecision": "deny"
#   allow/ → must yield "permissionDecision": "allow"
#   edge/  → expected decision in <name>.expect.json (default: allow);
#            optional `env` map to set environment variables before running.

HOOK="global/hooks/gh-write-verb-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

CORPUS_ROOT="tests/hooks/fixtures/ghwvg-corpus"

# Use a scratch log dir so assertions don't touch ~/.claude/logs.
SCRATCH_ROOT="${TMPDIR:-/tmp}"
TEST_LOG_DIR=$(mktemp -d "$SCRATCH_ROOT/ghwvg-golden.XXXXXX" 2>/dev/null) \
    || TEST_LOG_DIR="$SCRATCH_ROOT/ghwvg-golden.$$"
mkdir -p "$TEST_LOG_DIR"
export CLAUDE_LOG_DIR="$TEST_LOG_DIR"
trap 'rm -rf "$TEST_LOG_DIR"' EXIT

expect_for_edge() {
    local fixture="$1"
    local expect_file="${fixture%.json}.expect.json"
    if [ -f "$expect_file" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.expect_decision // "allow"' "$expect_file" 2>/dev/null
    else
        echo "allow"
    fi
}

# Read environment map from .expect.json and apply it inline. Returns
# the env-var pairs as `KEY=VALUE` lines on stdout.
expect_env_pairs() {
    local fixture="$1"
    local expect_file="${fixture%.json}.expect.json"
    if [ -f "$expect_file" ] && command -v jq >/dev/null 2>&1; then
        jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value)"' "$expect_file" 2>/dev/null
    fi
}

assert_decision() {
    local expected="$1"
    local fixture="$2"
    local label
    label=$(basename "$fixture" .json)

    local result
    local -a env_pairs=()
    while IFS= read -r pair; do
        [ -n "$pair" ] && env_pairs+=("$pair")
    done < <(expect_env_pairs "$fixture")

    if [ "${#env_pairs[@]}" -gt 0 ]; then
        result=$(env "${env_pairs[@]}" bash "$HOOK" < "$fixture" 2>/dev/null)
    else
        result=$(bash "$HOOK" < "$fixture" 2>/dev/null)
    fi

    if echo "$result" | grep -q "\"$expected\""; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected $expected, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== gh-write-verb-guard golden corpus ==="
echo ""

# --- deny corpus ---
deny_count=$(ls "$CORPUS_ROOT"/deny/*.json 2>/dev/null | wc -l | tr -d ' ')
echo "[deny — $deny_count fixtures]"
for f in "$CORPUS_ROOT"/deny/*.json; do
    [ -f "$f" ] || continue
    assert_decision "deny" "$f"
done

echo ""
allow_count=$(ls "$CORPUS_ROOT"/allow/*.json 2>/dev/null | wc -l | tr -d ' ')
echo "[allow — $allow_count fixtures]"
for f in "$CORPUS_ROOT"/allow/*.json; do
    [ -f "$f" ] || continue
    assert_decision "allow" "$f"
done

echo ""
edge_count=0
for f in "$CORPUS_ROOT"/edge/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
        *.expect.json) continue ;;
    esac
    edge_count=$((edge_count + 1))
done
echo "[edge — $edge_count fixtures]"
for f in "$CORPUS_ROOT"/edge/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
        *.expect.json) continue ;;
    esac
    expected=$(expect_for_edge "$f")
    assert_decision "$expected" "$f"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
