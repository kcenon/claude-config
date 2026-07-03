#!/bin/bash
# Test suite: merge-gate-guard.sh — opt-in pending-check timeout (Issue #747)
# Run: bash tests/hooks/test-merge-gate-pending-timeout.sh
#
# Validates the GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES escape hatch:
#   - UNSET (default): pending checks hard-block (strict, unchanged).
#   - SET + pending older than threshold + no other blockers: allow+warning.
#   - SET + pending newer than threshold: still deny.
#   - SET + a fail/cancel bucket alongside pending: still deny.
# A stub `gh` on PATH supplies controllable bucket/state/startedAt so no real
# GitHub call is made.

HOOK="global/hooks/merge-gate-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

SCRATCH_ROOT="${TMPDIR:-/tmp}"
STUB_DIR=$(mktemp -d "$SCRATCH_ROOT/mggpt-stub.XXXXXX" 2>/dev/null) \
    || STUB_DIR="$SCRATCH_ROOT/mggpt-stub.$$"
trap 'rm -rf "$STUB_DIR"' EXIT

# The stub emits a JSON array driven by MOCK_MODE. For the "old" and "fresh"
# pending cases it computes startedAt relative to now so the test is not clock
# dependent. The hook requests `--json bucket,name,state,startedAt` when the
# timeout is active; the stub ignores the field list and always emits the full
# shape (extra fields are harmless to jq).
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/bin/bash
iso() {
    # iso <seconds-ago> -> ISO-8601 UTC timestamp that many seconds in the past.
    local ago="$1" now
    now=$(date -u +%s)
    local then=$((now - ago))
    if date -u -d "@${then}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then return; fi
    date -u -r "${then}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
case "${MOCK_MODE:-}" in
    pending_old)
        # Single pending check started 2 hours ago.
        printf '[{"bucket":"pending","name":"build","state":"IN_PROGRESS","startedAt":"%s"}]\n' "$(iso 7200)"
        ;;
    pending_fresh)
        # Single pending check started 30 seconds ago.
        printf '[{"bucket":"pending","name":"build","state":"IN_PROGRESS","startedAt":"%s"}]\n' "$(iso 30)"
        ;;
    pending_old_plus_fail)
        # Old pending AND a failing check — the fail must keep the gate closed.
        printf '[{"bucket":"pending","name":"build","state":"IN_PROGRESS","startedAt":"%s"},{"bucket":"fail","name":"lint","state":"FAILURE","startedAt":"%s"}]\n' "$(iso 7200)" "$(iso 7200)"
        ;;
    all_pass)
        printf '[{"bucket":"pass","name":"build","state":"COMPLETED","startedAt":"%s"}]\n' "$(iso 7200)"
        ;;
    *)
        echo "stub gh: unknown MOCK_MODE='${MOCK_MODE:-}'" >&2
        exit 2
        ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB_DIR/gh"
export PATH="$STUB_DIR:$PATH"

if [ "$(command -v gh)" != "$STUB_DIR/gh" ]; then
    echo "FATAL: gh stub not on PATH (resolved $(command -v gh))" >&2
    exit 1
fi

INPUT_PR='{"tool_input":{"command":"gh pr merge 42 --squash"}}'

run_hook() {
    local mode="$1" timeout_minutes="$2"
    if [ -n "$timeout_minutes" ]; then
        MOCK_MODE="$mode" GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES="$timeout_minutes" \
            bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
    else
        MOCK_MODE="$mode" bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
    fi
}

assert_contains() {
    local label="$1" needle="$2" result="$3"
    if echo "$result" | grep -q "$needle"; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $label — expected /$needle/, got: $result"); echo "  FAIL: $label"
    fi
}

echo "=== merge-gate-guard.sh pending-timeout tests ==="
echo ""

echo "[Default (env unset): pending hard-blocks — strict, unchanged]"
assert_contains "old pending, no env → deny" '"deny"' "$(run_hook pending_old '')"
assert_contains "fresh pending, no env → deny" '"deny"' "$(run_hook pending_fresh '')"

echo ""
echo "[Opt-in: only pending, older than threshold → allow + warning]"
result=$(run_hook pending_old 60)
assert_contains "old pending + 60m timeout → allow" '"allow"' "$result"
assert_contains "old pending + 60m timeout → carries warning context" 'additionalContext' "$result"

echo ""
echo "[Opt-in: pending not yet past threshold → still deny]"
assert_contains "fresh pending + 60m timeout → deny" '"deny"' "$(run_hook pending_fresh 60)"

echo ""
echo "[Opt-in: fail bucket present alongside pending → still deny]"
assert_contains "old pending + fail + 60m timeout → deny" '"deny"' "$(run_hook pending_old_plus_fail 60)"

echo ""
echo "[Opt-in: invalid env value falls back to strict]"
assert_contains "old pending + env=0 → deny (0 not positive)" '"deny"' "$(run_hook pending_old 0)"
assert_contains "old pending + env=abc → deny (non-numeric)" '"deny"' "$(run_hook pending_old abc)"

echo ""
echo "[Clean gate unaffected by env]"
assert_contains "all pass + 60m timeout → allow" '"allow"' "$(run_hook all_pass 60)"

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
