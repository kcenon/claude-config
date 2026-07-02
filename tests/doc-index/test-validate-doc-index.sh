#!/usr/bin/env bash
# Test suite for scripts/validate-doc-index.sh.
# Run: bash tests/doc-index/test-validate-doc-index.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
VALIDATOR="$ROOT_DIR/scripts/validate-doc-index.sh"

PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH" >&2
    exit 0
fi
if ! "$PYTHON" -c "import yaml" >/dev/null 2>&1; then
    echo "SKIP: missing PyYAML" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ERRORS=()

write_manifest() {
    local repo="$1"
    local path="$2"
    local size="$3"
    mkdir -p "$repo/docs/.index"
    cat > "$repo/docs/.index/manifest.yaml" <<EOF
_meta: {schema: "1.0.0", generated: "2026-07-02", docs: 1, size_mb: 0.00}
documents:
  - path: "$path"
    title: "Fixture"
    description: "Fixture"
    category: docs
    scope: docs
    size: $size
    tags: [documentation]
    sections: []
EOF
}

write_index_meta() {
    local repo="$1"
    local file="$2"
    local generated="$3"
    mkdir -p "$repo/docs/.index"
    cat > "$repo/docs/.index/$file" <<EOF
_meta: {schema: "1.0.0", generated: "$generated"}
routes: []
EOF
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

assert_contains() {
    local needle="$1" haystack="$2" label="$3"
    if echo "$haystack" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output did not contain '$needle': $haystack")
        echo "  FAIL: $label"
    fi
}

echo "=== validate-doc-index.sh tests ==="

REPO_OK="$WORK/ok"
mkdir -p "$REPO_OK/docs"
printf 'hello' > "$REPO_OK/docs/a.md"
write_manifest "$REPO_OK" "docs/a.md" 5
out=$(bash "$VALIDATOR" "$REPO_OK" 2>&1); rc=$?
assert_exit 0 "$rc" "valid manifest passes"
assert_contains "OK (1 documents)" "$out" "valid manifest reports count"

REPO_SIZE="$WORK/size"
mkdir -p "$REPO_SIZE/docs"
printf 'hello' > "$REPO_SIZE/docs/a.md"
write_manifest "$REPO_SIZE" "docs/a.md" 99
out=$(bash "$VALIDATOR" "$REPO_SIZE" 2>&1); rc=$?
assert_exit 1 "$rc" "size drift fails"
assert_contains "size mismatch" "$out" "size drift message"

REPO_MISSING="$WORK/missing"
mkdir -p "$REPO_MISSING/docs"
write_manifest "$REPO_MISSING" "docs/missing.md" 1
out=$(bash "$VALIDATOR" "$REPO_MISSING" 2>&1); rc=$?
assert_exit 1 "$rc" "missing path fails"
assert_contains "missing file" "$out" "missing path message"

REPO_STALE_INDEX="$WORK/stale-index"
mkdir -p "$REPO_STALE_INDEX/docs"
printf 'hello' > "$REPO_STALE_INDEX/docs/a.md"
write_manifest "$REPO_STALE_INDEX" "docs/a.md" 5
write_index_meta "$REPO_STALE_INDEX" "router.yaml" "2026-04-10"
out=$(bash "$VALIDATOR" "$REPO_STALE_INDEX" 2>&1); rc=$?
assert_exit 1 "$rc" "stale non-manifest index date fails"
assert_contains "generated mismatch" "$out" "stale index date message"

REPO_SYMLINK="$WORK/symlink"
mkdir -p "$REPO_SYMLINK/docs"
printf 'target body\n' > "$REPO_SYMLINK/docs/target.md"
if ln -s target.md "$REPO_SYMLINK/docs/link.md" 2>/dev/null; then
    link_size=$("$PYTHON" - "$REPO_SYMLINK/docs/link.md" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).lstat().st_size)
PY
)
    write_manifest "$REPO_SYMLINK" "docs/link.md" "$link_size"
    out=$(bash "$VALIDATOR" "$REPO_SYMLINK" 2>&1); rc=$?
    assert_exit 0 "$rc" "symlink manifest size uses link entry"
else
    echo "  SKIP: symlink manifest size uses link entry (ln -s unsupported)"
fi

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
