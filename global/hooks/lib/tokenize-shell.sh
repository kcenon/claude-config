#!/bin/bash
# tokenize-shell.sh
# Shell-aware tokenizer used by dangerous-command-guard.sh.
#
# Provides two helpers:
#   split_subcommands <command_string>
#       Emits one sub-command per line, splitting on shell control operators
#       (`;`, `&&`, `||`, `|`, `&`) and on substitution boundaries
#       (`$(...)`, `<(...)`, `>(...)`, backtick `...`, `<<<`, here-doc body).
#       Quote contexts (single, double, ANSI-C `$'...'`) are respected so that
#       operators inside quoted strings are NOT treated as separators.
#
#   tokenize_argv <subcommand_string>
#       Emits one argv token per line for a single sub-command, with quote
#       characters stripped. Backslash-escaped first character (e.g. `\rm`)
#       is collapsed to its bare form. `${IFS}`/`$IFS` substitutions are
#       expanded to a single space so that `r${IFS}m` becomes the token `r m`
#       (which then fails any `^rm$` argv match — i.e. denied as suspicious).
#
# These helpers are intentionally pure-bash (no awk/sed/python) so the hook
# stays usable on minimal images. They are NOT a full bash parser; they
# exist to defeat the most common bypass classes documented in the audit:
#   - Trailing chained commands after a whitelisted prefix
#   - Dangerous strings echoed/quoted as data (must NOT match)
#   - Substituted whitespace (`r${IFS}m`)
#   - Subshells `$(rm -rf /)` and process substitution `<(curl ... | sh)`
#   - Backtick command substitution
#
# Limitations (documented for reviewers):
#   - Does not perform full POSIX expansion (no glob, no $((arith)) eval).
#   - Does not handle nested quote escapes inside ANSI-C strings beyond
#     identifying their boundaries.
#   - Heredoc body content is treated as a separate sub-command, which is
#     conservative: a heredoc carrying a payload to `bash -s` will still be
#     scanned.

# split_subcommands <cmd>
#   Walks the input character-by-character maintaining quote state and
#   bracket depth. Emits the buffer when an unquoted, depth-0 separator is
#   reached. The substitution openers `$(`, `<(`, `>(` push a new context
#   that emits the inner command as its own sub-command line; the outer
#   command continues with a single space placeholder so its overall length
#   is preserved for follow-on parsing.
split_subcommands() {
    local cmd="$1"
    local len=${#cmd}
    local i=0
    local buf=""
    local quote=""        # one of: '', '"', $'
    local depth=0         # depth of $( / <( / >( / `
    local stack=()        # parallel stack of sub-command buffers per depth
    local ch next prev

    flush() {
        # Trim leading/trailing whitespace and emit if non-empty.
        local s="$1"
        # shellcheck disable=SC2295
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        if [ -n "$s" ]; then
            printf '%s\n' "$s"
        fi
    }

    while [ "$i" -lt "$len" ]; do
        ch="${cmd:$i:1}"
        next="${cmd:$((i+1)):1}"
        prev=""
        [ "$i" -gt 0 ] && prev="${cmd:$((i-1)):1}"

        # Inside a single-quoted string nothing is special except the
        # closing quote.
        if [ "$quote" = "'" ]; then
            buf+="$ch"
            if [ "$ch" = "'" ]; then
                quote=""
            fi
            i=$((i+1))
            continue
        fi

        # ANSI-C quoting: $'...'. Backslash escapes the next char inside.
        if [ "$quote" = "\$'" ]; then
            buf+="$ch"
            if [ "$ch" = "\\" ] && [ "$i" -lt "$((len-1))" ]; then
                buf+="$next"
                i=$((i+2))
                continue
            fi
            if [ "$ch" = "'" ]; then
                quote=""
            fi
            i=$((i+1))
            continue
        fi

        # Inside a double-quoted string only `\` and `"` are interesting
        # for boundary tracking. Command substitution `$(` is allowed in
        # double quotes and we recurse on it.
        if [ "$quote" = '"' ]; then
            if [ "$ch" = "\\" ] && [ "$i" -lt "$((len-1))" ]; then
                buf+="$ch$next"
                i=$((i+2))
                continue
            fi
            if [ "$ch" = '"' ]; then
                buf+="$ch"
                quote=""
                i=$((i+1))
                continue
            fi
            if [ "$ch" = '$' ] && [ "$next" = '(' ]; then
                buf+="\$("
                stack+=("$buf")
                buf=""
                depth=$((depth+1))
                i=$((i+2))
                continue
            fi
            if [ "$ch" = '`' ]; then
                buf+='`'
                stack+=("$buf")
                buf=""
                depth=$((depth+1))
                # Mark the opener so the close path can match.
                quote='`'
                i=$((i+1))
                continue
            fi
            buf+="$ch"
            i=$((i+1))
            continue
        fi

        # Backtick command substitution outside double quotes.
        if [ "$quote" = '`' ]; then
            if [ "$ch" = '`' ]; then
                # Close subshell: emit the inner buffer as its own line.
                flush "$buf"
                buf="${stack[${#stack[@]}-1]}"
                unset 'stack[${#stack[@]}-1]'
                stack=("${stack[@]}")
                buf+=" "  # placeholder so the outer command still parses
                depth=$((depth-1))
                quote=""
                i=$((i+1))
                continue
            fi
            buf+="$ch"
            i=$((i+1))
            continue
        fi

        # Unquoted state — the interesting separators live here.
        case "$ch" in
            "'")
                buf+="$ch"
                quote="'"
                ;;
            '"')
                buf+="$ch"
                quote='"'
                ;;
            '\\')
                # Escape next char into the buffer verbatim.
                if [ "$i" -lt "$((len-1))" ]; then
                    buf+="$ch$next"
                    i=$((i+2))
                    continue
                fi
                buf+="$ch"
                ;;
            '$')
                if [ "$next" = "'" ]; then
                    buf+="\$'"
                    quote="\$'"
                    i=$((i+2))
                    continue
                fi
                if [ "$next" = '(' ]; then
                    # $( ... ) — start of command substitution.
                    buf+="\$("
                    stack+=("$buf")
                    buf=""
                    depth=$((depth+1))
                    i=$((i+2))
                    continue
                fi
                buf+="$ch"
                ;;
            '<')
                if [ "$next" = '(' ]; then
                    # <( ... ) process substitution.
                    buf+="<("
                    stack+=("$buf")
                    buf=""
                    depth=$((depth+1))
                    i=$((i+2))
                    continue
                fi
                if [ "$next" = '<' ]; then
                    # `<<` heredoc or `<<<` here-string. Treat the body as
                    # a continuation of the current sub-command — the next
                    # whitespace-delimited token is the payload for `<<<`.
                    buf+="<<"
                    i=$((i+2))
                    continue
                fi
                buf+="$ch"
                ;;
            '`')
                buf+='`'
                stack+=("$buf")
                buf=""
                depth=$((depth+1))
                quote='`'
                ;;
            ')')
                if [ "$depth" -gt 0 ]; then
                    # Close the current subshell substitution.
                    flush "$buf"
                    buf="${stack[${#stack[@]}-1]}"
                    unset 'stack[${#stack[@]}-1]'
                    stack=("${stack[@]}")
                    buf+=") "
                    depth=$((depth-1))
                    i=$((i+1))
                    continue
                fi
                buf+="$ch"
                ;;
            ';')
                if [ "$depth" -eq 0 ]; then
                    flush "$buf"
                    buf=""
                    i=$((i+1))
                    continue
                fi
                buf+="$ch"
                ;;
            '&')
                if [ "$next" = '&' ] && [ "$depth" -eq 0 ]; then
                    flush "$buf"
                    buf=""
                    i=$((i+2))
                    continue
                fi
                if [ "$depth" -eq 0 ]; then
                    flush "$buf"
                    buf=""
                    i=$((i+1))
                    continue
                fi
                buf+="$ch"
                ;;
            '|')
                if [ "$next" = '|' ] && [ "$depth" -eq 0 ]; then
                    flush "$buf"
                    buf=""
                    i=$((i+2))
                    continue
                fi
                if [ "$depth" -eq 0 ]; then
                    flush "$buf"
                    buf=""
                    i=$((i+1))
                    continue
                fi
                buf+="$ch"
                ;;
            *)
                buf+="$ch"
                ;;
        esac
        i=$((i+1))
    done

    # Drain any unterminated subshells so their contents still get
    # inspected (fail-open on parse, but the hook adds a structural deny
    # for unbalanced quoting at the higher layer).
    while [ "$depth" -gt 0 ]; do
        flush "$buf"
        buf="${stack[${#stack[@]}-1]}"
        unset 'stack[${#stack[@]}-1]'
        stack=("${stack[@]}")
        depth=$((depth-1))
    done

    flush "$buf"
}

# tokenize_argv <subcommand>
#   Emits one token per line. Strips outer quotes. Collapses leading
#   backslash escape (`\rm` -> `rm`). Replaces `${IFS}`/`$IFS` with a
#   space so that obfuscated whitespace splits a single token into two.
tokenize_argv() {
    local cmd="$1"
    # Pre-expand IFS-based whitespace tricks.
    cmd="${cmd//\$\{IFS\}/ }"
    cmd="${cmd//\$IFS/ }"

    local len=${#cmd}
    local i=0
    local buf=""
    local quote=""
    local ch next

    emit() {
        local t="$1"
        if [ -z "$t" ]; then
            return 0
        fi
        # Strip a leading backslash that escapes the first char ("\rm" -> "rm").
        if [ "${t:0:1}" = '\' ] && [ ${#t} -gt 1 ]; then
            t="${t:1}"
        fi
        # Strip surrounding matching quotes.
        if [ ${#t} -ge 2 ]; then
            local first="${t:0:1}"
            local last="${t: -1}"
            if { [ "$first" = "'" ] && [ "$last" = "'" ]; } \
                || { [ "$first" = '"' ] && [ "$last" = '"' ]; }; then
                t="${t:1:${#t}-2}"
            fi
        fi
        printf '%s\n' "$t"
    }

    while [ "$i" -lt "$len" ]; do
        ch="${cmd:$i:1}"
        next="${cmd:$((i+1)):1}"

        if [ "$quote" = "'" ]; then
            buf+="$ch"
            if [ "$ch" = "'" ]; then quote=""; fi
            i=$((i+1)); continue
        fi
        if [ "$quote" = '"' ]; then
            if [ "$ch" = "\\" ] && [ "$i" -lt "$((len-1))" ]; then
                buf+="$ch$next"; i=$((i+2)); continue
            fi
            buf+="$ch"
            if [ "$ch" = '"' ]; then quote=""; fi
            i=$((i+1)); continue
        fi

        case "$ch" in
            "'") buf+="$ch"; quote="'" ;;
            '"') buf+="$ch"; quote='"' ;;
            '\\')
                if [ "$i" -lt "$((len-1))" ]; then
                    buf+="$ch$next"; i=$((i+2)); continue
                fi
                buf+="$ch"
                ;;
            ' '|$'\t'|$'\n')
                emit "$buf"
                buf=""
                ;;
            *) buf+="$ch" ;;
        esac
        i=$((i+1))
    done
    emit "$buf"
}

# If sourced, only export the helpers. If executed directly, dispatch to
# the requested helper (used for ad-hoc smoke testing).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    fn="${1:-}"
    shift || true
    case "$fn" in
        split) split_subcommands "$1" ;;
        argv)  tokenize_argv "$1" ;;
        *) echo "usage: $0 {split|argv} <command>" >&2; exit 2 ;;
    esac
fi
