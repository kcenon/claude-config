#!/bin/bash
# markdown-anchor-validator.sh
# Validates markdown anchor references before git commit
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Performance: Uses single-pass awk extraction + bulk sed/tr pipeline
# to minimize subprocess spawns (~15 total vs ~4800 in naive approach)
#
# Requires bash 4+ (associative arrays). macOS ships bash 3.2; on that
# platform the script auto-re-execs via Homebrew bash if available, or
# falls back to "allow" with a skip notice so the hook never blocks on
# an environment issue.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
        if [ -x "$candidate" ] && "$candidate" -c 'test "${BASH_VERSINFO[0]}" -ge 4' 2>/dev/null; then
            exec "$candidate" "$0" "$@"
        fi
    done
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"markdown-anchor-validator skipped: bash 4+ required, found %s. Install via: brew install bash"}}' "${BASH_VERSION}"
    exit 0
fi

set -euo pipefail
# C.UTF-8 is universally available and enables Unicode in sed/tr character classes (e.g., [:alnum:] matching Korean)
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=C.utf8 2>/dev/null || true

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# jq is required to parse the hook input JSON. If it's missing, fail open
# with a warning rather than aborting silently (which would leave Claude
# Code without a decision response and effectively break the hook).
if ! command -v jq >/dev/null 2>&1; then
    echo "markdown-anchor-validator: jq not found on PATH; skipping validation" >&2
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Tolerate jq pipeline failures (malformed input, pipefail): treat as empty CMD
# and fall back to the env-var path below.
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
# Fallback to environment variable for backward compatibility
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Only check git commit commands
if ! echo "$CMD" | grep -qE 'git\s+commit'; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Collect markdown files: docs/*.md (core) + docs/reference/*.md
# Excludes docs/ui/, docs/placeholders/ to avoid anchor registry pollution
MD_FILES=()
if [ -d "docs" ]; then
    while IFS= read -r f; do [[ -n "$f" ]] && MD_FILES+=("$f"); done < <(find docs -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
    [ -d "docs/reference" ] && while IFS= read -r f; do [[ -n "$f" ]] && MD_FILES+=("$f"); done < <(find docs/reference -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
else
    while IFS= read -r f; do [[ -n "$f" ]] && MD_FILES+=("$f"); done < <(find . -maxdepth 2 -name '*.md' -type f 2>/dev/null | sort)
fi

if [ ${#MD_FILES[@]} -eq 0 ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# === Single-pass AWK extraction ===
# Extract headings and references from all files in one awk invocation.
# Output format (TSV):
#   H<TAB>file<TAB>heading_text           (heading line)
#   I<TAB>file<TAB>line_num<TAB>anchor    (intra-file reference)
#   X<TAB>file<TAB>line_num<TAB>ref_file<TAB>anchor  (inter-file reference)
AWK_OUTPUT=$(awk '
FNR == 1 { f = FILENAME; c = 0 }
/^[[:space:]]*(```|~~~)/ { c = !c; next }
c { next }
# Headings: CommonMark/GitHub accept 1-6 hashes only; 7+ is regular text.
/^#{1,6}[[:space:]]/ {
    h = $0
    sub(/^#{1,6}[[:space:]]+/, "", h)
    sub(/[[:space:]#]*$/, "", h)
    if (h != "") printf "H\t%s\t%s\n", f, h
}
{
    # Strip inline-code spans so that example syntax inside backticks
    # (e.g., `[a](#missing)`) does not count as a live reference.
    line = $0
    gsub(/`[^`]*`/, "", line)

    # Intra-file refs: ](#anchor)
    work = line
    while (match(work, /\]\(#[^)]+\)/)) {
        ref = substr(work, RSTART + 3, RLENGTH - 4)
        printf "I\t%s\t%d\t%s\n", f, FNR, ref
        work = substr(work, RSTART + RLENGTH)
    }
    # Inter-file refs: ](path.md#anchor) — exclude URLs (no colon in path)
    work = line
    while (match(work, /\]\([^:)#]*\.md#[^)]+\)/)) {
        ref = substr(work, RSTART + 2, RLENGTH - 3)
        idx = index(ref, "#")
        ref_file = substr(ref, 1, idx - 1)
        anchor = substr(ref, idx + 1)
        sub(/^\.\//, "", ref_file)
        printf "X\t%s\t%d\t%s\t%s\n", f, FNR, ref_file, anchor
        work = substr(work, RSTART + RLENGTH)
    }
}
' "${MD_FILES[@]}" 2>/dev/null) || true

# === Build anchor registry (bulk pipeline) ===
# Extract heading lines, transform ALL heading texts to anchors in a single pipeline
H_LINES=$(echo "$AWK_OUTPUT" | grep '^H' || true)

declare -A ANCHORS
declare -A ANCHOR_COUNTS

if [ -n "$H_LINES" ]; then
    # Temp files for parallel field extraction + bulk anchor generation
    TMP_FILES=$(mktemp)
    TMP_ANCHORS=$(mktemp)
    trap 'rm -f "$TMP_FILES" "$TMP_ANCHORS"' EXIT

    # Extract file paths (field 2)
    echo "$H_LINES" | cut -f2 > "$TMP_FILES"

    # Extract heading texts (field 3+) → bulk transform to GitHub-style anchors
    # Pipeline: strip formatting markers → lowercase → remove non-alnum/space/hyphen/underscore → spaces→hyphens → trim
    # NOTE: GitHub does NOT collapse consecutive hyphens (e.g., "A / B" → "a--b")
    echo "$H_LINES" | cut -f3- | \
        sed -e 's/\]([^)]*)//g' -e 's/\[//g' -e 's/\*//g' -e 's/`//g' -e 's/<[^>]*>//g' | \
        tr '[:upper:]' '[:lower:]' | \
        sed -e 's/[^[:alnum:]_ -]//g' -e 's/ /-/g' -e 's/^-//;s/-$//' \
        > "$TMP_ANCHORS"

    # Merge file paths with generated anchors and build registry
    while IFS=$'\t' read -r file anchor; do
        [[ -z "$anchor" ]] && continue
        count_key="${file}::${anchor}"
        if [[ -n "${ANCHOR_COUNTS[$count_key]+x}" ]]; then
            ANCHOR_COUNTS["$count_key"]=$(( ANCHOR_COUNTS["$count_key"] + 1 ))
            ANCHORS["${file}::${anchor}-${ANCHOR_COUNTS[$count_key]}"]=1
        else
            ANCHOR_COUNTS["$count_key"]=0
            ANCHORS["${file}::${anchor}"]=1
        fi
    done < <(paste "$TMP_FILES" "$TMP_ANCHORS")
fi

# === Check references ===
ERRORS=()

# Check intra-file references (I lines)
while IFS=$'\t' read -r _type file line_num anchor; do
    [[ -z "$anchor" ]] && continue
    if [[ -z "${ANCHORS[${file}::${anchor}]+x}" ]]; then
        ERRORS+=("${file##*/}:${line_num}: #${anchor}")
    fi
done < <(echo "$AWK_OUTPUT" | grep '^I' || true)

# Check inter-file references (X lines)
while IFS=$'\t' read -r _type file line_num ref_file anchor; do
    [[ -z "$anchor" ]] && continue
    # Resolve relative to referencing file's directory
    dir="${file%/*}"
    [[ "$dir" == "$file" ]] && dir="."
    target="${dir}/${ref_file}"
    # Normalize ./ and ../ segments
    target="${target//\/.\//\/}"
    while [[ "$target" == *"/.."* ]]; do
        target="$(echo "$target" | sed 's|[^/]*/\.\./||')"
    done
    if [[ -z "${ANCHORS[${target}::${anchor}]+x}" ]]; then
        ERRORS+=("${file##*/}:${line_num}: ${ref_file}#${anchor}")
    fi
done < <(echo "$AWK_OUTPUT" | grep '^X' || true)

# === Output ===
if [ ${#ERRORS[@]} -eq 0 ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Build the error message as real text (actual newlines, not literal "\n"),
# then let jq produce a correctly-escaped JSON string. This handles `\`, `"`,
# control characters, and any non-ASCII content reliably.
ERROR_MSG="Broken markdown anchor(s) found:"
for err in "${ERRORS[@]}"; do
    ERROR_MSG+=$'\n  - '"${err}"
done
ERROR_MSG+=$'\n\nFix the anchors or update the references before committing.'

REASON_JSON=$(printf '%s' "$ERROR_MSG" | jq -Rs .)

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ${REASON_JSON}
  }
}
EOF
exit 0
