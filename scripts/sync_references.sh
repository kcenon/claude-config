#!/usr/bin/env bash
# Sync mapped canonical reference files to mirror locations.
#
# Usage: scripts/sync_references.sh [repo-root] [reference-map.yml]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
MAP_FILE="${2:-$ROOT_DIR/reference-map.yml}"

if [ ! -f "$MAP_FILE" ]; then
    echo "ERROR: reference map missing: $MAP_FILE" >&2
    exit 1
fi

strip_frontmatter() {
    local file="$1"
    awk '
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---" { in_fm = 0; skip_blank = 1; next }
        in_fm { next }
        skip_blank && $0 == "" { skip_blank = 0; next }
        { skip_blank = 0; print }
    ' "$file"
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

count=0
while IFS='|' read -r source target mode; do
    [ -n "$source" ] || continue
    count=$((count + 1))
    src="$ROOT_DIR/$source"
    dst="$ROOT_DIR/$target"
    if [ ! -f "$src" ]; then
        echo "ERROR: canonical file missing: $source" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    case "$mode" in
        exact) cp "$src" "$dst" ;;
        strip-source-frontmatter) strip_frontmatter "$src" > "$dst" ;;
        *)
            echo "ERROR: unsupported reference sync mode: $mode" >&2
            exit 1
            ;;
    esac
    echo "synced: $source -> $target ($mode)"
done < <(read_map_entries)

if [ "$count" -eq 0 ]; then
    echo "ERROR: no references declared in $MAP_FILE" >&2
    exit 1
fi

echo "sync_references: done ($count mapped mirrors)"
