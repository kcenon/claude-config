#!/bin/bash
# Test suite: dangerous-command-guard.sh — golden corpus runner
# Run: bash tests/hooks/test-dangerous-command-guard-golden.sh
#
# Iterates over JSON fixtures under tests/hooks/fixtures/dcg-corpus/{deny,allow,edge}
# and asserts that each one produces the expected permission decision.
#
# Outcome is encoded by directory:
#   deny/  → must yield "permissionDecision": "deny"
#   allow/ → must yield "permissionDecision": "allow"
#   edge/  → expected decision specified in <name>.expect.json (default: allow)
#
# Edge fixtures may also carry runtime constraints in <name>.expect.json,
# such as max_runtime_ms (1 MB perf) or the "generate" marker that asks the
# runner to synthesize a large payload at execution time.

HOOK="global/hooks/dangerous-command-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

CORPUS_ROOT="tests/hooks/fixtures/dcg-corpus"

# Use a scratch log dir so assertions don't touch ~/.claude/logs.
SCRATCH_ROOT="${TMPDIR:-/tmp}"
TEST_LOG_DIR=$(mktemp -d "$SCRATCH_ROOT/dcg-golden.XXXXXX" 2>/dev/null) \
    || TEST_LOG_DIR="$SCRATCH_ROOT/dcg-golden.$$"
mkdir -p "$TEST_LOG_DIR"
export CLAUDE_LOG_DIR="$TEST_LOG_DIR"
trap 'rm -rf "$TEST_LOG_DIR"' EXIT

# expect_for_edge <fixture_path>
# Reads the matching .expect.json sidecar and prints the expected decision
# (defaults to "allow" when the sidecar is missing).
expect_for_edge() {
    local fixture="$1"
    local expect_file="${fixture%.json}.expect.json"
    if [ -f "$expect_file" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.expect_decision // "allow"' "$expect_file" 2>/dev/null
    else
        echo "allow"
    fi
}

# expect_runtime_limit <fixture_path>
# Returns the max_runtime_ms constraint or empty string.
expect_runtime_limit() {
    local fixture="$1"
    local expect_file="${fixture%.json}.expect.json"
    if [ -f "$expect_file" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.max_runtime_ms // empty' "$expect_file" 2>/dev/null
    fi
}

# expect_generate_marker <fixture_path>
# Returns the "generate" marker (e.g. "1mb_payload") or empty string.
expect_generate_marker() {
    local fixture="$1"
    local expect_file="${fixture%.json}.expect.json"
    if [ -f "$expect_file" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.generate // empty' "$expect_file" 2>/dev/null
    fi
}

# build_fixture_input <fixture_path> <generate_marker>
# Outputs the JSON payload to feed the hook on stdout. For "1mb_payload" the
# payload is synthesized at runtime; for everything else the file content is
# emitted verbatim (this also covers raw non-JSON inputs like 02-malformed-json).
build_fixture_input() {
    local fixture="$1"
    local marker="$2"
    if [ "$marker" = "1mb_payload" ]; then
        # ~1 MB of safe filler inside a single JSON command field. Use python3
        # (always available on the CI matrix) so we never hit the shell
        # ARG_MAX limit that bites jq --arg with a 1 MB string.
        if command -v python3 >/dev/null 2>&1; then
            python3 -c '
import json, sys
filler = "a" * 1048576
sys.stdout.write(json.dumps({"tool_name":"Bash",
                             "tool_input":{"command":"echo " + filler}}))
'
        else
            local filler
            filler=$(awk 'BEGIN{for(i=0;i<1048576;i++)printf "a"}')
            printf '{"tool_name":"Bash","tool_input":{"command":"echo %s"}}' "$filler"
        fi
    else
        cat "$fixture"
    fi
}

# now_ms — millisecond epoch, portable across macOS/Linux.
now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time()*1000))'
    else
        echo $(($(date +%s) * 1000))
    fi
}

# assert_decision <expected> <fixture_path> [marker]
assert_decision() {
    local expected="$1"
    local fixture="$2"
    local marker="${3:-}"
    local label
    label=$(basename "$fixture" .json)

    local input
    input=$(build_fixture_input "$fixture" "$marker")

    local start_ms end_ms elapsed_ms
    start_ms=$(now_ms)
    local result
    result=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)
    end_ms=$(now_ms)
    elapsed_ms=$((end_ms - start_ms))

    if echo "$result" | grep -q "\"$expected\""; then
        ((PASS++))
        echo "  PASS: $label (${elapsed_ms} ms)"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected $expected, got: $result")
        echo "  FAIL: $label"
    fi

    # Runtime-bound assertion (edge cases only).
    local limit
    limit=$(expect_runtime_limit "$fixture")
    if [ -n "$limit" ]; then
        if [ "$elapsed_ms" -le "$limit" ]; then
            ((PASS++))
            echo "    PASS: $label runtime ${elapsed_ms}ms <= ${limit}ms"
        else
            ((FAIL++))
            ERRORS+=("FAIL: $label runtime ${elapsed_ms}ms exceeded ${limit}ms")
            echo "    FAIL: $label runtime ${elapsed_ms}ms exceeded ${limit}ms"
        fi
    fi
}

echo "=== dangerous-command-guard golden corpus ==="
echo ""

# --- deny corpus ---
echo "[deny — $(ls "$CORPUS_ROOT/deny"/*.json 2>/dev/null | wc -l | tr -d ' ') fixtures]"
for f in "$CORPUS_ROOT"/deny/*.json; do
    [ -f "$f" ] || continue
    assert_decision "deny" "$f"
done

echo ""
echo "[allow — $(ls "$CORPUS_ROOT/allow"/*.json 2>/dev/null | wc -l | tr -d ' ') fixtures]"
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
    marker=$(expect_generate_marker "$f")
    assert_decision "$expected" "$f" "$marker"
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
