#!/usr/bin/env bash
# Test suite for scripts/diff-readme.sh.
# Run: bash tests/scripts/test-diff-readme.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
DIFF_README="$ROOT_DIR/scripts/diff-readme.sh"

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

echo "=== diff-readme.sh tests ==="

EN="$WORK/en.md"
KO="$WORK/ko.md"

write_file "$EN" '# Title

```bash
# Heading in a fenced block is ignored
```

## Install

Run `bash scripts/install.sh` and check `COMPATIBILITY.md#settings-field-inventory-and-stability`.
'
write_file "$KO" '# 제목

```bash
# fenced 블록 안 heading은 무시
```

## 설치

`bash scripts/install.sh`를 실행하고 `COMPATIBILITY.md#settings-field-inventory-and-stability`를 확인합니다.
'
out=$(bash "$DIFF_README" "$EN" "$KO" 2>&1); rc=$?
assert_exit 0 "$rc" "matching heading counts and contract tokens pass"

write_file "$KO" '# 제목

## 설치

### 추가

`bash scripts/install.sh`
'
out=$(bash "$DIFF_README" "$EN" "$KO" 2>&1); rc=$?
assert_exit 1 "$rc" "heading count mismatch fails"
assert_contains "structural skeleton diverges" "$out" "heading mismatch message"

write_file "$KO" '# 제목

## 설치

`bash scripts/install.sh`를 실행합니다.
'
out=$(bash "$DIFF_README" "$EN" "$KO" 2>&1); rc=$?
assert_exit 1 "$rc" "missing compatibility path token fails"
assert_contains "contract token drift" "$out" "token drift message"

write_file "$EN" '# Title

## Install

Inline translated prose like `current value` is ignored.
'
write_file "$KO" '# 제목

## 설치

`현재 값` 같은 번역 산문 inline code는 무시합니다.
'
out=$(bash "$DIFF_README" "$EN" "$KO" 2>&1); rc=$?
assert_exit 0 "$rc" "non-contract inline prose is ignored"

out=$(bash "$DIFF_README" "$WORK/missing.md" "$KO" 2>&1); rc=$?
assert_exit 2 "$rc" "missing file returns exit 2"

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
