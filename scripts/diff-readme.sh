#!/bin/bash
# diff-readme.sh — guard the bilingual README contract (#623).
#
# README.md is canonical; README.ko.md is a full translation. The two must
# stay in shape parity: same section heading counts at each level, same
# ordered list of headings (Korean prose for the heading text, but matched
# 1:1 by position).
#
# Strategy:
#   1. Extract heading lines (lines beginning with #, ##, ### …) from each
#      file.
#   2. Compare per-level counts. A divergence means a section was added or
#      removed in one file but not mirrored in the other.
#   3. Compare narrow contract tokens from inline code spans. This catches
#      drift in commands, paths, config files, and environment variables without
#      requiring translated prose to share the same wording.
#
# Exit codes:
#   0  shape match
#   1  count mismatch at one or more levels
#   2  files missing or unreadable
#
# Usage:
#   bash scripts/diff-readme.sh                       # use repo paths
#   bash scripts/diff-readme.sh path/a.md path/b.md   # explicit pair

set -uo pipefail

EN="${1:-README.md}"
KO="${2:-README.ko.md}"

if [[ ! -f "$EN" ]]; then
    echo "diff-readme: $EN not found" >&2
    exit 2
fi
if [[ ! -f "$KO" ]]; then
    echo "diff-readme: $KO not found" >&2
    exit 2
fi

# Capture only ATX-style headings outside fenced code blocks. Lines inside
# ``` ... ``` are skipped to avoid false positives on '# 1. comment'-style
# bash/python comment markers in install instructions.
extract_headings() {
    awk '
        /^```/ { in_fence = !in_fence; next }
        in_fence { next }
        /^#{1,6} .+$/ { print }
    ' "$1"
}

en_headings="$(extract_headings "$EN")"
ko_headings="$(extract_headings "$KO")"

count_at_level() {
    local content="$1" level="$2"
    printf '%s\n' "$content" | awk -v lvl="$level" 'NF>0 {
        n = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "#") n++
            else break
        }
        if (n == lvl) count++
    } END { print count + 0 }'
}

mismatch=0
for level in 1 2 3 4 5; do
    en_n=$(count_at_level "$en_headings" "$level")
    ko_n=$(count_at_level "$ko_headings" "$level")
    if [[ "$en_n" != "$ko_n" ]]; then
        printf 'level %d: %s=%d, %s=%d\n' "$level" "$EN" "$en_n" "$KO" "$ko_n"
        mismatch=1
    fi
done

if (( mismatch )); then
    echo
    echo "diff-readme: structural skeleton diverges between $EN and $KO."
    echo "Re-sync README.ko.md to match README.md or update README.md if the"
    echo "Korean side intentionally added a section."
    exit 1
fi

# Capture inline-code tokens outside fenced code blocks, then keep only tokens
# that represent operational contracts rather than translated prose.
extract_contract_tokens() {
    awk '
        /^```/ { in_fence = !in_fence; next }
        in_fence { next }
        {
            line = $0
            while (match(line, /`[^`]+`/)) {
                token = substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
                if (is_contract_token(token)) {
                    print token
                }
            }
        }
        function is_contract_token(token, ok) {
            ok = 0
            if (token ~ /^\/[A-Za-z0-9_-]+([[:space:]].*)?$/) ok = 1
            if (token ~ /^(\.\/|\.\.\/|~\/|\/|[A-Za-z]:[\/\\])/) ok = 1
            if (token ~ /[\/\\]/) ok = 1
            if (token ~ /\.(sh|ps1|psm1|md|json|yml|yaml|toml|plist|service|timer|py|txt)(#[A-Za-z0-9_-]+)?$/) ok = 1
            if (token ~ /^\$?[A-Z][A-Z0-9_]{2,}$/) ok = 1
            if (token ~ /^(gh|git|bash|pwsh|powershell|curl|claude|python|python3|pip|npm)([[:space:]].*)?$/) ok = 1
            return ok
        }
    ' "$1" | LC_ALL=C sort -u
}

en_tokens="$(extract_contract_tokens "$EN")"
ko_tokens="$(extract_contract_tokens "$KO")"

if [[ "$en_tokens" != "$ko_tokens" ]]; then
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    printf '%s\n' "$en_tokens" > "$tmp_dir/en.tokens"
    printf '%s\n' "$ko_tokens" > "$tmp_dir/ko.tokens"
    echo "diff-readme: contract token drift between $EN and $KO."
    echo "Tokens represent inline-code commands, paths, config files, and env vars."
    diff -u "$tmp_dir/en.tokens" "$tmp_dir/ko.tokens" || true
    exit 1
fi

echo "diff-readme: OK ($EN and $KO have matching heading counts and contract tokens)"
exit 0
