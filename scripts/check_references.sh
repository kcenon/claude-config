#!/usr/bin/env bash
# Verify mapped reference mirrors match their canonical source.
# Exits 2 if any mirror drifts from canonical; 0 otherwise.
#
# Usage: scripts/check_references.sh [repo-root] [reference-map.yml]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
MAP_FILE="${2:-$ROOT_DIR/reference-map.yml}"

if [ ! -f "$MAP_FILE" ]; then
    echo "ERROR: reference map missing: $MAP_FILE" >&2
    exit 1
fi

normalize_newlines() {
    local file="$1"
    tr -d '\r' < "$file"
}

strip_frontmatter() {
    local file="$1"
    normalize_newlines "$file" | \
    awk '
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---" { in_fm = 0; skip_blank = 1; next }
        in_fm { next }
        skip_blank && $0 == "" { skip_blank = 0; next }
        { skip_blank = 0; print }
    '
}

emit_normalized() {
    local file="$1" mode="$2" side="$3"
    case "$mode:$side" in
        strip-source-frontmatter:source) strip_frontmatter "$file" ;;
        exact:source|exact:target|strip-source-frontmatter:target) normalize_newlines "$file" ;;
        *)
            echo "ERROR: unsupported reference comparison mode: $mode" >&2
            return 1
            ;;
    esac
}

read_map_entries() {
    awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            gsub(/^"|"$/, "", s)
            return s
        }
        function emit() {
            if (source != "" || target != "" || mode != "") {
                if (source == "" || target == "" || mode == "") {
                    print "ERROR: malformed reference-map.yml entry" > "/dev/stderr"
                    exit 1
                }
                print source "|" target "|" mode
            }
            source = ""; target = ""; mode = ""
        }
        /^[[:space:]]*-[[:space:]]+source:[[:space:]]*/ {
            emit()
            source = $0
            sub(/^[[:space:]]*-[[:space:]]+source:[[:space:]]*/, "", source)
            source = trim(source)
            next
        }
        /^[[:space:]]+target:[[:space:]]*/ {
            target = $0
            sub(/^[[:space:]]+target:[[:space:]]*/, "", target)
            target = trim(target)
            next
        }
        /^[[:space:]]+mode:[[:space:]]*/ {
            mode = $0
            sub(/^[[:space:]]+mode:[[:space:]]*/, "", mode)
            mode = trim(mode)
            next
        }
        END { emit() }
    ' "$MAP_FILE"
}

tracked_project_reference_symlinks() {
    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi
    if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    git -C "$ROOT_DIR" ls-files -s -- project/.claude/skills 2>/dev/null | \
    awk '
        $1 == "120000" {
            path = $0
            sub(/^[^\t]*\t/, "", path)
            if (path ~ /^project\/\.claude\/skills\/.*\/reference\//) {
                print path
            }
        }
    '
}

tracked_symlinks="$(tracked_project_reference_symlinks)"
if [ -n "$tracked_symlinks" ]; then
    while IFS= read -r path; do
        echo "FAIL: tracked symlink mode 120000: $path" >&2
    done <<< "$tracked_symlinks"
    echo "" >&2
    echo "check_references: project skill reference files must be tracked as regular files." >&2
    exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

drift=0
count=0
while IFS='|' read -r source target mode; do
    [ -n "$source" ] || continue
    count=$((count + 1))
    src="$ROOT_DIR/$source"
    dst="$ROOT_DIR/$target"
    if [ ! -f "$src" ]; then
        echo "FAIL: canonical missing: $source" >&2
        drift=1
        continue
    fi
    if [ ! -f "$dst" ]; then
        echo "FAIL: mirror missing: $target" >&2
        drift=1
        continue
    fi
    src_norm="$tmp_dir/src-$count"
    dst_norm="$tmp_dir/dst-$count"
    if ! emit_normalized "$src" "$mode" source > "$src_norm"; then
        exit 1
    fi
    if ! emit_normalized "$dst" "$mode" target > "$dst_norm"; then
        exit 1
    fi
    if ! diff -q "$src_norm" "$dst_norm" >/dev/null 2>&1; then
        echo "FAIL: drift detected: $target (source: $source, mode: $mode)" >&2
        diff -u "$src_norm" "$dst_norm" | head -40 >&2 || true
        drift=1
    fi
done < <(read_map_entries)

if [ "$count" -eq 0 ]; then
    echo "ERROR: no references declared in $MAP_FILE" >&2
    exit 1
fi

if [ "$drift" -eq 0 ]; then
    echo "check_references: OK ($count mapped mirrors match)"
    exit 0
fi

echo "" >&2
echo "check_references: drift detected. Run scripts/sync_references.sh to regenerate mirrors." >&2
exit 2
