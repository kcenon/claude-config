#!/bin/bash
# Regression test for issue #447 Phase 1 / #448.
#
# Verifies that pr-language-guard.sh honours CLAUDE_CONTENT_LANGUAGE
# propagated from the parent shell into the hook subprocess. The original
# bug: operators set korean_plus_english in settings.json but still saw
# Korean content rejected, because the shared validator library was not
# deployed and the inline fallback read the env var in a subprocess that
# never received it (or never respected it).
#
# Scope:
#   * The policy dispatcher is exercised end-to-end through the hook
#     (stdin JSON in, permissionDecision JSON out).
#   * Env var propagation is checked in both exported and unset states.
#   * Accept and reject samples cover the three supported policies
#     (english, korean_plus_english, any).
#
# Out of scope: the exclusive_bilingual policy (Phase 2 of #447).
#
# Run: bash tests/hooks/test-pr-language-guard-env.sh
# Exit: 0 on all-pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/global/hooks/pr-language-guard.sh"

if [ ! -x "$HOOK" ] && [ ! -r "$HOOK" ]; then
    echo "FAIL: pr-language-guard.sh not found at $HOOK" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not on PATH; pr-language-guard parses stdin via jq"
    exit 0
fi

PASS=0
FAIL=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helper: run the hook with a given env var setting and a gh command, then
# print the resulting permission decision ("allow" or "deny" or "error").
# ---------------------------------------------------------------------------
run_hook() {
    local policy="$1"      # empty string = unset, otherwise the value
    local gh_cmd="$2"      # the shell command gh-pr/issue would run

    local payload
    payload=$(jq -n --arg cmd "$gh_cmd" '{tool_input: {command: $cmd}}')

    local out
    if [ -z "$policy" ]; then
        out=$(env -u CLAUDE_CONTENT_LANGUAGE bash "$HOOK" <<<"$payload" 2>/dev/null)
    else
        out=$(CLAUDE_CONTENT_LANGUAGE="$policy" bash "$HOOK" <<<"$payload" 2>/dev/null)
    fi

    local decision
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "error"' 2>/dev/null)
    printf '%s' "$decision"
}

assert_decision() {
    local name="$1" expected="$2" got="$3"
    if [ "$expected" = "$got" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$name: expected=$expected got=$got")
        echo "  FAIL: $name (expected=$expected got=$got)"
    fi
}

# Quick sanity: make sure the hook actually sourced the shared library
# rather than falling through to the inline fallback. The deployed layout
# for this test is repo-relative, so $REPO_ROOT/hooks/lib/validate-language.sh
# must exist.
echo "=== Shared validator library available ==="
if [ -f "$REPO_ROOT/hooks/lib/validate-language.sh" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: hooks/lib/validate-language.sh present for hook to source"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("hooks/lib/validate-language.sh missing at repo root")
    echo "  FAIL: hooks/lib/validate-language.sh missing"
fi

# ---------------------------------------------------------------------------
# Default (unset env): english policy
# ---------------------------------------------------------------------------
echo ""
echo "=== CLAUDE_CONTENT_LANGUAGE unset (english default) ==="

assert_decision \
    "unset env: ASCII title allowed" \
    "allow" \
    "$(run_hook "" "gh issue create --title \"Add new feature\" --body \"plain ASCII body\"")"

assert_decision \
    "unset env: Hangul title denied" \
    "deny" \
    "$(run_hook "" "gh issue create --title \"기능 추가\" --body \"plain body\"")"

assert_decision \
    "unset env: Hangul body denied" \
    "deny" \
    "$(run_hook "" "gh issue create --title \"plain title\" --body \"한글 본문\"")"

# ---------------------------------------------------------------------------
# english policy (explicit)
# ---------------------------------------------------------------------------
echo ""
echo "=== CLAUDE_CONTENT_LANGUAGE=english ==="

assert_decision \
    "english: ASCII allowed" \
    "allow" \
    "$(run_hook "english" "gh pr create --title \"fix bug\" --body \"ascii body\"")"

assert_decision \
    "english: Hangul body denied" \
    "deny" \
    "$(run_hook "english" "gh pr create --title \"fix bug\" --body \"한글 설명\"")"

# ---------------------------------------------------------------------------
# korean_plus_english policy (the bug that motivated #447)
# ---------------------------------------------------------------------------
echo ""
echo "=== CLAUDE_CONTENT_LANGUAGE=korean_plus_english ==="

assert_decision \
    "korean_plus_english: Hangul title allowed" \
    "allow" \
    "$(run_hook "korean_plus_english" "gh issue create --title \"한국어 제목\" --body \"한국어 설명\"")"

assert_decision \
    "korean_plus_english: mixed ASCII+Hangul body allowed" \
    "allow" \
    "$(run_hook "korean_plus_english" "gh pr create --title \"fix\" --body \"fix 버그 수정\"")"

assert_decision \
    "korean_plus_english: Japanese Hiragana denied" \
    "deny" \
    "$(run_hook "korean_plus_english" "gh issue create --title \"fix\" --body \"こんにちは\"")"

# ---------------------------------------------------------------------------
# any policy
# ---------------------------------------------------------------------------
echo ""
echo "=== CLAUDE_CONTENT_LANGUAGE=any ==="

assert_decision \
    "any: arbitrary unicode allowed" \
    "allow" \
    "$(run_hook "any" "gh issue create --title \"fix\" --body \"Omega Я 中 naive\"")"

# ---------------------------------------------------------------------------
# Non-gh commands must be ignored regardless of env
# ---------------------------------------------------------------------------
echo ""
echo "=== Non-gh commands bypass validation ==="

assert_decision \
    "non-gh command allowed under english" \
    "allow" \
    "$(run_hook "english" "echo 한국어")"

assert_decision \
    "gh commands outside the artifact scope allowed" \
    "allow" \
    "$(run_hook "english" "gh repo view")"

# ---------------------------------------------------------------------------
# Extended scope: gh pr review (review-thread comment body)
# ---------------------------------------------------------------------------
echo ""
echo "=== gh pr review --body coverage ==="

assert_decision \
    "english: gh pr review ASCII body allowed" \
    "allow" \
    "$(run_hook "english" "gh pr review 42 --comment --body \"LGTM, looks good\"")"

assert_decision \
    "english: gh pr review Hangul body denied" \
    "deny" \
    "$(run_hook "english" "gh pr review 42 --comment --body \"리뷰 의견\"")"

assert_decision \
    "korean_plus_english: gh pr review Hangul body allowed" \
    "allow" \
    "$(run_hook "korean_plus_english" "gh pr review 42 --request-changes --body \"수정 필요\"")"

# ---------------------------------------------------------------------------
# Extended scope: gh release create / edit (release notes + title)
# ---------------------------------------------------------------------------
echo ""
echo "=== gh release coverage ==="

assert_decision \
    "english: gh release create ASCII notes allowed" \
    "allow" \
    "$(run_hook "english" "gh release create v1.0.0 --notes \"Initial release\"")"

assert_decision \
    "english: gh release create Hangul notes denied" \
    "deny" \
    "$(run_hook "english" "gh release create v1.0.0 --notes \"초기 릴리스\"")"

assert_decision \
    "english: gh release create Hangul title denied" \
    "deny" \
    "$(run_hook "english" "gh release create v1.0.0 --title \"릴리스\" --notes \"ASCII notes\"")"

assert_decision \
    "english: gh release edit Hangul notes denied" \
    "deny" \
    "$(run_hook "english" "gh release edit v1.0.0 --notes \"수정된 노트\"")"

assert_decision \
    "any --notes-file is skipped (cannot validate file content here)" \
    "allow" \
    "$(run_hook "english" "gh release create v1.0.0 --notes-file CHANGELOG.md")"

assert_decision \
    "korean_plus_english: gh release create Hangul notes allowed" \
    "allow" \
    "$(run_hook "korean_plus_english" "gh release create v1.0.0 --notes \"한국어 릴리스 노트\"")"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi

exit 0
