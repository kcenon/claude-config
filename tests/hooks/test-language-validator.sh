#!/bin/bash
# test-language-validator.sh
# Matrix tests for the CLAUDE_CONTENT_LANGUAGE dispatcher introduced in #410.
# Covers hooks/lib/validate-language.sh and the Rule 2 branch in
# hooks/lib/validate-commit-message.sh.
#
# Exit codes: 0 on all-pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../hooks/lib/validate-language.sh
. "$REPO_ROOT/hooks/lib/validate-language.sh"
# shellcheck source=../../hooks/lib/validate-commit-message.sh
. "$REPO_ROOT/hooks/lib/validate-commit-message.sh"

PASS=0
FAIL=0

# run_case <name> <expected 0|1> <policy> <fn> <args...>
run_case() {
    local name="$1" expected="$2" policy="$3" fn="$4"
    shift 4

    local got
    if [ -n "$policy" ]; then
        CLAUDE_CONTENT_LANGUAGE="$policy" "$fn" "$@" >/dev/null 2>&1
    else
        unset CLAUDE_CONTENT_LANGUAGE
        "$fn" "$@" >/dev/null 2>&1
    fi
    got=$?

    if [ "$got" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name (expected exit=$expected, got=$got)"
    fi
}

echo "=== validate-language.sh (PR/issue content) ==="

echo ""
echo "[english policy — default, unset, empty]"
run_case "unset env accepts ASCII"               0 ""        validate_content_language "simple ASCII text"
run_case "english rejects Hangul"                1 "english" validate_content_language "한국어 텍스트"
run_case "english rejects accented Latin"        1 "english" validate_content_language "naïve café"
run_case "english rejects emoji"                 1 "english" validate_content_language "party 🎉"

echo ""
echo "[korean_plus_english policy]"
run_case "korean+en accepts Hangul syllables"    0 "korean_plus_english" validate_content_language "한국어"
run_case "korean+en accepts Hangul Jamo"         0 "korean_plus_english" validate_content_language "ㄱㄴㄷ"
run_case "korean+en accepts mixed ASCII+Hangul"  0 "korean_plus_english" validate_content_language "fix 버그 수정"
run_case "korean+en rejects Japanese"            1 "korean_plus_english" validate_content_language "こんにちは"
run_case "korean+en rejects Chinese"             1 "korean_plus_english" validate_content_language "你好"
run_case "korean+en rejects emoji"               1 "korean_plus_english" validate_content_language "rocket 🚀"

echo ""
echo "[any policy]"
run_case "any accepts Japanese"                  0 "any"     validate_content_language "こんにちは"
run_case "any accepts emoji + accented"          0 "any"     validate_content_language "fête 🎉 café"
run_case "any accepts arbitrary Unicode"         0 "any"     validate_content_language "Ω Я 中"

echo ""
echo "[empty input always valid]"
run_case "english + empty"                       0 "english" validate_content_language ""
run_case "korean_plus_english + empty"           0 "korean_plus_english" validate_content_language ""
run_case "exclusive_bilingual + empty"           0 "exclusive_bilingual" validate_content_language ""
run_case "any + empty"                           0 "any"     validate_content_language ""

echo ""
echo "[exclusive_bilingual policy — issue #447 accept/reject matrix]"
# English-mode branch (no Hangul syllable → validate_english_only applies).
run_case "excl: pure ASCII accepted (english mode)" 0 "exclusive_bilingual" validate_content_language "Add a new feature via gh pr create"
run_case "excl: pure ASCII rejects accented Latin"  1 "exclusive_bilingual" validate_content_language "naive cafe that is naïve"

# Korean-mode branch (Hangul present → validate_korean_with_tech_terms).
# Reject rows from issue #447 matrix.
run_case "excl: 'PR을 만든다' rejected"              1 "exclusive_bilingual" validate_content_language "PR을 만든다"
run_case "excl: '/pr-work 를 실행' rejected"         1 "exclusive_bilingual" validate_content_language "/pr-work 를 실행"
run_case "excl: 'GitHub Actions에서' rejected"       1 "exclusive_bilingual" validate_content_language "GitHub Actions에서"
run_case "excl: '버전 v1.10.0 배포' rejected"       1 "exclusive_bilingual" validate_content_language "버전 v1.10.0 배포"

# Accept rows from issue #447 matrix.
run_case "excl: '훅(hook)을 설치' accepted"          0 "exclusive_bilingual" validate_content_language "훅(hook)을 설치"
run_case "excl: URL reference accepted"              0 "exclusive_bilingual" validate_content_language "https://example.com 참조"
run_case "excl: backtick-wrapped token accepted"     0 "exclusive_bilingual" validate_content_language "이슈 \`#247\` 참조"

# Fenced-code block strip.
run_case "excl: fenced-code block accepted"          0 "exclusive_bilingual" validate_content_language "한국어 설명

\`\`\`bash
echo hello
\`\`\`

끝"

echo ""
echo "[unknown policy falls back to english]"
run_case "unknown policy rejects Hangul"         1 "martian" validate_content_language "한국어"
run_case "unknown policy accepts ASCII"          0 "martian" validate_content_language "plain text"

echo ""
echo "=== validate-commit-message.sh (Rule 2 branching) ==="

echo ""
echo "[english policy — Rule 2 enforces lowercase ASCII]"
run_case "english accepts lowercase ASCII commit"  0 "english" validate_commit_message "feat: add feature"
run_case "english rejects uppercase first char"    1 "english" validate_commit_message "feat: Add feature"
run_case "english rejects Hangul first char"       1 "english" validate_commit_message "feat: 기능 추가"

echo ""
echo "[korean_plus_english policy — Hangul first char allowed]"
run_case "korean+en accepts lowercase ASCII"       0 "korean_plus_english" validate_commit_message "feat: add feature"
run_case "korean+en accepts Hangul first"          0 "korean_plus_english" validate_commit_message "feat: 기능 추가"
run_case "korean+en rejects uppercase first"       1 "korean_plus_english" validate_commit_message "feat: Add feature"

echo ""
echo "[any policy — Rule 2 bypassed]"
run_case "any accepts uppercase first"             0 "any"     validate_commit_message "feat: Mixed Case Text"
run_case "any accepts Russian first"               0 "any"     validate_commit_message "feat: Начало"

echo ""
echo "[attribution hard rule — MUST block under every policy]"
run_case "english blocks 'generated with claude'"       1 "english"              validate_commit_message "feat: generated with claude"
run_case "korean+en blocks 'claude' string"             1 "korean_plus_english"  validate_commit_message "feat: claude assisted"
run_case "any blocks 'anthropic' string"                1 "any"                  validate_commit_message "feat: anthropic reviewed"

echo ""
echo "[emoji hard rule — MUST block under every policy]"
run_case "english blocks emoji"                         1 "english"              validate_commit_message "feat: add 🎉"
run_case "korean+en blocks emoji"                       1 "korean_plus_english"  validate_commit_message "feat: 기능 🎉 추가"
run_case "any blocks emoji"                             1 "any"                  validate_commit_message "feat: add 🎉"

echo ""
echo "[Conventional Commits format — MUST be enforced under every policy]"
run_case "english rejects missing type"                 1 "english"              validate_commit_message "just a message"
run_case "korean+en rejects missing type"               1 "korean_plus_english"  validate_commit_message "버그 수정"
run_case "any rejects missing type"                     1 "any"                  validate_commit_message "just a message"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
