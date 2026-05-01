#!/bin/bash
# memory-status.sh -- Read-only diagnostic CLI for the cross-machine memory
# system. Aggregates state from the local memory clone, git history, audit
# reports, and the alerts log. Intended as the on-demand counterpart to the
# SessionStart hook (#522).
#
# Three output modes:
#   (default) brief    one-screen human summary
#   --detail           brief + per-machine activity, audit history,
#                      tier-by-type matrix, stale entries
#   --json             machine-readable JSON (jq optional)
#
# Reads only. Never mutates the clone, never triggers sync, never writes the
# alerts log or read-mark.
#
# Exit codes:
#    0   healthy (or successfully reported state)
#    1   warnings present (stale memories, unread alerts, pending push/pull)
#    2   errors (clone missing, repo invalid)
#   64   usage error
#
# Bash 3.2 compatible (macOS default): no associative arrays, no mapfile,
# explicit return-code checks.

set -u

# ----- defaults (mirror memory-sync.sh #520 conventions) -----

DEFAULT_LOCAL_CLONE="$HOME/.claude/memory-shared"
DEFAULT_ALERTS_LOG="$HOME/.claude/logs/memory-alerts.log"
DEFAULT_ALERTS_READ_MARK="$HOME/.claude/.memory-alerts-read-mark"
DEFAULT_BRANCH="main"
STALE_THRESHOLD_DAYS=90
ALERTS_TAIL_LINES=100
AUDIT_HISTORY_DEFAULT=4

# ----- runtime configuration (mutated by parse_args) -----

LOCAL_CLONE=""
ALERTS_LOG=""
ALERTS_READ_MARK=""
MODE="brief"           # brief | detail | json
USE_COLOR=0

# ----- exit-code accumulator -----
# 0 healthy, 1 warning, 2 error. Code only increases.
STATUS_CODE=0
bump_status() {
  local n="$1"
  if (( n > STATUS_CODE )); then
    STATUS_CODE="$n"
  fi
}

# ----- usage -----

print_help() {
  cat <<'EOF'
memory-status.sh -- diagnostic CLI for the cross-machine memory system.

USAGE
    memory-status.sh                        brief health summary (default)
    memory-status.sh --detail               + machines, audit, tier matrix
    memory-status.sh --json                 machine-readable JSON
    memory-status.sh --clone-dir PATH       override ~/.claude/memory-shared
    memory-status.sh --alerts-log PATH      override ~/.claude/logs/memory-alerts.log
    memory-status.sh --read-mark PATH       override ~/.claude/.memory-alerts-read-mark
    memory-status.sh --help | -h            show this help

EXIT CODES
     0  healthy
     1  warnings (stale entries, unread alerts, pending push/pull)
     2  errors (clone missing, repo invalid)
    64  usage error

NOTES
    Read-only. Never modifies the clone, alerts log, or read-mark.
    Color output is suppressed when stdout is not a tty.
EOF
}

parse_args() {
  LOCAL_CLONE="${CLAUDE_MEMORY_CLONE:-$DEFAULT_LOCAL_CLONE}"
  ALERTS_LOG="${CLAUDE_MEMORY_ALERTS_LOG:-$DEFAULT_ALERTS_LOG}"
  ALERTS_READ_MARK="${CLAUDE_MEMORY_ALERTS_READ_MARK:-$DEFAULT_ALERTS_READ_MARK}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --detail)         MODE="detail"; shift ;;
      --json)           MODE="json"; shift ;;
      --clone-dir)
        [[ $# -ge 2 ]] || { printf 'error: --clone-dir requires PATH\n' >&2; exit 64; }
        LOCAL_CLONE="$2"; shift 2 ;;
      --alerts-log)
        [[ $# -ge 2 ]] || { printf 'error: --alerts-log requires PATH\n' >&2; exit 64; }
        ALERTS_LOG="$2"; shift 2 ;;
      --read-mark)
        [[ $# -ge 2 ]] || { printf 'error: --read-mark requires PATH\n' >&2; exit 64; }
        ALERTS_READ_MARK="$2"; shift 2 ;;
      --help|-h)        print_help; exit 0 ;;
      --)               shift; break ;;
      -*)
        printf 'error: unknown option %s\n' "$1" >&2
        exit 64 ;;
      *)
        printf 'error: unexpected argument %s\n' "$1" >&2
        exit 64 ;;
    esac
  done

  if [[ "$MODE" != "json" ]] && [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    USE_COLOR=1
  fi
}

# ----- color helpers (no-op outside tty) -----

c_dim()   { if (( USE_COLOR )); then tput dim    2>/dev/null; fi; }
c_bold()  { if (( USE_COLOR )); then tput bold   2>/dev/null; fi; }
c_red()   { if (( USE_COLOR )); then tput setaf 1 2>/dev/null; fi; }
c_green() { if (( USE_COLOR )); then tput setaf 2 2>/dev/null; fi; }
c_yel()   { if (( USE_COLOR )); then tput setaf 3 2>/dev/null; fi; }
c_off()   { if (( USE_COLOR )); then tput sgr0   2>/dev/null; fi; }

# ----- time helpers -----

# Convert seconds-ago to a short human label like "37 min", "2h", "3d".
# 0..119 sec -> "<n> sec"; 2..119 min -> "<n> min"; 2..47 h -> "<n>h";
# >=48 h -> "<n>d". Bash 3.2 safe (no integer overflow expected for our scale).
human_ago_seconds() {
  local s="${1:-0}"
  if [[ -z "$s" ]] || [[ "$s" -lt 0 ]]; then s=0; fi
  if (( s < 120 )); then printf '%d sec' "$s"; return; fi
  local m=$(( s / 60 ))
  if (( m < 120 )); then printf '%d min' "$m"; return; fi
  local h=$(( m / 60 ))
  if (( h < 48 )); then printf '%dh' "$h"; return; fi
  local d=$(( h / 24 ))
  printf '%dd' "$d"
}

# Convert a date string `YYYY-MM-DD` to weekday name. Empty on parse failure.
date_to_weekday() {
  local d="$1"
  local out=""
  case "$(uname)" in
    Darwin)
      out="$(date -j -f '%Y-%m-%d' "$d" '+%A' 2>/dev/null || true)" ;;
    *)
      out="$(date -d "$d" '+%A' 2>/dev/null || true)" ;;
  esac
  # Trim leading/trailing whitespace (bash 3.2 safe).
  out="${out#"${out%%[![:space:]]*}"}"
  out="${out%"${out##*[![:space:]]}"}"
  printf '%s' "$out"
}

# Now in epoch seconds (cross-platform).
now_epoch() { date +%s; }

# Epoch seconds for `YYYY-MM-DD`. Empty on parse failure.
date_to_epoch() {
  local d="$1"
  local out=""
  case "$(uname)" in
    Darwin)
      out="$(date -j -f '%Y-%m-%d' "$d" '+%s' 2>/dev/null || true)" ;;
    *)
      out="$(date -d "$d" '+%s' 2>/dev/null || true)" ;;
  esac
  printf '%s' "$out"
}

# Epoch seconds for an ISO 8601 datetime (with or without timezone).
# Empty on parse failure.
iso_to_epoch() {
  local s="$1"
  local out=""
  case "$(uname)" in
    Darwin)
      # Try with tz suffix first, then without.
      out="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${s/Z/+0000}" '+%s' 2>/dev/null || true)"
      if [[ -z "$out" ]]; then
        out="$(date -j -f '%Y-%m-%dT%H:%M:%S' "${s%%Z}" '+%s' 2>/dev/null || true)"
      fi
      ;;
    *)
      out="$(date -d "$s" '+%s' 2>/dev/null || true)" ;;
  esac
  printf '%s' "$out"
}

# ----- JSON helpers (jq optional) -----

# Quote a string as a JSON string literal. Escapes \, ", control chars.
json_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# ----- repo state -----

REPO_PRESENT=0
REPO_BRANCH=""
TRACKING_STATUS="unknown"   # up_to_date | ahead | behind | diverged | no_upstream | no_commits
PENDING_PUSH=0
PENDING_PULL=0
LAST_SYNC_ISO=""
LAST_SYNC_AGO_SEC=0
LAST_SYNC_HOST=""
HAS_COMMITS=0

probe_repo_state() {
  if [[ ! -d "$LOCAL_CLONE" ]]; then
    REPO_PRESENT=0
    return
  fi
  if ! git -C "$LOCAL_CLONE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_PRESENT=0
    return
  fi
  REPO_PRESENT=1

  REPO_BRANCH="$(git -C "$LOCAL_CLONE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  # ahead/behind without `git status` (which refreshes the index and counts as
  # a write per `find -newer`). We use `rev-parse` + `rev-list --count`, both
  # of which are pure read operations on the object database.
  local has_head=0
  if git -C "$LOCAL_CLONE" rev-parse --verify HEAD >/dev/null 2>&1; then
    has_head=1
  fi

  local upstream=""
  upstream="$(git -C "$LOCAL_CLONE" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"

  if (( has_head == 0 )); then
    TRACKING_STATUS="no_commits"
  elif [[ -z "$upstream" ]]; then
    TRACKING_STATUS="no_upstream"
  else
    local ahead behind
    ahead="$(git -C "$LOCAL_CLONE" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
    behind="$(git -C "$LOCAL_CLONE" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
    PENDING_PUSH="${ahead:-0}"
    PENDING_PULL="${behind:-0}"
    if (( PENDING_PUSH == 0 )) && (( PENDING_PULL == 0 )); then
      TRACKING_STATUS="up_to_date"
    elif (( PENDING_PUSH > 0 )) && (( PENDING_PULL == 0 )); then
      TRACKING_STATUS="ahead"
    elif (( PENDING_PULL > 0 )) && (( PENDING_PUSH == 0 )); then
      TRACKING_STATUS="behind"
    else
      TRACKING_STATUS="diverged"
    fi
  fi

  # Last commit / sync probe.
  local last
  last="$(git -C "$LOCAL_CLONE" log -1 --format='%cI%x09%an' 2>/dev/null || true)"
  if [[ -n "$last" ]]; then
    HAS_COMMITS=1
    LAST_SYNC_ISO="${last%%	*}"
    LAST_SYNC_HOST="${last#*	}"
    local epoch
    epoch="$(iso_to_epoch "$LAST_SYNC_ISO")"
    if [[ -n "$epoch" ]]; then
      LAST_SYNC_AGO_SEC=$(( $(now_epoch) - epoch ))
      if (( LAST_SYNC_AGO_SEC < 0 )); then LAST_SYNC_AGO_SEC=0; fi
    fi
  fi
}

# ----- memory counts -----

MEM_TOTAL=0
MEM_VERIFIED=0
MEM_INFERRED=0
MEM_QUARANTINED=0
MEM_TYPE_USER=0
MEM_TYPE_FEEDBACK=0
MEM_TYPE_PROJECT=0
MEM_TYPE_REFERENCE=0
# 4x3 tier-by-type counters (tier rows: verified/inferred/quarantined).
# Bash 3.2 -- use parallel scalar vars.
MTX_USER_VERIFIED=0;       MTX_USER_INFERRED=0;       MTX_USER_QUAR=0
MTX_FEEDBACK_VERIFIED=0;   MTX_FEEDBACK_INFERRED=0;   MTX_FEEDBACK_QUAR=0
MTX_PROJECT_VERIFIED=0;    MTX_PROJECT_INFERRED=0;    MTX_PROJECT_QUAR=0
MTX_REFERENCE_VERIFIED=0;  MTX_REFERENCE_INFERRED=0;  MTX_REFERENCE_QUAR=0

# Stale list (verified files with last-verified > STALE_THRESHOLD_DAYS).
# Bash 3.2: newline-separated string instead of array growth.
STALE_LIST=""

# Read a single frontmatter scalar `key: value` from the first 40 lines.
# Returns the value (trimmed) or empty.
fm_field() {
  local file="$1" key="$2"
  local line
  line="$(head -n 40 "$file" 2>/dev/null | grep -E "^${key}:[[:space:]]" | head -n 1 || true)"
  if [[ -z "$line" ]]; then return; fi
  local v="${line#${key}:}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# Increment matrix cell `type+tier`.
mtx_inc() {
  local t="$1" tier="$2"
  case "$t.$tier" in
    user.verified)         MTX_USER_VERIFIED=$((MTX_USER_VERIFIED+1)) ;;
    user.inferred)         MTX_USER_INFERRED=$((MTX_USER_INFERRED+1)) ;;
    user.quarantined)      MTX_USER_QUAR=$((MTX_USER_QUAR+1)) ;;
    feedback.verified)     MTX_FEEDBACK_VERIFIED=$((MTX_FEEDBACK_VERIFIED+1)) ;;
    feedback.inferred)     MTX_FEEDBACK_INFERRED=$((MTX_FEEDBACK_INFERRED+1)) ;;
    feedback.quarantined)  MTX_FEEDBACK_QUAR=$((MTX_FEEDBACK_QUAR+1)) ;;
    project.verified)      MTX_PROJECT_VERIFIED=$((MTX_PROJECT_VERIFIED+1)) ;;
    project.inferred)      MTX_PROJECT_INFERRED=$((MTX_PROJECT_INFERRED+1)) ;;
    project.quarantined)   MTX_PROJECT_QUAR=$((MTX_PROJECT_QUAR+1)) ;;
    reference.verified)    MTX_REFERENCE_VERIFIED=$((MTX_REFERENCE_VERIFIED+1)) ;;
    reference.inferred)    MTX_REFERENCE_INFERRED=$((MTX_REFERENCE_INFERRED+1)) ;;
    reference.quarantined) MTX_REFERENCE_QUAR=$((MTX_REFERENCE_QUAR+1)) ;;
  esac
}

# Type by filename prefix (per docs/MEMORY_TRUST_MODEL.md storage layout).
infer_type_by_name() {
  local name="$1"
  case "$name" in
    user_*)      printf 'user' ;;
    feedback_*)  printf 'feedback' ;;
    project_*)   printf 'project' ;;
    reference_*) printf 'reference' ;;
    *)           printf '' ;;
  esac
}

count_memories() {
  if (( REPO_PRESENT == 0 )); then return; fi

  local now_e
  now_e="$(now_epoch)"
  local stale_cutoff=$(( now_e - STALE_THRESHOLD_DAYS * 86400 ))

  local f base type_v tier_v lv_v fmt_type
  for f in "$LOCAL_CLONE"/memories/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"

    type_v="$(fm_field "$f" 'type')"
    tier_v="$(fm_field "$f" 'trust-level')"
    lv_v="$(fm_field "$f" 'last-verified')"

    fmt_type="$(infer_type_by_name "$base")"
    # Frontmatter wins; filename is fallback.
    if [[ -z "$type_v" ]]; then type_v="$fmt_type"; fi
    if [[ -z "$tier_v" ]]; then
      printf 'memory-status: warn: %s missing trust-level; skipping tier count\n' "$base" >&2
      MEM_TOTAL=$((MEM_TOTAL+1))
      continue
    fi

    MEM_TOTAL=$((MEM_TOTAL+1))

    case "$tier_v" in
      verified)    MEM_VERIFIED=$((MEM_VERIFIED+1)) ;;
      inferred)    MEM_INFERRED=$((MEM_INFERRED+1)) ;;
      quarantined) MEM_QUARANTINED=$((MEM_QUARANTINED+1)) ;;
      *)
        printf 'memory-status: warn: %s has unknown trust-level %s\n' "$base" "$tier_v" >&2
        ;;
    esac

    case "$type_v" in
      user)      MEM_TYPE_USER=$((MEM_TYPE_USER+1)) ;;
      feedback)  MEM_TYPE_FEEDBACK=$((MEM_TYPE_FEEDBACK+1)) ;;
      project)   MEM_TYPE_PROJECT=$((MEM_TYPE_PROJECT+1)) ;;
      reference) MEM_TYPE_REFERENCE=$((MEM_TYPE_REFERENCE+1)) ;;
    esac

    mtx_inc "$type_v" "$tier_v"

    # Stale check: tier=verified, last-verified older than threshold.
    if [[ "$tier_v" == "verified" ]] && [[ -n "$lv_v" ]]; then
      local lv_epoch
      lv_epoch="$(date_to_epoch "$lv_v")"
      if [[ -n "$lv_epoch" ]] && [[ "$lv_epoch" -lt "$stale_cutoff" ]]; then
        if [[ -n "$STALE_LIST" ]]; then STALE_LIST="${STALE_LIST}"$'\n'; fi
        STALE_LIST="${STALE_LIST}${base}|${lv_v}"
      fi
    fi
  done

  # Quarantine directory contributes additional quarantined entries that may
  # not appear in memories/. They are real and should be counted.
  for f in "$LOCAL_CLONE"/quarantine/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    type_v="$(infer_type_by_name "$base")"
    MEM_TOTAL=$((MEM_TOTAL+1))
    MEM_QUARANTINED=$((MEM_QUARANTINED+1))
    case "$type_v" in
      user)      MTX_USER_QUAR=$((MTX_USER_QUAR+1));        MEM_TYPE_USER=$((MEM_TYPE_USER+1)) ;;
      feedback)  MTX_FEEDBACK_QUAR=$((MTX_FEEDBACK_QUAR+1));  MEM_TYPE_FEEDBACK=$((MEM_TYPE_FEEDBACK+1)) ;;
      project)   MTX_PROJECT_QUAR=$((MTX_PROJECT_QUAR+1));   MEM_TYPE_PROJECT=$((MEM_TYPE_PROJECT+1)) ;;
      reference) MTX_REFERENCE_QUAR=$((MTX_REFERENCE_QUAR+1)); MEM_TYPE_REFERENCE=$((MEM_TYPE_REFERENCE+1)) ;;
    esac
  done
}

# ----- audit history -----

AUDIT_LAST_ISO=""
AUDIT_LAST_STALE=0
AUDIT_LAST_CONFLICTS=0
AUDIT_LAST_UNUSED=0
AUDIT_LAST_QREVIEW=0
AUDIT_HISTORY=""

# Parse a single audit report. Per #F1/#F3/#G2 the report is a markdown file
# whose first ~60 lines contain counters with substrings like `2 stale`,
# `0 conflicts`, etc. We extract the numbers via tolerant regex; missing
# counters default to 0.
parse_audit_summary() {
  local f="$1"
  local body
  body="$(head -n 60 "$f" 2>/dev/null || true)"
  local stale=0 conflicts=0 unused=0 qreview=0
  local re_stale='([0-9]+)[[:space:]]+stale'
  local re_conf='([0-9]+)[[:space:]]+conflict'
  local re_unu='([0-9]+)[[:space:]]+unused'
  local re_qr='([0-9]+)[[:space:]]+quarantine'
  if [[ "$body" =~ $re_stale ]]; then stale="${BASH_REMATCH[1]}"; fi
  if [[ "$body" =~ $re_conf  ]]; then conflicts="${BASH_REMATCH[1]}"; fi
  if [[ "$body" =~ $re_unu   ]]; then unused="${BASH_REMATCH[1]}"; fi
  if [[ "$body" =~ $re_qr    ]]; then qreview="${BASH_REMATCH[1]}"; fi
  printf '%s|%s|%s|%s' "$stale" "$conflicts" "$unused" "$qreview"
}

probe_audit_history() {
  if (( REPO_PRESENT == 0 )); then return; fi
  local audit_dir="$LOCAL_CLONE/audit"
  if [[ ! -d "$audit_dir" ]]; then return; fi

  # Audit reports named with leading ISO date. Sort reverse-chronological.
  local files
  files="$(ls -1 "$audit_dir"/*.md 2>/dev/null | sort -r || true)"
  [[ -z "$files" ]] && return

  local count=0
  local f base date_part findings
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    base="$(basename "$f")"
    if [[ "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      date_part="${BASH_REMATCH[1]}"
    else
      continue
    fi
    findings="$(parse_audit_summary "$f")"
    if [[ -n "$AUDIT_HISTORY" ]]; then AUDIT_HISTORY="${AUDIT_HISTORY}"$'\n'; fi
    AUDIT_HISTORY="${AUDIT_HISTORY}${date_part}|${findings}"
    count=$((count+1))
    if (( count == 1 )); then
      AUDIT_LAST_ISO="$date_part"
      AUDIT_LAST_STALE="${findings%%|*}"
      local rest="${findings#*|}"
      AUDIT_LAST_CONFLICTS="${rest%%|*}"
      rest="${rest#*|}"
      AUDIT_LAST_UNUSED="${rest%%|*}"
      AUDIT_LAST_QREVIEW="${rest##*|}"
    fi
    if (( count >= AUDIT_HISTORY_DEFAULT )); then break; fi
  done <<<"$files"
}

# ----- alerts -----

UNREAD_ALERTS=0

probe_alerts() {
  if [[ ! -f "$ALERTS_LOG" ]]; then return; fi
  # Read-mark file: epoch second of last read, per #524 contract.
  local mark=0
  if [[ -f "$ALERTS_READ_MARK" ]]; then
    mark="$(head -n 1 "$ALERTS_READ_MARK" 2>/dev/null | tr -dc '0-9' || true)"
    mark="${mark:-0}"
  fi

  # Tail for performance per acceptance criteria (logs may grow).
  # Each line: "<ISO datetime> <severity> <message>"
  local line iso epoch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    iso="$(printf '%s' "$line" | awk '{print $1}')"
    epoch="$(iso_to_epoch "$iso")"
    if [[ -z "$epoch" ]]; then continue; fi
    if (( epoch > mark )); then
      UNREAD_ALERTS=$((UNREAD_ALERTS+1))
    fi
  done < <(tail -n "$ALERTS_TAIL_LINES" "$ALERTS_LOG" 2>/dev/null || true)
}

# ----- per-machine activity (last 30 days) -----

# MACHINE_LIST: newline-separated `name|commits_30d|last_push_ago_seconds`.
MACHINE_LIST=""

probe_machines() {
  if (( REPO_PRESENT == 0 )); then return; fi
  if (( HAS_COMMITS == 0 )); then return; fi

  local raw
  raw="$(git -C "$LOCAL_CLONE" log --since='30 days ago' --pretty=format:'%cI%x09%an' 2>/dev/null || true)"
  [[ -z "$raw" ]] && return

  local now_e
  now_e="$(now_epoch)"

  # Group by author: count + most-recent ISO. awk used purely for in-memory
  # grouping arithmetic (no redirection), per implementation-notes guidance.
  local processed
  processed="$(printf '%s\n' "$raw" | awk -F'\t' '
    {
      cnt[$2]++
      if (last[$2] == "" || $1 > last[$2]) last[$2] = $1
    }
    END {
      for (a in cnt) printf "%s\t%d\t%s\n", a, cnt[a], last[a]
    }
  ' 2>/dev/null || true)"

  # Sort by commits descending, then name.
  processed="$(printf '%s\n' "$processed" | sort -t$'\t' -k2,2nr -k1,1 || true)"

  local author count last_iso last_epoch ago_s
  while IFS=$'\t' read -r author count last_iso; do
    [[ -z "$author" ]] && continue
    last_epoch="$(iso_to_epoch "$last_iso")"
    if [[ -n "$last_epoch" ]]; then
      ago_s=$(( now_e - last_epoch ))
      if (( ago_s < 0 )); then ago_s=0; fi
    else
      ago_s=0
    fi
    if [[ -n "$MACHINE_LIST" ]]; then MACHINE_LIST="${MACHINE_LIST}"$'\n'; fi
    MACHINE_LIST="${MACHINE_LIST}${author}|${count}|${ago_s}"
  done <<<"$processed"
}

# ----- output: brief -----

emit_brief() {
  if (( REPO_PRESENT == 0 )); then
    if [[ ! -d "$LOCAL_CLONE" ]]; then
      printf '%s[error]%s %s not found; run memory-bootstrap.sh\n' \
        "$(c_red)" "$(c_off)" "$LOCAL_CLONE" >&2
    else
      printf '%s[error]%s %s exists but is not a git repo; run memory-bootstrap.sh\n' \
        "$(c_red)" "$(c_off)" "$LOCAL_CLONE" >&2
    fi
    bump_status 2
    return
  fi

  printf 'Repository: %s\n' "$LOCAL_CLONE"

  local track_phrase
  case "$TRACKING_STATUS" in
    up_to_date)  track_phrase="up to date with origin/${REPO_BRANCH}" ;;
    ahead)       track_phrase="$(printf 'ahead of origin/%s by %d' "$REPO_BRANCH" "$PENDING_PUSH")" ;;
    behind)      track_phrase="$(printf 'behind origin/%s by %d' "$REPO_BRANCH" "$PENDING_PULL")" ;;
    diverged)    track_phrase="$(printf 'diverged: %d ahead, %d behind' "$PENDING_PUSH" "$PENDING_PULL")" ;;
    no_upstream) track_phrase="no upstream tracking" ;;
    no_commits)  track_phrase="no commits yet" ;;
    *)           track_phrase="$TRACKING_STATUS" ;;
  esac
  printf 'Branch: %s (%s)\n' "${REPO_BRANCH:-?}" "$track_phrase"

  if (( HAS_COMMITS == 1 )) && [[ -n "$LAST_SYNC_ISO" ]]; then
    local ago
    ago="$(human_ago_seconds "$LAST_SYNC_AGO_SEC")"
    printf 'Last sync: %s (%s ago)\n' "$LAST_SYNC_ISO" "$ago"
  else
    printf 'Last sync: never (no commits yet)\n'
  fi

  printf 'Memories: %d (verified:%d, inferred:%d, quarantined:%d)\n' \
    "$MEM_TOTAL" "$MEM_VERIFIED" "$MEM_INFERRED" "$MEM_QUARANTINED"

  printf 'Pending push: %d commits\n' "$PENDING_PUSH"
  printf 'Pending pull: %d commits\n' "$PENDING_PULL"

  if [[ -n "$AUDIT_LAST_ISO" ]]; then
    local wd
    wd="$(date_to_weekday "$AUDIT_LAST_ISO")"
    if [[ -n "$wd" ]]; then
      printf 'Last audit: %s (%s) - %d stale, %d conflicts, %d unused\n' \
        "$AUDIT_LAST_ISO" "$wd" "$AUDIT_LAST_STALE" "$AUDIT_LAST_CONFLICTS" "$AUDIT_LAST_UNUSED"
    else
      printf 'Last audit: %s - %d stale, %d conflicts, %d unused\n' \
        "$AUDIT_LAST_ISO" "$AUDIT_LAST_STALE" "$AUDIT_LAST_CONFLICTS" "$AUDIT_LAST_UNUSED"
    fi
  else
    printf 'Last audit: never\n'
  fi

  printf 'Recent alerts: %d\n' "$UNREAD_ALERTS"

  # Status accumulation: stale, pending push/pull, unread alerts -> warn.
  if [[ -n "$STALE_LIST" ]]; then bump_status 1; fi
  if (( PENDING_PUSH > 0 )) || (( PENDING_PULL > 0 )); then bump_status 1; fi
  if (( UNREAD_ALERTS > 0 )); then bump_status 1; fi

  # Recommendations.
  local rec=""
  if (( PENDING_PUSH > 0 )); then
    rec="${rec}  - Run \`memory-sync.sh --push-only\` to ship $PENDING_PUSH local commit(s)."$'\n'
  fi
  if (( PENDING_PULL > 0 )); then
    rec="${rec}  - Run \`memory-sync.sh --pull-only\` to fetch $PENDING_PULL remote commit(s)."$'\n'
  fi
  if [[ "$TRACKING_STATUS" == "diverged" ]]; then
    rec="${rec}  - Diverged: run \`memory-sync.sh\` to rebase + push."$'\n'
  fi
  if (( UNREAD_ALERTS > 0 )); then
    rec="${rec}  - $UNREAD_ALERTS unread alert(s); review $ALERTS_LOG."$'\n'
  fi
  if [[ -n "$STALE_LIST" ]]; then
    local stale_count
    stale_count="$(printf '%s\n' "$STALE_LIST" | grep -c . || true)"
    rec="${rec}  - $stale_count stale entry(ies); run --detail to list, then re-affirm via /memory-review."$'\n'
  fi
  if [[ -n "$rec" ]]; then
    printf 'Recommendations:\n%s' "$rec"
  fi
}

# ----- output: detail (printed AFTER brief) -----

emit_detail() {
  if (( REPO_PRESENT == 0 )); then return; fi

  printf '\n'

  # Active machines.
  printf 'Active machines (last 30 days):\n'
  if [[ -z "$MACHINE_LIST" ]]; then
    printf '  (none)\n'
  else
    # Compute max name width (capped at 25); render aligned rows.
    local maxw=0 line name count ago_s
    while IFS='|' read -r name count ago_s; do
      [[ -z "$name" ]] && continue
      local nl=${#name}
      if (( nl > 25 )); then nl=25; fi
      if (( nl > maxw )); then maxw=$nl; fi
    done <<<"$MACHINE_LIST"
    while IFS='|' read -r name count ago_s; do
      [[ -z "$name" ]] && continue
      if (( ${#name} > 25 )); then name="${name:0:24}+"; fi
      local ago_label
      ago_label="$(human_ago_seconds "$ago_s")"
      printf '  %-*s  last-push: %-8s  commits: %3d\n' "$maxw" "$name" "${ago_label} ago" "$count"
    done <<<"$MACHINE_LIST"
  fi

  printf '\n'

  # Audit history.
  printf 'Audit history (last %d reports):\n' "$AUDIT_HISTORY_DEFAULT"
  if [[ -z "$AUDIT_HISTORY" ]]; then
    printf '  (none)\n'
  else
    local d s c u q
    while IFS='|' read -r d s c u q; do
      [[ -z "$d" ]] && continue
      printf '  %s: %d stale, %d conflicts, %d unused, %d quarantine review\n' \
        "$d" "$s" "$c" "$u" "$q"
    done <<<"$AUDIT_HISTORY"
  fi

  printf '\n'

  # Tier-by-type matrix.
  printf 'Trust-level distribution by type:\n'
  printf '            verified  inferred  quarantined\n'
  printf '  user      %8d  %8d  %11d\n' \
    "$MTX_USER_VERIFIED"      "$MTX_USER_INFERRED"      "$MTX_USER_QUAR"
  printf '  feedback  %8d  %8d  %11d\n' \
    "$MTX_FEEDBACK_VERIFIED"  "$MTX_FEEDBACK_INFERRED"  "$MTX_FEEDBACK_QUAR"
  printf '  project   %8d  %8d  %11d\n' \
    "$MTX_PROJECT_VERIFIED"   "$MTX_PROJECT_INFERRED"   "$MTX_PROJECT_QUAR"
  printf '  reference %8d  %8d  %11d\n' \
    "$MTX_REFERENCE_VERIFIED" "$MTX_REFERENCE_INFERRED" "$MTX_REFERENCE_QUAR"

  printf '\n'

  # Stale entries.
  printf 'Stale entries (last-verified > %d days):\n' "$STALE_THRESHOLD_DAYS"
  if [[ -z "$STALE_LIST" ]]; then
    printf '  (none)\n'
  else
    local name lv
    while IFS='|' read -r name lv; do
      [[ -z "$name" ]] && continue
      printf '  %s (last-verified: %s)\n' "$name" "$lv"
    done <<<"$STALE_LIST"
  fi

  printf '\n'

  # Recent alerts (count only; full read is left to operator).
  if (( UNREAD_ALERTS == 0 )); then
    printf 'Recent unread alerts: (none)\n'
  else
    printf 'Recent unread alerts: %d (see %s)\n' "$UNREAD_ALERTS" "$ALERTS_LOG"
  fi
}

# ----- output: json -----

emit_json() {
  # Build JSON by hand. jq is optional and we never depend on it -- per
  # acceptance criteria.

  if (( REPO_PRESENT == 0 )); then
    printf '{"error":"clone_missing","clone":%s}\n' "$(json_quote "$LOCAL_CLONE")"
    bump_status 2
    return
  fi

  # Stale array.
  local stale_json="[]"
  if [[ -n "$STALE_LIST" ]]; then
    local entries=""
    local name lv first=1
    while IFS='|' read -r name lv; do
      [[ -z "$name" ]] && continue
      if (( first == 1 )); then first=0; else entries="${entries},"; fi
      entries="${entries}$(json_quote "$name")"
    done <<<"$STALE_LIST"
    stale_json="[${entries}]"
  fi

  # Machines array.
  local machines_json="[]"
  if [[ -n "$MACHINE_LIST" ]]; then
    local entries="" name count ago_s first=1
    while IFS='|' read -r name count ago_s; do
      [[ -z "$name" ]] && continue
      if (( first == 1 )); then first=0; else entries="${entries},"; fi
      entries="${entries}{\"name\":$(json_quote "$name"),\"last_push_ago_seconds\":${ago_s},\"commits_30d\":${count}}"
    done <<<"$MACHINE_LIST"
    machines_json="[${entries}]"
  fi

  # Last sync object (or null).
  local last_sync_json="null"
  if (( HAS_COMMITS == 1 )) && [[ -n "$LAST_SYNC_ISO" ]]; then
    last_sync_json="{\"iso\":$(json_quote "$LAST_SYNC_ISO"),\"ago_seconds\":${LAST_SYNC_AGO_SEC},\"host\":$(json_quote "$LAST_SYNC_HOST")}"
  fi

  # Audit object.
  local audit_json="null"
  if [[ -n "$AUDIT_LAST_ISO" ]]; then
    audit_json="{\"last_iso\":$(json_quote "$AUDIT_LAST_ISO"),\"last_findings\":{\"stale\":${AUDIT_LAST_STALE},\"conflicts\":${AUDIT_LAST_CONFLICTS},\"unused\":${AUDIT_LAST_UNUSED},\"quarantine_review\":${AUDIT_LAST_QREVIEW}}}"
  fi

  # Status accumulation matches emit_brief so JSON callers see the same code.
  if [[ -n "$STALE_LIST" ]]; then bump_status 1; fi
  if (( PENDING_PUSH > 0 )) || (( PENDING_PULL > 0 )); then bump_status 1; fi
  if (( UNREAD_ALERTS > 0 )); then bump_status 1; fi

  printf '{'
  printf '"repo":%s,' "$(json_quote "$LOCAL_CLONE")"
  printf '"branch":%s,' "$(json_quote "${REPO_BRANCH:-}")"
  printf '"tracking_status":%s,' "$(json_quote "$TRACKING_STATUS")"
  printf '"last_sync":%s,' "$last_sync_json"
  printf '"memories":{"total":%d,"by_tier":{"verified":%d,"inferred":%d,"quarantined":%d},"by_type":{"user":%d,"feedback":%d,"project":%d,"reference":%d}},' \
    "$MEM_TOTAL" "$MEM_VERIFIED" "$MEM_INFERRED" "$MEM_QUARANTINED" \
    "$MEM_TYPE_USER" "$MEM_TYPE_FEEDBACK" "$MEM_TYPE_PROJECT" "$MEM_TYPE_REFERENCE"
  printf '"pending":{"push":%d,"pull":%d},' "$PENDING_PUSH" "$PENDING_PULL"
  printf '"stale":%s,' "$stale_json"
  printf '"machines":%s,' "$machines_json"
  printf '"audit":%s,' "$audit_json"
  printf '"unread_alerts":%d,' "$UNREAD_ALERTS"
  printf '"status_code":%d' "$STATUS_CODE"
  printf '}\n'
}

# ----- main -----

main() {
  parse_args "$@"

  probe_repo_state
  count_memories
  probe_audit_history
  probe_alerts
  probe_machines

  case "$MODE" in
    json)
      emit_json
      ;;
    detail)
      emit_brief
      emit_detail
      ;;
    *)
      emit_brief
      ;;
  esac

  exit "$STATUS_CODE"
}

main "$@"
