#!/bin/bash
# prune-permission-rules.sh
# Prunes permissions.allow entries that can never match again from the project-scope settings.local.json
# Hook Type: SessionEnd
# Input: JSON via stdin with session_id, cwd, transcript_path, hook_event_name
# Exit codes: 0=always (fail-open; teardown is never blocked)
# Response format: none (lifecycle event, no JSON output needed)
# Fail policy: fail-open - any parse, classification, or IO error leaves the file byte-identical

# Deliberately no `set -e`: every failure path must fall through to an
# untouched file rather than abort mid-write. Measured behavior behind the
# SessionEnd choice is recorded in issue #923 - the harness does not rewrite
# permissions.allow after SessionEnd hooks complete, and the pruned file
# survives the session boundary.
set -uo pipefail

MAX_ENTRY_LEN=120

# --- classification -------------------------------------------------------
#
# Removed:
#   denylisted unbounded-argument rules; entries carrying a session-scoped
#   UUID path; compound entries (`;` or `|`); over-long literals; entries
#   already subsumed by a broader Tool(prefix:*) rule in the same file.
# Kept:
#   Tool(prefix:*) rules, bare-string entries (Read, WebFetch, Skill, ...),
#   and anything not positively classified as dead.

# Unbounded-argument destructive or arbitrary-execution rules. Fixed rather
# than configurable: a per-machine list drifts, which is how this exact class
# of rule returned after the 2026-07-27 manual cleanup (#923).
#   pattern 1: `Tool(<anything> *)`   - a space before the trailing star means
#              the argument list is unbounded, e.g. PowerShell(Remove-Item *)
#   pattern 2: `Tool(<anything>':*)`  - a quote immediately before `:*` anchors
#              the prefix inside a quoted string, e.g. Bash(git commit -m ':*)
is_denylisted() {
    local entry="$1"
    [[ "$entry" =~ ^[A-Za-z][A-Za-z]*\(.+\ \*\)$ ]] && return 0
    [[ "$entry" =~ ^[A-Za-z][A-Za-z]*\(.*[\'\"]:\*\)$ ]] && return 0
    return 1
}

# A reusable prefix rule: ends in `:*)`. These are the entries worth keeping.
is_prefix_rule() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z]*\(.*:\*\)$ ]]
}

# Bare-string entries carry no argument at all (Read, WebFetch, Skill, WebSearch).
is_bare_string() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]
}

# A session scratchpad path embeds a session UUID, so the literal is dead the
# moment that session ends.
has_session_uuid() {
    [[ "$1" =~ [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12} ]]
}

# Compound one-off literals have no reducible prefix, so the whole command
# string was stored verbatim and will not match a second time.
is_compound() {
    case "$1" in
        *";"*|*"|"*) return 0 ;;
        *)           return 1 ;;
    esac
}

# Extract the `Tool` name and the body inside the parentheses.
entry_tool() {
    local entry="$1"
    [[ "$entry" == *"("*")" ]] || return 1
    printf '%s' "${entry%%(*}"
}
entry_body() {
    local entry="$1" body
    [[ "$entry" == *"("*")" ]] || return 1
    body="${entry#*(}"
    printf '%s' "${body%)}"
}

# --- entry extraction -----------------------------------------------------

# Turn one array line (`      "Bash(git:*)",`) into its JSON string content.
# Returns 1 when the line is not a plain quoted scalar, which makes the caller
# treat the whole file as unrecognized and leave it alone.
extract_entry() {
    local line="$1"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line%,}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
        '"'*'"') ;;
        *) return 1 ;;
    esac
    line="${line#\"}"
    line="${line%\"}"
    printf '%s' "$line"
}

# --- main -----------------------------------------------------------------

INPUT=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$CWD" ] || exit 0

# Project scope only. The growth was measured there and the SessionEnd payload
# hands us the project cwd directly; widening to the user-scope file would add
# blast radius with no evidence behind it (#923).
TARGET="$CWD/.claude/settings.local.json"
[ -f "$TARGET" ] || exit 0
[ -w "$TARGET" ] || exit 0

# Refuse to touch a file that is not already valid JSON.
jq -e . "$TARGET" >/dev/null 2>&1 || exit 0

# Locate the permissions.allow array. Only the pretty-printed, one-entry-per-line
# shape is handled; a collapsed array is left untouched rather than reformatted.
start_line=$(grep -n '"allow"[[:space:]]*:[[:space:]]*\[[[:space:]]*$' "$TARGET" 2>/dev/null | head -1 | cut -d: -f1)
[ -n "${start_line:-}" ] || exit 0

total_lines=$(wc -l < "$TARGET" | tr -d ' ')
[ -n "$total_lines" ] || exit 0

# The array ends at the first line that is nothing but a closing bracket. An
# entry line always begins with a quote, so a `]` inside a rule string (e.g. a
# sed character class) cannot be mistaken for the terminator.
end_line=""
i=$((start_line + 1))
while [ "$i" -le "$total_lines" ]; do
    line=$(sed -n "${i}p" "$TARGET")
    if [[ "$line" =~ ^[[:space:]]*\][[:space:]]*,?[[:space:]]*$ ]]; then
        end_line="$i"
        break
    fi
    i=$((i + 1))
done
[ -n "$end_line" ] || exit 0

# Pass 1: collect the prefix rules present in this file, so subsumption can be
# judged against what actually survives alongside the entry.
declare -a prefix_tools=()
declare -a prefix_bodies=()
i=$((start_line + 1))
while [ "$i" -lt "$end_line" ]; do
    raw=$(sed -n "${i}p" "$TARGET")
    if entry=$(extract_entry "$raw"); then
        if is_prefix_rule "$entry" && ! is_denylisted "$entry"; then
            if tool=$(entry_tool "$entry") && body=$(entry_body "$entry"); then
                prefix_tools+=("$tool")
                prefix_bodies+=("${body%:\*}")
            fi
        fi
    fi
    i=$((i + 1))
done

# An entry is subsumed when a prefix rule for the same tool already covers its
# command, e.g. Bash(gh:*) makes Bash(gh pr list ...) unreachable.
is_subsumed() {
    local entry="$1" tool body idx
    tool=$(entry_tool "$entry") || return 1
    body=$(entry_body "$entry") || return 1
    for idx in "${!prefix_tools[@]}"; do
        [ "${prefix_tools[$idx]}" = "$tool" ] || continue
        local p="${prefix_bodies[$idx]}"
        [ -n "$p" ] || continue
        [ "$body" = "$p" ] && continue
        case "$body" in
            "$p" | "$p "* | "$p:"*) return 0 ;;
        esac
    done
    return 1
}

# Pass 2: build the candidate file, preserving every kept line byte for byte
# apart from the trailing comma required to keep the array valid.
#
# The temp file has to live in the target's own directory. Across volumes `mv`
# degrades from an atomic rename to copy-then-delete, which is exactly the
# truncation window the atomic-replace requirement exists to close.
tmp=$(mktemp "${TARGET}.prune.XXXXXX" 2>/dev/null) || exit 0

# Carry the original mode over; the replacement must not silently widen or
# narrow access to the settings file. BSD and GNU stat spell this differently.
if perms=$(stat -f '%Lp' "$TARGET" 2>/dev/null || stat -c '%a' "$TARGET" 2>/dev/null); then
    [ -n "$perms" ] && chmod "$perms" "$tmp" 2>/dev/null
fi

cleanup_tmp() { [ -n "${tmp:-}" ] && rm -f "$tmp"; }

sed -n "1,${start_line}p" "$TARGET" > "$tmp" 2>/dev/null || { cleanup_tmp; exit 0; }

declare -a kept=()
removed=0
c_deny=0
c_uuid=0
c_compound=0
c_long=0
c_subsumed=0
unparsed=0

i=$((start_line + 1))
while [ "$i" -lt "$end_line" ]; do
    raw=$(sed -n "${i}p" "$TARGET")
    if ! entry=$(extract_entry "$raw"); then
        unparsed=1
        break
    fi
    if is_denylisted "$entry"; then
        removed=$((removed + 1)); c_deny=$((c_deny + 1))
    elif is_bare_string "$entry" || is_prefix_rule "$entry"; then
        kept+=("$raw")
    elif has_session_uuid "$entry"; then
        removed=$((removed + 1)); c_uuid=$((c_uuid + 1))
    elif is_compound "$entry"; then
        removed=$((removed + 1)); c_compound=$((c_compound + 1))
    elif [ "${#entry}" -gt "$MAX_ENTRY_LEN" ]; then
        removed=$((removed + 1)); c_long=$((c_long + 1))
    elif is_subsumed "$entry"; then
        removed=$((removed + 1)); c_subsumed=$((c_subsumed + 1))
    else
        kept+=("$raw")
    fi
    i=$((i + 1))
done

# An array line we cannot read as a plain string means the file is shaped in a
# way this hook does not understand. Leave it alone.
if [ "$unparsed" -eq 1 ]; then
    cleanup_tmp
    exit 0
fi

if [ "$removed" -eq 0 ]; then
    cleanup_tmp
    exit 0
fi

last=$(( ${#kept[@]} - 1 ))
for idx in "${!kept[@]}"; do
    line="${kept[$idx]}"
    if [ "$idx" -eq "$last" ]; then
        line="${line%,}"
    else
        case "$line" in
            *,) ;;
            *) line="${line}," ;;
        esac
    fi
    printf '%s\n' "$line" >> "$tmp" || { cleanup_tmp; exit 0; }
done

sed -n "${end_line},\$p" "$TARGET" >> "$tmp" 2>/dev/null || { cleanup_tmp; exit 0; }

# Re-parse before replacing: a candidate that is not valid JSON is discarded.
jq -e . "$tmp" >/dev/null 2>&1 || { cleanup_tmp; exit 0; }

# Every other key must survive. Compare the whole document minus the pruned
# array; any other difference means the edit went wrong.
before=$(jq -S 'del(.permissions.allow)' "$TARGET" 2>/dev/null) || { cleanup_tmp; exit 0; }
after=$(jq -S 'del(.permissions.allow)' "$tmp" 2>/dev/null) || { cleanup_tmp; exit 0; }
[ "$before" = "$after" ] || { cleanup_tmp; exit 0; }

kept_count=${#kept[@]}
total_count=$((kept_count + removed))

# Atomic replace: an interrupted run must not truncate the settings file.
if ! mv "$tmp" "$TARGET" 2>/dev/null; then
    cleanup_tmp
    exit 0
fi

# Logging is best-effort. The braces keep a failed redirection quiet too - a
# read-only log directory must not write to a SessionEnd hook's stderr.
LOG_DIR="${HOME}/.claude/logs"
{
    mkdir -p "$LOG_DIR" &&
    printf '[%s] prune-permission-rules: pruned %d of %d -> %d kept  [denylisted=%d scratchpad=%d compound=%d long=%d subsumed=%d]  %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$removed" "$total_count" "$kept_count" \
        "$c_deny" "$c_uuid" "$c_compound" "$c_long" "$c_subsumed" "$TARGET" \
        >> "$LOG_DIR/permission-prune.log"
} 2>/dev/null || true

exit 0
