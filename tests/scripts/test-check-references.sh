#!/usr/bin/env bash
# Test suite for scripts/check_references.sh and scripts/sync_references.sh.
# Run: bash tests/scripts/test-check-references.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
CHECK="$ROOT_DIR/scripts/check_references.sh"
SYNC="$ROOT_DIR/scripts/sync_references.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ERRORS=()

write_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected exit $expected, got $actual")
        echo "  FAIL: $label (expected $expected, got $actual)"
    fi
}

echo "=== check_references.sh tests ==="

REPO="$WORK/repo"
mkdir -p "$REPO"
write_file "$REPO/source/exact.md" 'same'
write_file "$REPO/target/exact.md" 'same'
write_file "$REPO/source/fm.md" '---
title: Source
---

body
'
write_file "$REPO/target/fm.md" 'body
'
cat > "$REPO/reference-map.yml" <<'YAML'
version: 1
references:
  - source: source/exact.md
    target: target/exact.md
    mode: exact
  - source: source/fm.md
    target: target/fm.md
    mode: strip-source-frontmatter
YAML

out=$(bash "$CHECK" "$REPO" "$REPO/reference-map.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "exact and strip-source-frontmatter entries pass"

write_file "$REPO/target/exact.md" 'drift'
out=$(bash "$CHECK" "$REPO" "$REPO/reference-map.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "drift exits 2"

out=$(bash "$SYNC" "$REPO" "$REPO/reference-map.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "sync exits 0"
out=$(bash "$CHECK" "$REPO" "$REPO/reference-map.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "sync restores drift"

REPO_CRLF="$WORK/repo-crlf"
mkdir -p "$REPO_CRLF"
write_file "$REPO_CRLF/source/crlf-exact.md" $'same\r\nnext\r\n'
write_file "$REPO_CRLF/target/crlf-exact.md" $'same\nnext\n'
write_file "$REPO_CRLF/source/crlf-fm.md" $'---\r\ntitle: Source\r\n---\r\n\r\nbody\r\n'
write_file "$REPO_CRLF/target/crlf-fm.md" $'body\n'
cat > "$REPO_CRLF/reference-map.yml" <<'YAML'
version: 1
references:
  - source: source/crlf-exact.md
    target: target/crlf-exact.md
    mode: exact
  - source: source/crlf-fm.md
    target: target/crlf-fm.md
    mode: strip-source-frontmatter
YAML
out=$(bash "$CHECK" "$REPO_CRLF" "$REPO_CRLF/reference-map.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "CRLF entries compare equal after normalization"

REPO_GIT="$WORK/repo-git"
mkdir -p "$REPO_GIT"
git -C "$REPO_GIT" init -q
write_file "$REPO_GIT/source/exact.md" 'same'
write_file "$REPO_GIT/target/exact.md" 'same'
cat > "$REPO_GIT/reference-map.yml" <<'YAML'
version: 1
references:
  - source: source/exact.md
    target: target/exact.md
    mode: exact
YAML
link_blob=$(printf '../../../rules/demo.md' | git -C "$REPO_GIT" hash-object -w --stdin)
git -C "$REPO_GIT" update-index --add --cacheinfo "120000,$link_blob,project/.claude/skills/demo/reference/link.md"
out=$(bash "$CHECK" "$REPO_GIT" "$REPO_GIT/reference-map.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "tracked project reference symlink exits 2"

echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
