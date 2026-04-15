#!/bin/bash
# Test suite for tests/batch_drift_benchmark/extractors.sh
# Run: bash tests/batch_drift_benchmark/test-extractors.sh

EXTRACTORS="tests/batch_drift_benchmark/extractors.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

if [ ! -f "$EXTRACTORS" ]; then
    echo "ERROR: $EXTRACTORS not found"
    exit 1
fi

# shellcheck source=./extractors.sh
. "$EXTRACTORS"

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label — expected '$expected', got '$actual'")
        echo "  FAIL: $label (expected '$expected', got '$actual')"
    fi
}

echo "=== drift signal extractor tests ==="
echo ""

echo "[language_violations]"
assert_eq "$(extract_language_violations '')" 0 "empty input"
assert_eq "$(extract_language_violations 'pure ASCII text')" 0 "pure ASCII"
assert_eq "$(extract_language_violations '한국어')" 3 "korean 3 chars"
assert_eq "$(extract_language_violations 'mixed 한 글')" 2 "mixed ASCII + 2 hangul"
assert_eq "$(extract_language_violations '中文')" 2 "chinese 2 chars"
assert_eq "$(extract_language_violations 'カタカナ')" 4 "katakana 4 chars"
assert_eq "$(extract_language_violations 'ひらがな')" 4 "hiragana 4 chars"

echo ""
echo "[attribution_leaks]"
assert_eq "$(extract_attribution_leaks '')" 0 "empty input"
assert_eq "$(extract_attribution_leaks 'fix typo in readme')" 0 "clean message"
assert_eq "$(extract_attribution_leaks 'add claude integration')" 1 "single claude reference"
assert_eq "$(extract_attribution_leaks 'generated with claude code by anthropic')" 3 "generated with + claude + anthropic"
assert_eq "$(extract_attribution_leaks 'AI-assisted refactor')" 1 "ai-assisted"
assert_eq "$(extract_attribution_leaks 'Co-Authored-By: Claude')" 1 "co-authored-by claude"

echo ""
echo "[ci_gate_violations]"
CLEAN_PR='{"mergedAt":"2026-04-15T10:00:00Z","statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"SUCCESS"}]}'
DRIFTED_PR='{"mergedAt":"2026-04-15T10:00:00Z","statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]}'
PENDING_PR='{"mergedAt":"2026-04-15T10:00:00Z","statusCheckRollup":[{"conclusion":null,"status":"IN_PROGRESS"}]}'
UNMERGED_PR='{"mergedAt":null,"statusCheckRollup":[{"conclusion":"FAILURE"}]}'
NEUTRAL_PR='{"mergedAt":"2026-04-15T10:00:00Z","statusCheckRollup":[{"conclusion":"NEUTRAL"},{"conclusion":"SKIPPED"}]}'
CANCELLED_PR='{"mergedAt":"2026-04-15T10:00:00Z","statusCheckRollup":[{"conclusion":"CANCELLED"}]}'
assert_eq "$(extract_ci_gate_violations "$CLEAN_PR")" 0 "all checks success"
assert_eq "$(extract_ci_gate_violations "$DRIFTED_PR")" 1 "merged with failing check"
assert_eq "$(extract_ci_gate_violations "$PENDING_PR")" 1 "merged with pending check"
assert_eq "$(extract_ci_gate_violations "$UNMERGED_PR")" 0 "not merged yet"
assert_eq "$(extract_ci_gate_violations "$NEUTRAL_PR")" 0 "neutral and skipped count as pass"
assert_eq "$(extract_ci_gate_violations "$CANCELLED_PR")" 1 "cancelled check is violation"
assert_eq "$(extract_ci_gate_violations '')" 0 "empty json"

echo ""
echo "[missing_closes]"
assert_eq "$(extract_missing_closes 'Closes #42')" 0 "Closes #42"
assert_eq "$(extract_missing_closes 'Fixes #42 in body')" 0 "Fixes #42"
assert_eq "$(extract_missing_closes 'resolves #1234')" 0 "lowercase resolves"
assert_eq "$(extract_missing_closes 'no closing keyword here')" 1 "no closing keyword"
assert_eq "$(extract_missing_closes '')" 1 "empty body"
assert_eq "$(extract_missing_closes 'closes#42')" 1 "no whitespace between keyword and hash"
assert_eq "$(extract_missing_closes 'Some prose. Closes #5. More prose.')" 0 "Closes embedded in prose"

echo ""
echo "[commit_format_violations]"
CLEAN_COMMITS=$(cat <<'GIT_LOG'
feat: add feature
fix(auth): handle null token
docs: update readme
GIT_LOG
)
DRIFTED_COMMITS=$(cat <<'GIT_LOG'
feat: add feature
Updated the parser
fix: Resolve issue.
chore: add claude integration
GIT_LOG
)
assert_eq "$(extract_commit_format_violations "$CLEAN_COMMITS")" 0 "all clean commits"
assert_eq "$(extract_commit_format_violations "$DRIFTED_COMMITS")" 3 "no-type + uppercase/period + attribution"
assert_eq "$(extract_commit_format_violations '')" 0 "empty input"
assert_eq "$(extract_commit_format_violations $'\n\n')" 0 "blank-only input"

echo ""
echo "[SSOT verification]"
if [ -n "${CMV_ATTRIBUTION_REGEX:-}" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: CMV_ATTRIBUTION_REGEX sourced from SSOT"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: CMV_ATTRIBUTION_REGEX not loaded from SSOT")
    echo "  FAIL: CMV_ATTRIBUTION_REGEX not loaded"
fi

if type validate_commit_message >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: validate_commit_message callable from SSOT"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: validate_commit_message not callable from SSOT")
    echo "  FAIL: validate_commit_message not callable"
fi

echo ""
echo "[determinism — 3 identical runs]"
SAMPLE='Closes #42 with claude attribution and 한글'
R1="$(extract_language_violations "$SAMPLE")|$(extract_attribution_leaks "$SAMPLE")|$(extract_missing_closes "$SAMPLE")"
R2="$(extract_language_violations "$SAMPLE")|$(extract_attribution_leaks "$SAMPLE")|$(extract_missing_closes "$SAMPLE")"
R3="$(extract_language_violations "$SAMPLE")|$(extract_attribution_leaks "$SAMPLE")|$(extract_missing_closes "$SAMPLE")"
if [ "$R1" = "$R2" ] && [ "$R2" = "$R3" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: 3 runs produced identical output ($R1)"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: non-deterministic output across runs")
    echo "  FAIL: 3 runs differed: $R1 vs $R2 vs $R3"
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
