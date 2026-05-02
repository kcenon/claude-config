#!/bin/bash
# memory-access-logger.sh
# Logs Claude Code Read tool calls targeting memory files (path only).
# Hook Type: PostToolUse (Read)
# Exit codes: 0 (always — this is a passive logger; failure must NOT affect tool flow)
# Response format: empty stdout (PostToolUse cannot influence the past tool call)
#
# Path gate:
#   Only logs when realpath(tool_input.file_path) is under
#   "$HOME/.claude/memory-shared/memories/". The top-level MEMORY.md (which
#   lives at memory-shared/MEMORY.md) is intentionally NOT logged.
#
# Log file: $HOME/.claude/logs/memory-access.log
# Log line: "<ISO8601 UTC timestamp> <session_id> read <relative-path>"
#   - Path is stored relative to "memory-shared/" (so it begins "memories/...").
#   - session_id falls back to "unknown" when the field is absent.
#
# Rotation policy (lazy, checked on each invocation):
#   - When file size exceeds 1 MiB OR the file's calendar month differs from
#     the current calendar month, rotate to "<log>.YYYY-MM" using the file's
#     own month so the archive carries the period it covers. The original
#     log path is then truncated and the new entry is appended to a fresh
#     file.
#   - Older archives are reaped by the project's existing cleanup convention.
#
# Failure isolation:
#   Any internal failure (jq missing, log unwritable, mktemp failure, etc.) is
#   silently swallowed and exit 0 is returned so that the user's Read flow is
#   never disrupted. The PostToolUse Read hook is registered with async: true
#   in settings.json for the same reason.
#
# Bash 3.2 compatible (macOS default).

set -u

LOG_FILE="${HOME}/.claude/logs/memory-access.log"
MEMORY_ROOT="${HOME}/.claude/memory-shared/memories"
SHARED_ROOT="${HOME}/.claude/memory-shared"

# ----- helpers ---------------------------------------------------------------

# Always exit 0 to preserve tool flow on any failure path.
silent_exit() { exit 0; }

# JSON string extractor: prefer jq, fall back to a sed-only path.
# This hook needs only three string fields: .tool_name, .session_id, and
# .tool_input.file_path. The fallback handles those three specifically; it is
# NOT a general-purpose JSON parser and does not attempt to handle nested
# arrays, escaped Unicode, or non-string values.
extract_json_field() {
    # Args: <json> <jq-path>  e.g. '.tool_input.file_path' or '.session_id'
    local json="$1"
    local path="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r "$path // empty" 2>/dev/null
        return
    fi
    # Fallback: extract the rightmost key segment from the jq path and search
    # for "<key>": "<value>" with sed. Limited to the three fields we need.
    local key
    key="$(printf '%s' "$path" | sed 's|^.*\.||')"
    printf '%s' "$json" \
        | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
        | head -n 1
}

# Resolve realpath. When file does not exist, resolve the parent directory and
# append the basename — same trick memory-write-guard uses (#521).
resolve_path() {
    local p="$1"
    if [ -e "$p" ]; then
        if command -v realpath >/dev/null 2>&1; then
            realpath "$p" 2>/dev/null || printf '%s' "$p"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p" 2>/dev/null || printf '%s' "$p"
        else
            printf '%s' "$p"
        fi
    else
        local parent base rp
        parent="$(dirname "$p")"
        base="$(basename "$p")"
        if [ -d "$parent" ]; then
            if command -v realpath >/dev/null 2>&1; then
                rp="$(realpath "$parent" 2>/dev/null)"
                if [ -n "$rp" ]; then printf '%s/%s' "$rp" "$base"; return; fi
            elif command -v python3 >/dev/null 2>&1; then
                rp="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$parent" 2>/dev/null)"
                if [ -n "$rp" ]; then printf '%s/%s' "$rp" "$base"; return; fi
            fi
        fi
        printf '%s' "$p"
    fi
}

# File size in bytes (cross-platform).
# GNU and BSD `stat` use different flags. GNU's `stat -f` is "filesystem stat"
# (different output, exit 0) so we cannot rely on exit code alone — validate
# that the output is purely numeric before accepting it.
file_size_bytes() {
    local out
    out="$(stat -c%s "$1" 2>/dev/null || true)"
    case "$out" in (''|*[!0-9]*) ;; (*) printf '%s' "$out"; return 0 ;; esac
    out="$(stat -f%z "$1" 2>/dev/null || true)"
    case "$out" in (''|*[!0-9]*) ;; (*) printf '%s' "$out"; return 0 ;; esac
    return 1
}

# YYYY-MM stamp from a file's mtime (UTC). Returns empty on failure.
file_month_utc() {
    local epoch out
    # GNU stat path: -c%Y -> epoch seconds; convert via `date -d @N`.
    epoch="$(stat -c%Y "$1" 2>/dev/null || true)"
    case "$epoch" in (''|*[!0-9]*) epoch="" ;; esac
    if [ -n "$epoch" ]; then
        out="$(date -u -d "@$epoch" +%Y-%m 2>/dev/null \
                || date -u -r "$epoch" +%Y-%m 2>/dev/null \
                || true)"
        case "$out" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]) printf '%s' "$out"; return 0 ;;
        esac
    fi
    # BSD stat path (macOS): -f %Sm -t %Y-%m -> formatted directly.
    out="$(stat -f "%Sm" -t "%Y-%m" "$1" 2>/dev/null || true)"
    case "$out" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]) printf '%s' "$out"; return 0 ;;
    esac
    return 1
}

# Rotate the log when size > 1 MiB OR the file's month != current month.
maybe_rotate() {
    local file="$1"
    [ -f "$file" ] || return 0

    local size
    size="$(file_size_bytes "$file")"
    [ -z "$size" ] && return 0

    local current_month
    current_month="$(date -u +%Y-%m 2>/dev/null)"
    local file_month
    file_month="$(file_month_utc "$file")"

    local one_mib=$((1024 * 1024))
    local rotate=0
    if [ "$size" -gt "$one_mib" ]; then rotate=1; fi
    if [ -n "$current_month" ] && [ -n "$file_month" ] && [ "$file_month" != "$current_month" ]; then
        rotate=1
    fi
    [ "$rotate" -eq 1 ] || return 0

    # Archive carries the period it actually covers (file_month preferred).
    local stamp="${file_month:-$current_month}"
    [ -z "$stamp" ] && stamp="$(date -u +%Y-%m 2>/dev/null)"
    [ -z "$stamp" ] && stamp="archive"

    local target="${file}.${stamp}"
    # Avoid clobbering an existing archive for the same month.
    if [ -e "$target" ]; then
        local n=1
        while [ -e "${target}.${n}" ]; do n=$((n + 1)); done
        target="${target}.${n}"
    fi
    mv -f "$file" "$target" 2>/dev/null || return 0
    : > "$file" 2>/dev/null || return 0
    return 0
}

# ----- read input ------------------------------------------------------------

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && silent_exit

TOOL_NAME="$(extract_json_field "$INPUT" '.tool_name')"
[ "$TOOL_NAME" = "Read" ] || silent_exit

FILE_PATH="$(extract_json_field "$INPUT" '.tool_input.file_path')"
[ -z "$FILE_PATH" ] && silent_exit

SESSION_ID="$(extract_json_field "$INPUT" '.session_id')"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

# ----- path gate -------------------------------------------------------------

RESOLVED="$(resolve_path "$FILE_PATH")"

# Strict prefix match: must be under memories/ specifically. The top-level
# MEMORY.md is intentionally NOT logged (it is auto-generated, not user
# memory content).
case "$RESOLVED" in
    "$MEMORY_ROOT"/*) ;;
    *) silent_exit ;;
esac

# Compute the relative path from memory-shared/ for compactness.
RELATIVE="${RESOLVED#"$SHARED_ROOT"/}"

# ----- write log entry -------------------------------------------------------

LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR" 2>/dev/null || silent_exit

# Lazy rotation BEFORE the append so the new entry lands in a fresh file
# whenever rotation triggers. Failure is silent; logging still proceeds.
maybe_rotate "$LOG_FILE"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
[ -z "$TIMESTAMP" ] && TIMESTAMP="-"

# Sanitize whitespace in the path so a single space-delimited line stays
# parseable. The audit consumer splits on whitespace and uses field 4 for the
# path — see #528.
SAFE_RELATIVE="$(printf '%s' "$RELATIVE" | tr '\t\n\r' '   ')"

# Single-line append < PIPE_BUF is atomic on POSIX, so concurrent reads are safe.
printf '%s %s read %s\n' "$TIMESTAMP" "$SESSION_ID" "$SAFE_RELATIVE" >> "$LOG_FILE" 2>/dev/null

silent_exit
