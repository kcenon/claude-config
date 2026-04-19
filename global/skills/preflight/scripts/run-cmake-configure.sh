#!/bin/bash
# preflight: run-cmake-configure.sh
# CMake configure-only pass with warnings-as-errors equivalents enabled.
# Emits a single JSON line to stdout and exits non-zero on failure.

set -uo pipefail

CHECK="cmake-configure"
VERBOSE="${CLAUDE_PREFLIGHT_VERBOSE:-}"
BUILD_DIR="${CLAUDE_PREFLIGHT_CMAKE_BUILD_DIR:-build/preflight}"
EXTRA_FLAGS="${CLAUDE_PREFLIGHT_CMAKE_FLAGS:--Wdev -Werror=dev}"

while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# emit_json STATUS [key json-value ...]
emit_json() {
    printf '{"check":"%s","status":"%s"' "$CHECK" "$1"
    shift
    while [ $# -gt 1 ]; do
        printf ',"%s":%s' "$1" "$2"
        shift 2
    done
    printf '}\n'
}

now_ms() {
    local ns
    if ns=$(date +%s%N 2>/dev/null) && [ "${ns}" != "+%s%N" ] && [[ "$ns" =~ ^[0-9]+$ ]]; then
        echo "$((ns / 1000000))"
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

if ! command -v cmake >/dev/null 2>&1; then
    emit_json skip reason '"cmake not on PATH"'
    exit 0
fi

if [ ! -f CMakeLists.txt ]; then
    emit_json skip reason '"no CMakeLists.txt at repo root"'
    exit 0
fi

LOG="${TMPDIR:-/tmp}/preflight-cmake-$$.log"
START=$(now_ms)

# shellcheck disable=SC2086
if cmake -S . -B "$BUILD_DIR" $EXTRA_FLAGS >"$LOG" 2>&1; then
    END=$(now_ms)
    DUR=$((END - START))
    emit_json pass duration_ms "$DUR" build_dir "\"$BUILD_DIR\""
    [ -n "$VERBOSE" ] && sed 's/^/    cmake: /' "$LOG"
    rm -f "$LOG"
    exit 0
else
    END=$(now_ms)
    DUR=$((END - START))
    emit_json fail duration_ms "$DUR" evidence "\"$LOG\""
    if [ -n "$VERBOSE" ]; then
        sed 's/^/    cmake: /' "$LOG" >&2
    else
        tail -30 "$LOG" | sed 's/^/    cmake: /' >&2
    fi
    exit 1
fi
