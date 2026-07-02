#!/bin/bash
# push-target-guard.sh
# Blocks git pushes that bypass the two-layer defense (issue #782):
#   1. `git push --no-verify ...`  — defeats the terminal-side pre-push hook.
#   2. Direct push to a protected branch (main / master / develop) — whether
#      the target is explicit (`git push origin main`, `... HEAD:main`) or the
#      resolved upstream of the current branch (`git push` while on main).
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
#
# `git push -n` / `--dry-run` is intentionally NOT treated as --no-verify and
# not blocked on target: it performs no real push (verifier note, #782).
#
# Modeled on pr-target-guard.sh (same jq response + fail-closed input parsing).

set -euo pipefail

deny_response() {
    local reason="$1"
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

allow_response() {
    jq -nc \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
    exit 0
}

# --- Read input from stdin (Claude Code passes JSON) ---
INPUT=$(cat)

# Fail-closed: deny if stdin is empty or missing.
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

JQ_RC=0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || JQ_RC=$?
if [ "$JQ_RC" -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi
CMD="${CMD//$'\r'/}"

# --- Scope gate: only inspect `git push` commands ---
if ! echo "$CMD" | grep -qE 'git[[:space:]]+push'; then
    allow_response
fi

# Strip quoted substrings so a flag-looking token inside a quoted argument
# cannot false-trigger the flag checks below.
DEQUOTED=$(printf '%s' "$CMD" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")

# --- Check A: --no-verify defeats the pre-push hook ---
if printf '%s' "$DEQUOTED" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
    deny_response "git push --no-verify is blocked: it bypasses the pre-push hook, the terminal-side half of the two-layer protected-branch defense. Push without --no-verify."
fi

# --- Dry-run is harmless: skip the protected-target check for it (#782) ---
DRY_RUN=0
if printf '%s' "$DEQUOTED" | grep -qE '(^|[[:space:]])(-n|--dry-run)([[:space:]]|$)'; then
    DRY_RUN=1
fi

# --- Check B: direct push to a protected branch ---
if [ "$DRY_RUN" -eq 0 ]; then
    # Isolate the `git push` invocation's arguments, stopping at the first
    # shell operator so a following `&& ...` cannot leak in as positionals.
    PUSH_ARGS=$(printf '%s' "$DEQUOTED" | sed -nE 's/.*git[[:space:]]+push[[:space:]]*(.*)/\1/p' | head -1)
    PUSH_ARGS="${PUSH_ARGS%%&&*}"
    PUSH_ARGS="${PUSH_ARGS%%;*}"
    PUSH_ARGS="${PUSH_ARGS%%|*}"

    # Collect positional (non-flag) args: [remote] [refspec].
    read -ra _tokens <<< "$PUSH_ARGS"
    positionals=()
    for _t in "${_tokens[@]:-}"; do
        [ -n "$_t" ] || continue
        case "$_t" in
            -*) continue ;;
            *)  positionals+=("$_t") ;;
        esac
    done

    REFSPEC="${positionals[1]:-}"
    DST=""
    if [ -n "$REFSPEC" ]; then
        # `src:dst` -> dst; a bare `branch` -> branch.
        DST="${REFSPEC##*:}"
    else
        # No refspec: bare `git push` targets the current branch's upstream
        # when one exists. Resolve that destination first, then fall back to the
        # current branch for repos without an upstream.
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
        if [ -n "$UPSTREAM" ]; then
            DST="${UPSTREAM#*/}"
        else
            DST=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        fi
    fi

    # Normalize: strip a leading '+' (force refspec) and a refs/heads/ prefix.
    DST="${DST#+}"
    DST="${DST#refs/heads/}"

    case "$DST" in
        main|master|develop)
            deny_response "Direct push to protected branch '${DST}' is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main). If you must, push from a work branch instead."
            ;;
    esac
fi

allow_response
