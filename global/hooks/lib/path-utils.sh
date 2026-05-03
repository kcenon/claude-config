#!/bin/bash
# path-utils.sh
# Shared path-resolution helpers for hook scripts.
#
# Sourced by:
#   - global/hooks/sensitive-file-guard.sh
#   - global/hooks/bash-write-guard.sh
#
# Rationale (Issue #569)
# ----------------------
# Multiple guards need the same canonicalization semantics: expand `~`/`$HOME`
# at the head, run through `realpath` so symlinks collapse and macOS
# `/var/...` becomes `/private/var/...`, and fall back to a manual cleanup
# when realpath cannot resolve the path (BSD realpath rejects missing files,
# which the Write tool legitimately produces for new files).
#
# This file is the single source of truth for `resolve_path()`. Both guards
# previously carried near-identical copies; consolidating them here eliminates
# drift and lets future hooks reuse the same primitive.

set -euo pipefail

# resolve_path <raw_path>
#   Expands ~/ and $HOME at the head, then resolves the path through
#   realpath so symlinks collapse and macOS `/var/...` is canonicalized
#   to `/private/var/...`. Falls back to a manual cleanup when realpath
#   cannot resolve the path (BSD realpath rejects missing files).
#
#   Always returns 0. Empty input prints nothing (caller decides policy).
resolve_path() {
    local p="$1"
    [ -z "$p" ] && return 0
    case "$p" in
        '~')         p="${HOME:-$p}" ;;
        '~/'*)       p="${HOME}/${p#'~/'}" ;;
        '$HOME')     p="${HOME:-$p}" ;;
        '$HOME/'*)   p="${HOME}/${p#'$HOME/'}" ;;
    esac
    local resolved
    if command -v realpath >/dev/null 2>&1; then
        resolved=$(realpath "$p" 2>/dev/null) || resolved=""
    fi
    if [ -z "$resolved" ]; then
        # Fallback: resolve the parent directory (which usually exists)
        # and reattach the basename. This collapses `//` and trailing
        # `/` while keeping behavior consistent for write targets that
        # don't exist yet.
        local parent base
        parent=$(dirname "$p")
        base=$(basename "$p")
        if [ -d "$parent" ] && command -v realpath >/dev/null 2>&1; then
            local rp
            rp=$(realpath "$parent" 2>/dev/null) || rp="$parent"
            resolved="${rp%/}/$base"
        else
            # Last-resort manual cleanup.
            resolved=$(printf '%s' "$p" | sed -e 's://*:/:g' -e 's:/$::')
        fi
    fi
    printf '%s' "$resolved"
}
