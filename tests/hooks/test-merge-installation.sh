#!/bin/bash
# Test suite for install-hooks.sh merge mode prepend behavior (#619).
#
# Verifies that when a user chooses option 2 "병합", claude-config
# validators are PREPENDED before the existing hook content so an
# existing `exit 0` cannot silently bypass them.
#
# Run: bash tests/hooks/test-merge-installation.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

PASS=0
FAIL=0
ERRORS=()

INSTALLER="hooks/install-hooks.sh"

note_pass() {
    ((PASS++))
    echo "  PASS: $1"
}

note_fail() {
    ((FAIL++))
    ERRORS+=("FAIL: $1")
    echo "  FAIL: $1"
}

echo "=== install-hooks.sh merge mode tests (#619) ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: prepend ordering
# ---------------------------------------------------------------------------
echo "[Test 1: claude-config block is prepended, not appended]"
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
TARGET="$TMP/git-hooks"
mkdir -p "$TARGET"

# Plant an existing commit-msg hook whose primary path exits 0.
cat > "$TARGET/commit-msg" <<'EOF'
#!/bin/bash
echo "EXISTING_HOOK_RAN" >&2
exit 0
EOF
chmod +x "$TARGET/commit-msg"

# Feed "2" to the only prompt (commit-msg has an existing hook). The other
# two installs (pre-commit, pre-push) write fresh and do not prompt.
INSTALL_HOOKS_TARGET_DIR="$TARGET" \
  bash "$INSTALLER" <<<"2" >"$TMP/install.log" 2>&1 || true

if [[ ! -f "$TARGET/commit-msg" ]]; then
    note_fail "commit-msg hook was not installed"
else
    content=$(cat "$TARGET/commit-msg")
    # The claude-config prepend marker must appear before the existing marker.
    prepend_pos=$(grep -n "claude-config commit-msg (prepended" <<<"$content" | head -1 | cut -d: -f1)
    existing_pos=$(grep -n "EXISTING_HOOK_RAN" <<<"$content" | head -1 | cut -d: -f1)
    if [[ -z "$prepend_pos" ]]; then
        note_fail "claude-config prepend marker missing in merged commit-msg"
    elif [[ -z "$existing_pos" ]]; then
        note_fail "existing-hook content missing in merged commit-msg"
    elif (( prepend_pos < existing_pos )); then
        note_pass "claude-config block precedes existing content (prepend@${prepend_pos} < existing@${existing_pos})"
    else
        note_fail "claude-config block is not before existing (prepend@${prepend_pos} >= existing@${existing_pos}) — bug regressed"
    fi
fi

# ---------------------------------------------------------------------------
# Test 2: installer reports merge order
# ---------------------------------------------------------------------------
echo ""
echo "[Test 2: installer prints merge order summary]"
if grep -q "merge order: 1) claude-config validators  2) existing hook content" "$TMP/install.log"; then
    note_pass "merge order summary present in installer stdout"
else
    note_fail "merge order summary missing — install log:"
    sed 's/^/    /' "$TMP/install.log" | head -20 >&2
fi

# ---------------------------------------------------------------------------
# Test 3: claude-config validators have authority — invalid message rejected
# ---------------------------------------------------------------------------
# The "prepend" model means the new validators decide first and exit. An
# existing 'exit 0' downstream cannot override unless claude-config falls
# through. Send an invalid commit message and verify the merged hook
# rejects it (exit non-zero) — proves new validators ran and were not
# bypassed.
echo ""
echo "[Test 3: invalid message rejected (existing exit 0 cannot bypass new validators)]"
mkdir -p "$TARGET/lib"
cp hooks/lib/validate-commit-message.sh "$TARGET/lib/" 2>/dev/null || true
[[ -f hooks/lib/validate-traceability.sh ]] && cp hooks/lib/validate-traceability.sh "$TARGET/lib/" 2>/dev/null || true

INVALID_MSG="$TMP/invalid-commit"
# Invalid Conventional Commits type — rejected by validate-commit-message.sh.
# (commit-msg only inspects the first non-comment line.)
printf 'nope: this commit type is not allowed\n' > "$INVALID_MSG"

set +e
(cd "$TARGET" && bash "./commit-msg" "$INVALID_MSG") >"$TMP/invalid.out" 2>&1
rc=$?
set -e

if (( rc != 0 )); then
    note_pass "claude-config validators rejected invalid commit-type message (exit $rc); existing exit 0 did not bypass"
else
    note_fail "merged hook returned 0 on invalid message — new validators were bypassed (regression)"
    sed 's/^/    /' "$TMP/invalid.out" | head -10 >&2
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
