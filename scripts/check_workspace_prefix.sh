#!/bin/bash
# Workspace Prefix Linter (warn-only)
# ====================================
# Verifies that files inside `_workspace/{date}-{n}/` directories follow
# the `NN_<phase>.<ext>` convention defined in global/skills/_policy.md.
#
# Convention:
#   NN_       2-digit zero-padded phase index (00..99)
#   <phase>   lowercase snake_case phase name
#   <ext>     artifact extension
#
# Usage:
#   scripts/check_workspace_prefix.sh                # scan repo root
#   scripts/check_workspace_prefix.sh <root>         # scan an explicit root
#   scripts/check_workspace_prefix.sh --quiet ...    # suppress per-file warnings
#
# Exit code: 0 always (warn-only by design during P3 rollout).

set -u

QUIET=0
ROOT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) ROOT="$1"; shift ;;
    esac
done

if [ -z "$ROOT" ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    ROOT="$(dirname "$SCRIPT_DIR")"
fi

if [ ! -d "$ROOT" ]; then
    echo "check_workspace_prefix: root not found: $ROOT" >&2
    exit 0
fi

# NN_<phase>.<ext>
#   NN          : ^[0-9][0-9]_
#   <phase>     : [a-z][a-z0-9_]*
#   <ext>       : \.[a-z0-9]+$
PREFIX_RE='^[0-9][0-9]_[a-z][a-z0-9_]*\.[a-z0-9]+$'

WS_ROOTS=()
while IFS= read -r d; do
    [ -n "$d" ] && WS_ROOTS+=("$d")
done < <(find "$ROOT" -type d -name "_workspace" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)

WARN_COUNT=0
SCAN_COUNT=0

for ws in "${WS_ROOTS[@]:-}"; do
    [ -z "${ws:-}" ] && continue
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        SCAN_COUNT=$((SCAN_COUNT + 1))
        name="$(basename "$f")"
        if ! [[ "$name" =~ $PREFIX_RE ]]; then
            WARN_COUNT=$((WARN_COUNT + 1))
            if [ "$QUIET" -eq 0 ]; then
                rel="${f#$ROOT/}"
                echo "WARN: $rel does not match NN_<phase>.<ext> convention"
            fi
        fi
    done < <(find "$ws" -mindepth 2 -type f 2>/dev/null)
done

if [ "$QUIET" -eq 0 ]; then
    echo "check_workspace_prefix: scanned=$SCAN_COUNT warnings=$WARN_COUNT roots=${#WS_ROOTS[@]}"
fi

exit 0
