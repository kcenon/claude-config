#!/bin/bash
# Migrate legacy halt_condition (string) -> halt_conditions (array of {type, expr})
# =================================================================================
# Reads SKILL.md frontmatter, splits the legacy halt_condition string on " OR "
# delimiters, and proposes a halt_conditions array. Type is inferred from
# keyword heuristics:
#
#   success    "all-green", "merged", "complete", "tag published", "reach terminal"
#   limit      "N retries", "N rounds", "drains", "in a row"
#   user       "user", "human", "aborts", "confirms"
#   failure    "fail", "error", "integrity"
#   fallback   "unknown", "escalat"
#
# Compound clauses (any clause containing " AND " or "; ") are flagged for
# manual review — the migrator will not attempt to split them.
#
# Usage:
#   scripts/migrate_halt_conditions.sh                # dry-run repo defaults
#   scripts/migrate_halt_conditions.sh path/to/SKILL.md ...
#   scripts/migrate_halt_conditions.sh --quiet ...    # suppress non-diff lines
#
# Exit code: 0 on success; 1 if any input file lacks halt_condition.

set -u

QUIET=0
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        --help|-h)
            sed -n '2,22p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) FILES+=("$1"); shift ;;
    esac
done

if [ ${#FILES[@]} -eq 0 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    ROOT="$(dirname "$SCRIPT_DIR")"
    for s in ci-fix fleet-orchestrator issue-work pr-work release research; do
        f="$ROOT/global/skills/$s/SKILL.md"
        [ -f "$f" ] && FILES+=("$f")
    done
fi

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "migrate_halt_conditions: python3/python not in PATH" >&2
    exit 2
fi

EXIT_CODE=0
for f in "${FILES[@]}"; do
    [ "$QUIET" -eq 0 ] && echo "=== $f ==="
    if ! "$PYTHON" - "$f" "$QUIET" <<'PY'
import re, sys

path = sys.argv[1]
quiet = sys.argv[2] == "1"

KEYWORD_RULES = [
    ("user",     re.compile(r"\b(user|human|aborts?|confirms?)\b", re.I)),
    ("fallback", re.compile(r"\b(unknown|escalat)\w*", re.I)),
    ("limit",    re.compile(r"\b(\d+\s+(retries|rounds|attempts)|in a row|drains?|target reached|consecutive|persists?\s+after)\b", re.I)),
    ("success",  re.compile(r"\b(all[- ]green|all\s+[\w\s]*pass(es)?|merged|published|complete[ds]?|reach(es)?\s+terminal|success|\bpass\b)\b", re.I)),
    ("failure",  re.compile(r"\b(fail\w*|error\w*|integrity)\b", re.I)),
]

def classify(clause: str) -> str:
    for ttype, rx in KEYWORD_RULES:
        if rx.search(clause):
            return ttype
    return "failure"

with open(path) as fh:
    text = fh.read()

m = re.search(r'^halt_condition:\s*"([^"]+)"\s*$', text, re.M)
if not m:
    if re.search(r'^halt_conditions:\s*$', text, re.M):
        print(f"  OK: already migrated (halt_conditions array present)")
        sys.exit(0)
    print(f"  SKIP: no halt_condition string found in {path}")
    sys.exit(1)

original = m.group(1)
if not quiet:
    print(f'  ORIGINAL: halt_condition: "{original}"')

clauses = [c.strip().rstrip(",;").strip() for c in re.split(r"\s*,?\s+OR\s+", original) if c.strip()]
compound = any(re.search(r"\s+AND\s+|;\s", c) for c in clauses)

if not quiet:
    print("  PROPOSED:")
    print("  halt_conditions:")
    for c in clauses:
        ttype = classify(c)
        print(f'    - {{ type: {ttype}, expr: "{c}" }}')
    if compound:
        print("  [MANUAL REVIEW: compound clause(s) detected]")
PY
    then
        EXIT_CODE=1
    fi
done

exit $EXIT_CODE
