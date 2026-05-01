#!/bin/bash
# memory-write-guard.sh
# Validates Claude Code Edit/Write tool calls targeting memory files BEFORE disk write.
# Hook Type: PreToolUse (Edit|Write)
# Exit codes: 0 (always — decision is encoded in JSON response)
# Response format: hookSpecificOutput with hookEventName "PreToolUse"
#
# Path gate:
#   Only acts when realpath(tool_input.file_path) is under
#   "$HOME/.claude/memory-shared/memories/" and ends with ".md".
#   All other paths pass through with permissionDecision=allow (< 5ms target).
#
# Validation flow (per docs/MEMORY_VALIDATION_SPEC.md §7):
#   1. Build the proposed post-write content:
#        - Write: tool_input.content
#        - Edit:  apply tool_input.old_string -> tool_input.new_string
#                 against current file content (respects replace_all)
#   2. Write proposed content to a temp file (.md).
#   3. Run validate.sh, secret-check.sh, injection-check.sh against the temp file.
#   4. Decide:
#        validate.sh exit 1 or 2 -> deny  (FAIL-STRUCT / FAIL-FORMAT)
#        secret-check.sh exit 1  -> deny  (SECRET-DETECTED)
#        injection-check.sh exit 3 -> allow with feedback (warn-only, never blocks)
#        validate.sh exit 3       -> allow with feedback (semantic warning)
#        else                     -> allow
#   5. Cleanup temp file (trap on EXIT).
#
# Internal-failure policy (issue #521):
#   If validators are missing, jq is missing, or any internal step crashes,
#   emit allow with a diagnostic feedback string. Pre-commit and CI catch
#   anything that slips through; this hook must NOT block legitimate work
#   because of its own bug.
#
# Bash 3.2 compatible (macOS default).

set -u

# ----- response helpers ------------------------------------------------------

emit_allow() {
    # Optional feedback string in $1 -> rendered as additionalContext.
    local feedback="${1:-}"
    if [ -n "$feedback" ]; then
        feedback="${feedback//\\/\\\\}"
        feedback="${feedback//\"/\\\"}"
        feedback="${feedback//$'\n'/\\n}"
        cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "$feedback"
  }
}
EOF
    else
        cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    fi
    exit 0
}

emit_deny() {
    local reason="$1"
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    reason="${reason//$'\n'/\\n}"
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

# ----- temp-file lifecycle ---------------------------------------------------

TMP_FILE=""
cleanup_tmp() {
    if [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ]; then
        rm -f "$TMP_FILE" 2>/dev/null || true
    fi
}
trap cleanup_tmp EXIT

# ----- read input ------------------------------------------------------------

INPUT=$(cat 2>/dev/null || true)

# Empty input: fail-open (let the call proceed; other guards will flag it).
if [ -z "$INPUT" ]; then
    emit_allow ""
fi

# jq is required for safe JSON parsing. Without it, fail-open with diagnostic.
if ! command -v jq >/dev/null 2>&1; then
    emit_allow "memory-write-guard: jq not available; validation skipped"
fi

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Only Edit and Write are guarded. Anything else passes through.
case "$TOOL_NAME" in
    Edit|Write) ;;
    *) emit_allow "" ;;
esac

# Missing file_path: fail-open with diagnostic.
if [ -z "$FILE_PATH" ]; then
    emit_allow "memory-write-guard: tool_input.file_path missing"
fi

# ----- path gate (realpath, suffix check) -----------------------------------

# Resolve symlinks to prevent ../ or symlink-walk bypass. When the file does
# not yet exist (Write of new file), resolve the parent and append basename.
resolve_path() {
    local p="$1"
    if [ -e "$p" ]; then
        if command -v realpath >/dev/null 2>&1; then
            realpath "$p" 2>/dev/null || printf '%s' "$p"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p" 2>/dev/null || printf '%s' "$p"
        else
            printf '%s' "$p"
        fi
    else
        local parent base
        parent="$(dirname "$p")"
        base="$(basename "$p")"
        if [ -d "$parent" ]; then
            if command -v realpath >/dev/null 2>&1; then
                local rp
                rp="$(realpath "$parent" 2>/dev/null)"
                if [ -n "$rp" ]; then
                    printf '%s/%s' "$rp" "$base"
                    return
                fi
            elif command -v python3 >/dev/null 2>&1; then
                local rp
                rp="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$parent" 2>/dev/null)"
                if [ -n "$rp" ]; then
                    printf '%s/%s' "$rp" "$base"
                    return
                fi
            fi
        fi
        printf '%s' "$p"
    fi
}

RESOLVED="$(resolve_path "$FILE_PATH")"

# Activation gate: path must be a .md file under $HOME/.claude/memory-shared/memories/.
MEMORY_ROOT="${HOME}/.claude/memory-shared/memories"
case "$RESOLVED" in
    "$MEMORY_ROOT"/*.md) ;;
    *) emit_allow "" ;;
esac

# MEMORY.md (the auto-generated index) is exempt per validate.sh.
case "$(basename "$RESOLVED")" in
    MEMORY.md) emit_allow "" ;;
esac

# ----- locate validators -----------------------------------------------------

find_validator() {
    local name="$1"
    local script_dir
    script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
    local candidates=(
        "${HOME}/.claude/scripts/memory/${name}"
        "${HOME}/.claude/memory-scripts/${name}"
    )
    if [ -n "$script_dir" ]; then
        candidates+=("${script_dir}/../../scripts/memory/${name}")
    fi
    local c
    for c in "${candidates[@]}"; do
        if [ -x "$c" ]; then
            printf '%s' "$c"
            return 0
        fi
    done
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    return 1
}

VALIDATE_BIN="$(find_validator validate.sh || true)"
SECRET_BIN="$(find_validator secret-check.sh || true)"
INJECTION_BIN="$(find_validator injection-check.sh || true)"

if [ -z "$VALIDATE_BIN" ] || [ -z "$SECRET_BIN" ] || [ -z "$INJECTION_BIN" ]; then
    emit_allow "memory-write-guard: validators not found; validation skipped"
fi

# ----- build proposed content ------------------------------------------------

# Materialize a temp file holding the would-be post-write content.
TMP_FILE="$(mktemp -t claude-write-guard.XXXXXX 2>/dev/null || mktemp 2>/dev/null || true)"
if [ -z "$TMP_FILE" ] || [ ! -f "$TMP_FILE" ]; then
    emit_allow "memory-write-guard: mktemp failed; validation skipped"
fi

# Rename to .md so validators that key off extension behave correctly.
TMP_MD="${TMP_FILE}.md"
if mv "$TMP_FILE" "$TMP_MD" 2>/dev/null; then
    TMP_FILE="$TMP_MD"
fi

case "$TOOL_NAME" in
    Write)
        if ! printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' > "$TMP_FILE" 2>/dev/null; then
            emit_allow "memory-write-guard: failed to read tool_input.content; validation skipped"
        fi
        ;;
    Edit)
        OLD_STRING="$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)"
        NEW_STRING="$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)"
        REPLACE_ALL="$(printf '%s' "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null)"

        CURRENT=""
        if [ -f "$RESOLVED" ]; then
            CURRENT="$(cat "$RESOLVED" 2>/dev/null || true)"
        fi

        if [ "$REPLACE_ALL" = "true" ]; then
            SIMULATED="${CURRENT//"$OLD_STRING"/"$NEW_STRING"}"
        else
            SIMULATED="${CURRENT/"$OLD_STRING"/"$NEW_STRING"}"
        fi

        if ! printf '%s' "$SIMULATED" > "$TMP_FILE" 2>/dev/null; then
            emit_allow "memory-write-guard: failed to write simulated content; validation skipped"
        fi
        ;;
esac

# ----- run validators --------------------------------------------------------

VALIDATE_OUT="$("$VALIDATE_BIN" "$TMP_FILE" 2>&1)"; VALIDATE_RC=$?
SECRET_OUT="$("$SECRET_BIN" "$TMP_FILE" 2>&1)"; SECRET_RC=$?
INJECTION_OUT="$("$INJECTION_BIN" "$TMP_FILE" 2>&1)"; INJECTION_RC=$?

# ----- decision --------------------------------------------------------------

build_deny_reason() {
    local reason="memory-write-guard rejected write to $(basename "$RESOLVED")"
    if [ "$VALIDATE_RC" -eq 1 ] || [ "$VALIDATE_RC" -eq 2 ]; then
        reason="${reason}\nvalidate.sh (exit ${VALIDATE_RC}):\n${VALIDATE_OUT}"
    fi
    if [ "$SECRET_RC" -eq 1 ]; then
        reason="${reason}\nsecret-check.sh blocked write:\n${SECRET_OUT}"
    fi
    printf '%s' "$reason"
}

# Per spec: validate.sh codes 1 (FAIL-STRUCT) and 2 (FAIL-FORMAT) are blocking;
# code 3 (WARN-SEMANTIC) is non-blocking. secret-check.sh code 1 is blocking.
BLOCK=0
if [ "$VALIDATE_RC" -eq 1 ] || [ "$VALIDATE_RC" -eq 2 ]; then
    BLOCK=1
fi
if [ "$SECRET_RC" -eq 1 ]; then
    BLOCK=1
fi

if [ "$BLOCK" -eq 1 ]; then
    emit_deny "$(build_deny_reason)"
fi

# Allowed path. Surface injection warnings as feedback (warn-only).
FEEDBACK=""
if [ "$INJECTION_RC" -eq 3 ]; then
    FEEDBACK="memory-write-guard: write allowed but injection-check flagged:\n${INJECTION_OUT}\nReview before merge."
elif [ "$VALIDATE_RC" -eq 3 ]; then
    FEEDBACK="memory-write-guard: write allowed with semantic warnings:\n${VALIDATE_OUT}"
fi

emit_allow "$FEEDBACK"
