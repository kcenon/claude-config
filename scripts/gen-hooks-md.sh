#!/bin/bash
# gen-hooks-md.sh
# Generates the auto-managed section of HOOKS.md from the top-of-file
# comment blocks of every script under global/hooks/*.sh (lib/ excluded).
#
# Usage:
#   bash scripts/gen-hooks-md.sh           # rewrite HOOKS.md in place
#   bash scripts/gen-hooks-md.sh --check   # exit 1 if HOOKS.md would change
#   bash scripts/gen-hooks-md.sh --stdout  # print generated file to stdout
#
# Idempotency: running the script twice in a row produces no diff. The
# auto-generated region is bracketed by the markers below; everything
# outside the markers is preserved verbatim.
#
# The generator extracts the following fields per hook:
#   - filename (e.g., attribution-guard.sh)
#   - one-line summary (first non-banner comment line after the filename
#     comment, trimmed)
#   - Hook Type
#   - Trigger / Matcher (parsed from Hook Type or a separate Trigger: line)
#   - Exit codes
#   - Response format
#   - Fail policy (when present)
#
# This keeps HOOKS.md and the filesystem in lock-step. Any drift between
# the two is flagged by the validate-hooks-doc.yml CI workflow which
# runs this script in --check mode.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/global/hooks"
HOOKS_MD="${REPO_ROOT}/HOOKS.md"
BEGIN_MARKER='<!-- BEGIN AUTO-GENERATED HOOKS -->'
END_MARKER='<!-- END AUTO-GENERATED HOOKS -->'

MODE="write"
case "${1:-}" in
    --check)  MODE="check" ;;
    --stdout) MODE="stdout" ;;
    "")       MODE="write" ;;
    *)
        echo "usage: $0 [--check|--stdout]" >&2
        exit 2
        ;;
esac

# Build a slug from a filename for stable section anchors.
slugify() {
    # e.g., attribution-guard.sh -> attribution-guard
    local name="$1"
    name="${name%.sh}"
    printf '%s\n' "$name"
}

# Extract the leading "# ..." comment block from a hook script (skipping
# the shebang). Stops at the first non-comment, non-empty line.
extract_header() {
    awk '
        NR == 1 && /^#!/ { next }
        /^#/ { sub(/^# ?/, "", $0); print; next }
        /^[[:space:]]*$/ { print ""; next }
        { exit }
    ' "$1"
}

# Render one hook block from the header text + filename.
render_hook() {
    local file="$1"
    local base header summary hook_type trigger exit_codes response fail_policy
    base="$(basename "$file")"

    header="$(extract_header "$file")"

    # The summary is the prose between the title line(s) (filename or
    # "X Hook" banner, plus any "===" underlines) and the first
    # structured field (Hook Type:, Exit codes:, etc.) or the first
    # blank line — whichever comes first. Multi-line prose is collapsed
    # into a single line for the table cell.
    summary="$(printf '%s\n' "$header" \
        | awk '
            BEGIN { skipped_title = 0 }
            !skipped_title {
                if ($0 ~ /\.sh$/ || $0 ~ /[Hh]ook$/ || $0 ~ /^=+$/) { next }
                skipped_title = 1
            }
            /^[A-Z][A-Za-z ]+:/ { exit }       # structured field — stop
            /^=+$/              { next }       # banner underline
            /^$/                { if (out) exit; else next }
            { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; out = 1 }
          ' \
        | tr '\n' ' ' \
        | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]//; s/[[:space:]]$//')"
    [[ -z "$summary" ]] && summary="(no summary)"

    hook_type="$(printf '%s\n' "$header" \
        | grep -m1 '^Hook Type:' \
        | sed 's/^Hook Type:[[:space:]]*//')"
    [[ -z "$hook_type" ]] && hook_type="(unspecified)"

    trigger="$(printf '%s\n' "$header" \
        | grep -m1 -E '^(Trigger|Matcher):' \
        | sed -E 's/^(Trigger|Matcher):[[:space:]]*//')"
    if [[ -z "$trigger" ]]; then
        # Fall back to anything in parentheses on the Hook Type line.
        trigger="$(printf '%s\n' "$hook_type" \
            | sed -nE 's/.*\(([^)]+)\).*/\1/p')"
    fi
    [[ -z "$trigger" ]] && trigger="—"

    exit_codes="$(printf '%s\n' "$header" \
        | grep -m1 '^Exit codes:' \
        | sed 's/^Exit codes:[[:space:]]*//')"
    [[ -z "$exit_codes" ]] && exit_codes="—"

    response="$(printf '%s\n' "$header" \
        | grep -m1 '^Response format:' \
        | sed 's/^Response format:[[:space:]]*//')"
    [[ -z "$response" ]] && response="—"

    fail_policy="$(printf '%s\n' "$header" \
        | grep -m1 -iE '^Fail policy:' \
        | sed -E 's/^[Ff]ail [Pp]olicy:[[:space:]]*//')"

    local ps1="${file%.sh}.ps1"
    local ps1_status="absent"
    if [[ -f "$ps1" ]]; then
        ps1_status="present (\`$(basename "$ps1")\`)"
    fi

    local slug
    slug="$(slugify "$base")"

    {
        printf '\n### %s\n\n' "$base"
        printf '_Anchor:_ `#%s`\n\n' "$slug"
        printf '%s\n\n' "$summary"
        printf '| Field | Value |\n|---|---|\n'
        printf '| Hook Type | %s |\n' "$hook_type"
        printf '| Trigger / Matcher | %s |\n' "$trigger"
        printf '| Exit codes | %s |\n' "$exit_codes"
        printf '| Response format | %s |\n' "$response"
        if [[ -n "$fail_policy" ]]; then
            printf '| Fail policy | %s |\n' "$fail_policy"
        fi
        printf '| PowerShell counterpart | %s |\n' "$ps1_status"
        printf '| Source | `global/hooks/%s` |\n' "$base"
    }
}

# Build the auto-generated section.
build_generated_section() {
    local total ps1_total
    total=0
    ps1_total=0

    {
        printf '%s\n' "$BEGIN_MARKER"
        printf '\n<!-- This section is regenerated by scripts/gen-hooks-md.sh.\n'
        printf '     Do not edit by hand — your changes will be overwritten.\n'
        printf '     To update: edit the leading comment block of the\n'
        printf '     relevant `global/hooks/*.sh` script and re-run the\n'
        printf '     generator. -->\n\n'

        printf '## Auto-Generated Hook Catalog\n\n'
        printf 'The catalog below is built from the leading comment block\n'
        printf 'of each hook script under `global/hooks/`. It is the\n'
        printf 'authoritative listing — the hand-written sections elsewhere\n'
        printf 'in this document provide narrative context but defer to\n'
        printf 'this catalog for the canonical hook inventory.\n\n'

        # Index table.
        printf '### Index\n\n'
        printf '| Hook | Hook Type | PowerShell |\n|---|---|---|\n'
        local f base header hook_type ps1
        while IFS= read -r f; do
            base="$(basename "$f")"
            header="$(extract_header "$f")"
            hook_type="$(printf '%s\n' "$header" \
                | grep -m1 '^Hook Type:' \
                | sed 's/^Hook Type:[[:space:]]*//')"
            [[ -z "$hook_type" ]] && hook_type="(unspecified)"
            ps1="${f%.sh}.ps1"
            local pcell="no"
            if [[ -f "$ps1" ]]; then
                pcell="yes"
                ps1_total=$((ps1_total + 1))
            fi
            total=$((total + 1))
            printf '| [`%s`](#%s) | %s | %s |\n' \
                "$base" "$(slugify "$base")" "$hook_type" "$pcell"
        done < <(find "$HOOKS_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

        printf '\n_Total: %d bash hooks, %d with PowerShell counterparts._\n' \
            "$total" "$ps1_total"

        printf '\n### Hook Details\n'

        while IFS= read -r f; do
            render_hook "$f"
        done < <(find "$HOOKS_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

        printf '\n%s\n' "$END_MARKER"
    }
}

# Splice the generated section into HOOKS.md, preserving the surrounding
# hand-written content. If the markers are absent, append the section to
# the end of the file.
splice_into_hooks_md() {
    local generated_file="$1"

    if grep -qF "$BEGIN_MARKER" "$HOOKS_MD" \
        && grep -qF "$END_MARKER" "$HOOKS_MD"; then
        # Replace the bracketed region. Pass the generated content via
        # a file (gen) to sidestep awk's `-v` newline restriction.
        awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v genfile="$generated_file" '
            BEGIN { in_skip = 0 }
            $0 == begin {
                while ((getline line < genfile) > 0) print line
                close(genfile)
                in_skip = 1
                next
            }
            $0 == end   { in_skip = 0; next }
            !in_skip    { print }
        ' "$HOOKS_MD"
    else
        cat "$HOOKS_MD"
        printf '\n'
        cat "$generated_file"
    fi
}

_tmpdir="${TMPDIR:-/tmp}"
tmp_gen="$(mktemp "${_tmpdir%/}/gen-hooks-XXXXXX")"
tmp_doc="$(mktemp "${_tmpdir%/}/gen-hooks-doc-XXXXXX")"
trap 'rm -f "$tmp_gen" "$tmp_doc"' EXIT

build_generated_section > "$tmp_gen"

case "$MODE" in
    stdout)
        # Emit only the generated section.
        cat "$tmp_gen"
        ;;
    check|write)
        splice_into_hooks_md "$tmp_gen" > "$tmp_doc"
        if [[ "$MODE" == "check" ]]; then
            if ! diff -u "$HOOKS_MD" "$tmp_doc" >/dev/null; then
                echo "HOOKS.md is out of sync with global/hooks/*.sh." >&2
                echo "Run: bash scripts/gen-hooks-md.sh" >&2
                diff -u "$HOOKS_MD" "$tmp_doc" >&2 || true
                exit 1
            fi
        else
            cp "$tmp_doc" "$HOOKS_MD"
        fi
        ;;
esac
