#!/bin/bash
# bash-sensitive-read-guard.sh
# Blocks reading sensitive files via the Bash tool channel.
#
# The Edit/Write/Read PreToolUse matchers already gate Edit/Write/Read tool
# calls against `permissions.deny`. The Bash channel was previously
# unguarded, so `cat .env`, `grep AWS_SECRET ~/.aws/credentials`, and
# `find / -name '.env' -exec cat {} \;` could exfiltrate secrets without a
# prompt. This hook closes that gap.
#
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Strategy
# --------
# 1. Parse the command into sub-commands (respecting quotes/substitutions
#    via lib/tokenize-shell.sh — same library as dangerous-command-guard).
# 2. For each sub-command, identify well-known read tools.
# 3. Extract their file-path arguments (skipping flags and -exec sentinels).
# 4. Resolve `~`, `$HOME`, and relative paths via realpath when possible
#    (defeats Red Team Vector F: symlink-to-secret race).
# 5. Match the resolved path against the sensitive deny patterns.
# 6. Deny on match; fall through to allow otherwise.

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
#   Expand ~ and $HOME, then resolve symlinks via realpath when available.
resolve_path() {
    local p="$1"
    [ -z "$p" ] && return 0
    # Expand $HOME and ~ at the start of the path. The single-quoted
    # patterns inside ${p#'...'} are required because some bash builds
    # tilde-expand the unquoted form, leaving a literal `~` in the result
    # and producing nonsense like `/Users/x/~/.ssh/id_rsa`.
    case "$p" in
        '~')         p="${HOME:-$p}" ;;
        '~/'*)       p="${HOME}/${p#'~/'}" ;;
        '$HOME')     p="${HOME:-$p}" ;;
        '$HOME/'*)   p="${HOME}/${p#'$HOME/'}" ;;
    esac
    local resolved
    if command -v realpath >/dev/null 2>&1; then
        # GNU coreutils realpath accepts -m for missing paths; macOS BSD
        # does not. Try the unflagged form first.
        resolved=$(realpath "$p" 2>/dev/null) || resolved=""
    fi
    if [ -z "$resolved" ]; then
        # Fallback: resolve the parent directory and reattach the basename.
        # Defeats Red Team Vector F when the link target exists, even when
        # the link itself was created against a missing path.
        local parent base
        parent=$(dirname "$p")
        base=$(basename "$p")
        if [ -d "$parent" ] && command -v realpath >/dev/null 2>&1; then
            local rp
            rp=$(realpath "$parent" 2>/dev/null) || rp="$parent"
            resolved="${rp%/}/$base"
        else
            resolved=$(printf '%s' "$p" | sed -e 's://*:/:g' -e 's:/$::')
        fi
    fi
    printf '%s' "$resolved"
}

# is_sensitive <path>
#   Returns 0 if the resolved path matches any sensitive pattern.
#   Patterns mirror permissions.deny[] in global/settings.json.
is_sensitive() {
    local p="$1"
    [ -z "$p" ] && return 1
    # Lowercase for case-insensitive directory match (secrets/Secrets).
    local lower
    lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')

    # .env, .env.*, including dotted suffix variants.
    case "$p" in
        */.env|*.env|*/.env.*|*.env.*)
            return 0 ;;
    esac
    # SSH private keys and well-known credential filenames.
    case "$p" in
        */.ssh/id_*|*/.ssh/*_rsa|*/.ssh/*_dsa|*/.ssh/*_ecdsa|*/.ssh/*_ed25519)
            return 0 ;;
        */.aws/credentials|*/.aws/config)
            return 0 ;;
        */.gnupg/*|*/.gnupg)
            return 0 ;;
        */.netrc|*/.npmrc|*/.pypirc|*/.dockerconfigjson|*/.docker/config.json)
            return 0 ;;
        */.kube/config)
            return 0 ;;
    esac
    # Cryptographic material by extension.
    case "$lower" in
        *.pem|*.key|*.p12|*.pfx|*.crt|*.cer)
            return 0 ;;
    esac
    # Sensitive directory tokens anywhere in the path. Match both
    # absolute (`/foo/secrets/bar`) and relative (`secrets/bar`) forms.
    case "$lower" in
        */secrets/*|*/credentials/*|*/passwords/*) return 0 ;;
        secrets/*|credentials/*|passwords/*)      return 0 ;;
        *password*)                                return 0 ;;
    esac
    # Bare credential filenames — e.g. `find -name id_rsa` exposes the
    # filename without a `.ssh/` prefix; treat the bare names as sensitive
    # so a deliberate search for them is also flagged.
    case "$p" in
        id_rsa|id_dsa|id_ecdsa|id_ed25519|*/id_rsa|*/id_dsa|*/id_ecdsa|*/id_ed25519)
            return 0 ;;
        credentials|*/credentials)
            return 0 ;;
    esac
    # System credential files. The `*/etc/...` variants catch macOS where
    # realpath resolves /etc to /private/etc.
    case "$p" in
        /etc/shadow|/etc/sudoers|/etc/sudoers.d/*|/etc/ssh/ssh_host_*_key) return 0 ;;
        */etc/shadow|*/etc/sudoers|*/etc/sudoers.d/*|*/etc/ssh/ssh_host_*_key) return 0 ;;
    esac
    return 1
}

# extract_read_paths <argv...>
#   For a known read-tool argv, emit each candidate file-path argument on
#   its own line. Skips flags and conservative -exec/-execdir sentinels for
#   `find`. Best-effort: false negatives are preferred over false positives
#   for non-read tokens.
extract_read_paths() {
    local cmd0="$1"
    shift
    local skip_next=0
    local in_find_exec=0
    local grep_pattern_seen=0
    local arg
    for arg in "$@"; do
        if [ "$skip_next" = "1" ]; then
            skip_next=0
            continue
        fi
        case "$cmd0" in
            grep|egrep|fgrep|rg)
                # grep [-flags] PATTERN PATH... — the first non-flag arg
                # is the pattern (when -e is not used) and must NOT be
                # treated as a path. Subsequent non-flag args are paths.
                case "$arg" in
                    -e|--regexp|-f|--file|--include|--exclude|--include-dir|--exclude-dir)
                        # `-e PATTERN` — the next arg is a pattern, not a path.
                        skip_next=1
                        grep_pattern_seen=1
                        continue ;;
                    -*)
                        continue ;;
                esac
                if [ "$grep_pattern_seen" = "0" ]; then
                    grep_pattern_seen=1
                    continue
                fi
                printf '%s\n' "$arg"
                continue
                ;;
            find)
                # find PATH... [predicates]. After the first predicate flag,
                # subsequent paths are usually arguments to predicates, not
                # search roots — but we still want to flag the explicit
                # -path/-name/-iname target file when it points at a secret.
                case "$arg" in
                    -exec|-execdir|-ok|-okdir)
                        in_find_exec=1; continue ;;
                    \;|+)
                        in_find_exec=0; continue ;;
                esac
                if [ "$in_find_exec" = "1" ]; then
                    # The argv inside -exec/-execdir is itself a command —
                    # the tokenizer will surface it as a separate sub-command
                    # only if the user used a shell metachar, so inspect
                    # known sub-commands ourselves: `cat {}` is fine because
                    # `{}` is not a literal sensitive path; the dangerous
                    # case is `-exec cat /etc/shadow` which we do flag.
                    case "$arg" in
                        \{\}) continue ;;
                        -*)   continue ;;
                    esac
                    printf '%s\n' "$arg"
                    continue
                fi
                case "$arg" in
                    -*) continue ;;
                esac
                printf '%s\n' "$arg"
                continue
                ;;
            tar)
                # `tar c FILE...` — emit each non-flag path. Strip leading
                # `-c` / `c` mode token.
                case "$arg" in
                    c|cv|cvf|cf|czf|cjf|cJf|tf|tvf|xf|xvf|xzf|xjf)
                        # Mode flag — next non-flag is archive name (skip).
                        skip_next=1; continue ;;
                    -[a-zA-Z]*) continue ;;
                esac
                printf '%s\n' "$arg"
                continue
                ;;
            *)
                # Generic: treat any non-flag token as a candidate path.
                case "$arg" in
                    -*) continue ;;
                esac
                printf '%s\n' "$arg"
                ;;
        esac
    done
}

# inspect_subcommand <subcommand_string>
#   Returns 0 (allow) or prints a deny reason and returns 1.
inspect_subcommand() {
    local sub="$1"
    [ -z "$sub" ] && return 0

    # Tokenize argv.
    local -a argv=()
    local t
    while IFS= read -r t; do
        argv+=("$t")
    done < <(tokenize_argv "$sub")
    [ ${#argv[@]} -eq 0 ] && return 0

    # Strip a leading wrapper (sudo/env/nice/...). Mirrors the dangerous-
    # command-guard logic so `sudo cat /etc/shadow` is also caught.
    local head="${argv[0]}"
    case "$head" in
        sudo|nice|nohup|time|stdbuf|exec)
            argv=("${argv[@]:1}")
            ;;
        env)
            argv=("${argv[@]:1}")
            while [ ${#argv[@]} -gt 0 ]; do
                case "${argv[0]}" in
                    *=*) argv=("${argv[@]:1}") ;;
                    *)   break ;;
                esac
            done
            ;;
    esac
    [ ${#argv[@]} -eq 0 ] && return 0

    local cmd0="${argv[0]}"

    # Whitelist of read tools we inspect. Other commands may still read
    # files (their own -f flags etc.) but we keep the set bounded so the
    # hook stays predictable; new read patterns are added on demand.
    case "$cmd0" in
        cat|head|tail|less|more|bat|view)
            ;;
        grep|egrep|fgrep|rg)
            ;;
        find)
            ;;
        tar)
            ;;
        xxd|od|strings|hexdump)
            ;;
        cp|mv|rsync|install|scp)
            # Source argument(s) to copy/move are reads; targets are writes.
            # We only flag the source side here (everything except the last
            # token). Write-side enforcement lives in bash-write-guard.sh.
            ;;
        *)
            return 0
            ;;
    esac

    # For cp/mv/rsync/install/scp the last argument is the destination.
    # Inspect only the source positions.
    local -a inspect_args=("${argv[@]:1}")
    case "$cmd0" in
        cp|mv|rsync|install|scp)
            local n=${#inspect_args[@]}
            if [ "$n" -ge 1 ]; then
                inspect_args=("${inspect_args[@]:0:$((n-1))}")
            else
                inspect_args=()
            fi
            ;;
    esac

    local path resolved
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        resolved=$(resolve_path "$path")
        if is_sensitive "$resolved"; then
            echo "Bash read of sensitive file blocked: $cmd0 $path (resolved: $resolved)"
            return 1
        fi
    done < <(extract_read_paths "$cmd0" "${inspect_args[@]}")
    return 0
}

# --- main -------------------------------------------------------------------

INPUT=$(cat 2>/dev/null || true)

# Fail-open on totally empty input — mirrors pre-edit-read-guard. The
# upstream dangerous-command-guard already fails closed on parse errors;
# duplicating that here would make the Bash chain double-deny on transient
# stdin issues.
if [ -z "$INPUT" ]; then
    allow_response
fi

command -v jq >/dev/null 2>&1 || allow_response

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$CMD" ]; then
    allow_response
fi

# Performance bound: same threshold as dangerous-command-guard. For very
# large pasted blobs fall through to a coarse regex that still flags the
# obvious patterns.
SRG_TOKENIZER_MAX_BYTES="${SRG_TOKENIZER_MAX_BYTES:-16384}"
if [ "${#CMD}" -gt "$SRG_TOKENIZER_MAX_BYTES" ]; then
    if echo "$CMD" | grep -qE '(^|[[:space:]])(cat|head|tail|less|more|grep|egrep|fgrep|rg|xxd|od|strings)[[:space:]]+[^|;&]*\.env(\s|$|[^[:alnum:]])'; then
        deny_response "Bash read of .env file blocked (coarse-scan)"
    fi
    if echo "$CMD" | grep -qE '(^|[[:space:]])(cat|head|tail|grep|egrep|fgrep|rg|xxd|od|strings)[[:space:]]+[^|;&]*(\.pem|\.key|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.aws/credentials|/etc/shadow)'; then
        deny_response "Bash read of sensitive credential blocked (coarse-scan)"
    fi
    allow_response
fi

# Walk every sub-command. Single hit denies the whole call.
prev=""
while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    if reason=$(inspect_subcommand "$sub"); then
        :
    else
        deny_response "$reason"
    fi
    prev="$sub"
done < <(split_subcommands "$CMD")

allow_response
