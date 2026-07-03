# shellcheck shell=bash
# scripts/lib/safe-rm.sh
# =====================================================================
# Sourced library: no shebang, no `set -e`. The caller is responsible
# for strict mode (`set -euo pipefail`); this file inherits it.
#
# Public API
# ----------
#   safe_rm_rf <target>
#     Removes <target> recursively after asserting the resolved canonical
#     path lies within an allow-listed prefix. Idempotent: a missing
#     target succeeds quietly so cleanup blocks can run twice.
#
# Threat model
# ------------
#   The original `rm -rf "$BACKUP_DIR/<sub>"/*` callers in bootstrap.sh
#   and scripts/backup.sh derive `$BACKUP_DIR` from `dirname "$SCRIPT_DIR"`
#   where `$SCRIPT_DIR` is built from `$BASH_SOURCE`. An attacker who
#   controls `$BASH_SOURCE` (e.g. via `source` of a hostile script) or a
#   misconfigured invocation that leaves the variable empty can redirect
#   the deletion target to an arbitrary path — historically up to the
#   parent directory of whatever `$SCRIPT_DIR` resolves to. With `set -u`
#   addressed in M1.1, undefined variables now error early, but symlinks
#   and `..` traversal remain. This helper converts the assumption
#   "the variable is honest" into the verifiable invariant "the resolved
#   target lies under a prefix the project owns."
#
# Allow-list
# ----------
#   The prefixes below cover every legitimate deletion target across the
#   repository. Extend this list — do not weaken it — when adding new
#   callers. Each addition should name the script and rationale.
#
#   1. "$HOME"/.claude/*           — global Claude Code config tree
#                                   (rotated by install/sync flows)
#   2. "$HOME"/.claude-backup/*    — historical backup snapshots
#                                   (legacy layout, kept for migration)
#   3. "$HOME"/claude_config_backup/*
#                                  — bootstrap.sh INSTALL_DIR default and
#                                   backup.sh BACKUP_DIR (project clone
#                                   acting as a backup carrier)
#   4. /tmp/claude-*               — sha256-pinned installer scratch
#                                   files from bootstrap.sh ensure_claude_cli
#   5. /tmp/claude-config-*        — test fixtures created by tests/
#                                   safe-rm-rf.sh and other suites
# =====================================================================

# Idempotency guard: avoid redefining the function or duplicating
# realpath cost when sourced multiple times in the same shell.
if [ -n "${SAFE_RM_SH_LOADED:-}" ]; then
    return 0
fi
SAFE_RM_SH_LOADED=1

safe_rm_rf() {
    local raw="${1:-}"

    if [ -z "$raw" ]; then
        echo "safe_rm_rf: target required" >&2
        return 1
    fi

    # Idempotent cleanup: a missing target is not an error. Repeated
    # invocations on the same path (e.g. retry of a partial restore)
    # must be safe.
    if [ ! -e "$raw" ] && [ ! -L "$raw" ]; then
        return 0
    fi

    local target
    # `realpath -e` requires every component to exist and follows
    # symlinks. This collapses `..` traversal and resolves symlinks
    # before the allow-list check, so a symlinked redirect cannot
    # bypass the guard.
    target=$(realpath -e "$raw") || {
        echo "safe_rm_rf: cannot resolve $raw" >&2
        return 1
    }

    case "$target" in
        "$HOME"/.claude/*) ;;
        "$HOME"/.claude-backup/*) ;;
        "$HOME"/claude_config_backup/*) ;;
        /tmp/claude-*) ;;
        /tmp/claude-config-*) ;;
        *)
            echo "safe_rm_rf: refused — $target is outside allow-listed prefix" >&2
            return 1
            ;;
    esac

    rm -rf -- "$target"
}
