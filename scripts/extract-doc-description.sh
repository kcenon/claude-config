#!/bin/bash
# extract-doc-description.sh — derive the manifest.yaml description for a
# markdown document (#625).
#
# The /doc-index skill stores a one-line description per file in
# docs/.index/manifest.yaml. The pre-#625 heuristic took the first
# non-empty line, which produced literal HTML tags ('<p align="center">')
# for documents that begin with a centered badge block — exactly the case
# in README.ko.md, the Korean entry point.
#
# This helper implements the corrected extraction:
#   1. Skip a YAML frontmatter block at the top (between two '---' lines).
#   2. Skip ATX headings ('# ', '## ', etc).
#   3. Skip lines that are pure HTML structural tags (open/close, opening
#      tags whose content runs into other lines) — recognized by the line
#      not containing any non-whitespace, non-tag content.
#   4. For lines that mix HTML and prose (e.g. '<strong>여러 시스템…</strong>'),
#      strip the tags and use the remaining text.
#   5. Return the first non-empty result, trimmed and truncated to 200
#      characters.
#
# Output: the extracted description on stdout. Empty stdout + non-zero
# exit if no description could be derived.
#
# Exit codes:
#   0  description emitted on stdout
#   1  no description found
#   2  usage error (missing arg / unreadable file)
#
# Usage:
#   bash scripts/extract-doc-description.sh path/to/file.md

set -uo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: extract-doc-description.sh <markdown-file>" >&2
    exit 2
fi

f="$1"
if [[ ! -r "$f" ]]; then
    echo "extract-doc-description: cannot read $f" >&2
    exit 2
fi

# strip_html: remove tags from a single line and collapse whitespace.
strip_html() {
    # 1. Remove '<...>' tags greedily but non-spanningly. Use sed; the
    #    pattern intentionally allows attributes and self-closing forms.
    # 2. Collapse runs of whitespace (incl. NBSP) to single ASCII space.
    # 3. Trim leading/trailing whitespace.
    sed -E 's/<[^>]+>//g' \
        | tr -s '[:space:]' ' ' \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Single-pass scan: for each non-frontmatter, non-heading, non-blank line,
# strip HTML tags. Return the first line that has prose content after the
# stripping. Truncate to 200 chars.
in_fm=0
fm_seen=0
while IFS= read -r line; do
    if [[ "$fm_seen" == 0 && "$line" == "---" ]]; then
        in_fm=1; fm_seen=1; continue
    fi
    if [[ "$in_fm" == 1 ]]; then
        if [[ "$line" == "---" ]]; then in_fm=0; fi
        continue
    fi
    # Skip ATX headings (any line starting with one or more '#' then space).
    case "$line" in
        '#'*' '*) continue ;;
        '#'*) continue ;;
    esac
    # Skip blank lines.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    cleaned=$(printf '%s' "$line" | strip_html)
    if [[ -n "$cleaned" ]]; then
        printf '%s\n' "${cleaned:0:200}"
        exit 0
    fi
done < "$f"

exit 1
