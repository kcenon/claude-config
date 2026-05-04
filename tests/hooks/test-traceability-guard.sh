#!/bin/bash
# Test suite for traceability-guard.sh PreToolUse hook + the shared
# validate-traceability.sh library. Both layers source the same library,
# so exercising the library plus the JSON-decision wrapper covers the
# full enforcement path documented in issue #590.
#
# Run: bash tests/hooks/test-traceability-guard.sh

HOOK="global/hooks/traceability-guard.sh"
LIB="hooks/lib/validate-traceability.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1
REPO_DIR="$(pwd)"

# --- helpers ---
seed_repo() {
    # Build a tiny git repo with a graph.yaml, two doc-id-bearing markdown
    # files, and a source file. The caller picks which files end up in the
    # diff range by editing them after the initial commit.
    local root="$1"
    local with_graph="${2:-1}"
    mkdir -p "$root"
    cd "$root" || return 1
    git init --quiet --initial-branch=main 2>/dev/null \
        || { git init --quiet && git checkout -q -b main; }
    git config user.email "ci@example.com"
    git config user.name "ci"
    git config commit.gpgsign false 2>/dev/null || true

    mkdir -p docs/srs docs/tests src/calc

    cat >docs/srs/calc.md <<'EOF'
---
doc_id: SRS-CALC-001
doc_title: Calculator engine
---
# SRS-CALC-001 Calculator engine

The system shall compute sums.
EOF

    cat >docs/tests/calc.md <<'EOF'
---
doc_id: TC-CALC-001
doc_title: Calculator engine test cases
---
# TC-CALC-001 Calculator sums

Verifies SRS-CALC-001.
EOF

    cat >src/calc/engine.cpp <<'EOF'
int add(int a, int b) { return a + b; }
EOF

    if [ "$with_graph" = "1" ]; then
        mkdir -p docs/.index
        cat >docs/.index/graph.yaml <<'EOF'
graph:
  SRS-CALC-001:
    cascade:
      - TC-CALC-001
      - src/calc/engine.cpp
  TC-CALC-001:
    cascade: []
EOF
    fi

    git add -A
    git commit --quiet -m "chore: seed repo"
    git checkout -q -b feature
    cd "$REPO_DIR" || return 1
}

cleanup_repo() {
    rm -rf "$1"
}

assert_lib_pass() {
    local label="$1" base="$2" head="$3" root="$4"
    bash -c "
        cd '$root' && . '$REPO_DIR/$LIB' && validate_traceability_range '$base' '$head' '$root'
    " 2>/dev/null
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected rc=0, got rc=$rc")
        echo "  FAIL: $label"
    fi
}

assert_lib_fail() {
    local label="$1" base="$2" head="$3" root="$4"
    bash -c "
        cd '$root' && . '$REPO_DIR/$LIB' && validate_traceability_range '$base' '$head' '$root'
    " 2>/dev/null
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected rc!=0, got rc=$rc")
        echo "  FAIL: $label"
    fi
}

assert_hook_allow() {
    local label="$1" input="$2"
    local result
    result=$(echo "$input" | bash "$REPO_DIR/$HOOK" 2>/dev/null)
    if echo "$result" | grep -q '"allow"'; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected allow, got: $result")
        echo "  FAIL: $label"
    fi
}

echo "=== traceability-guard.sh / validate-traceability.sh tests ==="
echo ""

# --- Scope tests on the PreToolUse wrapper ---
echo "[Scope: non-gh-pr-create commands pass through]"
assert_hook_allow 'ls -la' '{"tool_input":{"command":"ls -la"}}'
assert_hook_allow 'gh pr view' '{"tool_input":{"command":"gh pr view 123"}}'
assert_hook_allow 'gh issue create' '{"tool_input":{"command":"gh issue create --title test"}}'
assert_hook_allow 'git push' '{"tool_input":{"command":"git push origin develop"}}'

echo ""
echo "[Empty/malformed input → allow (pre-push is the gate)]"
assert_hook_allow 'empty input' ''
assert_hook_allow 'malformed JSON' 'NOT JSON'

echo ""
echo "[Library: opt-out path — no graph.yaml → return 0]"
TMP1=$(mktemp -d)
seed_repo "$TMP1" 0
echo "// adjustment" >>"$TMP1/src/calc/engine.cpp"
( cd "$TMP1" && git add -A && git commit --quiet -m "chore: edit src" )
assert_lib_pass 'no graph.yaml → opt-out (return 0)' "main" "HEAD" "$TMP1"
cleanup_repo "$TMP1"

echo ""
echo "[Library: happy path — SRS edited together with cascade targets]"
TMP2=$(mktemp -d)
seed_repo "$TMP2" 1
# Edit all three files declared in cascade together — should pass.
echo "" >>"$TMP2/docs/srs/calc.md"
echo "Updated requirement statement." >>"$TMP2/docs/srs/calc.md"
echo "" >>"$TMP2/docs/tests/calc.md"
echo "New verification step." >>"$TMP2/docs/tests/calc.md"
echo "// note" >>"$TMP2/src/calc/engine.cpp"
( cd "$TMP2" && git add -A && git commit --quiet -m "feat: full cascade update" )
assert_lib_pass 'happy path — full cascade update' "main" "HEAD" "$TMP2"
cleanup_repo "$TMP2"

echo ""
echo "[Library: cascade-miss — SRS edited but TC + source not updated]"
TMP3=$(mktemp -d)
seed_repo "$TMP3" 1
echo "" >>"$TMP3/docs/srs/calc.md"
echo "Updated requirement statement." >>"$TMP3/docs/srs/calc.md"
( cd "$TMP3" && git add -A && git commit --quiet -m "feat: only requirement edited" )
assert_lib_fail 'cascade miss — SRS only' "main" "HEAD" "$TMP3"
cleanup_repo "$TMP3"

echo ""
echo "[Library: partial cascade — only TC updated, source still missing]"
TMP4=$(mktemp -d)
seed_repo "$TMP4" 1
echo "" >>"$TMP4/docs/srs/calc.md"
echo "Updated requirement." >>"$TMP4/docs/srs/calc.md"
echo "" >>"$TMP4/docs/tests/calc.md"
echo "More verification." >>"$TMP4/docs/tests/calc.md"
( cd "$TMP4" && git add -A && git commit --quiet -m "feat: partial cascade" )
assert_lib_fail 'partial cascade — source missing' "main" "HEAD" "$TMP4"
cleanup_repo "$TMP4"

echo ""
echo "[Library: unrelated diff — no cascade obligation]"
TMP5=$(mktemp -d)
seed_repo "$TMP5" 1
mkdir -p "$TMP5/docs/notes"
echo "Plain note, no doc_id." >"$TMP5/docs/notes/journal.md"
( cd "$TMP5" && git add -A && git commit --quiet -m "docs: add unrelated note" )
assert_lib_pass 'unrelated diff — no cascade obligation' "main" "HEAD" "$TMP5"
cleanup_repo "$TMP5"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
