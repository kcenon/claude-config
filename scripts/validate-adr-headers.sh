#!/bin/bash
# validate-adr-headers.sh — enforce ADR frontmatter on docs/design/*.md (#624).
#
# Schema (YAML at top of file):
#   ---
#   status: Active           # Active | Superseded | Draft
#   audience: maintainer     # maintainer | contributor | user
#   last_reviewed: YYYY-MM-DD
#   supersedes: []
#   superseded_by: null
#   ---
#
# The check is intentionally lightweight — it verifies presence and basic
# shape of each required field, not deep YAML correctness. Deeper schema
# validation can layer on later (e.g. via the doc-index skill once the
# extractor knows about ADR fields).
#
# Exit codes:
#   0  every targeted file passes
#   1  one or more files missing or malformed
#   2  no files matched the glob (configuration error)
#
# Usage:
#   bash scripts/validate-adr-headers.sh                # docs/design/*.md
#   bash scripts/validate-adr-headers.sh path/...       # explicit list

set -uo pipefail

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    shopt -s nullglob
    files=(docs/design/*.md docs/tier2-benchmark-results.md docs/batch-drift-regression.md)
    shopt -u nullglob
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "validate-adr-headers: no files matched" >&2
    exit 2
fi

required_keys=(status audience last_reviewed supersedes superseded_by)
status_values_re='^(Active|Superseded|Draft)$'
audience_values_re='^(maintainer|contributor|user)$'
date_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

failures=0
total=0

for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
        printf 'MISSING %s\n' "$f"
        failures=$((failures + 1))
        continue
    fi
    total=$((total + 1))
    file_failed=0

    # Frontmatter must start at line 1 with literal '---' and end at the
    # next '---'. Capture only those lines.
    if ! head -1 "$f" | grep -qx '\-\-\-'; then
        printf 'NO-FRONTMATTER %s\n' "$f"
        failures=$((failures + 1))
        continue
    fi
    block=$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag' "$f")
    if [[ -z "$block" ]]; then
        printf 'EMPTY-FRONTMATTER %s\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    # Required-key presence
    for key in "${required_keys[@]}"; do
        if ! grep -qE "^${key}:" <<<"$block"; then
            printf 'MISSING-KEY %s: %s\n' "$f" "$key"
            file_failed=1
        fi
    done

    # Value sanity for the three free-form-ish keys (status, audience, date)
    status_v=$(grep -E '^status:' <<<"$block" | head -1 | sed -E 's/^status:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+$//')
    audience_v=$(grep -E '^audience:' <<<"$block" | head -1 | sed -E 's/^audience:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+$//')
    date_v=$(grep -E '^last_reviewed:' <<<"$block" | head -1 | sed -E 's/^last_reviewed:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+$//')

    if [[ -n "$status_v" ]] && ! [[ "$status_v" =~ $status_values_re ]]; then
        printf 'BAD-STATUS %s: "%s" (expected Active|Superseded|Draft)\n' "$f" "$status_v"
        file_failed=1
    fi
    if [[ -n "$audience_v" ]] && ! [[ "$audience_v" =~ $audience_values_re ]]; then
        printf 'BAD-AUDIENCE %s: "%s" (expected maintainer|contributor|user)\n' "$f" "$audience_v"
        file_failed=1
    fi
    if [[ -n "$date_v" ]] && ! [[ "$date_v" =~ $date_re ]]; then
        printf 'BAD-DATE %s: "%s" (expected YYYY-MM-DD)\n' "$f" "$date_v"
        file_failed=1
    fi

    if (( file_failed )); then
        failures=$((failures + 1))
    else
        printf 'OK %s\n' "$f"
    fi
done

echo
if (( failures == 0 )); then
    echo "validate-adr-headers: ${total} files OK"
    exit 0
else
    echo "validate-adr-headers: ${failures} of ${total} files failed"
    exit 1
fi
