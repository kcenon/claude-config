#!/bin/bash
# bash-guard-dispatcher.sh
# Decides in the hook's own bash process whether a Bash call needs the guards, as the first stage of the Windows Bash dispatcher.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - the decision travels in the JSON payload)
# Response format: hookSpecificOutput with hookEventName
# Fail policy: anything this stage cannot read as a Bash payload goes to bash-guard-dispatcher.ps1, which fails closed
#
# Not a twin of bash-guard-dispatcher.ps1: the two are the two stages of the
# Windows dispatcher. global/settings.windows.json sources this file
# (". ~/.claude/hooks/bash-guard-dispatcher.sh"); global/settings.json
# registers the POSIX guards directly and never names it.
#
# The one place it runs off Windows is a Linux container that mounts a Windows
# ~/.claude: claude-docker passes a bash-native hook command through unchanged,
# and there is no pwsh there for the second stage. In that case this file runs
# the guards global/settings.json registers, so the container is guarded as a
# POSIX install is (see bgd_posix_guards).
#
# Why this exists: every Windows guard runs in pwsh, and the pwsh dispatcher
# cost a median of 641 ms per Bash call where a call answered here costs about
# 40 ms (#1041). Claude Code already runs each hook command in Git Bash, so this
# stage runs there and starts bash-guard-dispatcher.ps1 only when a guard rule
# could match the command. Every other call gets the plain allow the second
# stage would have written, from the same process.
#
# The filter is deliberately COARSER than every guard behind it: it may send a
# harmless command to the guards, and must never keep one from them that a
# guard would deny, ask about or annotate. It therefore matches words, not
# meanings, on a copy of the command in which the spellings a shell would undo
# are undone first (line continuations, backslashes, quotes inside a word).
# tests/hooks/test-bash-guard-dispatcher.sh feeds it every deny and ask case of
# the guards' corpus; a rule added to a guard without its word here fails there.

# Payload size above which the second stage always runs: dangerous-command-guard
# answers inputs over its 16 KiB tokenizer budget with a note of its own.
BGD_MAX_BYTES=8192

# Words a guard rule names. dangerous-command-guard: recursive rm, a fetch
# piped to an interpreter, chmod, IFS tricks, the git operations that discard
# work or rewrite a remote, and the shells and eval that read commands from a
# payload or from standard input. merge-gate-guard: gh pr merge.
# shell-env-secret-guard: printenv and compgen.
BGD_WORDS='rm|curl|wget|chmod|ifs|push|reset|checkout|switch|restore|clean|stash|merge|eval|printenv|compgen|(ba|z|da|k|a|c|tc|fi)?sh'

# Text that needs no word boundary: every gh and find deletion, the dump forms
# shell-env-secret-guard warns about, and the paths and names
# bash-sensitive-read-guard treats as secrets.
BGD_TEXT='delete|(export|declare)[[:space:]]+-p'
BGD_TEXT="$BGD_TEXT"'|\.(env|ssh|aws|gnupg|netrc|npmrc|pypirc|docker|kube|pem|key|p12|pfx|crt|cer)'
BGD_TEXT="$BGD_TEXT"'|hosts\.yml|secrets|credentials|password|id_(rsa|dsa|ecdsa|ed25519)|/etc/(shadow|sudoers)|ssh_host_'

# An expansion or substitution can stand for any command name, which only the
# guards resolve. A bare env or set dumps the environment.
BGD_RE='[$`]|(^|[^[:alnum:]_])('"$BGD_WORDS"')([^[:alnum:]_]|$)|'"$BGD_TEXT"'|(^|[;&|])[[:space:]]*(env|set)[[:space:]]*($|[;&|])'

# bgd_needs_guards <payload>
#   Returns 0 when the second stage has to see the payload, 1 when no guard
#   rule can match it.
bgd_needs_guards() {
    local LC_ALL=C
    local p="$1" c bs=$'\001' nocase=0 rc=1

    # The second stage fails closed on empty or unparseable input, and it is
    # the one that knows the payload: anything unexpected goes to it. That
    # includes a payload whose layout differs from the compact one Claude Code
    # writes, so a format change costs time, never a guard.
    [ -n "$p" ] || return 0
    case "$p" in *'"tool_input":{"command":"'*) ;; *) return 0 ;; esac
    [ "${#p}" -le "$BGD_MAX_BYTES" ] || return 0

    # The command, still JSON-escaped. A quote inside it is written \", so the
    # first unescaped ","description":" ends it. Without that field the tail
    # of the payload stays in, which can only add matches.
    c="${p#*\"tool_input\":\{\"command\":\"}"
    c="${c%%\",\"description\":\"*}"
    [ -n "$c" ] || return 0

    # Undo what a shell would undo before it looks for the command name.
    c="${c//\\\\\\n/}"        # backslash-newline joins two lines
    c="${c//\\\\/$bs}"        # set literal backslashes aside ...
    c="${c//\\n/ }"           # ... so that these are real newlines, tabs, CRs
    c="${c//\\t/ }"
    c="${c//\\r/ }"
    c="${c//$bs/}"            # r\m is rm
    c="${c//\\\"/}"           # "r""m" is rm
    c="${c//\'/}"             # 'r'm is rm

    # No command substitution in this function: on Windows each one forks, and
    # the point of this stage is to stay inside one process.
    shopt -q nocasematch && nocase=1
    shopt -s nocasematch
    [[ "$c" =~ $BGD_RE ]] && rc=0
    [ "$nocase" = 1 ] || shopt -u nocasematch
    return "$rc"
}

# bgd_posix_guards <payload>
#   The guards of global/settings.json, run the way that file runs them:
#   dangerous-command-guard on every call, merge-gate-guard when the call can
#   be a merge (the guard applies its own gh pr merge test). Decisions merge as
#   Claude Code merges hooks: deny > ask > allow. Does not return.
bgd_posix_guards() {
    local p="$1" here="${BASH_SOURCE[0]%/*}" d='' m='' want out
    d=$(printf '%s' "$p" | bash "$here/dangerous-command-guard.sh")
    case "$p" in *merge*) m=$(printf '%s' "$p" | bash "$here/merge-gate-guard.sh") ;; esac
    for want in deny ask; do
        for out in "$d" "$m"; do
            case "$out" in *"\"permissionDecision\":\"$want\""*) printf '%s\n' "$out"; exit 0 ;; esac
        done
    done
    [ -z "$d" ] || printf '%s\n' "$d"
    exit 0
}

# bgd_main
#   Reads the payload once. With no rule in reach it writes the second stage's
#   own plain allow; otherwise the second stage takes over this process, with
#   the payload on its standard input.
bgd_main() {
    local p='' here="${BASH_SOURCE[0]%/*}"
    IFS= read -r -d '' p || true
    # On Windows pwsh is a prerequisite of the profile, and looking for it on
    # every call would cost a PATH search. Elsewhere it decides which guards
    # exist: without it there is no second stage, and an allow from this stage
    # would vouch for guards that never ran.
    case "$OSTYPE" in
        msys*|cygwin*) ;;
        *) command -v pwsh >/dev/null 2>&1 || bgd_posix_guards "$p" ;;
    esac
    if bgd_needs_guards "$p"; then
        exec pwsh -NoProfile -File "$here/bash-guard-dispatcher.ps1" <<< "$p"
    fi
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
}

# The test suite sources this file for bgd_needs_guards alone.
if [ "${BGD_LIB_ONLY:-}" != "1" ]; then
    bgd_main
fi
