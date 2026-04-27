#!/bin/bash
# Test suite: merge-gate-guard.sh — timeout / external-CLI behavior
# Run: bash tests/hooks/test-merge-gate-guard-timeout.sh
#
# Validates how merge-gate-guard.sh reacts when the upstream `gh` CLI behaves
# unusually (slow, hanging, failing). Uses a stub `gh` binary on PATH so we
# never call real GitHub. Cases below match the issue #479 acceptance
# criteria.

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
        # path. With a default 10 s timeout the hook still returns allow; the
        # perl-fallback case below uses a tighter budget to fire the timeout.
        sleep 2
        echo '[{"bucket":"pass","name":"build","state":"COMPLETED"}]'
        exit 0
        ;;
    hang)
        # Long sleep simulating an unresponsive gh process. The hook's
        # internal timeout should kill this and fall through to fail-open
        # allow without waiting the full 30 s.
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

# Run the hook with the test stub on PATH. The hook itself is responsible for
# bounding the gh call — these tests no longer wrap the hook in a host-level
# timeout because the contract under test is "hook returns within budget".
run_hook() {
    local mode="$1"
    local timeout_sec="${2:-10}"
    GH_CHECKS_TIMEOUT_SEC="$timeout_sec" MOCK_MODE="$mode" \
        bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
}

# Run the hook with a deliberately stripped PATH that excludes any
# coreutils binaries, forcing the timeout-wrapper down to the perl fallback.
# Keeps stub gh + system perl/jq reachable via absolute paths.
run_hook_no_coreutils() {
    local mode="$1"
    local timeout_sec="${2:-10}"
    local minimal_path="$STUB_DIR:/usr/bin:/bin"
    PATH="$minimal_path" GH_CHECKS_TIMEOUT_SEC="$timeout_sec" MOCK_MODE="$mode" \
        bash "$HOOK" <<<"$INPUT_PR" 2>/dev/null
}

assert_decision() {
    local label="$1"
    local expected="$2"
    local result="$3"

    if echo "$result" | grep -q "\"$expected\""; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected $expected, got: $result")
        echo "  FAIL: $label"
    fi
}

now_ms() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time()*1000))'
    elif command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf("%d\n", int(time()*1000))'
    else
        echo 0
    fi
}

echo "=== merge-gate-guard.sh timeout / stub-gh tests ==="
echo ""

# Case 1: fast pass — gh returns immediately with all-pass checks → allow.
echo "[1] fast pass — all checks green, immediate response"
result=$(run_hook fast)
assert_decision "fast pass → allow" "allow" "$result"

# Case 2: slow gh (2 s) within budget — hook waits for the response and
# allows. Default 10 s budget comfortably covers this.
echo ""
echo "[2] slow gh (2 s) within 10 s budget — eventually returns all-pass"
start_ms=$(now_ms)
result=$(run_hook slow2)
end_ms=$(now_ms)
elapsed=$((end_ms - start_ms))
assert_decision "slow gh → allow (eventual)" "allow" "$result"
echo "    info: hook returned in ${elapsed}ms"

# Case 3: hung gh (>30 s sleep) with a 2 s budget — hook's internal timeout
# wrapper fires, we expect a fail-open allow within ~3 s, not the full 30 s.
echo ""
echo "[3] hung gh — hook internal 2 s timeout fires, fail-open allow"
start_ms=$(now_ms)
result=$(run_hook hang 2)
end_ms=$(now_ms)
elapsed=$((end_ms - start_ms))
assert_decision "hung gh → allow (timeout fail-open)" "allow" "$result"
if [ "$elapsed" -gt 5000 ]; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: hung gh exceeded 5 s wall time (${elapsed}ms) — timeout did not fire")
    echo "  FAIL: timeout did not bound wall time (${elapsed}ms > 5000ms)"
else
    PASS=$((PASS + 1))
    echo "  PASS: wall time bounded (${elapsed}ms)"
fi

# Case 4: gh exits non-zero — fail-open per merge-gate-guard policy. The
# guard's stated contract is "FAIL-OPEN on gh CLI errors" so the hook must
# still allow the merge and let server-side branch protection be the gate.
echo ""
echo "[4] gh exits non-zero — fail-open policy"
result=$(run_hook fail)
assert_decision "gh fail → allow (fail-open)" "allow" "$result"

# Case 5: non-passing checks — gh succeeds but reports a failing bucket,
# guard must deny.
echo ""
echo "[5] non-passing check — guard denies merge"
result=$(run_hook nonpassing)
assert_decision "non-passing checks → deny" "deny" "$result"

# Case 6: cross-platform timeout fallback — strip coreutils from PATH so the
# wrapper must use perl alarm. Fast stub still resolves; allow is expected.
echo ""
echo "[6] perl fallback — PATH without timeout/gtimeout, fast stub"
result=$(run_hook_no_coreutils fast)
assert_decision "perl fallback fast → allow" "allow" "$result"

# Case 7: cross-platform timeout fires via perl fallback — same stripped
# PATH, hung stub, 2 s budget. Wall time must be bounded by the budget.
echo ""
echo "[7] perl fallback — hung stub, internal timeout fires"
start_ms=$(now_ms)
result=$(run_hook_no_coreutils hang 2)
end_ms=$(now_ms)
elapsed=$((end_ms - start_ms))
assert_decision "perl fallback hang → allow (timeout)" "allow" "$result"
if [ "$elapsed" -gt 5000 ]; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: perl fallback exceeded 5 s wall time (${elapsed}ms)")
    echo "  FAIL: perl fallback did not bound wall time (${elapsed}ms > 5000ms)"
else
    PASS=$((PASS + 1))
    echo "  PASS: perl fallback bounded wall time (${elapsed}ms)"
fi

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
