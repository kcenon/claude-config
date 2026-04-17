#!/bin/bash
# extractors.sh
# Drift signal extractor library for Tier 2 benchmark (epic #287, issue #310).
#
# Pure functions: each extractor takes raw text/JSON input and returns a numeric
# count. No network calls, no `gh` invocations — callers fetch data once and
# pass it in. This keeps the library offline-testable and reusable across the
# benchmark orchestrator (#314), the regression test (#311), and ad-hoc audits.
#
# Sources hooks/lib/validate-commit-message.sh for CMV_ATTRIBUTION_REGEX and
# validate_commit_message so the regex/format rules stay single-source.

set -u

EXTRACTORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR_LIB="$EXTRACTORS_DIR/../../hooks/lib/validate-commit-message.sh"

if [ ! -f "$VALIDATOR_LIB" ]; then
    echo "ERROR: SSOT validator not found at $VALIDATOR_LIB" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=../../hooks/lib/validate-commit-message.sh
. "$VALIDATOR_LIB"

# extract_language_violations <text>
# Counts CJK code points (Hangul, Han ideographs, Hiragana, Katakana).
# Used to detect non-English leaks in PR bodies and issue comments.
extract_language_violations() {
    local text="${1:-}"
    if [ -z "$text" ]; then
        echo 0
        return 0
    fi
    printf '%s' "$text" | perl -CSD -e '
        local $/;
        my $t = <STDIN>;
        my $n = () = $t =~ /[\x{AC00}-\x{D7AF}\x{1100}-\x{11FF}\x{3130}-\x{318F}\x{4E00}-\x{9FFF}\x{3040}-\x{309F}\x{30A0}-\x{30FF}]/g;
        print $n;
    '
}

# extract_attribution_leaks <text>
# Counts matches of the SSOT attribution regex (claude, anthropic, ai-assisted,
# co-authored-by: claude, generated with). Same regex used by commit-msg hook
# and the attribution-guard PreToolUse hook — divergence here would create a
# silent gap between enforcement and measurement.
extract_attribution_leaks() {
    local text="${1:-}"
    if [ -z "$text" ]; then
        echo 0
        return 0
    fi
    local count
    count=$(printf '%s' "$text" | grep -oiE "$CMV_ATTRIBUTION_REGEX" 2>/dev/null | wc -l)
    echo $((count + 0))
}

# extract_ci_gate_violations <pr_json>
# Returns 1 if the PR was merged while any check was non-passing, else 0.
# Input must include `mergedAt` and `statusCheckRollup` fields from
# `gh pr view --json mergedAt,statusCheckRollup`.
# A null/missing conclusion on a merged PR counts as a violation (treated as
# pending — merging a PR with pending checks is exactly what the gate forbids).
extract_ci_gate_violations() {
    local pr_json="${1:-}"
    if [ -z "$pr_json" ]; then
        echo 0
        return 0
    fi
    local result
    result=$(printf '%s' "$pr_json" | jq -r '
        if (.mergedAt // null) == null then 0
        else
            (.statusCheckRollup // [])
            | map(.conclusion // "PENDING")
            | map(ascii_upcase)
            | map(select(. != "SUCCESS" and . != "NEUTRAL" and . != "SKIPPED"))
            | (if length > 0 then 1 else 0 end)
        end
    ' 2>/dev/null)
    echo "${result:-0}"
}

# extract_missing_closes <pr_body>
# Returns 1 if the PR body has no `Closes #N` / `Fixes #N` / `Resolves #N`
# keyword, else 0. Strict format: keyword + whitespace + `#` + digits.
# Empty body counts as missing.
extract_missing_closes() {
    local body="${1:-}"
    if [ -z "$body" ]; then
        echo 1
        return 0
    fi
    if printf '%s' "$body" | grep -qiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+'; then
        echo 0
    else
        echo 1
    fi
}

# extract_commit_format_violations <commit_messages>
# Counts commits that fail the SSOT validate_commit_message check.
# Input: newline-separated commit subject lines.
extract_commit_format_violations() {
    local commits="${1:-}"
    if [ -z "$commits" ]; then
        echo 0
        return 0
    fi
    local count=0
    local msg
    while IFS= read -r msg; do
        [ -z "$msg" ] && continue
        if ! validate_commit_message "$msg" >/dev/null 2>&1; then
            count=$((count + 1))
        fi
    done <<< "$commits"
    echo "$count"
}
