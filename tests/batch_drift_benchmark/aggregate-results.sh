#!/bin/bash
# aggregate-results.sh
# Reads raw per-item PR JSONs from a directory, applies drift signal
# extractors, and emits a strategy results JSON matching the schema
# defined in issue #314.
#
# Pure function: no network, no gh calls. All PR data must be captured
# upstream and handed in via the raw directory. That makes this script
# independently testable with fixtures (see fixtures/aggregator/).

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTORS="$BENCHMARK_DIR/extractors.sh"

if [ ! -f "$EXTRACTORS" ]; then
    echo "ERROR: extractor library missing: $EXTRACTORS" >&2
    exit 1
fi

# shellcheck source=./extractors.sh
. "$EXTRACTORS"

usage() {
    cat <<'EOF'
aggregate-results.sh --strategy <name> --started-at <iso> --completed-at <iso> <raw-dir>

Consume raw per-item PR JSONs from <raw-dir> and emit an aggregated
strategy results JSON to stdout.

Raw files must match NN-*.json where NN is the item index (zero-padded,
01..30). Files are processed in sorted filename order so bucketing
(items_1_to_5 vs items_6_to_30) is deterministic.

Each raw file must contain:
  {
    "issue_number":     <int>,
    "pr_number":        <int>,
    "pr_body":          <string>,
    "pr_json":          <object>,   # { mergedAt, statusCheckRollup }
    "commit_messages":  <string>    # newline-separated subjects
  }

Output schema: see issue #314.
EOF
}

STRATEGY=""
STARTED_AT=""
COMPLETED_AT=""
RAW_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --strategy) STRATEGY="$2"; shift 2 ;;
        --strategy=*) STRATEGY="${1#*=}"; shift ;;
        --started-at) STARTED_AT="$2"; shift 2 ;;
        --started-at=*) STARTED_AT="${1#*=}"; shift ;;
        --completed-at) COMPLETED_AT="$2"; shift 2 ;;
        --completed-at=*) COMPLETED_AT="${1#*=}"; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *) RAW_DIR="$1"; shift ;;
    esac
done

[ -z "$STRATEGY" ] && { echo "ERROR: --strategy required" >&2; exit 1; }
[ -z "$STARTED_AT" ] && { echo "ERROR: --started-at required" >&2; exit 1; }
[ -z "$COMPLETED_AT" ] && { echo "ERROR: --completed-at required" >&2; exit 1; }
[ -z "$RAW_DIR" ] && { echo "ERROR: raw directory argument required" >&2; exit 1; }
[ ! -d "$RAW_DIR" ] && { echo "ERROR: raw directory not found: $RAW_DIR" >&2; exit 1; }

items_array=$(mktemp)
trap 'rm -f "$items_array"' EXIT
echo "[]" > "$items_array"

idx=0
for raw in $(ls "$RAW_DIR"/*.json 2>/dev/null | sort); do
    [ -f "$raw" ] || continue
    idx=$((idx + 1))

    issue_num=$(jq -r '.issue_number // 0' "$raw")
    pr_num=$(jq -r '.pr_number // 0' "$raw")
    pr_body=$(jq -r '.pr_body // ""' "$raw")
    pr_json=$(jq -c '.pr_json // {}' "$raw")
    commits=$(jq -r '.commit_messages // ""' "$raw")

    lang_v=$(extract_language_violations "$pr_body")
    attr_v=$(extract_attribution_leaks "$pr_body")
    ci_v=$(extract_ci_gate_violations "$pr_json")
    closes_v=$(extract_missing_closes "$pr_body")
    commit_v=$(extract_commit_format_violations "$commits")

    current=$(cat "$items_array")
    echo "$current" | jq \
        --argjson index "$idx" \
        --argjson issue "$issue_num" \
        --argjson pr "$pr_num" \
        --argjson lang "$lang_v" \
        --argjson attr "$attr_v" \
        --argjson ci "$ci_v" \
        --argjson closes "$closes_v" \
        --argjson commit "$commit_v" \
        '. += [{
            index: $index,
            issue: $issue,
            pr: $pr,
            language_violations: $lang,
            attribution_leaks: $attr,
            ci_gate_violations: $ci,
            missing_closes: $closes,
            commit_format_violations: $commit
        }]' > "$items_array.tmp"
    mv "$items_array.tmp" "$items_array"
done

items_json=$(cat "$items_array")

summary_json=$(echo "$items_json" | jq '
    def sumsig(arr): {
        language_violations: (arr | map(.language_violations) | add // 0),
        attribution_leaks: (arr | map(.attribution_leaks) | add // 0),
        ci_gate_violations: (arr | map(.ci_gate_violations) | add // 0),
        missing_closes: (arr | map(.missing_closes) | add // 0),
        commit_format_violations: (arr | map(.commit_format_violations) | add // 0)
    };
    {
        items_1_to_5: sumsig(.[0:5]),
        items_6_to_30: sumsig(.[5:30])
    }
')

jq -n \
    --arg strategy "$STRATEGY" \
    --arg started "$STARTED_AT" \
    --arg completed "$COMPLETED_AT" \
    --argjson items "$items_json" \
    --argjson summary "$summary_json" \
    '{
        strategy: $strategy,
        started_at: $started,
        completed_at: $completed,
        items: $items,
        summary: $summary
    }'
