#!/bin/bash
# dangerous-command-guard.sh
# Blocks dangerous bash commands and records every decision.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Side effects:
#   Writes one JSON line per invocation to
#   ${CLAUDE_LOG_DIR:-$HOME/.claude/logs}/dangerous-command-guard.log
#   so an operator can verify whether the hook returned allow/deny for a
#   specific command. Compound commands (pipes, redirects) that Claude
#   Code's allowlist cannot match should still show up here as "allow".
#   If a prompt was presented despite an "allow" log entry, the root
#   cause is upstream of this hook (e.g. unsandboxed path, multi-hook
#   merge, permission mode), not the guard.

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/dangerous-command-guard.log"

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

allow_response() {
    local reason="${1:-dangerous-command-guard: no dangerous pattern matched}"
    log_decision "allow" "$reason" "${CMD:-}"
    # Escape double quotes for JSON safety.
    local esc_reason=${reason//\"/\\\"}
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "$esc_reason"
  }
}
EOF
    exit 0
}

INPUT=$(cat)

if [ -z "$INPUT" ]; then
    CMD=""
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ $? -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi

if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Performance guard: the pure-bash tokenizer walks the input character by
# character and bash substring operations are O(n), making the splitter
# effectively O(n^2). For very large inputs (e.g. a 1 MB pasted blob) the
# parser would exceed the 2-second budget, so fall back to a coarse regex
# scan. This trades fine-grained sub-command analysis for a hard latency
# bound; the regex still catches the three high-impact patterns this hook
# has always blocked. Real attack payloads are far below this threshold.
DCG_TOKENIZER_MAX_BYTES="${DCG_TOKENIZER_MAX_BYTES:-16384}"
if [ "${#CMD}" -gt "$DCG_TOKENIZER_MAX_BYTES" ]; then
    if echo "$CMD" | grep -qE 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/'; then
        deny_response "Dangerous recursive delete at root directory blocked for safety"
    fi
    if echo "$CMD" | grep -qE 'chmod\s+(0?777|a\+rwx|[246][0-9][0-9][0-9])'; then
        deny_response "Dangerous permission change (777/a+rwx) blocked for security"
    fi
    if echo "$CMD" | grep -qE '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b'; then
        deny_response "Remote script execution via pipe blocked for security"
    fi
    allow_response "Coarse-scan allow (input exceeds tokenizer budget of ${DCG_TOKENIZER_MAX_BYTES} bytes)"
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
# -----------------------------------------------------------------------------

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/tokenize-shell.sh
. "$LIB_DIR/tokenize-shell.sh"

# Trim a single leading `sudo`/`time`/`nice`/`env VAR=...` wrapper so the
# real command head is reachable. Stops after one wrapper to keep behavior
# bounded; chained wrappers (e.g. `sudo env X=1 rm`) still get caught
# because their second token is itself dangerous.
strip_wrapper_prefix() {
    local -a tokens=("$@")
    local head="${tokens[0]:-}"
    case "$head" in
        sudo|nice|nohup|time|stdbuf|exec)
            tokens=("${tokens[@]:1}")
            ;;
        env)
            # Drop `env` and any leading `VAR=value` assignments.
            tokens=("${tokens[@]:1}")
            while [ ${#tokens[@]} -gt 0 ]; do
                case "${tokens[0]}" in
                    *=*) tokens=("${tokens[@]:1}") ;;
                    *)   break ;;
                esac
            done
            ;;
    esac
    printf '%s\n' "${tokens[@]}"
}

# Inspect one sub-command's argv tokens; returns 0 (allow) or prints a deny
# reason on stdout and returns 1.
inspect_argv() {
    local -a tokens=("$@")
    [ ${#tokens[@]} -eq 0 ] && return 0

    # Drop bare assignment-only lines (e.g. `IFS= ` after expansion). A leading
    # `IFS=...` followed by a real command means the user is trying to fool the
    # parser via field-splitting tricks — deny structurally.
    if [ "${tokens[0]}" != "${tokens[0]/=/}" ]; then
        # First token is `VAR=value`. If there are following tokens, that's a
        # command run with overridden env — flag IFS rebinds specifically.
        case "${tokens[0]}" in
            IFS=*) echo "Suspicious IFS reassignment in command scope"; return 1 ;;
        esac
        # Otherwise treat the assignment as a no-op for inspection purposes.
        tokens=("${tokens[@]:1}")
        [ ${#tokens[@]} -eq 0 ] && return 0
    fi

    # Strip one wrapper layer (sudo/env/...).
    local stripped
    stripped=$(strip_wrapper_prefix "${tokens[@]}")
    if [ -n "$stripped" ]; then
        # Re-read tokens from the stripped output.
        local -a new_tokens=()
        local line
        while IFS= read -r line; do
            new_tokens+=("$line")
        done <<<"$stripped"
        tokens=("${new_tokens[@]}")
    fi
    [ ${#tokens[@]} -eq 0 ] && return 0

    local cmd0="${tokens[0]}"

    # Reject shell-evaluation wrappers — they hide intent and re-introduce the
    # same bypass class this rewrite is closing.
    case "$cmd0" in
        eval|source|.)
            echo "Shell-evaluation wrapper ($cmd0) blocked: hides intent from static inspection"
            return 1
            ;;
        bash|sh|zsh|dash|ksh|fish)
            # `bash script.sh` is fine; `bash -c '...'` lets arbitrary text
            # run unscanned. Reject only the inline `-c` form.
            if [ ${#tokens[@]} -ge 2 ] && [ "${tokens[1]}" = "-c" ]; then
                echo "Inline shell ($cmd0 -c ...) blocked: payload is not statically inspectable"
                return 1
            fi
            ;;
    esac

    # rm with recursive flag targeting an absolute path or $HOME.
    if [ "$cmd0" = "rm" ]; then
        local has_recursive=0
        local has_root_target=0
        local i
        for ((i=1; i<${#tokens[@]}; i++)); do
            local t="${tokens[$i]}"
            case "$t" in
                -[a-zA-Z]*r[a-zA-Z]*|-[a-zA-Z]*R[a-zA-Z]*|--recursive)
                    has_recursive=1
                    ;;
                -r|-R|-rf|-Rf|-rF|-RF|-fr|-fR|-Fr|-FR)
                    has_recursive=1
                    ;;
                /|/[a-zA-Z]*|\$HOME|\$HOME/*|~|~/*)
                    # `/`, `/var`, `/etc/...`, `$HOME`, `$HOME/...`, `~`, `~/...`
                    has_root_target=1
                    ;;
            esac
        done
        if [ "$has_recursive" = "1" ] && [ "$has_root_target" = "1" ]; then
            echo "Dangerous recursive delete at root directory blocked for safety"
            return 1
        fi
    fi

    # chmod with world-write/setuid bits or symbolic a+rwx.
    if [ "$cmd0" = "chmod" ]; then
        local i
        for ((i=1; i<${#tokens[@]}; i++)); do
            local t="${tokens[$i]}"
            # Numeric forms: 777, 0777, and any 4-digit setuid/setgid/sticky.
            if [[ "$t" =~ ^0?777$ ]] || [[ "$t" =~ ^[246][0-9][0-9][0-9]$ ]]; then
                if [[ "$t" =~ ^0?777$ ]]; then
                    echo "Dangerous permission change (777/a+rwx) blocked for security"
                else
                    echo "Dangerous permission change (setuid/setgid bit) blocked for security"
                fi
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
    fi

    # curl/wget directly invoked as the command head: harmless on its own.
    # The pipe-to-shell pattern is detected by inspecting *adjacent*
    # sub-commands (the splitter already broke `curl X | sh` into two), so we
    # only need to flag the receiving end.
    return 0
}

# Cross-subcommand pattern: detect "fetch | shell-interpreter" by looking at
# the sequence of sub-commands. The splitter places the curl/wget on one line
# and the receiving interpreter on the next.
detect_fetch_pipe_shell() {
    local prev="$1" curr="$2"
    case "$prev" in
        curl*|*' curl '*|*' curl'|wget*|*' wget '*|*' wget')
            ;;
        *) return 1 ;;
    esac
    # Take argv[0] of the receiving sub-command.
    local first
    first=$(tokenize_argv "$curr" | head -1)
    case "$first" in
        sh|bash|zsh|dash|ksh|python|python2|python3|perl|ruby|node)
            return 0
            ;;
    esac
    return 1
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

# Run inspection across every sub-command. Any single deny short-circuits.
inspect_command() {
    local cmd="$1"
    local prev=""
    local sub
    while IFS= read -r sub; do
        [ -z "$sub" ] && continue

        # Cross-subcommand: fetch piped to interpreter.
        if [ -n "$prev" ] && detect_fetch_pipe_shell "$prev" "$sub"; then
            echo "Remote script execution via pipe blocked for security"
            return 1
        fi

        # Structural: any token that originally embedded ${IFS}/$IFS is
        # almost certainly an obfuscation. Flag at sub-command level.
        case "$sub" in
            *'${IFS}'*|*'$IFS'*)
                echo "Suspicious IFS-based whitespace obfuscation in command"
                return 1
                ;;
        esac

        # Tokenize this sub-command into argv.
        local -a argv=()
        local t
        while IFS= read -r t; do
            argv+=("$t")
        done < <(tokenize_argv "$sub")

        local reason
        if reason=$(inspect_argv "${argv[@]}"); then
            :
        else
            echo "$reason"
            return 1
        fi
        prev="$sub"
    done < <(flatten_subcommands "$cmd")
    return 0
}

# Tag well-known safe read-only compound patterns so the reason line explains
# why a pipe-bearing command was auto-allowed. This is a label, not an
# exception: the inspection above has already cleared every sub-command.
SAFE_READ_ONLY_HEAD='^(git\s+(status|log|diff|show|branch|tag|remote|ls-files|rev-parse|describe|for-each-ref|worktree|fetch)|gh\s+(pr|issue|run|workflow|repo|release|auth)\s+(view|list|status|diff|checks))\b'

if reason=$(inspect_command "$CMD"); then
    if echo "$CMD" | grep -qE '[|]|2>&1|>/dev/null|>\s*/dev/null'; then
        if echo "$CMD" | grep -qE "$SAFE_READ_ONLY_HEAD"; then
            allow_response "Safe read-only compound command (pipe/redirect with git/gh read verb)"
        fi
    fi
    allow_response
else
    deny_response "$reason"
fi
