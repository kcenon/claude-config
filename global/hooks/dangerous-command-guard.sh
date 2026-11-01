#!/bin/bash
# dangerous-command-guard.sh
# Denies irreversible shell operations and asks before destructive local ones.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Decision tiers (issue #964):
#   deny  - irreversible AND reaching beyond the working tree or shared state:
#           recursive rm of /, an absolute path, ~ or $HOME; a fetch piped to
#           an interpreter; chmod 777 / setuid; IFS obfuscation; a direct push
#           to main/master/develop (ported from push-target-guard); gh repo
#           delete; gh api DELETE on repos/<owner>/<repo> itself.
#   ask   - irreversible but scoped to the working tree, or rewriting or
#           deleting a shared ref: git reset --hard, git checkout -- <path> /
#           . / -f, git switch -f / --force / --discard-changes and git
#           restore without --staged (only when the work tree has changes),
#           git clean -f, git stash drop|clear, git push --force
#           / -f / +<ref> (not --force-with-lease), git push --delete / -d /
#           <remote> :<ref>, recursive rm of ., .., *, .*, .git or a path that
#           resolves outside the repository, find -delete / -exec rm, gh
#           <group> delete|delete-asset, and every other gh api DELETE.
#   allow - everything else; recoverable through the reflog, the remote or
#           VCS history.
#
# Inspectability: the payload of `bash|sh|zsh|dash|ksh|fish -c '...'` and of
# `eval ...` is tokenized and inspected with the same rules, up to
# MAX_PAYLOAD_DEPTH nested levels. A payload that cannot be inspected
# (unbalanced quotes, a bare variable expansion, nesting past the bound) is
# denied (fail-closed). `source <file>` and `. <file>` are allowed; a fetch
# fed to eval/source (`eval "$(curl ...)"`) is still remote execution.
# Outside a payload, a command head that is a variable (`$X`, `${X}`,
# `${X:-word}`) is resolved from an earlier assignment of the same command
# (`X=value`, or through export, declare, local, readonly or typeset; unset
# forgets it), else from its default word. `$SHELL` and `$BASH` are inspected
# as a shell. Any other unresolved head, and a `$(...)` or backtick head at any
# depth, asks when its arguments would make rm deny or ask, or when the operand
# of a flag ending in c would make a shell deny or ask.
# The real command of a sub-command is found first (#991): shell grammar goes
# (`if`, `then`, `do`, `!`, `{`, `(`, a case pattern, a function head), then
# leading assignments and redirections, then known wrappers with their own flags
# (sudo, env, command, nice, nohup, time, timeout, xargs, ...). `command -v` is a
# lookup. rm through xargs, parallel or find -exec always asks. A fetch piped to
# a shell through a wrapper or `$SHELL` denies; to any other unresolved head it
# asks. `for` and `select` keep their words as data. A wrapper this list does not
# know, `ssh host '...'` and an interpreter's own body are not inspected.
# Input longer than DCG_TOKENIZER_MAX_BYTES is not tokenized: a regex scan of
# the text, with continuations joined and quoted prose blanked, denies the
# deny-tier shapes and asks on any keyword of an ask arm, on a git push with no
# refspec, or on an unresolved command name with a recursive flag.
#
# Side effects:
#   Writes one JSON line per deny or ask decision to
#   ${CLAUDE_LOG_DIR:-$HOME/.claude/logs}/dangerous-command-guard.log.
#   Allow decisions are not logged (#964); they were over 99% of the
#   entries. The work tree checks run `git status` / `git rev-parse` only
#   after a command has matched an arm, never on every call.
#
# Allow-path output (issue #715): plain allows emit the minimal allow JSON
# with no additionalContext (pass-path context is token noise on every Bash
# call). Only the coarse-scan allow (degraded inspection warning) keeps
# additionalContext.

set -euo pipefail

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/dangerous-command-guard.log"

# Nesting bound for `bash -c` / `eval` payload scanning. A wrapper found at
# this depth is denied instead of scanned.
MAX_PAYLOAD_DEPTH=3

# Best-effort log writer. Never blocks the decision on logging failure.
log_decision() {
    local decision="$1"
    local reason="$2"
    local cmd="$3"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Use jq to produce a safely escaped JSON line when available;
    # fall back to a minimal manual escape if jq is missing.
    if command -v jq >/dev/null 2>&1; then
        jq -cn \
            --arg ts "$ts" \
            --arg d "$decision" \
            --arg r "$reason" \
            --arg c "$cmd" \
            '{ts:$ts, decision:$d, reason:$r, command:$c}' \
            >>"$LOG_FILE" 2>/dev/null || true
    else
        local esc_cmd esc_reason
        esc_cmd=${cmd//\\/\\\\}
        esc_cmd=${esc_cmd//\"/\\\"}
        esc_reason=${reason//\\/\\\\}
        esc_reason=${esc_reason//\"/\\\"}
        printf '{"ts":"%s","decision":"%s","reason":"%s","command":"%s"}\n' \
            "$ts" "$decision" "$esc_reason" "$esc_cmd" \
            >>"$LOG_FILE" 2>/dev/null || true
    fi
}

deny_response() {
    local reason="$1"
    log_decision "deny" "$reason" "${CMD:-}"
    # Use jq so the JSON library handles all escaping (quotes, backslashes,
    # newlines, tabs, carriage returns, etc.). This closes the historical
    # injection class where a crafted reason string concatenated into the
    # heredoc could flip the decision (issue #567).
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

ask_response() {
    # "ask" makes Claude Code prompt the user, who sees the reason in the
    # permission prompt (hooks reference, PreToolUse decision control).
    local reason="$1"
    log_decision "ask" "$reason" "${CMD:-}"
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
    exit 0
}

allow_response() {
    # Plain allow is silent on stdout (issue #715) and not logged (#964).
    jq -nc \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
    exit 0
}

allow_with_context() {
    # Warning-class allow: the context has decision value for the model
    # (e.g. degraded coarse-scan inspection), so it stays on stdout under
    # additionalContext; permissionDecisionReason is reserved for deny/ask.
    local reason="$1"
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", additionalContext: $reason}}'
    exit 0
}

INPUT=$(cat)

if [ -z "$INPUT" ]; then
    CMD=""
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

# Capture jq's exit status without tripping set -e.
JQ_RC=0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || JQ_RC=$?

if [ "$JQ_RC" -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi

if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# The work tree checks resolve paths against the session directory the hook
# input reports, falling back to the hook process directory.
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$HOOK_CWD" ] || HOOK_CWD="$PWD"

# coarse_has <text> <ERE>: succeeds when a line of <text> matches. grep -c
# reads all of its input, unlike grep -q, so the writer never meets a closed
# pipe under pipefail.
coarse_has() {
    local n
    n=$(printf '%s\n' "$1" | LC_ALL=C grep -cE -- "$2" 2>/dev/null) || true
    [ "${n:-0}" -gt 0 ]
}

# coarse_ask <what>: the ask decision of the coarse scan.
coarse_ask() {
    ask_response "Input of ${#CMD} bytes exceeds the tokenizer budget (${DCG_TOKENIZER_MAX_BYTES} bytes) and contains $1, so it was not inspected in full. Confirm to proceed."
}

# coarse_prepare <text>: the text the coarse regexes read (#981). Joins `\`
# continuations (awk: a sed N loop is quadratic), then blanks quoted spans that
# hold whitespace, so that quoted prose does not read as a command. A span with
# no whitespace is an argument and stays (`git push "origin" "main"`).
#
# A line keeps its spans when one of them may run: it holds a substitution, a
# shell wrapper word, or a flag ending in c before a quote. Spans never cross a
# line. A line that leaves a quote open ends the blanking for good: the state of
# the lines after it is unknown, and what looks like a span between two
# multi-line strings is code. The alternatives of each regex are mutually
# exclusive on purpose: POSIX ERE picks the longest match, not the first.
coarse_prepare() {
    local q="'" d='"' b='\\'
    local keep="${b}.|${q}[^${q}[:space:]]*${q}|${d}([^${d}${b}[:space:]]|${b}.)*${d}"
    local blank="${q}[^${q}]*[[:space:]][^${q}]*${q}|${d}([^${d}${b}]|${b}.)*[[:space:]]([^${d}${b}]|${b}.)*${d}"
    local spans="${b}.|${q}[^${q}]*${q}|${d}([^${d}${b}]|${b}.)*${d}"
    local run="[\$][(]|\`|(^|[^[:alnum:]_.-])(bash|sh|zsh|dash|ksh|fish|eval)[[:space:]]|[[:space:]]-[[:alpha:]]*c[[:space:]]+[${d}${q}]"
    printf '%s\n' "$1" \
        | LC_ALL=C awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
        | LC_ALL=C sed -E "
h
s/${spans}//g
/[${d}${q}]/{
g
:raw
n
braw
}
g
/${run}/!s/(${keep})|${blank}/\\1/g
"
}

# coarse_scan: the deny and ask tiers for input over the tokenizer budget
# (#971). The regexes are line based; a sub-command is the run of text up to
# the next ; & | or newline. Any keyword of an ask arm asks, because the
# arm's own conditions (a dirty work tree, a path outside the repository)
# were not evaluated.
coarse_scan() {
    # A command word start, one sub-command's text, a space, a quote, and the
    # end of a word.
    local W='(^|[^[:alnum:]_.-])' G='[^;&|]*' S='[[:space:]]' Q="[\"']"
    local E="([[:space:]\"';&|)]|\$)"
    local git="${W}git${S}(${G}${S})?"
    local rec="(-[[:alpha:]]*[rR][[:alpha:]]*|--recursive)"
    local rm="${W}rm${S}(${G}${S})?"
    local rmr="${rm}${rec}"
    local home="(~|[\$]HOME|[\$][{]HOME[}])"
    # `git`, its global options as in inspect_git, and `push`: only those or an
    # expansion may come between them, so `git stash push` is not a push.
    local pushed="${W}git(${S}+((-C|-c|--git-dir|--work-tree|--namespace|--super-prefix)${S}+[^[:space:]]+|-[^[:space:]]*|${Q}?[\$][^[:space:]]*))*${S}+push"

    # A command name that cannot be resolved may be rm, as on the tokenized path
    # (#991). It holds no command word, and it must not pre-empt a deny below.
    local unresolved=0
    if coarse_has "$COARSE_TEXT" "(^|[;&|(])${S}*${Q}?[\$][^[:space:]]*${S}+(${G}${S})?${rec}${E}"; then
        unresolved=1
    fi

    # Cheap prefilter: none of the command words, nothing else to scan.
    if ! coarse_has "$COARSE_TEXT" '(rm|git|gh|find)'; then
        [ "$unresolved" = 0 ] || coarse_ask "a command name that cannot be resolved, with a recursive flag"
        return 0
    fi

    # A recursive flag and a denied target, in either order.
    if coarse_has "$COARSE_TEXT" "${rmr}${S}(${G}${S})?${Q}?(${home}(/|${E})|/)" \
        || coarse_has "$COARSE_TEXT" "${rm}${Q}?(${home}(/${G})?${Q}?|/${G})${S}(${G}${S})?${rec}${E}"; then
        deny_response "Dangerous recursive delete at root directory blocked for safety"
    fi

    # One git push per line, cut at a redirection or a comment, without the
    # dry runs: those update nothing (push-target-guard, #782).
    local push
    push=$(printf '%s\n' "$COARSE_TEXT" | LC_ALL=C grep -oE -- "${pushed}(${S}${G}|[)\"']|\$)" 2>/dev/null) || true
    push=$(printf '%s\n' "$push" | LC_ALL=C sed -E \
        -e "s/${S}+([0-9]*[<>]|#).*\$//" \
        -e "/${S}${Q}?(--dry-run|-[[:alpha:]]*n[[:alpha:]]*)${E}/d" \
        -e "s/[)\"']+${S}*\$//") || true

    if coarse_has "$push" "${pushed}${S}(${G}[[:space:]:+\"'])?(refs/heads/)?(main|master|develop)${E}"; then
        deny_response "Direct push to a protected branch (main, master or develop) is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main)."
    fi
    if coarse_has "$COARSE_TEXT" "${W}gh${S}(${G}${S})?repo${S}+delete${E}"; then
        deny_response "gh repo delete deletes a repository irreversibly. Blocked."
    fi
    local api
    api=$(printf '%s\n' "$COARSE_TEXT" | LC_ALL=C grep -oE -- "${W}gh${S}(${G}${S})?api${S}${G}" 2>/dev/null) || true
    api=$(printf '%s\n' "$api" | LC_ALL=C grep -E -- "(-X|--method)(${S}*|=)${Q}?[Dd][Ee][Ll][Ee][Tt][Ee]${E}" 2>/dev/null) || true
    if [ -n "$api" ] && coarse_has "$api" "(^|${S})${Q}?(https?://[^/[:space:]]+/)?(api/v3/)?/*repos/[^/[:space:]]+/[^/[:space:]?\"']+/*([?][^[:space:]]*)?${Q}?${E}"; then
        deny_response "gh api DELETE on repos/<owner>/<repo> deletes the repository itself, irreversibly. Blocked."
    fi

    [ "$unresolved" = 0 ] || coarse_ask "a command name that cannot be resolved, with a recursive flag"

    if coarse_has "$push" "${pushed}${S}(${G}${S})?${Q}?(--force|--delete|-[[:alpha:]]*[fd][[:alpha:]]*|[+:][^[:space:]]+)${E}"; then
        coarse_ask "git push --force / --delete / +<ref> / :<ref>"
    fi
    # No refspec: at most one word after the flags, or a last word that names
    # the current branch. The tokenized path resolves those; this one cannot.
    local flag="((-o|--push-option|--repo|--receive-pack|--exec)${S}+[^[:space:]]+|-[^[:space:]]*)"
    if coarse_has "$push" "${pushed}(${S}+${flag})*(${S}+[^-[:space:]][^[:space:]]*)?(${S}+${flag})*${S}*\$" \
        || coarse_has "$push" "${S}${Q}?(HEAD|@)${S}*\$"; then
        coarse_ask "git push without a refspec (the target is not known)"
    fi

    local -a labels=() res=()
    labels+=("git reset --hard")
    res+=("${git}reset${S}(${G}${S})?--hard${E}")
    labels+=("git checkout -f / --force / -- / .")
    res+=("${git}checkout${S}(${G}${S})?(-f|--force|--|[.]/?)${E}")
    labels+=("git restore")
    res+=("${git}restore${E}")
    labels+=("git switch -f / --force / --discard-changes")
    res+=("${git}switch${S}(${G}${S})?(-f|--force|--discard-changes)${E}")
    labels+=("git clean -")
    res+=("${git}clean${S}+-")
    labels+=("git stash drop / clear")
    res+=("${git}stash${S}+(drop|clear)${E}")
    labels+=("rm -r")
    res+=("${rmr}${E}")
    labels+=("find -delete / -exec rm")
    res+=("${W}find${S}${G}${S}(-delete|-(exec|execdir|ok|okdir)${S}+([^[:space:]]*/)?rm)${E}")
    labels+=("gh <group> delete")
    res+=("${W}gh${S}(${G}${S})?[[:alnum:]-]+${S}+delete(-asset)?${E}")
    labels+=("gh api ... DELETE")
    res+=("${W}gh${S}(${G}${S})?api${S}${G}[Dd][Ee][Ll][Ee][Tt][Ee]")

    local all="" i
    for ((i = 0; i < ${#res[@]}; i++)); do
        all="${all:+$all|}(${res[$i]})"
    done
    coarse_has "$COARSE_TEXT" "$all" || return 0
    for ((i = 0; i < ${#res[@]}; i++)); do
        if coarse_has "$COARSE_TEXT" "${res[$i]}"; then
            coarse_ask "${labels[$i]}"
        fi
    done
}

# Performance guard: the pure-bash tokenizer walks the input character by
# character and bash substring operations are O(n), making the splitter
# effectively O(n^2). For very large inputs (e.g. a 1 MB pasted blob) the
# parser would exceed the 2-second budget, so fall back to a coarse regex
# scan. This trades fine-grained sub-command analysis for a hard latency
# bound: coarse_scan denies the deny-tier shapes and asks on any keyword of
# an ask arm, so a long command cannot hide one of them at its end (#971).
DCG_TOKENIZER_MAX_BYTES="${DCG_TOKENIZER_MAX_BYTES:-16384}"
if [ "${#CMD}" -gt "$DCG_TOKENIZER_MAX_BYTES" ]; then
    COARSE_TEXT=$(coarse_prepare "$CMD") || COARSE_TEXT="$CMD"
    [ -n "$COARSE_TEXT" ] || COARSE_TEXT="$CMD"
    if coarse_has "$COARSE_TEXT" 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/'; then
        deny_response "Dangerous recursive delete at root directory blocked for safety"
    fi
    if coarse_has "$COARSE_TEXT" 'chmod\s+(0?777|a\+rwx|[246][0-9][0-9][0-9])'; then
        deny_response "Dangerous permission change (777/a+rwx) blocked for security"
    fi
    # A wrapper may stand in front of the receiver (#991).
    if coarse_has "$COARSE_TEXT" '(curl|wget)\s.*\|\s*((sudo|doas|env|exec|nohup|command|time)\s+(-\S+\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*)?("?\$\{?(SHELL|BASH)\}?"?|(\S*/)?(sh|bash|zsh|dash|python[23]?|perl|ruby|node))([[:space:];&|)]|$)'; then
        deny_response "Remote script execution via pipe blocked for security"
    fi
    coarse_scan
    allow_with_context "Coarse-scan allow (input exceeds tokenizer budget of ${DCG_TOKENIZER_MAX_BYTES} bytes)"
fi

# --- Tokenizer-based inspection ----------------------------------------------
# Strategy: split the command into sub-commands (respecting quotes and
# substitutions), tokenize each into argv, and check argv[0] (and selected
# argv[1..]) for dangerous patterns. This closes the first-match short-circuit
# bypass where `git status && rm -rf $HOOME` was allowed.
#
# Scope of the rewrite (Issue #476): replace regex-on-string with structural
# inspection at the sub-command level. Strings that merely *contain* dangerous
# text inside quotes (e.g. `echo "rm -rf /"`) are no longer flagged because
# they are argv[N>=1] and not an actual command head.
#
# Inspector protocol: every inspect_* function prints a reason and returns
# 0 (allow), 1 (deny) or 2 (ask). Any deny wins; asks are collected across
# sub-commands so that a later deny still takes precedence.
# -----------------------------------------------------------------------------

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/tokenize-shell.sh
. "$LIB_DIR/tokenize-shell.sh"

# Current payload nesting depth (0 = the command itself) and the directory
# the current sub-command runs in. A `cd` sub-command moves EFF_CWD for the
# sub-commands after it; an empty EFF_CWD means "cannot be known statically".
SCAN_DEPTH=0
EFF_CWD="$HOOK_CWD"

# Variables assigned by earlier sub-commands (`X=value`, `export X=value`,
# `declare X=value`, ...), as parallel arrays because bash 3.2 has no
# associative arrays. A name whose value cannot be known statically is removed
# (#971).
VAR_NAMES=()
VAR_VALUES=()

# 1 while inspecting a command that runs once per input (xargs, find -exec).
EACH_INPUT=0

# strip_compound_syntax: drop the shell grammar around a simple command from the
# caller's array `tokens`: reserved words, grouping, a function head, a case
# pattern, and the `)` that closes a subshell. `for x in a; do rm -rf ~; done`
# reaches the inspectors as `rm -rf ~`. `for` and `select` stay, because their
# words are data. SUBSHELL_OPENS and SUBSHELL_CLOSES count the parentheses, so
# that a `cd` inside a subshell ends with it.
strip_compound_syntax() {
    SUBSHELL_OPENS=0
    SUBSHELL_CLOSES=0
    local t opens closes
    while [ ${#tokens[@]} -gt 0 ]; do
        t="${tokens[0]}"
        case "$t" in
            '$'*) break ;;
            if|then|elif|else|while|until|do|'!'|'{'|coproc)
                tokens=("${tokens[@]:1}")
                ;;
            time)
                # The keyword form; `time make` and `time -o f make` are for
                # strip_wrappers, like /usr/bin/time.
                case "${tokens[1]:-}" in
                    -p) tokens=("${tokens[@]:2}") ;;
                    '{'|'!'|'('*) tokens=("${tokens[@]:1}") ;;
                    *) break ;;
                esac
                ;;
            function)
                tokens=("${tokens[@]:2}")
                [ "${tokens[0]:-}" != '()' ] || tokens=("${tokens[@]:1}")
                ;;
            case)
                [ "${tokens[2]:-}" = in ] || break
                tokens=("${tokens[@]:3}")
                ;;
            '('*')'|*'()')
                # `(pattern)` of a case arm, `(word)`, or `name()`.
                tokens=("${tokens[@]:1}")
                ;;
            '('*)
                SUBSHELL_OPENS=$((SUBSHELL_OPENS + 1))
                t="${t#(}"
                if [ -n "$t" ]; then tokens[0]="$t"; else tokens=("${tokens[@]:1}"); fi
                ;;
            *')')
                # A case pattern. A lone last word is the end of a subshell,
                # which the loop below handles.
                [ ${#tokens[@]} -gt 1 ] || break
                tokens=("${tokens[@]:1}")
                ;;
            *)
                # `name () {`
                [ "${tokens[1]:-}" = '()' ] || break
                tokens=("${tokens[@]:2}")
                ;;
        esac
    done
    while [ ${#tokens[@]} -gt 0 ]; do
        t="${tokens[${#tokens[@]}-1]}"
        case "$t" in
            *')') ;;
            *) break ;;
        esac
        # A balanced word is no closer: `$()`, `name()`, `(a)`.
        opens="${t//[!(]/}"
        closes="${t//[!)]/}"
        [ ${#closes} -gt ${#opens} ] || break
        SUBSHELL_CLOSES=$((SUBSHELL_CLOSES + 1))
        t="${t%)}"
        if [ -n "$t" ]; then
            tokens[${#tokens[@]}-1]="$t"
        else
            tokens=("${tokens[@]:0:${#tokens[@]}-1}")
        fi
    done
    return 0
}

# is_assignment_word <word>: NAME=value, NAME+=value or NAME[i]=value. IFS does
# not count, so that inspect_argv sees it and refuses it.
is_assignment_word() {
    local name="${1%%=*}"
    [ "$name" != "$1" ] || return 1
    name="${name%+}"
    name="${name%%\[*}"
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_]*|IFS) return 1 ;;
    esac
    return 0
}

# skip_wrapper_flags <value flags>: drop the leading flags of the caller's array
# `tokens`. <value flags> lists, between spaces, the flags that take the next
# word as a value. A short cluster reads like getopt: `-nu root` takes root for
# -u, and `-uroot` holds its own value.
skip_wrapper_flags() {
    local values="$1" t c i
    while [ ${#tokens[@]} -gt 0 ]; do
        t="${tokens[0]}"
        case "$t" in
            --)
                tokens=("${tokens[@]:1}")
                return 0
                ;;
            --*=*|-)
                tokens=("${tokens[@]:1}")
                ;;
            --*)
                tokens=("${tokens[@]:1}")
                case "$values" in
                    *" $t "*) [ ${#tokens[@]} -eq 0 ] || tokens=("${tokens[@]:1}") ;;
                esac
                ;;
            -*)
                tokens=("${tokens[@]:1}")
                for ((i = 1; i < ${#t}; i++)); do
                    c="${t:$i:1}"
                    case "$values" in
                        *" -$c "*)
                            if [ "$i" -eq $((${#t} - 1)) ] && [ ${#tokens[@]} -gt 0 ]; then
                                tokens=("${tokens[@]:1}")
                            fi
                            break
                            ;;
                    esac
                done
                ;;
            *) return 0 ;;
        esac
    done
    return 0
}

# strip_wrappers: drop what stands in front of the real command in the caller's
# array `tokens`: assignments, redirections, and known wrappers with their own
# flags, in any number and order. `sudo -u root env X=1 rm -rf ~` reaches the
# inspectors as `rm -rf ~`. Only the words in front go, so it is safe to run this
# twice. Each round drops a word, so it ends. xargs and parallel run the command
# once per input, which EACH_INPUT records. watch and env -S run a string, so it
# becomes a shell payload.
strip_wrappers() {
    local t
    while [ ${#tokens[@]} -gt 0 ]; do
        t="${tokens[0]}"
        if is_assignment_word "$t"; then
            tokens=("${tokens[@]:1}")
            continue
        fi
        case "$t" in
            '<'|'>'|'>>'|'<<<'|[0-9]'<'|[0-9]'>'|[0-9]'>>')
                tokens=("${tokens[@]:2}")
                continue
                ;;
            '<'*|'>'*|[0-9]'<'*|[0-9]'>'*)
                tokens=("${tokens[@]:1}")
                continue
                ;;
        esac
        case "${t##*/}" in
            sudo|doas)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -u -g -h -p -C -r -t -T -U -D -R --user --group --host --prompt --close-from --role --type --command-timeout --other-user --chdir --chroot "
                ;;
            env)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -u -C --unset --chdir "
                # `env -S 'rm -rf ~'`: a command name holds no space.
                case "${tokens[0]:-}" in
                    *' '*) tokens=(sh -c "${tokens[*]}") ;;
                esac
                ;;
            command)
                # `command -v rm` only looks the name up.
                for t in "${tokens[@]:1}"; do
                    case "$t" in
                        -*[vV]*) return 0 ;;
                        -*) ;;
                        *) break ;;
                    esac
                done
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " "
                ;;
            builtin|nohup|chronic|unbuffer|setsid)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " "
                ;;
            nice)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -n --adjustment "
                ;;
            ionice)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -c -n -p --class --classdata --pid "
                ;;
            time)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -o -f --output --format "
                ;;
            stdbuf)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -i -o -e --input --output --error "
                ;;
            exec)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -a "
                ;;
            timeout|gtimeout)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -k -s --kill-after --signal "
                # The duration.
                [ ${#tokens[@]} -eq 0 ] || tokens=("${tokens[@]:1}")
                ;;
            caffeinate)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -t -w "
                ;;
            xargs)
                EACH_INPUT=1
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -I -L -n -P -s -E -d -a --replace --max-lines --max-args --max-procs --max-chars --eof --delimiter --arg-file "
                ;;
            parallel)
                EACH_INPUT=1
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -j -P -a -S --jobs --arg-file --sshlogin --delay --timeout "
                ;;
            watch)
                tokens=("${tokens[@]:1}")
                skip_wrapper_flags " -n --interval "
                [ ${#tokens[@]} -eq 0 ] || tokens=(sh -c "${tokens[*]}")
                ;;
            *) return 0 ;;
        esac
    done
    return 0
}

# --- Path and work tree helpers ----------------------------------------------

# resolve_dir <base> <path>: print the directory <path> names when it runs
# from <base>; print nothing when that cannot be known statically (a
# variable, a substitution, a glob, `cd -`, or an unknown base).
resolve_dir() {
    local base="$1" p="$2"
    case "$p" in
        ''|-|*'$'*|*'`'*|*'*'*|*'?'*) return 0 ;;
        \~) printf '%s\n' "$HOME"; return 0 ;;
        \~/*) printf '%s\n' "$HOME/${p#\~/}"; return 0 ;;
        /*) printf '%s\n' "$p"; return 0 ;;
    esac
    [ -n "$base" ] || return 0
    printf '%s\n' "$base/$p"
}

# normalize_rel <path>: lexically normalize a relative path. Prints "" for
# the starting directory itself and keeps leading ".." segments, so
# "a/../.." prints "..".
normalize_rel() {
    local path="$1" seg out=""
    local -a stack=()
    local IFS='/'
    set -f
    for seg in $path; do
        case "$seg" in
            ''|.) ;;
            ..)
                if [ ${#stack[@]} -gt 0 ] && [ "${stack[${#stack[@]}-1]}" != ".." ]; then
                    stack=("${stack[@]:0:${#stack[@]}-1}")
                else
                    stack+=("..")
                fi
                ;;
            *) stack+=("$seg") ;;
        esac
    done
    set +f
    for seg in ${stack[@]+"${stack[@]}"}; do
        out="${out:+$out/}$seg"
    done
    printf '%s\n' "$out"
}

# is_dir_or_ancestor <normalized-rel-path>: succeeds for "" (the directory
# itself) and for paths made only of ".." segments (one of its ancestors).
is_dir_or_ancestor() {
    [ -z "$1" ] || [[ "$1" =~ ^\.\.(/\.\.)*$ ]]
}

# worktree_state <dir>: prints dirty, clean or norepo; unknown when <dir>
# is empty or missing, so that the caller asks rather than guesses.
worktree_state() {
    local dir="$1" out
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        echo unknown
        return 0
    fi
    if ! out=$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null); then
        echo norepo
        return 0
    fi
    if [ -n "$out" ]; then echo dirty; else echo clean; fi
}

# ask_if_dirty <dir> <what>: ask when the work tree at <dir> has changes or
# cannot be located. Allow on a clean tree, and outside a repository, where
# git itself refuses the command.
ask_if_dirty() {
    local dir="$1" what="$2"
    case "$(worktree_state "$dir")" in
        dirty)
            echo "${what}, and the work tree at ${dir} has some; they cannot be recovered afterwards. Confirm to proceed, or commit or stash them first."
            return 2
            ;;
        unknown)
            echo "${what}, and the work tree it targets cannot be determined statically. Confirm to proceed."
            return 2
            ;;
    esac
    return 0
}

# --- Command inspectors --------------------------------------------------------

inspect_rm() {
    shift
    local has_recursive=0 end_opts=0 t
    local -a targets=()
    for t in "$@"; do
        if [ "$end_opts" = 0 ]; then
            case "$t" in
                --) end_opts=1; continue ;;
                --recursive) has_recursive=1; continue ;;
                --*) continue ;;
                -*)
                    case "$t" in *[rR]*) has_recursive=1 ;; esac
                    continue
                    ;;
            esac
        fi
        targets+=("$t")
    done
    [ "$has_recursive" = 1 ] || return 0

    # Deny: the root, any absolute path, or the home directory.
    for t in ${targets[@]+"${targets[@]}"}; do
        case "$t" in
            /*|\$HOME|\$HOME/*|\$\{HOME\}|\$\{HOME\}/*|\~|\~/*)
                echo "Dangerous recursive delete at root directory blocked for safety"
                return 1
                ;;
        esac
    done

    # Ask: the current directory, a parent, a glob over either, .git, or a
    # path that resolves outside the repository work tree. Outside a work
    # tree only the literal targets apply.
    local n base parent glob info prefix="" repo="unchecked"
    for t in ${targets[@]+"${targets[@]}"}; do
        case "$t" in
            *'$'*|*'`'*|'~'*) continue ;;   # not statically resolvable
        esac
        n=$(normalize_rel "$t")
        base="${n##*/}"
        parent=""
        case "$n" in */*) parent="${n%/*}" ;; esac
        glob=0
        case "$base" in '*'|'.*') glob=1 ;; esac
        if is_dir_or_ancestor "$n" || [ "$base" = ".git" ] \
            || { [ "$glob" = 1 ] && is_dir_or_ancestor "$parent"; }; then
            echo "Recursive delete of '${t}' (the current directory, a parent, a glob over one of them, or .git) cannot be undone. Confirm to proceed."
            return 2
        fi
        if [ "$repo" = "unchecked" ]; then
            repo="no"
            if [ -n "$EFF_CWD" ] && [ -d "$EFF_CWD" ]; then
                info=$(git -C "$EFF_CWD" rev-parse --is-inside-work-tree --show-prefix 2>/dev/null) || info=""
                case "$info" in
                    true*)
                        repo="yes"
                        prefix="${info#true}"
                        prefix="${prefix#$'\n'}"
                        ;;
                esac
            fi
        fi
        [ "$repo" = "yes" ] || continue
        n=$(normalize_rel "${prefix}${t}")
        if [ -z "$n" ] || [ "${n%%/*}" = ".." ]; then
            echo "Recursive delete of '${t}' reaches the repository top level or outside the work tree and cannot be undone. Confirm to proceed."
            return 2
        fi
    done
    return 0
}

inspect_chmod() {
    shift
    local t
    for t in "$@"; do
        # Numeric forms: 777, 0777, and any 4-digit setuid/setgid/sticky.
        if [[ "$t" =~ ^0?777$ ]]; then
            echo "Dangerous permission change (777/a+rwx) blocked for security"
            return 1
        fi
        if [[ "$t" =~ ^[246][0-9][0-9][0-9]$ ]]; then
            echo "Dangerous permission change (setuid/setgid bit) blocked for security"
            return 1
        fi
        # Symbolic forms.
        case "$t" in
            a+rwx|*+rwx)
                echo "Dangerous permission change (777/a+rwx) blocked for security"
                return 1
                ;;
            u+s|g+s|*+s)
                echo "Dangerous permission change (setuid/setgid bit) blocked for security"
                return 1
                ;;
        esac
    done
    return 0
}

inspect_find() {
    shift
    local t i=0 rc reason
    local -a args=("$@") exec_argv
    while [ "$i" -lt "${#args[@]}" ]; do
        t="${args[$i]}"
        i=$((i + 1))
        case "$t" in
            -delete)
                echo "find -delete removes every match permanently. Confirm to proceed, or run the same find with -print first."
                return 2
                ;;
            -exec|-execdir|-ok|-okdir)
                exec_argv=()
                while [ "$i" -lt "${#args[@]}" ]; do
                    t="${args[$i]}"
                    i=$((i + 1))
                    case "$t" in
                        ';'|'+') break ;;
                    esac
                    exec_argv+=("$t")
                done
                rc=0
                reason=$(EACH_INPUT=1 inspect_argv ${exec_argv[@]+"${exec_argv[@]}"}) || rc=$?
                if [ "$rc" != 0 ]; then
                    echo "$reason"
                    return "$rc"
                fi
                ;;
        esac
    done
    return 0
}

is_protected_branch() {
    case "$1" in
        main|master|develop) return 0 ;;
    esac
    return 1
}

# push_default_target <dir>: the branch a refspec-less `git push` updates:
# the current branch's upstream, else the current branch (push-target-guard).
push_default_target() {
    local dir="$1" up
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    up=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    if [ -n "$up" ]; then
        printf '%s\n' "${up#*/}"
    else
        git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true
    fi
}

git_push() {
    local dir="$1"
    shift
    local t force=0 delete=0 dry=0 skip_value=0
    local -a pos=()
    for t in "$@"; do
        if [ "$skip_value" = 1 ]; then
            skip_value=0
            continue
        fi
        case "$t" in
            --force) force=1 ;;
            --delete) delete=1 ;;
            --dry-run) dry=1 ;;
            --repo|--push-option|--receive-pack|--exec|-o) skip_value=1 ;;
            --*) ;;   # includes --force-with-lease and --force-if-includes
            -*)
                case "$t" in *f*) force=1 ;; esac
                case "$t" in *d*) delete=1 ;; esac
                case "$t" in *n*) dry=1 ;; esac
                ;;
            *) pos+=("$t") ;;
        esac
    done
    # A dry run updates nothing (push-target-guard, #782).
    [ "$dry" = 0 ] || return 0

    local -a dsts=()
    local spec dst
    if [ ${#pos[@]} -le 1 ]; then
        dst=$(push_default_target "$dir")
        [ -z "$dst" ] || dsts+=("$dst")
    else
        for spec in "${pos[@]:1}"; do
            case "$spec" in +*) force=1; spec="${spec#+}" ;; esac
            case "$spec" in :*) delete=1 ;; esac
            dst="${spec##*:}"
            if [ "$dst" = "HEAD" ] && [ -n "$dir" ] && [ -d "$dir" ]; then
                dst=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
            fi
            dsts+=("$dst")
        done
    fi

    for dst in ${dsts[@]+"${dsts[@]}"}; do
        dst="${dst#refs/heads/}"
        if is_protected_branch "$dst"; then
            echo "Direct push to protected branch '${dst}' is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main). If you must, push from a work branch instead."
            return 1
        fi
    done

    local reason=""
    if [ "$force" = 1 ]; then
        reason="git push --force overwrites remote history that other clones may depend on; prefer --force-with-lease"
    fi
    if [ "$delete" = 1 ]; then
        reason="${reason:+$reason; }git push --delete (or <remote> :<ref>) deletes a remote ref"
    fi
    if [ -n "$reason" ]; then
        echo "${reason}. Confirm to proceed."
        return 2
    fi
    return 0
}

inspect_git() {
    shift
    local dir="$EFF_CWD"
    # Global options before the subcommand. -C moves the directory the
    # work tree checks run in; an explicit --git-dir/--work-tree makes the
    # target unknowable, which ask_if_dirty treats as "ask".
    while [ $# -gt 0 ]; do
        case "$1" in
            -C)
                [ $# -ge 2 ] || return 0
                dir=$(resolve_dir "$dir" "$2")
                shift 2
                ;;
            --git-dir|--work-tree)
                dir=""
                [ $# -ge 2 ] || return 0
                shift 2
                ;;
            --git-dir=*|--work-tree=*) dir=""; shift ;;
            -c|--namespace|--super-prefix)
                [ $# -ge 2 ] || return 0
                shift 2
                ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    [ $# -gt 0 ] || return 0
    local sub="$1"
    shift
    local t
    case "$sub" in
        reset)
            for t in "$@"; do
                if [ "$t" = "--hard" ]; then
                    ask_if_dirty "$dir" "git reset --hard discards uncommitted changes"
                    return $?
                fi
            done
            ;;
        checkout)
            local i=0
            for t in "$@"; do
                i=$((i + 1))
                case "$t" in
                    -f|--force|.|./)
                        ask_if_dirty "$dir" "git checkout ${t} discards uncommitted changes"
                        return $?
                        ;;
                    --)
                        if [ "$i" -lt $# ]; then
                            ask_if_dirty "$dir" "git checkout -- <path> discards uncommitted changes"
                            return $?
                        fi
                        ;;
                esac
            done
            ;;
        switch)
            # -C / --force-create only moves a branch ref, which the reflog
            # keeps; -m merges the local changes instead of dropping them.
            for t in "$@"; do
                case "$t" in
                    -f|--force|--discard-changes)
                        ask_if_dirty "$dir" "git switch ${t} discards uncommitted changes"
                        return $?
                        ;;
                esac
            done
            ;;
        restore)
            local staged=0 worktree=0
            for t in "$@"; do
                case "$t" in
                    --staged) staged=1 ;;
                    --worktree) worktree=1 ;;
                    --*) ;;
                    -*)
                        case "$t" in *S*) staged=1 ;; esac
                        case "$t" in *W*) worktree=1 ;; esac
                        ;;
                esac
            done
            if [ "$staged" = 1 ] && [ "$worktree" = 0 ]; then
                return 0
            fi
            ask_if_dirty "$dir" "git restore without --staged discards uncommitted changes"
            return $?
            ;;
        clean)
            local force=0 dry=0
            for t in "$@"; do
                case "$t" in
                    --force) force=1 ;;
                    --dry-run) dry=1 ;;
                    --*) ;;
                    -*)
                        case "$t" in *f*) force=1 ;; esac
                        case "$t" in *n*) dry=1 ;; esac
                        ;;
                esac
            done
            if [ "$force" = 1 ] && [ "$dry" = 0 ]; then
                echo "git clean -f permanently deletes untracked files, which git history cannot restore. Confirm to proceed, or preview with git clean -n."
                return 2
            fi
            ;;
        stash)
            for t in "$@"; do
                case "$t" in
                    -*) continue ;;
                    drop|clear)
                        echo "git stash ${t} permanently discards stashed changes. Confirm to proceed."
                        return 2
                        ;;
                    *) return 0 ;;
                esac
            done
            ;;
        push)
            git_push "$dir" "$@"
            return $?
            ;;
    esac
    return 0
}

inspect_gh() {
    shift
    local -a pos=()
    local t method="" expect=""
    for t in "$@"; do
        if [ -n "$expect" ]; then
            [ "$expect" != "method" ] || method="$t"
            expect=""
            continue
        fi
        case "$t" in
            -X|--method) expect="method" ;;
            --method=*) method="${t#--method=}" ;;
            -X*) method="${t#-X}" ;;
            -R|--repo|-H|--header|-f|-F|--field|--raw-field|--input|-q|--jq|-t|--template|--hostname|-p|--preview|--cache)
                expect="value"
                ;;
            -*) ;;
            *) pos+=("$t") ;;
        esac
    done
    local group="${pos[0]:-}" verb="${pos[1]:-}"

    if [ "$group" = "api" ]; then
        case "$method" in
            [Dd][Ee][Ll][Ee][Tt][Ee]) ;;
            *) return 0 ;;
        esac
        local ep="$verb"
        ep=$(printf '%s' "$ep" | sed -E 's#^https?://[^/]+/##; s#^api/v3/##; s#^/+##; s#[?].*$##; s#/+$##')
        if [[ "$ep" =~ ^repos/[^/]+/[^/]+$ ]]; then
            echo "gh api DELETE on ${ep} deletes the repository itself, irreversibly. Blocked."
            return 1
        fi
        echo "gh api DELETE ${ep} irreversibly deletes a GitHub resource. Confirm to proceed."
        return 2
    fi

    if [ "$group" = "repo" ] && [ "$verb" = "delete" ]; then
        echo "gh repo delete deletes a repository irreversibly. Blocked."
        return 1
    fi
    case "$verb" in
        delete|delete-asset)
            echo "gh ${group} ${verb} irreversibly deletes a GitHub resource. Confirm to proceed."
            return 2
            ;;
    esac
    return 0
}

# quotes_balanced <text>: fails when a quote (single, double or $'...')
# is left open, i.e. the text cannot be tokenized reliably.
quotes_balanced() {
    local s="$1" q="" ch next i
    local len=${#s}
    for ((i = 0; i < len; i++)); do
        ch="${s:$i:1}"
        next="${s:$((i + 1)):1}"
        case "$q" in
            "'")
                [ "$ch" != "'" ] || q=""
                ;;
            '"'|"\$'")
                if [ "$ch" = '\' ]; then
                    i=$((i + 1))
                elif [ "$q" = '"' ] && [ "$ch" = '"' ]; then
                    q=""
                elif [ "$q" != '"' ] && [ "$ch" = "'" ]; then
                    q=""
                fi
                ;;
            *)
                if [ "$ch" = '\' ]; then
                    i=$((i + 1))
                elif [ "$ch" = '$' ] && [ "$next" = "'" ]; then
                    q="\$'"
                    i=$((i + 1))
                elif [ "$ch" = "'" ] || [ "$ch" = '"' ]; then
                    q="$ch"
                fi
                ;;
        esac
    done
    [ -z "$q" ]
}

# inspect_payload <label> <text>: run the full inspection on the text a
# shell wrapper evaluates. Fails closed when the text cannot be inspected.
inspect_payload() {
    local label="$1" payload="$2"
    if [ "$SCAN_DEPTH" -ge "$MAX_PAYLOAD_DEPTH" ]; then
        echo "Inline shell payload (${label}) nested deeper than ${MAX_PAYLOAD_DEPTH} levels blocked: not statically inspectable"
        return 1
    fi
    if ! quotes_balanced "$payload"; then
        echo "Inline shell payload (${label}) has unbalanced quotes and cannot be inspected; blocked (fail-closed)"
        return 1
    fi
    SCAN_DEPTH=$((SCAN_DEPTH + 1))
    local out rc=0
    out=$(inspect_command "$payload") || rc=$?
    if [ -n "$out" ]; then
        echo "$out"
    fi
    return "$rc"
}

inspect_eval() {
    shift
    [ $# -gt 0 ] || return 0
    local payload="$1" t
    shift
    for t in "$@"; do
        payload="$payload $t"
    done
    inspect_payload "eval" "$payload"
}

inspect_inline_shell() {
    local sh="$1"
    shift
    local t has_c=0 skip=0
    for t in "$@"; do
        if [ "$skip" = 1 ]; then
            skip=0
            continue
        fi
        case "$t" in
            -o|+o|-O|+O|--rcfile|--init-file) skip=1 ;;
            --) ;;
            --*) ;;
            -*) case "$t" in *c*) has_c=1 ;; esac ;;
            +*) ;;
            *)
                # The first operand is the -c payload, or a script file.
                if [ "$has_c" = 1 ]; then
                    inspect_payload "${sh} -c" "$t"
                    return $?
                fi
                return 0
                ;;
        esac
    done
    return 0
}

# Inspect one sub-command's argv tokens with the protocol above.
inspect_argv() {
    local -a tokens=("$@")
    [ ${#tokens[@]} -eq 0 ] && return 0

    strip_wrappers
    [ ${#tokens[@]} -eq 0 ] && return 0

    local cmd0="${tokens[0]}"

    # A command run with a rebound IFS is trying to fool the parser through
    # field splitting. `while IFS= read -r line` only reads a line verbatim.
    case "$cmd0" in
        IFS=*|IFS+=*)
            case "${tokens[1]:-}" in
                read|readarray|mapfile) return 0 ;;
            esac
            echo "Suspicious IFS reassignment in command scope"
            return 1
            ;;
    esac

    # An unquoted `$(...)/rm` arrives as `$()` and `/rm`: the path is the head.
    if [ "$cmd0" = '$()' ]; then
        case "${tokens[1]:-}" in
            /*)
                tokens=("${tokens[@]:1}")
                cmd0="${tokens[0]}"
                ;;
        esac
    fi

    # A path after an expansion (`$X/bin/rm`, `"$(...)/rm"`) leaves a plain
    # basename, which is matched below. Anything else is no command name:
    # `${X:-/bin/rm}` would read as `rm}`.
    local base="${cmd0##*/}"
    case "$cmd0" in
        '$('*|'`'*)
            # The substituted command was split out and inspected on its own,
            # but the outer arguments were not.
            case "$base" in
                *'$'*|*'`'*)
                    inspect_unresolved_head '$(...)' "${tokens[@]:1}"
                    return $?
                    ;;
            esac
            ;;
        '$'*)
            # Inside a payload, a command head that is a parameter expansion
            # runs text this guard cannot see (`bash -c "$X"`, `eval "$X"`).
            # Fail closed, as the blanket wrapper deny did.
            if [ "$SCAN_DEPTH" -gt 0 ]; then
                echo "Inline shell payload runs a variable expansion (${cmd0}) that cannot be statically inspected; blocked (fail-closed)"
                return 1
            fi
            # Outside a payload, resolve a variable head (#971). A tracked value
            # holds no expansion, so another one can only come from a word of
            # the command itself, and this ends (`X=sudo; $X $SHELL -c ...`).
            case "$base" in
                *'$'*|*'}'*|*'`'*)
                    inspect_var_head "${tokens[@]}"
                    return $?
                    ;;
            esac
            ;;
    esac

    # Match on the basename so `/bin/rm` and `/usr/bin/git` are inspected too.
    case "$base" in
        eval) inspect_eval "${tokens[@]}" ;;
        bash|sh|zsh|dash|ksh|fish) inspect_inline_shell "${tokens[@]}" ;;
        rm)
            inspect_rm "${tokens[@]}" || return $?
            if [ "$EACH_INPUT" = 1 ]; then
                echo "rm through xargs, parallel or find -exec removes every input permanently. Confirm to proceed, or list the inputs first."
                return 2
            fi
            return 0
            ;;
        chmod) inspect_chmod "${tokens[@]}" ;;
        git) inspect_git "${tokens[@]}" ;;
        find) inspect_find "${tokens[@]}" ;;
        gh) inspect_gh "${tokens[@]}" ;;
        *) return 0 ;;
    esac
}

# Cross-subcommand pattern: detect "fetch | shell-interpreter" by looking at
# the sequence of sub-commands. The splitter places the curl/wget on one line
# and the receiving interpreter on the next; it also emits a substitution's
# inner command before its outer command, so `eval "$(curl ...)"` and
# `source <(curl ...)` reach this check as curl followed by eval/source.
# is_fetch <sub-command> <head>
is_fetch() {
    case "${2##*/}" in
        curl|wget) return 0 ;;
    esac
    case "$1" in
        curl*|*' curl '*|*' curl'|wget*|*' wget '*|*' wget') return 0 ;;
    esac
    return 1
}

# fetch_receiver <head>: the verdict on the command after a fetch, with the
# wrappers already gone from <head>.
fetch_receiver() {
    local refused="Remote script execution via pipe blocked for security"
    case "$1" in
        '$SHELL'|'${SHELL}'|'$BASH'|'${BASH}')
            echo "$refused"
            return 1
            ;;
    esac
    case "${1##*/}" in
        sh|bash|zsh|dash|ksh|python|python2|python3|perl|ruby|node|eval|source|.)
            echo "$refused"
            return 1
            ;;
    esac
    case "$1" in
        '$'*|'`'*)
            echo "A download reaches a command name that cannot be resolved (${1}); if it is a shell, this is remote execution. Confirm to proceed."
            return 2
            ;;
    esac
    return 0
}

# Recursively flatten sub-commands: a single splitter pass leaves the
# *inner* contents of `$(...)`, `<(...)`, and backticks intact (e.g. the
# splitter emits `curl X | bash` as one line when it appears inside a
# subshell). Walk the output and re-split until idempotent so chained
# fetch-pipe-shell payloads inside substitutions are detected.
flatten_subcommands() {
    local cmd="$1"
    local current_lines next_lines
    current_lines=$(split_subcommands "$cmd")
    while :; do
        next_lines=""
        local changed=0
        local line
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local sub
            sub=$(split_subcommands "$line")
            # If a sub-line splits into multiple lines, mark changed.
            if [ "$(printf '%s\n' "$sub" | wc -l)" -gt 1 ]; then
                changed=1
            fi
            next_lines+="${sub}"$'\n'
        done <<<"$current_lines"
        current_lines="$next_lines"
        [ "$changed" -eq 0 ] && break
    done
    printf '%s' "$current_lines"
}

# track_cd <argv...>: move EFF_CWD for a `cd`/`pushd` sub-command so that the
# work tree checks of later sub-commands look at the right directory.
track_cd() {
    shift
    local t target=""
    for t in "$@"; do
        case "$t" in
            -P|-L|-e|-@|--) continue ;;
            *) target="$t"; break ;;
        esac
    done
    if [ -z "$target" ]; then
        EFF_CWD="$HOME"
    else
        EFF_CWD=$(resolve_dir "$EFF_CWD" "$target")
    fi
}

# var_lookup <name>: print the tracked value of <name>; fails when untracked.
var_lookup() {
    local i
    for ((i = 0; i < ${#VAR_NAMES[@]}; i++)); do
        if [ "${VAR_NAMES[$i]}" = "$1" ]; then
            printf '%s\n' "${VAR_VALUES[$i]}"
            return 0
        fi
    done
    return 1
}

# var_forget <name>: stop tracking <name>.
var_forget() {
    local i
    for ((i = 0; i < ${#VAR_NAMES[@]}; i++)); do
        [ "${VAR_NAMES[$i]}" != "$1" ] || VAR_NAMES[i]=""
    done
    return 0
}

# track_assign <NAME=value>: record the value, or forget NAME when the value
# still holds an expansion (`$`, `$(`, a backtick), is an array (a value that
# starts with an opening parenthesis) or is an append (+=).
track_assign() {
    local name="${1%%=*}" value="${1#*=}" known=1 i
    case "$name" in *+) name="${name%+}"; known=0 ;; esac
    case "$name" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 0 ;; esac
    case "$value" in *'$'*|*'`'*|'('*) known=0 ;; esac
    for ((i = 0; i < ${#VAR_NAMES[@]}; i++)); do
        if [ "${VAR_NAMES[$i]}" = "$name" ]; then
            [ "$known" = 1 ] || VAR_NAMES[i]=""
            VAR_VALUES[i]="$value"
            return 0
        fi
    done
    if [ "$known" = 1 ]; then
        VAR_NAMES+=("$name")
        VAR_VALUES+=("$value")
    fi
    return 0
}

# track_vars <argv...>: record the assignments of an assignment-only
# sub-command or of `export|declare|local|readonly|typeset NAME=value ...`,
# and forget what `unset NAME` removes (`unset -f NAME` removes a function).
track_vars() {
    local t forget=0
    case "$1" in
        unset)
            shift
            for t in "$@"; do
                case "$t" in -*f*) return 0 ;; esac
            done
            for t in "$@"; do
                case "$t" in -*) ;; *) var_forget "$t" ;; esac
            done
            return 0
            ;;
        export)
            shift
            ;;
        declare|local|readonly|typeset)
            shift
            # An array, a nameref or a case-converting variable does not hold
            # its literal value.
            for t in "$@"; do
                case "$t" in -*[aAnlu]*) forget=1 ;; esac
            done
            ;;
        *)
            # An array value may be split over words (`X=(rm -rf)`), so forget
            # it even though the other words are no assignments.
            local only=1
            for t in "$@"; do
                case "$t" in
                    *=*) case "${t#*=}" in '('*) track_assign "$t" ;; esac ;;
                    *) only=0 ;;
                esac
            done
            [ "$only" = 1 ] || return 0
            ;;
    esac
    for t in "$@"; do
        case "$t" in
            -*|+*) ;;
            *=*)
                if [ "$forget" = 1 ]; then var_forget "${t%%=*}"; else track_assign "$t"; fi
                ;;
            *) [ "$forget" = 0 ] || var_forget "$t" ;;
        esac
    done
    return 0
}

# inspect_unresolved_head <head> <args...>: nothing says what <head> runs, but
# it may be rm or a shell. Ask when the arguments would make rm refuse, or when
# the operand of a flag ending in c would make a shell refuse. The c must come
# last: `$TAR -cf "$archive" dir` has no payload. Everything else stays allowed
# (`$EDITOR file`, `"$PYTHON" x.py`, `$(date)`).
inspect_unresolved_head() {
    local head="$1" reason rc=0
    shift
    reason=$(inspect_rm rm "$@") || rc=$?
    if [ "$rc" != 0 ]; then
        echo "The command name comes from ${head}, which cannot be resolved statically; as rm this command would be refused (${reason}). Confirm to proceed."
        return 2
    fi
    while [ $# -gt 0 ]; do
        if [[ "$1" =~ ^-[A-Za-z]*c$ ]]; then
            shift
            reason=$(inspect_inline_shell "$head" -c "$@") || rc=$?
            [ "$rc" != 0 ] || return 0
            echo "The command name comes from ${head}, which cannot be resolved statically; if it is a shell, this payload would be refused (${reason}). Confirm to proceed."
            return 2
        fi
        shift
    done
    return 0
}

# inspect_var_head <argv...>: argv[0] is an expansion outside a payload. A
# tracked `$NAME` / `${NAME}`, or the literal default of `${NAME:-word}`, is
# replaced by its words and inspected. Otherwise `$SHELL` and `$BASH` name
# a shell by definition and get its decision, and any other head is unresolved.
inspect_var_head() {
    local head="$1" name="" op="" word="" value="" known=0 w
    shift
    local re='^\$\{([A-Za-z_][A-Za-z0-9_]*)(:?[-=])(.*)\}$'
    if [[ "$head" =~ $re ]]; then
        name="${BASH_REMATCH[1]}"
        op="${BASH_REMATCH[2]}"
        word="${BASH_REMATCH[3]}"
    else
        case "$head" in
            '${'*'}') name="${head:2:${#head}-3}" ;;
            '$'*) name="${head:1}" ;;
        esac
        case "$name" in ''|[0-9]*|*[!A-Za-z0-9_]*) name="" ;; esac
    fi
    if [ -n "$name" ] && value=$(var_lookup "$name"); then
        known=1
    fi
    # `:-` and `:=` also take the word when the variable is empty. An empty
    # word says nothing about what runs when the variable is set.
    case "$op" in :*) [ -n "$value" ] || known=0 ;; esac
    if [ -n "$op" ] && [ "$known" = 0 ]; then
        case "$word" in
            ''|*'$'*|*'`'*) ;;
            *)
                value="$word"
                known=1
                ;;
        esac
    fi
    if [ "$known" = 1 ]; then
        local -a words=()
        set -f
        for w in $value; do words+=("$w"); done
        set +f
        inspect_argv ${words[@]+"${words[@]}"} "$@"
        return $?
    fi
    case "$head" in
        '$SHELL'|'${SHELL}'|'$BASH'|'${BASH}')
            inspect_inline_shell "$head" "$@"
            return $?
            ;;
    esac
    inspect_unresolved_head "$head" "$@"
}

# add_ask <reason>: collect an ask in the caller's `asks`, once.
add_ask() {
    case "; $asks; " in
        *"; $1; "*) ;;
        *) asks="${asks:+$asks; }$1" ;;
    esac
}

# Run inspection across every sub-command. A deny short-circuits; asks are
# collected and reported only when nothing denies.
inspect_command() {
    # A backslash-newline is no separator: `rm \<newline>-rf ~` is one command.
    local continuation=$'\\\n'
    local cmd="${1//"$continuation"/}"
    local asks="" sub rc reason head t k
    local prev_fetch=0 prev2_fetch=0 this_fetch
    # A payload of `xargs sh -c '...'` runs once per input as well.
    local each_input="$EACH_INPUT"
    local -a cwd_stack=()
    while IFS= read -r sub; do
        [ -z "$sub" ] && continue

        # Structural: any token that originally embedded ${IFS}/$IFS is
        # almost certainly an obfuscation. Flag at sub-command level.
        case "$sub" in
            *'${IFS}'*|*'$IFS'*)
                echo "Suspicious IFS-based whitespace obfuscation in command"
                return 1
                ;;
        esac

        # Tokenize this sub-command into argv, without the shell grammar.
        local -a tokens=()
        while IFS= read -r t; do
            tokens+=("$t")
        done < <(tokenize_argv "$sub")
        strip_compound_syntax
        local -a argv=(${tokens[@]+"${tokens[@]}"})

        # The command behind any wrappers receives a fetch.
        EACH_INPUT="$each_input"
        strip_wrappers
        head="${tokens[0]:-}"

        # Cross-subcommand: fetch piped to interpreter. The inner command of a
        # substitution stands between a fetch and a `$(...)` receiver.
        rc=0
        reason=""
        if [ "$prev_fetch" = 1 ]; then
            reason=$(fetch_receiver "$head") || rc=$?
        elif [ "$prev2_fetch" = 1 ]; then
            case "$head" in
                '$('*|'`'*) reason=$(fetch_receiver "$head") || rc=$? ;;
            esac
        fi
        case "$rc" in
            0) ;;
            2) add_ask "$reason" ;;
            *)
                echo "$reason"
                return 1
                ;;
        esac
        prev2_fetch="$prev_fetch"
        this_fetch=0
        if is_fetch "$sub" "$head"; then this_fetch=1; fi
        prev_fetch="$this_fetch"

        for ((k = 0; k < SUBSHELL_OPENS; k++)); do
            cwd_stack+=("$EFF_CWD")
        done

        case "${argv[0]:-}" in
            cd|pushd) track_cd "${argv[@]}" ;;
            export|declare|local|readonly|typeset|unset|*=*) track_vars "${argv[@]}" ;;
        esac

        rc=0
        reason=$(inspect_argv ${argv[@]+"${argv[@]}"}) || rc=$?
        case "$rc" in
            0) ;;
            2) add_ask "$reason" ;;
            *)
                echo "${reason:-dangerous-command-guard: inspection failed (fail-closed)}"
                return 1
                ;;
        esac

        # A subshell's `cd` ends with it.
        for ((k = 0; k < SUBSHELL_CLOSES; k++)); do
            [ ${#cwd_stack[@]} -gt 0 ] || break
            EFF_CWD="${cwd_stack[${#cwd_stack[@]}-1]}"
            cwd_stack=("${cwd_stack[@]:0:${#cwd_stack[@]}-1}")
        done
    done < <(flatten_subcommands "$cmd")
    if [ -n "$asks" ]; then
        echo "$asks"
        return 2
    fi
    return 0
}

RC=0
REASON=$(inspect_command "$CMD") || RC=$?
case "$RC" in
    0) allow_response ;;
    2) ask_response "$REASON" ;;
    *) deny_response "${REASON:-dangerous-command-guard: inspection failed (fail-closed)}" ;;
esac
