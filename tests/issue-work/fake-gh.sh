#!/usr/bin/env bash
# Fake gh for triage state machine tests.
# ======================================
# Serves canned responses from $FAKE_GH_DIR and records mutations so tests can
# assert exact side-effect counts (comments posted, children created, assigns).
# Only the gh surface that scripts/triage.sh touches is implemented.
#
# Fixture files under $FAKE_GH_DIR:
#   user                    current-user login (default "me")
#   autoselect              number returned by `issue list --limit 1` auto-select
#   issue-<n>.json          issue object for `issue view <n>`
#   issue-<n>.postclaim.json  optional swap returned after an edit (race sim)
#   issue-<n>.comments      comment text (markers live here; appended on post)
#   children-<n>.json       array for `issue list --search "Part of #<n>"`
#   pr-<n>.json             array for `pr list --search <n>` (default [])
#   pr-view-<n>.json        object for `pr view <n>` (default {}); #840 reconcile
#   mutations.log           appended: COMMENT <n> / CREATE <title> / ASSIGN <n> / UNASSIGN <n>
#   edited-<n>              marker touched on `issue edit <n>`

set -uo pipefail

DIR="${FAKE_GH_DIR:?FAKE_GH_DIR must be set}"
LOG="$DIR/mutations.log"

# Pull a flag value out of the argument list.
arg_value() {
    local flag="$1"; shift
    while [ $# -gt 0 ]; do
        if [ "$1" = "$flag" ]; then printf '%s' "${2:-}"; return 0; fi
        shift
    done
}

cmd="${1:-}"; sub="${2:-}"

case "$cmd" in
    api)
        # `gh api user --jq .login`
        if [ "$sub" = "user" ]; then
            cat "$DIR/user" 2>/dev/null || echo "me"
        fi
        ;;

    issue)
        case "$sub" in
            view)
                num="$3"
                json_fields="$(arg_value --json "$@")"
                jq_expr="$(arg_value --jq "$@")"
                if [ "$json_fields" = "comments" ]; then
                    cat "$DIR/issue-${num}.comments" 2>/dev/null || echo '{"comments":[]}'
                    exit 0
                fi
                # Return post-claim swap once an edit has occurred (race sim).
                src="$DIR/issue-${num}.json"
                if [ -f "$DIR/edited-${num}" ] && [ -f "$DIR/issue-${num}.postclaim.json" ]; then
                    src="$DIR/issue-${num}.postclaim.json"
                fi
                if [ "$jq_expr" = ".state" ]; then
                    python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("state",""))' "$src" 2>/dev/null
                else
                    cat "$src" 2>/dev/null
                fi
                ;;

            list)
                search="$(arg_value --search "$@")"
                jq_expr="$(arg_value --jq "$@")"
                case "$search" in
                    "Part of #"*)
                        parent="$(printf '%s' "$search" | grep -oE '#[0-9]+' | tr -d '#' | head -n1)"
                        file="$DIR/children-${parent}.json"
                        [ -f "$file" ] || { echo '[]'; exit 0; }
                        if [ "$jq_expr" = ".[].title" ]; then
                            python3 -c 'import json,sys
for it in json.load(open(sys.argv[1])):
    print(it.get("title",""))' "$file" 2>/dev/null
                        else
                            cat "$file"
                        fi
                        ;;
                    *)
                        # Auto-select: `issue list --limit 1 --json number --jq .[0].number`
                        cat "$DIR/autoselect" 2>/dev/null || true
                        ;;
                esac
                ;;

            comment)
                num="$3"
                bf="$(arg_value --body-file "$@")"
                if [ -n "$bf" ] && [ -f "$bf" ]; then
                    cat "$bf" >> "$DIR/issue-${num}.comments"
                fi
                echo "COMMENT $num" >> "$LOG"
                ;;

            create)
                title="$(arg_value --title "$@")"
                echo "CREATE $title" >> "$LOG"
                echo "https://github.com/fake/repo/issues/999"
                ;;

            edit)
                num="$3"
                case " $* " in
                    *" --remove-assignee "*)
                        echo "UNASSIGN $num" >> "$LOG"
                        ;;
                    *)
                        : > "$DIR/edited-${num}"
                        echo "ASSIGN $num" >> "$LOG"
                        ;;
                esac
                ;;
        esac
        ;;

    pr)
        case "$sub" in
            list)
                search="$(arg_value --search "$@")"
                num="$(printf '%s' "$search" | grep -oE '[0-9]+' | head -n1)"
                cat "$DIR/pr-${num}.json" 2>/dev/null || echo '[]'
                ;;

            view)
                # #840 reconcile: `pr view <n> --json ... --jq <dotted.path>`.
                num="$3"
                jq_expr="$(arg_value --jq "$@")"
                file="$DIR/pr-view-${num}.json"
                if [ ! -f "$file" ]; then
                    echo '{}'
                    exit 0
                fi
                if [ -n "$jq_expr" ]; then
                    # Extract a simple dotted path (e.g. .state, .mergeCommit.oid,
                    # .headRefName, .mergedAt) with python3 -- no jq dependency.
                    python3 -c '
import json, sys
obj = json.load(open(sys.argv[1]))
cur = obj
for part in sys.argv[2].lstrip(".").split("."):
    if part == "":
        continue
    if isinstance(cur, dict):
        cur = cur.get(part, "")
    else:
        cur = ""
        break
print("" if cur is None else cur)
' "$file" "$jq_expr" 2>/dev/null
                else
                    cat "$file"
                fi
                ;;
        esac
        ;;
esac
exit 0
