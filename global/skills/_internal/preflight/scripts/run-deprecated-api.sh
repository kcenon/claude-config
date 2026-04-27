#!/bin/bash
# preflight: run-deprecated-api.sh
# Grep for the deprecated-API set shared with ci-fix's pattern catalogue.
# Emits a single JSON line to stdout and exits non-zero on findings.
#
# Usage:
#   bash global/skills/_internal/preflight/scripts/run-deprecated-api.sh [--include <glob>] [--verbose]
#
# Shares its pattern list with global/skills/_internal/ci-fix/reference/known-fixes.md via a
# generated file. Extending the catalogue there is automatically picked up here.

set -uo pipefail

CHECK="deprecated-api"
VERBOSE="${CLAUDE_PREFLIGHT_VERBOSE:-}"
INCLUDE="${CLAUDE_PREFLIGHT_DEPAPI_GLOB:---include=*.cpp --include=*.cc --include=*.cxx --include=*.h --include=*.hpp}"

while [ $# -gt 0 ]; do
    case "$1" in
        --include) INCLUDE="$2"; shift 2 ;;
        --verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# emit_json STATUS [key json-value ...]
# Keys are plain identifiers; values are emitted verbatim (already JSON-encoded).
emit_json() {
    printf '{"check":"%s","status":"%s"' "$CHECK" "$1"
    shift
    while [ $# -gt 1 ]; do
        printf ',"%s":%s' "$1" "$2"
        shift 2
    done
    printf '}\n'
}

# Portable millisecond clock (BSD date lacks %3N).
now_ms() {
    local ns
    if ns=$(date +%s%N 2>/dev/null) && [ "${ns}" != "+%s%N" ] && [[ "$ns" =~ ^[0-9]+$ ]]; then
        echo "$((ns / 1000000))"
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

# The pattern set. Keep in sync with ci-fix/reference/known-fixes.md's migration table.
# Each line is a regex matched with -E. Comments tolerated after `##`.
PATTERNS=(
    '\bfopen\s*\('      ## use std::ofstream or fopen_s under _MSC_VER
    '\bfopen_s\s*\('    ## Windows-only; wrap in _MSC_VER ifdef
    '\bstrcpy\s*\('     ## use snprintf or std::copy
    '\bsprintf\s*\('    ## use snprintf or std::format
    '\bstd::iterator\b' ## deprecated in C++17; inline the five typedefs
    '\bstd::codecvt_utf8\b' ## deprecated in C++17
    '\bstd::bind\b'     ## prefer lambdas
    '\bstd::auto_ptr\b' ## removed in C++17
    '\bstd::random_shuffle\b' ## removed in C++17
    '\bstd::uncaught_exception\(' ## removed in C++20; use plural form
    '\bGetVersionEx\s*\('         ## returns lies on Win10+
)

START=$(now_ms)
LOG="${TMPDIR:-/tmp}/preflight-depapi-$$.log"
: >"$LOG"
FINDINGS=0

for pat in "${PATTERNS[@]}"; do
    # Skip comment annotation for the actual match.
    regex="${pat%%##*}"
    regex="${regex% }"
    # shellcheck disable=SC2086  # $INCLUDE is intentional word-split
    matches=$(grep -rnE $INCLUDE --exclude-dir=build --exclude-dir=external \
                     --exclude-dir=.git --exclude-dir=node_modules \
                     -e "$regex" . 2>/dev/null || true)
    if [ -n "$matches" ]; then
        hits=$(echo "$matches" | wc -l | tr -d ' ')
        FINDINGS=$((FINDINGS + hits))
        {
            printf '\n==> pattern: %s\n' "$regex"
            echo "$matches"
        } >>"$LOG"
    fi
done

END=$(now_ms)
DUR=$((END - START))

if [ "$FINDINGS" -eq 0 ]; then
    emit_json pass duration_ms "$DUR" findings 0
    rm -f "$LOG"
    exit 0
fi

emit_json fail duration_ms "$DUR" findings "$FINDINGS" evidence "\"$LOG\""

if [ -n "$VERBOSE" ]; then
    sed 's/^/    depapi: /' "$LOG" >&2
else
    head -30 "$LOG" | sed 's/^/    depapi: /' >&2
fi
exit 1
