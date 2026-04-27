#!/bin/bash
# bash-write-guard.sh
# Enforces the "Read before Edit/Write" invariant on the Bash tool channel.
#
# Rationale (Issue #477)
# ----------------------
# The PreToolUse "Edit|Write|Read" matcher already enforces Read-before-
# Edit for the structured Edit/Write tools. The Bash channel was previously
# unguarded, so `cat > existing.py <<EOF`, `tee file`, `sed -i`, `python -c
# "open(f,'w').write(...)"`, `awk 'BEGIN{print > "f"}'`, `cp /dev/stdin f`,
# `install -m`, and `dd of=` all bypassed the contract.
#
# Whitelist, not blacklist
# ------------------------
# Red Team Vector E showed a blacklist of write commands is unbounded:
# new interpreters and obscure tools keep appearing. This guard inverts
# the question: any command whose argv head is in the WRITE_VERBS set or
# that contains a redirect-to-file is treated as a write, then we attempt
# to extract the destination path. If extraction fails, we DENY with a
# message asking the agent to use the Edit/Write tool instead — that is
# the stated breaking-change behavior in the issue spec.
#
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/tokenize-shell.sh
. "$LIB_DIR/tokenize-shell.sh"

# --- helpers ----------------------------------------------------------------

allow_response() {
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
}

deny_response() {
    local reason="$1"
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0
}

# resolve_path <raw_path>
#   Expands ~/ and $HOME at the head, then resolves the path through
#   realpath so symlinks collapse and macOS `/var/...` is canonicalized
#   to `/private/var/...`. Falls back to a manual cleanup when realpath
#   cannot resolve the path (BSD realpath rejects missing files).
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

# is_sensitive_target <path>
#   Path patterns that must NEVER be written by the Bash channel without an
#   explicit prior Read. Mirrors permissions.deny[] in settings.json plus a
#   superset for system credential files.
is_sensitive_target() {
    local p="$1"
    [ -z "$p" ] && return 1
    local lower
    lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
    case "$p" in
        */.env|*.env|*/.env.*|*.env.*) return 0 ;;
        */.ssh/id_*|*/.ssh/*_rsa|*/.ssh/*_dsa|*/.ssh/*_ecdsa|*/.ssh/*_ed25519) return 0 ;;
        */.aws/credentials|*/.aws/config) return 0 ;;
        */.gnupg/*|*/.gnupg) return 0 ;;
        */.netrc|*/.npmrc|*/.pypirc|*/.dockerconfigjson|*/.docker/config.json) return 0 ;;
        */.kube/config) return 0 ;;
        /etc/passwd|/etc/shadow|/etc/sudoers|/etc/sudoers.d/*|/etc/hosts) return 0 ;;
        */etc/passwd|*/etc/shadow|*/etc/sudoers|*/etc/sudoers.d/*|*/etc/hosts) return 0 ;;
    esac
    case "$lower" in
        *.pem|*.key|*.p12|*.pfx) return 0 ;;
        */secrets/*|*/credentials/*|*/passwords/*) return 0 ;;
    esac
    return 1
}

# tracker_has <path>
#   Returns 0 if the resolved path appears in the session Read tracker.
#   Mirrors the pre-edit-read-guard tracker file location.
tracker_has() {
    local resolved="$1"
    local session_id="${CLAUDE_SESSION_ID:-unknown}"
    local tracker_dir="${TMPDIR:-/tmp}"
    local tracker="${tracker_dir%/}/claude-read-set-${session_id}"
    [ -f "$tracker" ] || return 1
    grep -Fxq "$resolved" "$tracker" 2>/dev/null
}

# extract_redirect_target <subcommand_string>
#   Returns the file path of a `>`/`>>` redirect, if any, on stdout.
#   Walks the raw string with a simple quote-aware scan because the
#   tokenizer strips redirect operators from argv.
extract_redirect_target() {
    local cmd="$1"
    local len=${#cmd}
    local i=0 ch next quote=""
    local target=""
    local seen_redirect=0
    while [ "$i" -lt "$len" ]; do
        ch="${cmd:$i:1}"
        next="${cmd:$((i+1)):1}"
        if [ "$quote" = "'" ]; then
            [ "$ch" = "'" ] && quote=""
            i=$((i+1)); continue
        fi
        if [ "$quote" = '"' ]; then
            if [ "$ch" = "\\" ] && [ "$i" -lt "$((len-1))" ]; then i=$((i+2)); continue; fi
            [ "$ch" = '"' ] && quote=""
            i=$((i+1)); continue
        fi
        case "$ch" in
            "'") quote="'" ;;
            '"') quote='"' ;;
            '>')
                # Skip duplicate `>>` and `&>`/`>&` flavors — both still
                # imply a write target follows.
                seen_redirect=1
                if [ "$next" = '>' ]; then i=$((i+2)); continue; fi
                if [ "$next" = '&' ]; then i=$((i+2)); continue; fi
                ;;
            *)
                if [ "$seen_redirect" = "1" ]; then
                    case "$ch" in
                        ' '|$'\t') : ;;
                        *)
                            # Read the next whitespace-delimited token.
                            local j=$i
                            local tok=""
                            local tquote=""
                            while [ "$j" -lt "$len" ]; do
                                local c2="${cmd:$j:1}"
                                if [ "$tquote" = "'" ]; then
                                    [ "$c2" = "'" ] && tquote=""
                                    tok+="$c2"; j=$((j+1)); continue
                                fi
                                if [ "$tquote" = '"' ]; then
                                    [ "$c2" = '"' ] && tquote=""
                                    tok+="$c2"; j=$((j+1)); continue
                                fi
                                case "$c2" in
                                    "'") tquote="'"; tok+="$c2" ;;
                                    '"') tquote='"'; tok+="$c2" ;;
                                    ' '|$'\t'|$'\n'|';'|'&'|'|') break ;;
                                    *) tok+="$c2" ;;
                                esac
                                j=$((j+1))
                            done
                            # Strip surrounding quotes.
                            if [ ${#tok} -ge 2 ]; then
                                local f="${tok:0:1}" l="${tok: -1}"
                                if { [ "$f" = "'" ] && [ "$l" = "'" ]; } \
                                    || { [ "$f" = '"' ] && [ "$l" = '"' ]; }; then
                                    tok="${tok:1:${#tok}-2}"
                                fi
                            fi
                            target="$tok"
                            printf '%s\n' "$target"
                            return 0
                            ;;
                    esac
                fi
                ;;
        esac
        i=$((i+1))
    done
    return 1
}

# extract_target_from_argv <argv...>
#   For known write tools, extract the destination path from argv.
#   Returns 0 with the path on stdout, or 1 if the target cannot be
#   determined from argv alone (caller must deny as uninspectable).
extract_target_from_argv() {
    local cmd0="$1"
    shift
    local arg
    case "$cmd0" in
        tee)
            # `tee [-a] FILE...` — emit each non-flag arg.
            for arg in "$@"; do
                case "$arg" in
                    -*) continue ;;
                    *)  printf '%s\n' "$arg" ;;
                esac
            done
            return 0
            ;;
        cp|mv|install|rsync|scp)
            # Last positional argument is the destination.
            local last=""
            for arg in "$@"; do
                case "$arg" in
                    -*) continue ;;
                    *)  last="$arg" ;;
                esac
            done
            [ -n "$last" ] && printf '%s\n' "$last"
            return 0
            ;;
        sed)
            # Only -i (in-place) edits a file. Find the file argument(s).
            local has_inplace=0
            for arg in "$@"; do
                case "$arg" in
                    -i|-i*|--in-place|--in-place=*) has_inplace=1 ;;
                esac
            done
            if [ "$has_inplace" = "0" ]; then return 0; fi
            # The last non-flag token after the script is the file. Best
            # effort: emit every non-flag, non-script token.
            local script_seen=0
            for arg in "$@"; do
                case "$arg" in
                    -i|-i*|--in-place|--in-place=*|-e|--expression|-f|--file|-n|--quiet|-E|--regexp-extended) continue ;;
                    -*) continue ;;
                esac
                if [ "$script_seen" = "0" ]; then
                    script_seen=1
                    continue
                fi
                printf '%s\n' "$arg"
            done
            return 0
            ;;
        dd)
            # `dd of=PATH` — pull from of=.
            for arg in "$@"; do
                case "$arg" in
                    of=*) printf '%s\n' "${arg#of=}" ;;
                esac
            done
            return 0
            ;;
        truncate)
            # `truncate -s SIZE FILE`
            local prev=""
            for arg in "$@"; do
                if [ "$prev" = "-s" ] || [ "$prev" = "--size" ]; then
                    prev="$arg"; continue
                fi
                case "$arg" in
                    -*) prev="$arg"; continue ;;
                esac
                printf '%s\n' "$arg"
                prev="$arg"
            done
            return 0
            ;;
        ln)
            # `ln -s TARGET LINK_NAME` — the LINK_NAME is the writable side.
            local last=""
            for arg in "$@"; do
                case "$arg" in
                    -*) continue ;;
                    *)  last="$arg" ;;
                esac
            done
            [ -n "$last" ] && printf '%s\n' "$last"
            return 0
            ;;
        chmod|chown|chgrp)
            # Mode/owner is argv[1]; targets follow.
            local skipped_mode=0
            for arg in "$@"; do
                if [ "$skipped_mode" = "0" ]; then
                    skipped_mode=1; continue
                fi
                case "$arg" in
                    -*) continue ;;
                esac
                printf '%s\n' "$arg"
            done
            return 0
            ;;
        python|python2|python3|node|perl|ruby)
            # `python -c "..."`/`node -e "..."` — payload is opaque to
            # static inspection. Caller treats inability to extract as
            # uninspectable and denies.
            for arg in "$@"; do
                case "$arg" in
                    -c|-e|-E)
                        return 1 ;;
                esac
            done
            return 0
            ;;
        awk|gawk|mawk)
            # awk programs frequently write via redirection inside the
            # script body — uninspectable.
            return 1
            ;;
    esac
    return 0
}

# inspect_write_subcommand <subcommand_string>
#   Returns 0 (allow), or prints a deny reason and returns 1.
inspect_write_subcommand() {
    local sub="$1"
    [ -z "$sub" ] && return 0

    # Tokenize argv.
    local -a argv=()
    local t
    while IFS= read -r t; do
        argv+=("$t")
    done < <(tokenize_argv "$sub")
    [ ${#argv[@]} -eq 0 ] && return 0

    # Strip wrapper.
    local head="${argv[0]}"
    case "$head" in
        sudo|nice|nohup|time|stdbuf|exec)
            argv=("${argv[@]:1}") ;;
        env)
            argv=("${argv[@]:1}")
            while [ ${#argv[@]} -gt 0 ]; do
                case "${argv[0]}" in
                    *=*) argv=("${argv[@]:1}") ;;
                    *)   break ;;
                esac
            done ;;
    esac
    [ ${#argv[@]} -eq 0 ] && return 0

    local cmd0="${argv[0]}"

    # Detect the write category.
    #   1. Redirect-to-file present in the raw sub-command string.
    #   2. argv head matches a known write tool.
    local redirect_target=""
    if printf '%s' "$sub" | grep -qE '(^|[^0-9&|<])>+([^|]|$)'; then
        redirect_target=$(extract_redirect_target "$sub" || true)
    fi

    local is_write_tool=0
    case "$cmd0" in
        tee|cp|mv|install|rsync|scp|sed|dd|truncate|ln|chmod|chown|chgrp)
            is_write_tool=1 ;;
        python|python2|python3|node|perl|ruby|awk|gawk|mawk)
            is_write_tool=1 ;;
    esac

    # Nothing to inspect.
    if [ -z "$redirect_target" ] && [ "$is_write_tool" = "0" ]; then
        return 0
    fi

    # --- Sensitive-target check (always denied, regardless of Read state) ---
    local check_target resolved
    if [ -n "$redirect_target" ]; then
        case "$redirect_target" in
            /dev/null|/dev/stderr|/dev/stdout|/dev/tty)
                redirect_target="" ;;
        esac
    fi
    if [ -n "$redirect_target" ]; then
        resolved=$(resolve_path "$redirect_target")
        if is_sensitive_target "$resolved"; then
            echo "Bash write to sensitive file blocked: $redirect_target (resolved: $resolved)"
            return 1
        fi
    fi

    # --- Whitelist branch: opaque interpreters / awk ---
    case "$cmd0" in
        python|python2|python3|node|perl|ruby)
            local i
            for ((i=1; i<${#argv[@]}; i++)); do
                case "${argv[$i]}" in
                    -c|-e|-E)
                        echo "Uninspectable file mutation pattern ($cmd0 -${argv[$i]:1}); use Edit/Write tool instead"
                        return 1 ;;
                esac
            done
            ;;
        awk|gawk|mawk)
            # awk script bodies routinely write via `print > FILE`. Any
            # awk invocation that reaches this point is treated as
            # uninspectable; whitelist with `--whitelist-awk` is a future
            # extension (not in this PR).
            echo "Uninspectable file mutation pattern (awk script may write via redirection); use Edit/Write tool instead"
            return 1
            ;;
    esac

    # --- Extract argv-side targets (cp/mv/tee/sed -i/dd/...) ---
    local -a write_targets=()
    if [ "$is_write_tool" = "1" ]; then
        local target
        local -a rest=()
        if [ "${#argv[@]}" -gt 1 ]; then
            rest=("${argv[@]:1}")
        fi
        while IFS= read -r target; do
            [ -z "$target" ] && continue
            write_targets+=("$target")
        done < <(extract_target_from_argv "$cmd0" ${rest[@]+"${rest[@]}"})
    fi
    if [ -n "$redirect_target" ]; then
        write_targets+=("$redirect_target")
    fi

    # Sensitive-target check across all write targets.
    local wt
    for wt in ${write_targets[@]+"${write_targets[@]}"}; do
        resolved=$(resolve_path "$wt")
        if is_sensitive_target "$resolved"; then
            echo "Bash write to sensitive file blocked: $wt (resolved: $resolved)"
            return 1
        fi
    done

    # --- Read-before-Edit enforcement on existing files ---
    # Only enforce when at least one target points at an existing regular
    # file. New files are exempt (Write semantics).
    for wt in ${write_targets[@]+"${write_targets[@]}"}; do
        resolved=$(resolve_path "$wt")
        # Skip /dev/null and friends.
        case "$resolved" in
            /dev/null|/dev/stderr|/dev/stdout|/dev/tty) continue ;;
        esac
        if [ -e "$resolved" ] && [ ! -d "$resolved" ]; then
            if ! tracker_has "$resolved"; then
                # First-run safety: if no tracker exists yet, fall through
                # to allow (mirrors pre-edit-read-guard).
                local tracker_dir="${TMPDIR:-/tmp}"
                local session_id="${CLAUDE_SESSION_ID:-unknown}"
                local tracker="${tracker_dir%/}/claude-read-set-${session_id}"
                if [ ! -f "$tracker" ]; then
                    continue
                fi
                echo "Cannot Bash-write '$wt' without reading it first in this session. Call Read on '$wt' and retry."
                return 1
            fi
        fi
    done

    return 0
}

# --- main -------------------------------------------------------------------

INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    allow_response
fi

command -v jq >/dev/null 2>&1 || allow_response

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && allow_response

# Performance bound.
BWG_TOKENIZER_MAX_BYTES="${BWG_TOKENIZER_MAX_BYTES:-16384}"
if [ "${#CMD}" -gt "$BWG_TOKENIZER_MAX_BYTES" ]; then
    if echo "$CMD" | grep -qE '(^|[[:space:]])(python|node|perl|ruby)\s+(-c|-e)'; then
        deny_response "Uninspectable file mutation pattern (coarse-scan); use Edit/Write tool instead"
    fi
    allow_response
fi

prev=""
while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    if reason=$(inspect_write_subcommand "$sub"); then
        :
    else
        deny_response "$reason"
    fi
    prev="$sub"
done < <(split_subcommands "$CMD")

allow_response
