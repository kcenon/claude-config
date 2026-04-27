#!/bin/bash
# gh-write-verb-guard.sh
# Narrows the `gh` CLI surface on the Bash channel:
#
#   1. `gh api -X PATCH|PUT|DELETE|POST <endpoint>` — denied unless the
#      endpoint sits on a small explicit allowlist. Implicit GET (no `-X`)
#      and explicit `-X GET` pass.
#   2. `gh api graphql ... query=...` — payloads containing the literal
#      tokens `mutation` or `subscription` (outside of strings) are denied.
#      Read-only `query { ... }` payloads pass.
#   3. State-changing `gh` subcommands not routed through `gh api`
#      (issue comment/edit/close/reopen/delete, pr comment/edit/close/
#      reopen/review, workflow run/enable/disable, secret *, ssh-key *,
#      gist create/edit/delete, release create/edit/upload/delete) — by
#      default allowed with an `additionalContext` warning so the model is
#      reminded to scope the operation. When `--repo OTHER_ORG/REPO` is
#      passed, the call is denied because the audit found cross-repo
#      writes are the highest-risk subset (Issue #478, Vector I).
#
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
#
# Reuses lib/tokenize-shell.sh so quote/substitution-aware sub-command
# splitting matches the rest of the Bash hook chain (PR #483 / #484).
#
# Audit-only mode: set GH_WRITE_VERB_GUARD_AUDIT_ONLY=1 to downgrade every
# `deny` decision to `allow` while still emitting the diagnostic to
# stderr. This supports the issue's "1-week telemetry" rollout step
# without requiring code changes.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/tokenize-shell.sh
. "$LIB_DIR/tokenize-shell.sh"

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/gh-write-verb-guard.log"

log_decision() {
    local decision="$1"
    local reason="$2"
    local cmd="$3"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if command -v jq >/dev/null 2>&1; then
        jq -cn \
            --arg ts "$ts" \
            --arg d "$decision" \
            --arg r "$reason" \
            --arg c "$cmd" \
            '{ts:$ts, decision:$d, reason:$r, command:$c}' \
            >>"$LOG_FILE" 2>/dev/null || true
    fi
}

allow_response() {
    local reason="${1:-}"
    log_decision "allow" "${reason:-no-write-pattern}" "${CMD:-}"
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

allow_with_context() {
    local context="$1"
    log_decision "allow_with_context" "$context" "${CMD:-}"
    local esc
    esc="${context//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "gh-write-verb-guard: $esc"
  }
}
EOF
    exit 0
}

deny_response() {
    local reason="$1"
    if [ "${GH_WRITE_VERB_GUARD_AUDIT_ONLY:-0}" = "1" ]; then
        echo "gh-write-verb-guard (audit-only) would deny: $reason" >&2
        log_decision "audit_allow" "$reason" "${CMD:-}"
        cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
        exit 0
    fi
    log_decision "deny" "$reason" "${CMD:-}"
    local esc
    esc="${reason//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$esc"
  }
}
EOF
    exit 0
}

# --- Read input ---
INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    allow_response
fi

command -v jq >/dev/null 2>&1 || allow_response

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && allow_response

# Performance bound — defer to coarse regex on giant inputs.
GHWVG_TOKENIZER_MAX_BYTES="${GHWVG_TOKENIZER_MAX_BYTES:-16384}"

# Quick pre-filter: if `gh ` does not appear at all, skip work entirely.
if ! echo "$CMD" | grep -qE '(^|[[:space:]`(])gh[[:space:]]'; then
    allow_response "no-gh-invocation"
fi

# --- Endpoint allowlist for write-method `gh api` calls -----------------
#
# Each entry is a glob applied to the *endpoint argument* of
# `gh api <method> <endpoint> ...`. The endpoint is the first non-flag
# positional argument after `api`. Empty by default — the issue treats
# every write method against an arbitrary endpoint as denied. Operators
# can override at deploy time via $GH_API_WRITE_ALLOW (newline- or
# colon-separated globs).
gh_api_write_allow_globs() {
    local raw="${GH_API_WRITE_ALLOW:-}"
    [ -z "$raw" ] && return 0
    # Normalize : separators to newlines.
    printf '%s\n' "${raw//:/$'\n'}"
}

endpoint_on_write_allowlist() {
    local endpoint="$1"
    [ -z "$endpoint" ] && return 1
    local glob
    while IFS= read -r glob; do
        [ -z "$glob" ] && continue
        # shellcheck disable=SC2254
        case "$endpoint" in
            $glob) return 0 ;;
        esac
    done < <(gh_api_write_allow_globs)
    return 1
}

# --- Helpers ------------------------------------------------------------

# argv_to_array <subcommand> — populates the named array via printf-eval.
# Bash 3.2 (macOS) lacks namerefs, so callers iterate the helper directly.
read_argv() {
    local sub="$1"
    tokenize_argv "$sub"
}

# extract_repo_flag <argv...> — emit the value of -R / --repo if present.
extract_repo_flag() {
    local prev=""
    local arg
    for arg in "$@"; do
        if [ "$prev" = "-R" ] || [ "$prev" = "--repo" ]; then
            printf '%s' "$arg"
            return 0
        fi
        case "$arg" in
            --repo=*) printf '%s' "${arg#--repo=}"; return 0 ;;
        esac
        prev="$arg"
    done
    return 1
}

# extract_api_method <argv...> — emit the HTTP method for a gh api call.
# argv[0] is expected to be `gh`, argv[1] is `api`. Defaults follow gh's
# CLI semantics: GET when no `-X`/`--method` is present and no body flag
# (`-f`/`-F`/`--field`/`--raw-field`/`--input`) is present; POST when a
# body flag is present without `-X`. We intentionally treat the implicit
# POST conservatively because a body flag with no method is the same
# write-class request as `-X POST`.
extract_api_method() {
    local prev=""
    local method=""
    local has_body=0
    local arg
    for arg in "$@"; do
        if [ "$prev" = "-X" ] || [ "$prev" = "--method" ]; then
            method="$arg"
            prev=""
            continue
        fi
        case "$arg" in
            --method=*) method="${arg#--method=}" ;;
            -X|--method) prev="$arg"; continue ;;
            -f|--field|-F|--raw-field|--input) has_body=1 ;;
            -f=*|--field=*|-F=*|--raw-field=*|--input=*) has_body=1 ;;
        esac
        prev="$arg"
    done
    if [ -n "$method" ]; then
        # Normalize to upper-case.
        printf '%s' "$method" | tr '[:lower:]' '[:upper:]'
        return 0
    fi
    if [ "$has_body" = "1" ]; then
        printf 'POST'
        return 0
    fi
    printf 'GET'
}

# extract_api_endpoint <argv...> — first non-flag positional argument
# after `api`. Skips known flag forms; treats `-H NAME:VAL`, `-X METHOD`,
# `-f KEY=VAL`, `-F KEY=VAL`, `--input FILE`, `--method M` as flag pairs.
extract_api_endpoint() {
    local prev=""
    local arg
    # argv passed in is the full argv from `gh` onward; skip the first
    # two tokens (`gh api`).
    local skipped=0
    for arg in "$@"; do
        if [ "$skipped" -lt 2 ]; then
            skipped=$((skipped + 1))
            continue
        fi
        if [ "$prev" = "-X" ] || [ "$prev" = "--method" ] \
            || [ "$prev" = "-H" ] || [ "$prev" = "--header" ] \
            || [ "$prev" = "-f" ] || [ "$prev" = "--field" ] \
            || [ "$prev" = "-F" ] || [ "$prev" = "--raw-field" ] \
            || [ "$prev" = "--input" ] || [ "$prev" = "-q" ] \
            || [ "$prev" = "--jq" ] || [ "$prev" = "--template" ] \
            || [ "$prev" = "-t" ] || [ "$prev" = "--hostname" ] \
            || [ "$prev" = "--cache" ] || [ "$prev" = "--paginate-method" ]; then
            prev=""
            continue
        fi
        case "$arg" in
            --*=*|-*=*) prev=""; continue ;;
            -*) prev="$arg"; continue ;;
        esac
        printf '%s' "$arg"
        return 0
    done
    return 1
}

# scan_graphql_for_mutation <argv...> — returns 0 if a `-f query=` or
# `-F query=` argument carries a `mutation` or `subscription` operation.
# The check looks for the literal keyword followed by `{`, `(`, or
# whitespace (the GraphQL operation prefix). Anonymous mutations like
# `mutation { ... }` and named ones like `mutation Foo { ... }` both
# match. `query` is left alone.
scan_graphql_for_mutation() {
    local prev=""
    local arg
    for arg in "$@"; do
        local payload=""
        if [ "$prev" = "-f" ] || [ "$prev" = "--field" ] \
            || [ "$prev" = "-F" ] || [ "$prev" = "--raw-field" ]; then
            payload="$arg"
            prev=""
        else
            case "$arg" in
                -f=*|--field=*|-F=*|--raw-field=*)
                    payload="${arg#*=}" ;;
                *) prev="$arg"; continue ;;
            esac
        fi
        # The payload form is `key=value`; we only care about `query=...`
        # (the GraphQL document) and ignore `variables=...` JSON.
        case "$payload" in
            query=*)
                local doc="${payload#query=}"
                # `@file` reads from disk — we cannot statically inspect.
                # Conservatively flag as a mutation candidate so the
                # operator is forced to be explicit.
                case "$doc" in
                    @*)
                        printf 'opaque-file-reference: %s' "$doc"
                        return 0
                        ;;
                esac
                # Strip line comments (#...) before scanning so a quoted
                # `# mutation` in a comment does not trigger.
                local stripped
                stripped=$(printf '%s' "$doc" | sed -E 's/#[^\n]*//g')
                if printf '%s' "$stripped" | grep -qE '(^|[^A-Za-z0-9_])(mutation|subscription)([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*[\{(]'; then
                    printf 'graphql-mutation-or-subscription'
                    return 0
                fi
                ;;
        esac
    done
    return 1
}

# is_state_change_subcommand <argv...> — argv[0]=gh. Returns 0 with an
# emitted "<noun> <verb>" label if the call is a state-changing
# non-`api` subcommand.
is_state_change_subcommand() {
    [ "$#" -lt 3 ] && return 1
    local noun="$2"
    local verb="$3"
    case "$noun" in
        issue)
            case "$verb" in
                comment|edit|close|reopen|delete|develop|lock|unlock|pin|unpin|transfer)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        pr)
            case "$verb" in
                comment|edit|close|reopen|review|merge|ready|lock|unlock)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        workflow)
            case "$verb" in
                run|enable|disable)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        secret|variable|ssh-key|gpg-key)
            case "$verb" in
                set|delete|remove|add)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        gist)
            case "$verb" in
                create|edit|delete|clone)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        release)
            case "$verb" in
                create|edit|upload|delete)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        repo)
            case "$verb" in
                create|delete|edit|fork|rename|archive|unarchive|deploy-key|set-default)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        cache)
            case "$verb" in
                delete) printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
        label)
            case "$verb" in
                create|edit|delete|clone)
                    printf '%s %s' "$noun" "$verb"; return 0 ;;
            esac ;;
    esac
    return 1
}

# current_repo_slug — best-effort `<owner>/<repo>` for the working
# directory's `origin` remote. Empty on failure (we only use this for the
# cross-repo write check, which fails open).
current_repo_slug() {
    local url
    url=$(git -C "$(pwd)" remote get-url origin 2>/dev/null) || return 0
    # https://github.com/foo/bar.git or git@github.com:foo/bar.git
    case "$url" in
        *github.com[:/]*)
            url="${url#*github.com[:/]}"
            url="${url%.git}"
            printf '%s' "$url"
            ;;
    esac
}

# --- Main inspection ----------------------------------------------------

# Walk every sub-command (split by `;`, `&&`, `||`, pipes, substitutions)
# so chained gh invocations inside compound shells are individually
# checked.
inspect_subcommand() {
    local sub="$1"

    # Tokenize argv.
    local -a argv=()
    local t
    while IFS= read -r t; do
        argv+=("$t")
    done < <(read_argv "$sub")
    [ ${#argv[@]} -eq 0 ] && return 0

    # Strip a single benign wrapper.
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
    [ "${argv[0]}" = "gh" ] || return 0
    [ "${#argv[@]}" -lt 2 ] && return 0

    local subcmd="${argv[1]}"

    # --- gh api ---------------------------------------------------------
    if [ "$subcmd" = "api" ]; then
        local third="${argv[2]:-}"

        # GraphQL is a special case: the gh CLI sends `-f query=...` as
        # a POST regardless, so the HTTP-method check would always trip.
        # Instead we rely on a textual mutation scan: if the document
        # contains `mutation`/`subscription`, deny — otherwise allow.
        # Explicit `-X PATCH|PUT|DELETE` against graphql is still denied.
        if [ "$third" = "graphql" ]; then
            local why
            if why=$(scan_graphql_for_mutation "${argv[@]:2}"); then
                echo "GraphQL ${why} blocked: gh api graphql may not carry mutating or subscription operations. Use a specific gh subcommand (e.g. gh issue edit, gh pr merge) or restrict the document to a query."
                return 1
            fi
            local gql_method
            gql_method=$(extract_api_method "${argv[@]}")
            case "$gql_method" in
                PATCH|PUT|DELETE)
                    echo "gh api graphql -X ${gql_method} blocked: GraphQL endpoint only accepts GET/POST; explicit write verbs are not a legitimate use."
                    return 1
                    ;;
            esac
            return 0
        fi

        local method endpoint
        method=$(extract_api_method "${argv[@]}")
        endpoint=$(extract_api_endpoint "${argv[@]}" || true)

        case "$method" in
            GET|HEAD)
                # Read methods always allowed.
                return 0
                ;;
            POST|PATCH|PUT|DELETE)
                if endpoint_on_write_allowlist "$endpoint"; then
                    return 0
                fi
                echo "gh api -X ${method} ${endpoint:-<no-endpoint>} blocked: write methods require an explicit endpoint on the GH_API_WRITE_ALLOW allowlist. Use a dedicated gh subcommand (gh issue/pr/release/...) where possible."
                return 1
                ;;
            *)
                # Unknown method: deny conservatively.
                echo "gh api -X ${method} blocked: unrecognized HTTP method (only GET/HEAD pass without an allowlist match)."
                return 1
                ;;
        esac
    fi

    # --- gh <noun> <verb> (non-api state changes) ----------------------
    if [ "${#argv[@]}" -ge 3 ]; then
        local label
        if label=$(is_state_change_subcommand "${argv[@]}"); then
            # Cross-repo write: deny when --repo points outside the
            # current working tree's origin slug.
            local target_repo
            target_repo=$(extract_repo_flag "${argv[@]:2}" || true)
            if [ -n "$target_repo" ]; then
                local current
                current=$(current_repo_slug || true)
                if [ -n "$current" ] && [ "$target_repo" != "$current" ]; then
                    echo "gh ${label} --repo ${target_repo} blocked: cross-repo write does not match working tree origin (${current}). Re-run inside the target checkout or pass GH_WRITE_VERB_GUARD_AUDIT_ONLY=1 if intentional."
                    return 1
                fi
            fi
            # In-scope state change: allow with a context warning so the
            # model is reminded the operation mutates remote state.
            printf '__CONTEXT__%s' "$label"
            return 2
        fi
    fi

    return 0
}

# --- Drive every sub-command ------------------------------------------

if [ "${#CMD}" -gt "$GHWVG_TOKENIZER_MAX_BYTES" ]; then
    # Coarse regex pass for over-budget inputs: catch the two highest-
    # impact cases and otherwise fall through.
    if echo "$CMD" | grep -qE 'gh[[:space:]]+api[[:space:]]+graphql\b'; then
        if echo "$CMD" | grep -qE '(^|[^A-Za-z0-9_])(mutation|subscription)([[:space:]]+[A-Za-z_][A-Za-z0-9_]*)?[[:space:]]*[\{(]'; then
            deny_response "GraphQL mutation/subscription blocked (coarse-scan): gh api graphql payload exceeded the tokenizer budget but contained a mutating operation."
        fi
    fi
    if echo "$CMD" | grep -qE 'gh[[:space:]]+api[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-X|--method)[[:space:]]+(POST|PUT|PATCH|DELETE)\b'; then
        deny_response "gh api write-method blocked (coarse-scan): input exceeded tokenizer budget; rerun with a smaller payload to enable structured inspection."
    fi
    allow_response "coarse-scan-clear"
fi

context_messages=""
while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    reason=""
    if reason=$(inspect_subcommand "$sub"); then
        :
    else
        rc=$?
        if [ "$rc" = "2" ]; then
            # Allow-with-context channel: the helper printed a
            # __CONTEXT__<label> marker.
            label="${reason#__CONTEXT__}"
            if [ -n "$context_messages" ]; then
                context_messages="$context_messages; $label"
            else
                context_messages="$label"
            fi
            continue
        fi
        deny_response "$reason"
    fi
done < <(split_subcommands "$CMD")

if [ -n "$context_messages" ]; then
    allow_with_context "state-changing gh operation(s) detected: $context_messages"
fi

allow_response
