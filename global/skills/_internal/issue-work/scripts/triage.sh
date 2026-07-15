#!/usr/bin/env bash
# issue-work: triage state machine
# ================================
# Deterministic, idempotent front-end gate for the issue-work skill. Selects
# and claims an issue (or decomposes an oversized one) before any repository is
# cloned or any branch is created. See reference/triage-state-machine.md for the
# contract (states, outcome schema, fingerprint rule, eligibility, sort key).
#
# The script is both a sourceable library (unit-testable functions) and a CLI
# (`run_triage`). Every gh call goes through _triage_gh so tests can inject a
# fake gh via GH_BIN.
#
# Usage:
#   bash triage.sh --repo <owner/name> [--issue <number>] [--plan-file <path>]
#                  [--max-depth <n>] [--dry-run]

set -uo pipefail

# Injection seams (overridable by tests and callers).
GH_BIN="${GH_BIN:-gh}"
MAX_CHILD_DEPTH="${MAX_CHILD_DEPTH:-5}"

# ── Low-level gh wrapper ─────────────────────────────────────────────
# All GitHub access funnels through here so a fake gh can shadow it.
_triage_gh() {
    "$GH_BIN" "$@"
}

# ── Pure helpers (unit-testable without gh) ──────────────────────────

# Stable hex digest of stdin. sha256sum on Linux/Git Bash; shasum fallback on
# macOS; cksum as a last resort so the function never hard-fails.
triage_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -d' ' -f1
    else
        cksum | tr -d ' '
    fi
}

# Extract blocker issue numbers from a body. Matches "Blocked by #N" and
# "Depends on #N" (case-insensitive). Prints one number per line, sorted unique.
triage_extract_blockers() {
    local body="$1"
    printf '%s\n' "$body" \
        | grep -oiE '(blocked by|depends on)[[:space:]]+#[0-9]+' \
        | grep -oE '[0-9]+' \
        | sort -un
}

# Map a comma-separated label list to a numeric priority rank (lower = higher
# priority). Unlabeled issues rank last.
triage_priority_rank() {
    local labels="$1"
    case ",$labels," in
        *,priority/critical,*) echo 0 ;;
        *,priority/high,*)     echo 1 ;;
        *,priority/medium,*)   echo 2 ;;
        *,priority/low,*)      echo 3 ;;
        *)                     echo 4 ;;
    esac
}

# Return 0 if the raw comments blob already carries a marker of the given kind
# whose hash equals the supplied fingerprint (state unchanged -> skip posting).
# Return 1 otherwise (no marker, or a different hash -> post).
triage_comment_marker_matches() {
    local raw="$1" kind="$2" fingerprint="$3"
    local existing
    existing="$(printf '%s' "$raw" \
        | grep -oE "triage-fingerprint: ${kind}:[0-9a-f]+" \
        | sed -E "s/.*${kind}://" \
        | tail -n1)"
    [ -n "$existing" ] && [ "$existing" = "$fingerprint" ]
}

# Return 0 if the raw comments blob carries any marker of the given kind.
triage_comment_marker_present() {
    local raw="$1" kind="$2"
    printf '%s' "$raw" | grep -qE "triage-fingerprint: ${kind}:[0-9a-f]+"
}

# Eligibility predicate. Arguments are already-resolved scalar facts so the
# predicate itself is pure and testable. Returns 0 when eligible.
#   $1 state (OPEN/CLOSED)  $2 has_open_blocker (true/false)
#   $3 assigned_other_only (true/false)  $4 has_active_pr (true/false)
#   $5 visited (true/false)
triage_is_eligible() {
    local state="$1" blocked="$2" other_only="$3" active_pr="$4" visited="$5"
    [ "$state" = "OPEN" ] || return 1
    [ "$blocked" = "false" ] || return 1
    [ "$other_only" = "false" ] || return 1
    [ "$active_pr" = "false" ] || return 1
    [ "$visited" = "false" ] || return 1
    return 0
}

# ── gh-backed accessors ──────────────────────────────────────────────

_triage_current_user() {
    if [ -n "${TRIAGE_CURRENT_USER:-}" ]; then
        printf '%s' "$TRIAGE_CURRENT_USER"
        return 0
    fi
    _triage_gh api user --jq '.login' 2>/dev/null
}

# Fetch a single issue as JSON. Prints the raw JSON object on stdout, empty on
# failure.
_triage_issue_json() {
    local repo="$1" num="$2"
    _triage_gh issue view "$num" --repo "$repo" \
        --json number,title,state,body,labels,assignees,createdAt 2>/dev/null
}

# Raw comments blob for marker scanning (grepped as text, no jq needed).
_triage_comments_raw() {
    local repo="$1" num="$2"
    _triage_gh issue view "$num" --repo "$repo" --json comments 2>/dev/null
}

# True when an open PR references the issue (proxy for "active work in
# progress"; full work-branch detection belongs to the workspace stage #830).
_triage_has_active_pr() {
    local repo="$1" num="$2" out
    out="$(_triage_gh pr list --repo "$repo" --state open \
        --search "$num" --json number 2>/dev/null)"
    # Any element other than the empty array means a linked PR exists.
    case "$out" in
        ''|'[]') return 1 ;;
        *) return 0 ;;
    esac
}

# Minimal field extraction from an issue JSON object using python (already a CI
# dependency). Prints the requested scalar; arrays are comma-joined.
_triage_field() {
    local json="$1" expr="$2"
    printf '%s' "$json" | python3 -c '
import json, sys
try:
    obj = json.load(sys.stdin)
except Exception:
    sys.exit(0)
expr = sys.argv[1]
val = obj.get(expr)
if isinstance(val, list):
    if expr == "labels":
        print(",".join(x.get("name", "") for x in val))
    elif expr == "assignees":
        print(",".join(x.get("login", "") for x in val))
    else:
        print(",".join(str(x) for x in val))
elif val is None:
    print("")
else:
    print(val)
' "$expr"
}

# Resolve whether an issue is currently blocked. Prints "true"/"false" on the
# first line and the required-action text on the rest.
_triage_block_state() {
    local repo="$1" json="$2" body blockers b bstate action="" open_found="false"
    body="$(_triage_field "$json" body)"
    blockers="$(triage_extract_blockers "$body")"
    for b in $blockers; do
        bstate="$(_triage_gh issue view "$b" --repo "$repo" --json state \
            --jq '.state' 2>/dev/null)"
        if [ "$bstate" = "OPEN" ]; then
            open_found="true"
            action="${action}#${b} (OPEN) "
        fi
    done
    printf '%s\n' "$open_found"
    printf '%s\n' "$blockers is: ${action}"
}

# ── Mutations ────────────────────────────────────────────────────────

# Post a comment body (from a temp file) unless the same-kind fingerprint marker
# already matches. Returns 0 if posted, 1 if skipped as unchanged.
_triage_post_idempotent_comment() {
    local repo="$1" num="$2" kind="$3" fingerprint="$4" body="$5" raw tmp
    raw="$(_triage_comments_raw "$repo" "$num")"
    if triage_comment_marker_matches "$raw" "$kind" "$fingerprint"; then
        return 1
    fi
    if [ "${TRIAGE_DRY_RUN:-false}" = "true" ]; then
        return 0
    fi
    tmp="$(mktemp)"
    {
        printf '%s\n\n' "$body"
        printf '<!-- triage-fingerprint: %s:%s -->\n' "$kind" "$fingerprint"
    } > "$tmp"
    _triage_gh issue comment "$num" --repo "$repo" --body-file "$tmp" >/dev/null 2>&1
    rm -f "$tmp"
    return 0
}

# ── Emit outcome JSON and exit ───────────────────────────────────────
_triage_emit() {
    local outcome="$1" reason="$2" active="${3:-}" fingerprint="${4:-}"
    local visited_json="[]"
    if [ -n "${VISITED:-}" ]; then
        visited_json="$(printf '%s' "$VISITED" | tr ' ' '\n' \
            | grep -E '.' | sed 's/.*/"&"/' | paste -sd, -)"
        visited_json="[${visited_json}]"
    fi
    printf '{"outcome":"%s","requested":"%s","root":"%s","active":"%s","visited":%s,"reason":"%s","fingerprint":"%s"}\n' \
        "$outcome" "${REQUESTED:-}" "${ROOT:-}" "$active" "$visited_json" \
        "$reason" "$fingerprint"
    [ "$outcome" = "failed" ] && return 1
    return 0
}

# ── State machine driver ─────────────────────────────────────────────
run_triage() {
    local repo="$1" issue="${2:-}" plan_file="${3:-}"
    REQUESTED="$issue"
    ROOT=""
    VISITED=""
    local depth=0

    # RESOLVE_REQUESTED: pick the root issue.
    if [ -z "$issue" ]; then
        issue="$(_triage_gh issue list --repo "$repo" --state open \
            --limit 1 --json number --jq '.[0].number' 2>/dev/null)"
        if [ -z "$issue" ]; then
            _triage_emit skipped "no open issue to select"
            return $?
        fi
    fi
    ROOT="$issue"
    local active="$issue"
    local user; user="$(_triage_current_user)"

    while :; do
        if [ "$depth" -gt "$MAX_CHILD_DEPTH" ]; then
            _triage_emit failed "child traversal exceeded MAX_CHILD_DEPTH=$MAX_CHILD_DEPTH"
            return $?
        fi

        # REFRESH: re-fetch the active issue.
        local json; json="$(_triage_issue_json "$repo" "$active")"
        if [ -z "$json" ]; then
            _triage_emit failed "cannot fetch issue #$active"
            return $?
        fi
        local state; state="$(_triage_field "$json" state)"
        if [ "$state" != "OPEN" ]; then
            VISITED="$VISITED $active"
            _triage_emit skipped "issue #$active is $state"
            return $?
        fi

        # EVALUATE_BLOCKERS: recompute + idempotent blocked comment.
        local block_out open_blocker action
        block_out="$(_triage_block_state "$repo" "$json")"
        open_blocker="$(printf '%s' "$block_out" | head -n1)"
        action="$(printf '%s' "$block_out" | sed -n '2p')"
        if [ "$open_blocker" = "true" ]; then
            local fp
            fp="$(printf '%s' "$action" | triage_hash)"
            _triage_post_idempotent_comment "$repo" "$active" blocked "$fp" \
                "Blocked: unresolved dependency for #${active}. Required: ${action}"
            VISITED="$VISITED $active"
            _triage_emit blocked "unresolved blocker on #$active" "" "$fp"
            return $?
        fi

        # DECOMPOSE (explicit): a plan file means the caller is asking to
        # decompose this invocation. Reconcile existing-vs-planned children,
        # create only the missing ones, post one summary. This takes priority
        # over child selection so a partial decomposition can be completed on a
        # rerun (AC6) rather than immediately diving into an existing child.
        if [ -n "$plan_file" ] && [ -f "$plan_file" ]; then
            if _triage_create_children "$repo" "$active" "$plan_file"; then
                VISITED="$VISITED $active"
                _triage_emit decomposed "reconciled children for #$active" ""
                return $?
            fi
            _triage_emit failed "plan file supplied but contained no child titles for #$active"
            return $?
        fi

        # EVALUATE_SIZE (no plan): work directly, select a child, or audit.
        if ! _triage_needs_decompose "$json"; then
            # CLAIM
            if _triage_claim "$repo" "$active" "$user"; then
                VISITED="$VISITED $active"
                _triage_emit proceed "eligible issue #$active claimed" "$active"
                return $?
            fi
            # Claim lost: fall through to sibling selection below.
            VISITED="$VISITED $active"
        else
            # Oversized with no plan: prefer an existing eligible open child.
            local child
            child="$(_triage_select_child "$repo" "$active" "$user")"
            if [ -n "$child" ]; then
                VISITED="$VISITED $active"
                active="$child"
                depth=$((depth + 1))
                continue
            fi
            # No eligible open child. Distinguish "all children closed"
            # (completion audit, AC8) from other terminal cases.
            local stats total open_count
            stats="$(_triage_children_stats "$repo" "$active")"
            total="$(printf '%s' "$stats" | awk '{print $1+0}')"
            open_count="$(printf '%s' "$stats" | awk '{print $2+0}')"
            if [ "$total" -gt 0 ] && [ "$open_count" -eq 0 ]; then
                VISITED="$VISITED $active"
                _triage_emit skipped "all children of #$active are closed; run completion audit"
                return $?
            fi
            if [ "$total" -gt 0 ]; then
                VISITED="$VISITED $active"
                _triage_emit skipped "children of #$active exist but none are eligible"
                return $?
            fi
            # Oversized, no children, and no plan to create them with.
            VISITED="$VISITED $active"
            _triage_emit failed "issue #$active needs decomposition; re-invoke with --plan-file"
            return $?
        fi

        # Claim was lost: try the next eligible sibling of ROOT.
        local next
        next="$(_triage_select_child "$repo" "$ROOT" "$user")"
        if [ -n "$next" ]; then
            active="$next"
            depth=$((depth + 1))
            continue
        fi
        _triage_emit skipped "claim race lost and no remaining eligible child"
        return $?
    done
}

# Decide whether an issue must be decomposed. Large by label, or large by body
# with 4+ acceptance-criteria checkboxes.
_triage_needs_decompose() {
    local json="$1" labels body ac_count
    labels="$(_triage_field "$json" labels)"
    case ",$labels," in
        *,size/L,*|*,size/XL,*) return 0 ;;
    esac
    body="$(_triage_field "$json" body)"
    ac_count="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*- \[[ xX]\]' || true)"
    if [ "${#body}" -gt 1500 ] && [ "$ac_count" -ge 4 ]; then
        return 0
    fi
    return 1
}

# Print "<total> <open>" counts of a parent's children (any state).
_triage_children_stats() {
    local repo="$1" parent="$2" list
    list="$(_triage_gh issue list --repo "$repo" --state all \
        --search "Part of #${parent} in:body" \
        --json number,state 2>/dev/null)"
    printf '%s' "$list" | python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    print("0 0"); sys.exit(0)
total = len(items)
opened = sum(1 for it in items if it.get("state") == "OPEN")
print(f"{total} {opened}")
' 2>/dev/null || echo "0 0"
}

# List children of a parent (issues whose body references "Part of #<parent>"),
# filter to eligible ones, sort by the deterministic key, print the first.
_triage_select_child() {
    local repo="$1" parent="$2" user="$3" list
    list="$(_triage_gh issue list --repo "$repo" --state all \
        --search "Part of #${parent} in:body" \
        --json number,title,state,labels,assignees,createdAt 2>/dev/null)"
    [ -n "$list" ] || return 0
    printf '%s' "$list" | python3 -c '
import json, sys
repo, parent, user = sys.argv[1], sys.argv[2], sys.argv[3]
visited = set((sys.argv[4] or "").split())
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
rank = {"priority/critical":0,"priority/high":1,"priority/medium":2,"priority/low":3}
cands = []
for idx, it in enumerate(items):
    num = str(it.get("number",""))
    if it.get("state") != "OPEN":
        continue
    if num in visited:
        continue
    assignees = [a.get("login","") for a in it.get("assignees",[])]
    if assignees and user not in assignees:
        continue
    labels = [l.get("name","") for l in it.get("labels",[])]
    prio = min([rank.get(l,4) for l in labels] + [4])
    mine = 0 if user in assignees else 1
    cands.append((mine, idx, prio, it.get("createdAt",""), int(num), num))
if not cands:
    sys.exit(0)
cands.sort()
print(cands[0][5])
' "$repo" "$parent" "$user" "$VISITED"
}

# Assign the issue to the current user, then re-verify no one else won the race.
# Returns 0 if the claim holds, 1 if lost (issue closed, reassigned away, or a
# linked PR appeared).
_triage_claim() {
    local repo="$1" num="$2" user="$3"
    if [ "${TRIAGE_DRY_RUN:-false}" != "true" ]; then
        _triage_gh issue edit "$num" --repo "$repo" --add-assignee @me >/dev/null 2>&1
    fi
    # Re-read after the mutation to detect a race.
    local json; json="$(_triage_issue_json "$repo" "$num")"
    [ -n "$json" ] || return 1
    local state; state="$(_triage_field "$json" state)"
    [ "$state" = "OPEN" ] || return 1
    local assignees; assignees="$(_triage_field "$json" assignees)"
    if [ -n "$assignees" ]; then
        case ",$assignees," in
            *",$user,"*) : ;;   # we are (among) the assignees -> won
            *) return 1 ;;       # assigned only to others -> lost
        esac
    fi
    if _triage_has_active_pr "$repo" "$num"; then
        return 1
    fi
    return 0
}

# Reconcile and create children from a plan file (one child title per line).
# Idempotent: creates only titles that do not already exist; posts one parent
# summary guarded by a decompose fingerprint. Returns 1 if no usable plan.
_triage_create_children() {
    local repo="$1" parent="$2" plan_file="$3"
    [ -n "$plan_file" ] && [ -f "$plan_file" ] || return 1

    local existing planned created=0 title
    existing="$(_triage_gh issue list --repo "$repo" --state all \
        --search "Part of #${parent} in:body" --json title \
        --jq '.[].title' 2>/dev/null)"

    planned=0
    while IFS= read -r title || [ -n "$title" ]; do
        [ -n "$title" ] || continue
        planned=$((planned + 1))
        if printf '%s\n' "$existing" | grep -Fxq -- "$title"; then
            continue
        fi
        if [ "${TRIAGE_DRY_RUN:-false}" != "true" ]; then
            local tmp; tmp="$(mktemp)"
            printf 'Part of #%s\n' "$parent" > "$tmp"
            _triage_gh issue create --repo "$repo" --title "$title" \
                --body-file "$tmp" >/dev/null 2>&1
            rm -f "$tmp"
        fi
        created=$((created + 1))
    done < "$plan_file"

    [ "$planned" -gt 0 ] || return 1

    # Post the parent summary once (idempotent via decompose fingerprint).
    local fp
    fp="$(printf 'decompose:%s:%s' "$parent" "$planned" | triage_hash)"
    _triage_post_idempotent_comment "$repo" "$parent" decompose "$fp" \
        "Decomposed into ${planned} child issue(s); ${created} created this run."
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────
_triage_main() {
    local repo="" issue="" plan_file=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            --issue) issue="$2"; shift 2 ;;
            --plan-file) plan_file="$2"; shift 2 ;;
            --max-depth) MAX_CHILD_DEPTH="$2"; shift 2 ;;
            --dry-run) TRIAGE_DRY_RUN=true; shift ;;
            *) echo "unknown argument: $1" >&2; return 2 ;;
        esac
    done
    if [ -z "$repo" ]; then
        echo "error: --repo <owner/name> is required" >&2
        return 2
    fi
    run_triage "$repo" "$issue" "$plan_file"
}

# Run as CLI only when executed directly; stay quiet when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _triage_main "$@"
fi
