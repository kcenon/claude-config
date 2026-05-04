#!/bin/bash
# validate-traceability.sh
# Shared traceability cascade validation library.
# Single source of truth for traceability rules.
#
# Sourced by:
#   - hooks/pre-push                       (git hook — terminal-side gate)
#   - global/hooks/traceability-guard.sh   (PreToolUse — Claude-side feedback loop)
#
# Opt-in: when docs/.index/graph.yaml is absent, validate_traceability_range
# returns 0 silently so non-regulated repos are unaffected.
#
# Usage:
#   . /path/to/validate-traceability.sh
#   if ! validate_traceability_range "$BASE_REF" "$HEAD_REF" "$REPO_ROOT"; then
#       echo "cascade missing" >&2
#   fi
#
# The function prints a deterministic, line-per-finding report to stderr on
# failure and exits with the broken-edge count via the function's return code.

# Doc-id pattern recognised in graph.yaml. Mirrors the identifier conventions
# documented in global/skills/_internal/traceability/reference/matrix-schema.md
# (SRS-CAT-NNN, SI-CODE, IF-NNN, TC-CAT-NNN, H-NN, HUS-NN, SCR-NNN, FLW-NNN).
readonly VT_DOC_ID_REGEX='[A-Z]+(-[A-Z0-9]+)+'

# extract_doc_ids_from_path <repo_root> <relative_path>
# Print one doc_id per line found in the file's content. Doc-ids are
# discovered from front-matter doc_id fields and from in-body identifiers.
# Empty output when the file is binary, missing, or has no recognisable id.
extract_doc_ids_from_path() {
    local repo_root="$1"
    local rel_path="$2"
    local abs_path="$repo_root/$rel_path"

    if [ ! -f "$abs_path" ]; then
        return 0
    fi

    # 1) Front-matter doc_id field (lines like 'doc_id: SRS-CALC-001')
    grep -hE "^doc_id:[[:space:]]*[A-Za-z0-9_.-]+" "$abs_path" 2>/dev/null \
        | sed -E 's/^doc_id:[[:space:]]*//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//' \
        | grep -E "^${VT_DOC_ID_REGEX}$" 2>/dev/null

    # 2) In-body identifiers in headings and explicit anchors. We deliberately
    # match heading lines first to avoid noisy hits in prose; auditors keep
    # ids in '## SRS-CAT-NNN: Title' or table rows.
    grep -hoE "${VT_DOC_ID_REGEX}-[0-9]+" "$abs_path" 2>/dev/null
    grep -hoE "${VT_DOC_ID_REGEX}" "$abs_path" 2>/dev/null \
        | grep -E "^[A-Z]+-[A-Z0-9]+(-[0-9]+)?$"
}

# graph_cascade_targets <graph_yaml_path> <doc_id>
# Print one cascade target per line. Reads the simple cascade map
# documented in global/skills/_internal/doc-index. Format expected:
#
#   graph:
#     SRS-CALC-001:
#       cascade:
#         - TC-CALC-001
#         - SI-CALC
#     SI-CALC:
#       cascade:
#         - src/calc/engine.cpp
#
# A target may be either another doc_id or a repo-relative path.
graph_cascade_targets() {
    local graph_yaml="$1"
    local doc_id="$2"

    if [ ! -f "$graph_yaml" ] || [ -z "$doc_id" ]; then
        return 0
    fi

    # NOTE on regex portability: POSIX awk recognises neither the
    # [[:space:]] character class nor the {n} repetition quantifier, so
    # the patterns below use literal-space sequences. The schema in
    # global/skills/_internal/traceability/reference/matrix-schema.md fixes
    # YAML indentation at two spaces, so the literal forms are exact.
    awk -v id="$doc_id" '
        BEGIN { in_node = 0; in_cascade = 0 }
        # Top-level node line (two-space indent under graph:): "  SRS-CALC-001:"
        /^  [A-Za-z0-9_.\/-]+:[ ]*$/ {
            current = $1
            sub(/:$/, "", current)
            if (current == id) { in_node = 1 } else { in_node = 0; in_cascade = 0 }
            next
        }
        # cascade: marker inside a node
        in_node && /^    cascade:[ ]*$/ {
            in_cascade = 1
            next
        }
        # other field while in node — leaves cascade list
        in_node && /^    [A-Za-z0-9_]+:/ {
            in_cascade = 0
            next
        }
        # cascade list item: "      - SOMETHING"
        in_node && in_cascade && /^      - / {
            line = $0
            sub(/^      - +/, "", line)
            sub(/ +$/, "", line)
            gsub(/["'"'"']/, "", line)
            if (length(line) > 0) print line
        }
    ' "$graph_yaml"
}

# resolve_target_paths <repo_root> <target>
# Given a cascade target — either a path or another doc_id — print all
# repository-relative paths that satisfy it. Paths pass through verbatim;
# doc-ids are resolved via grep over the index.
resolve_target_paths() {
    local repo_root="$1"
    local target="$2"

    # Repo-relative path (contains a slash or extension)
    if echo "$target" | grep -qE '/|\.[a-zA-Z0-9]+$'; then
        printf '%s\n' "$target"
        return 0
    fi

    # Doc-id — find files declaring it via doc_id front-matter
    if [ -d "$repo_root/docs" ]; then
        grep -lrE "^doc_id:[[:space:]]*${target}[[:space:]]*$" "$repo_root/docs" 2>/dev/null \
            | sed -E "s|^${repo_root}/||"
    fi
}

# validate_traceability_range <base_ref> <head_ref> <repo_root>
# Returns 0 when no cascade targets are missing OR when the repo has not
# adopted the regulated track (no docs/.index/graph.yaml).
# Returns the number of broken edges otherwise (capped at 125 so it fits
# in a shell exit status), with one finding per line on stderr.
validate_traceability_range() {
    local base_ref="$1"
    local head_ref="$2"
    local repo_root="${3:-$(pwd)}"

    local graph_yaml="$repo_root/docs/.index/graph.yaml"
    if [ ! -f "$graph_yaml" ]; then
        # Opt-in gate. Repos without the regulated track are unaffected.
        return 0
    fi

    if [ -z "$base_ref" ] || [ -z "$head_ref" ]; then
        echo "validate-traceability: missing base/head ref — refusing to validate" >&2
        return 1
    fi

    # Touched files in the diff range. Use --diff-filter to include
    # additions, modifications, renames, and copies; deletions cannot
    # carry a cascade obligation.
    local touched
    touched=$(cd "$repo_root" && git diff --name-only --diff-filter=ACMR \
        "$base_ref" "$head_ref" 2>/dev/null) || {
        echo "validate-traceability: 'git diff' failed for ${base_ref}..${head_ref}" >&2
        return 1
    }

    if [ -z "$touched" ]; then
        return 0
    fi

    # Build the set of touched doc_ids and the set of touched paths.
    local touched_ids touched_paths
    touched_paths=$(printf '%s\n' "$touched" | sort -u)
    touched_ids=$(printf '%s\n' "$touched_paths" | while IFS= read -r p; do
        [ -n "$p" ] && extract_doc_ids_from_path "$repo_root" "$p"
    done | sort -u)

    if [ -z "$touched_ids" ]; then
        # Nothing in the diff carries a cascade obligation.
        return 0
    fi

    # For each touched doc_id, every cascade target must also appear in the
    # diff — either as the path itself, or as a doc_id whose declaring file
    # is in the diff.
    local broken=0
    while IFS= read -r src_id; do
        [ -z "$src_id" ] && continue
        local targets
        targets=$(graph_cascade_targets "$graph_yaml" "$src_id")
        [ -z "$targets" ] && continue

        while IFS= read -r tgt; do
            [ -z "$tgt" ] && continue

            # Resolve the target into one or more candidate paths.
            local resolved
            resolved=$(resolve_target_paths "$repo_root" "$tgt")

            # Cascade satisfied if (a) the bare doc-id is present in
            # touched_ids, OR (b) any resolved path is in touched_paths.
            local satisfied=0

            # Direct doc-id match.
            if printf '%s\n' "$touched_ids" | grep -qxF "$tgt"; then
                satisfied=1
            fi

            # Path-based satisfaction.
            if [ "$satisfied" -eq 0 ] && [ -n "$resolved" ]; then
                while IFS= read -r candidate; do
                    [ -z "$candidate" ] && continue
                    if printf '%s\n' "$touched_paths" | grep -qxF "$candidate"; then
                        satisfied=1
                        break
                    fi
                done <<EOF
$resolved
EOF
            fi

            if [ "$satisfied" -eq 0 ]; then
                broken=$((broken + 1))
                echo "BROKEN  ${src_id} -> ${tgt} (cascade target not in diff)" >&2
            fi
        done <<EOF
$targets
EOF
    done <<EOF
$touched_ids
EOF

    if [ "$broken" -gt 0 ]; then
        # Cap at 125 so shells that interpret a non-zero exit as a status
        # do not wrap. The exact number is reproduced in the report above.
        if [ "$broken" -gt 125 ]; then
            return 125
        fi
        return "$broken"
    fi

    return 0
}
