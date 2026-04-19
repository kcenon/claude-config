#!/bin/bash
# preflight: run-msvc-docker.sh
# Rebuild the project with an MSVC Docker image to catch /WX + C4996 early.
# Emits a single JSON line to stdout and exits non-zero on failure.
#
# Usage:
#   bash global/skills/preflight/scripts/run-msvc-docker.sh [--image <tag>] [--verbose]
#
# Env:
#   CLAUDE_PREFLIGHT_MSVC_IMAGE   Docker image (default: mcr.microsoft.com/windows/servercore)
#   CLAUDE_PREFLIGHT_MSVC_CMD     Build command inside the container
#                                 (default: cmake --preset windows && cmake --build --preset windows)
#   CLAUDE_PREFLIGHT_VERBOSE      When non-empty, stream build output.

set -uo pipefail

CHECK="msvc-docker"
VERBOSE="${CLAUDE_PREFLIGHT_VERBOSE:-}"
IMAGE="${CLAUDE_PREFLIGHT_MSVC_IMAGE:-mcr.microsoft.com/windows/servercore:ltsc2022}"
BUILD_CMD="${CLAUDE_PREFLIGHT_MSVC_CMD:-cmake --preset windows && cmake --build --preset windows}"

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:-}"; shift 2 ;;
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

# Skip cleanly when Docker is unavailable. Most developer machines fall here —
# Windows containers specifically require Windows hosts or Docker Desktop with
# the Windows-container feature enabled.
if ! command -v docker >/dev/null 2>&1; then
    emit_json skip reason '"docker not on PATH"'
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    emit_json skip reason '"docker daemon not reachable"'
    exit 0
fi

# Windows containers are Windows-host-only unless Docker Desktop is configured for them.
# Use `docker info --format '{{.OSType}}'` to guard the run — skip silently on a Linux
# daemon so the developer is not forced to install a Windows VM just to preflight.
OSTYPE=$(docker info --format '{{.OSType}}' 2>/dev/null || echo unknown)
case "$OSTYPE" in
    windows) ;;
    *)
        emit_json skip reason "\"docker OSType=${OSTYPE}; Windows containers required\""
        exit 0
        ;;
esac

LOG="${TMPDIR:-/tmp}/preflight-msvc-$$.log"
START=$(now_ms)

# Mount repo at C:\\src, run the build command, capture combined output.
if docker run --rm \
        -v "$(pwd):C:\\src" \
        -w 'C:\\src' \
        "$IMAGE" \
        cmd /c "$BUILD_CMD" >"$LOG" 2>&1; then
    END=$(now_ms)
    DUR=$((END - START))
    emit_json pass duration_ms "$DUR" image "\"$IMAGE\""
    [ -n "$VERBOSE" ] && sed 's/^/    msvc: /' "$LOG"
    rm -f "$LOG"
    exit 0
else
    END=$(now_ms)
    DUR=$((END - START))
    emit_json fail duration_ms "$DUR" evidence "\"$LOG\"" image "\"$IMAGE\""
    # Surface the last 20 lines on failure even without --verbose — most C4996
    # diagnostics fit in that window.
    if [ -n "$VERBOSE" ]; then
        sed 's/^/    msvc: /' "$LOG" >&2
    else
        tail -20 "$LOG" | sed 's/^/    msvc: /' >&2
    fi
    exit 1
fi
