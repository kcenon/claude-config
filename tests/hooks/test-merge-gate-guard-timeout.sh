#!/bin/bash
# Test suite: merge-gate-guard.sh — timeout / external-CLI behavior
# Run: bash tests/hooks/test-merge-gate-guard-timeout.sh
#
# Validates how merge-gate-guard.sh reacts when the upstream `gh` CLI behaves
# unusually (slow, hanging, failing). Uses a stub `gh` binary on PATH so we
# never call real GitHub. The 5 cases below match the issue acceptance
# criteria (merge-gate-guard timeout, 5 cases).

HOOK="global/hooks/merge-gate-guard.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

SCRATCH_ROOT="${TMPDIR:-/tmp}"
STUB_DIR=$(mktemp -d "$SCRATCH_ROOT/mgg-stub.XXXXXX" 2>/dev/null) \
    || STUB_DIR="$SCRATCH_ROOT/mgg-stub.$$"
trap 'rm -rf "$STUB_DIR"' EXIT

# Build the stub `gh` binary. MOCK_MODE selects behavior at run time so a
# single binary covers all cases. The hook always invokes
# `gh pr checks <num> --json bucket,name,state` so we mimic that response
# shape (a JSON array of {bucket,name,state}).
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/bin/bash
# Stub gh CLI for merge-gate-guard tests. Real CLI is never invoked.
case "${MOCK_MODE:-}" in
    fast)
        echo '[{"bucket":"pass","name":"build","state":"COMPLETED"}]'
        exit 0
        ;;
    slow2)
        # 2-second simulated slow response — exercises the "long but not hung"
        # path without slowing CI. The hook has no internal timeout, so this
        # is bounded only by real CI patience; the test wraps the call in a
        # host-level timeout.
        sleep 2
        echo '[{"bucket":"pass","name":"build","state":"COMPLETED"}]'
        exit 0
        ;;
    hang)
        # Long sleep simulating an unresponsive gh process. The test wraps
        # the hook in a 3-second host timeout to prove the process can be
        # interrupted without producing a stale "allow" response.
        sleep 30
        ;;
    fail)
        echo "X build failing" >&2
        exit 1
        ;;
    nonpassing)
        echo '[{"bucket":"fail","name":"build","state":"FAILURE"},{"bucket":"pass","name":"lint","state":"COMPLETED"}]'
        exit 0
        ;;
    *)
        echo "stub gh: unknown MOCK_MODE='${MOCK_MODE:-}'" >&2
        exit 2
        ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

# Place stub first on PATH so `command -v gh` inside the hook resolves to it.
export PATH="$STUB_DIR:$PATH"

# Verify the stub is actually being picked up.
if [ "$(command -v gh)" != "$STUB_DIR/gh" ]; then
    echo "FATAL: gh stub not on PATH (resolved $(command -v gh))" >&2
    exit 1
fi

INPUT_PR='{"tool_input":{"command":"gh pr merge 42 --squash --delete-branch"}}'

run_hook_with_timeout() {
    local timeout_sec="$1"
    local mode="$2"
    if command -v timeout >/dev/null 2>&1; then
        MOCK_MODE="$mode" timeout "${timeout_sec}s" bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
    elif command -v gtimeout >/dev/null 2>&1; then
        MOCK_MODE="$mode" gtimeout "${timeout_sec}s" bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
    else
        # Fallback: spawn the hook in a subshell and kill it after `timeout_sec`.
        # We use bash background + sleep rather than depending on `timeout(1)`
        # because macOS does not ship coreutils' timeout by default.
        (
            MOCK_MODE="$mode" bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null &
            local pid=$!
            (
                sleep "$timeout_sec"
                kill -KILL "$pid" 2>/dev/null
            ) &
            local killer=$!
            wait "$pid" 2>/dev/null
            kill -KILL "$killer" 2>/dev/null
        )
    fi
}

assert_decision() {
    local label="$1"
    local expected="$2"
    local result="$3"

    if echo "$result" | grep -q "\"$expected\""; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label — expected $expected, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== merge-gate-guard.sh timeout / stub-gh tests ==="
echo ""

# Case 1: fast pass — gh returns immediately with all-pass checks → allow.
echo "[1] fast pass — all checks green, immediate response"
result=$(run_hook_with_timeout 5 fast)
assert_decision "fast pass → allow" "allow" "$result"

# Case 2: slow gh (2 s) — the hook has no internal timeout, so it blocks until
# the stub responds. The host wraps it in a 6 s ceiling; result must still be
# allow because the stub returns all-pass once it eventually responds.
echo ""
echo "[2] slow gh (2 s) — eventually returns all-pass"
start_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
result=$(run_hook_with_timeout 6 slow2)
end_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
elapsed=$((end_ms - start_ms))
assert_decision "slow gh → allow (eventual)" "allow" "$result"
echo "    info: hook returned in ${elapsed}ms"

# Case 3: hung gh — 3-second host-level timeout kills the hook. We expect
# either a SIGKILL (empty result) or the host's timeout exit. Either way the
# hook should NOT have emitted a stale "allow" response.
echo ""
echo "[3] hung gh — host-level 3 s timeout"
result=$(run_hook_with_timeout 3 hang || true)
if echo "$result" | grep -q '"permissionDecision"'; then
    ((FAIL++))
    ERRORS+=("FAIL: hung gh produced a decision, expected truncation: $result")
    echo "  FAIL: hung gh produced a decision (should have been killed)"
else
    ((PASS++))
    echo "  PASS: hung gh — no decision emitted (process killed before response)"
fi

# Case 4: gh exits non-zero — fail-open per merge-gate-guard policy. The
# guard's stated contract is "FAIL-OPEN on gh CLI errors" so the hook must
# still allow the merge and let server-side branch protection be the gate.
echo ""
echo "[4] gh exits non-zero — fail-open policy"
result=$(run_hook_with_timeout 5 fail)
assert_decision "gh fail → allow (fail-open)" "allow" "$result"

# Case 5: non-passing checks — gh succeeds but reports a failing bucket,
# guard must deny.
echo ""
echo "[5] non-passing check — guard denies merge"
result=$(run_hook_with_timeout 5 nonpassing)
assert_decision "non-passing checks → deny" "deny" "$result"

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
