#!/bin/bash
# rotate.sh — log rotation utility
# Usage: source this file, then call rotate_log <file> [max_mb] [max_archives]

# Get file size in bytes (cross-platform: macOS + Linux)
_file_size_bytes() {
    if stat -f%z "$1" 2>/dev/null; then
        return
    fi
    stat -c%s "$1" 2>/dev/null
}

# rotate_log <file> [max_mb] [max_archives]
#   file         — log file path
#   max_mb       — rotate when file exceeds this size (default: 10)
#   max_archives — keep at most this many .N.gz archives (default: 5)
rotate_log() {
    local file="$1"
    local max_mb="${2:-10}"
    local max_archives="${3:-5}"

    [ -f "$file" ] || return 0

    local size_bytes
    size_bytes=$(_file_size_bytes "$file")
    [ -z "$size_bytes" ] && return 1

    local max_bytes=$((max_mb * 1024 * 1024))
    [ "$size_bytes" -le "$max_bytes" ] && return 0

    # Shift existing archives: .4.gz → .5.gz, .3.gz → .4.gz, ...
    local i=$max_archives
    while [ "$i" -gt 1 ]; do
        local prev=$((i - 1))
        if [ -f "${file}.${prev}.gz" ]; then
            if [ "$i" -gt "$max_archives" ]; then
                rm -f "${file}.${prev}.gz"
            else
                mv -f "${file}.${prev}.gz" "${file}.${i}.gz"
            fi
        fi
        i=$((i - 1))
    done

    # Compress current file to .1.gz
    gzip -c "$file" > "${file}.1.gz" 2>/dev/null || return 1

    # Truncate the original file
    : > "$file"

    # Remove archives beyond max count
    local j=$((max_archives + 1))
    while [ -f "${file}.${j}.gz" ]; do
        rm -f "${file}.${j}.gz"
        j=$((j + 1))
    done

    return 0
}
