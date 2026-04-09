#!/bin/bash
# markdown-anchor-validator.sh
# Validates markdown anchor references before git commit
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Performance: Uses single-pass awk extraction + bulk sed/tr pipeline
# to minimize subprocess spawns (~15 total vs ~4800 in naive approach)

set -euo pipefail
# C.UTF-8 is universally available and enables Unicode in sed/tr character classes (e.g., [:alnum:] matching Korean)
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=C.utf8 2>/dev/null || true

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
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
/^#+[[:space:]]/ {
    h = $0
    sub(/^#+[[:space:]]+/, "", h)
    sub(/[[:space:]#]*$/, "", h)
    if (h != "") printf "H\t%s\t%s\n", f, h
}
{
    line = $0
    # Intra-file refs: ](#anchor)
    while (match(line, /\]\(#[^)]+\)/)) {
        ref = substr(line, RSTART + 3, RLENGTH - 4)
        printf "I\t%s\t%d\t%s\n", f, FNR, ref
        line = substr(line, RSTART + RLENGTH)
    }
    # Inter-file refs: ](path.md#anchor) — exclude URLs (no colon in path)
    line = $0
    while (match(line, /\]\([^:)#]*\.md#[^)]+\)/)) {
        ref = substr(line, RSTART + 2, RLENGTH - 3)
        idx = index(ref, "#")
        ref_file = substr(ref, 1, idx - 1)
        anchor = substr(ref, idx + 1)
        sub(/^\.\//, "", ref_file)
        printf "X\t%s\t%d\t%s\t%s\n", f, FNR, ref_file, anchor
        line = substr(line, RSTART + RLENGTH)
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

# Build error message for JSON output
ERROR_MSG="Broken markdown anchor(s) found:"
for err in "${ERRORS[@]}"; do
    ERROR_MSG="${ERROR_MSG}\n  - ${err}"
done
ERROR_MSG="${ERROR_MSG}\n\nFix the anchors or update the references before committing."

# Escape double quotes for JSON safety
ERROR_MSG="${ERROR_MSG//\"/\\\"}"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "${ERROR_MSG}"
  }
}
EOF
exit 0
