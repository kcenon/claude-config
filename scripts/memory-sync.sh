#!/bin/bash
# memory-sync.sh -- Bidirectional sync between local memory clone and remote.
#
# Implements layers 3 (sync-pre-push) and 4 (sync-post-pull) of the five-layer
# defense described in docs/THREAT_MODEL.md (#534) and the design contract in
# issue #520. Operates on a local clone at ~/.claude/memory-shared/ that points
# at kcenon/claude-memory. All git mutations target branch `main`.
#
# Stage flow:
#   1. acquire_lock           flock; exit 5 on contention
#   2. validate_repo_state    is git repo, on main, no detached HEAD
#   3. capture_local_diff     local commits ahead and changed memory files
#   4. pre_push_validate      validate.sh + secret-check.sh on local diff
#   5. fetch_remote           git fetch origin
#   6. rebase_local_onto_remote   git rebase --autostash; abort + notify on conflict
#   7. post_pull_validate     all 3 validators on full memories/; auto-quarantine
#   8. regen_index            scripts/regen-index.sh; commit if drift
#   9. push_with_retry        git push; retry once on non-FF
#  10. release_lock           on EXIT trap
#  11. log_summary
#
# Exit codes (per issue #520 acceptance criteria):
#    0  success
#    1  pre-push validation failed
#    2  post-pull validation failed
#    3  merge conflict (rebase aborted)
#    4  push failed (still after one retry)
#    5  lock contention
#    6  git operation failed (other than the above)
#   64  usage error
#
# Bash 3.2 compatible (macOS default): no associative arrays, no mapfile,
# no `set -e` (issue #520 implementation notes prefer explicit return-code
# checks for clarity in this complex flow).

set -u

# ----- defaults -----

DEFAULT_LOCAL_CLONE="$HOME/.claude/memory-shared"
DEFAULT_LOG_FILE="$HOME/.claude/logs/memory-sync.log"
DEFAULT_LOCK_FILE="$HOME/.claude/.memory-sync.lock"
DEFAULT_LOCK_TIMEOUT=30
DEFAULT_BRANCH="main"
NOTIFY_SCRIPT="$HOME/.claude/scripts/memory-notify.sh"

# ----- runtime configuration (mutated by main()) -----

LOCAL_CLONE=""
LOG_FILE=""
LOCK_FILE=""
LOCK_TIMEOUT="$DEFAULT_LOCK_TIMEOUT"
DRY_RUN=0
PULL_ONLY=0
PUSH_ONLY=0
HOST_NAME=""

# Counters reported in log_summary.
DIFF_FILES_COUNT=0
DIFF_AHEAD_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
QUARANTINE_COUNT=0
PUSH_COUNT=0

# ----- usage -----

print_help() {
  cat <<'EOF'
memory-sync.sh -- bidirectional sync of the cross-machine claude-memory clone.

USAGE
    memory-sync.sh                          full sync (pull + push)
    memory-sync.sh --dry-run                show what would happen, no writes
    memory-sync.sh --pull-only              fetch + rebase + post-pull validate
    memory-sync.sh --push-only              pre-push validate + push only
    memory-sync.sh --lock-timeout SEC       flock timeout in seconds (default 30)
    memory-sync.sh --clone-dir PATH         override ~/.claude/memory-shared
    memory-sync.sh --log-file PATH          override ~/.claude/logs/memory-sync.log
    memory-sync.sh --lock-file PATH         override ~/.claude/.memory-sync.lock
    memory-sync.sh --help | -h              show this help

EXIT CODES
     0  success
     1  pre-push validation failed
     2  post-pull validation failed
     3  merge conflict (rebase aborted)
     4  push failed (after one retry)
     5  lock contention
     6  git operation failed (other than the above)
    64  usage error

NOTES
    The script never modifies ~/.claude/projects/.  It operates only on the
    clone directory. Symlinks from project memory dirs to the clone (set up
    by memory-bootstrap.sh #525) pass through transparently.

    A missing clone directory exits 6 with a diagnostic pointing at #525.
EOF
}

# ----- logging -----

# log <level> <stage> <message...>
# Always writes to stdout; appends to LOG_FILE when set. Timestamp is
# ISO 8601 UTC. Level is INFO|WARN|ERROR.
log() {
  local level="$1"
  local stage="$2"
  shift 2
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local line
  line="[${ts}] ${level} ${stage}: $*"
  printf '%s\n' "$line"
  if [[ -n "${LOG_FILE:-}" ]]; then
    # Ensure directory exists; ignore mkdir failures so logging stays
    # best-effort and never aborts the script.
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }

# notify <severity> <message>
# Calls the optional ~/.claude/scripts/memory-notify.sh hook (#524). When the
# hook is absent the call is a no-op so this script remains usable before
# #524 ships.
notify() {
  local severity="$1"
  local message="$2"
  if [[ -x "$NOTIFY_SCRIPT" ]]; then
    "$NOTIFY_SCRIPT" "$severity" "$message" >/dev/null 2>&1 || true
  fi
  log_info notify "severity=${severity} msg=${message}"
}

# dry_run_echo <words...>
# In dry-run mode, prints "[dry-run] would: <words>" and returns 0 without
# executing the underlying command. Caller is responsible for branching on
# DRY_RUN before invoking the real git/mv/commit.
dry_run_echo() {
  log_info dry-run "would: $*"
}

# ----- stage 1: lock -----

acquire_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
  exec 9>"$LOCK_FILE" || {
    log_error acquire_lock "cannot open lock file: $LOCK_FILE"
    return 6
  }
  if ! command -v flock >/dev/null 2>&1; then
    # macOS lacks flock by default; fall back to PID-file lock.
    if [[ -s "$LOCK_FILE" ]]; then
      local pid
      pid="$(head -1 "$LOCK_FILE" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        log_error acquire_lock "another sync running (pid=$pid)"
        return 5
      fi
    fi
    printf '%s\n' "$$" > "$LOCK_FILE"
    log_info acquire_lock "OK (pid-lock pid=$$)"
    return 0
  fi
  if ! flock -n -w "$LOCK_TIMEOUT" 9; then
    log_error acquire_lock "another sync running (timeout=${LOCK_TIMEOUT}s)"
    return 5
  fi
  printf '%s\n' "$$" >&9 2>/dev/null || true
  log_info acquire_lock "OK (flock pid=$$)"
  return 0
}

release_lock() {
  # The flock lease is released automatically when fd 9 closes on script
  # exit. Best-effort PID-file cleanup for the macOS fallback path.
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid="$(head -1 "$LOCK_FILE" 2>/dev/null || true)"
    if [[ "$pid" == "$$" ]]; then
      rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
  fi
}

# ----- stage 2: repo state -----

validate_repo_state() {
  if [[ ! -d "$LOCAL_CLONE" ]]; then
    log_error validate_repo_state "clone missing: $LOCAL_CLONE (run memory-bootstrap.sh from #525)"
    return 6
  fi
  if [[ ! -d "$LOCAL_CLONE/.git" ]]; then
    log_error validate_repo_state "not a git repo: $LOCAL_CLONE"
    return 6
  fi
  local branch
  branch="$(git -C "$LOCAL_CLONE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    log_error validate_repo_state "detached HEAD or no branch in $LOCAL_CLONE"
    return 6
  fi
  if [[ "$branch" != "$DEFAULT_BRANCH" ]]; then
    log_error validate_repo_state "expected branch=$DEFAULT_BRANCH, got=$branch"
    return 6
  fi
  if [[ ! -d "$LOCAL_CLONE/memories" ]]; then
    log_error validate_repo_state "missing memories/ dir in $LOCAL_CLONE"
    return 6
  fi
  log_info validate_repo_state "OK (branch=$branch)"
  return 0
}

# ----- stage 3: capture local diff -----

# Sets globals DIFF_AHEAD_COUNT, DIFF_FILES_COUNT, DIFF_FILES (newline-
# separated list of files changed under memories/ or quarantine/ in local
# commits ahead of origin/<branch>). Does NOT echo to stdout so callers can
# invoke directly (no `$(...)` subshell), preserving the global mutations.
DIFF_FILES=""
capture_local_diff() {
  local ahead=0
  ahead="$(git -C "$LOCAL_CLONE" rev-list --count "origin/${DEFAULT_BRANCH}..HEAD" 2>/dev/null || echo 0)"
  ahead="${ahead:-0}"
  DIFF_AHEAD_COUNT="$ahead"
  local files=""
  if (( ahead > 0 )); then
    files="$(git -C "$LOCAL_CLONE" diff --name-only "origin/${DEFAULT_BRANCH}..HEAD" -- 'memories/*.md' 'quarantine/*.md' 2>/dev/null || true)"
  fi
  # Uncommitted-but-tracked changes are handled by `git rebase --autostash`.
  # The pre-push contract validates only the committed-local-vs-origin diff.
  local files_count=0
  if [[ -n "$files" ]]; then
    files_count="$(printf '%s\n' "$files" | grep -c . || true)"
    files_count="${files_count:-0}"
  fi
  DIFF_FILES_COUNT="$files_count"
  DIFF_FILES="$files"
  log_info capture_local_diff "$ahead commits ahead, $files_count files changed"
  return 0
}

# ----- stage 4: pre-push validation -----

# Resolve the path to a memory validator. Validators live in this repo
# (claude-config) under scripts/memory/, but the runtime layout is the local
# clone of claude-config that the user has installed. We honour an env
# override (CLAUDE_CONFIG_DIR) and otherwise probe a couple of likely paths.
resolve_validator() {
  local name="$1"
  local candidates=(
    "${CLAUDE_CONFIG_DIR:-}/scripts/memory/$name"
    "$LOCAL_CLONE/scripts/$name"
    "$HOME/.claude/scripts/memory/$name"
    "$HOME/Development/claude-config/scripts/memory/$name"
    "$(cd "$(dirname "$0")" && pwd)/memory/$name"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

pre_push_validate() {
  local files="$1"
  if [[ -z "$files" ]]; then
    log_info pre_push_validate "skip (no local diff)"
    return 0
  fi

  local validate
  local secret
  local injection
  validate="$(resolve_validator validate.sh || true)"
  secret="$(resolve_validator secret-check.sh || true)"
  injection="$(resolve_validator injection-check.sh || true)"

  if [[ -z "$validate" || -z "$secret" ]]; then
    log_error pre_push_validate "validators not found (validate.sh / secret-check.sh)"
    return 6
  fi

  local f abs_path rc_v rc_s rc_i fail=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    abs_path="$LOCAL_CLONE/$f"
    if [[ ! -f "$abs_path" ]]; then
      # Deleted file: nothing to validate.
      continue
    fi
    "$validate" "$abs_path" >/dev/null
    rc_v=$?
    "$secret" "$abs_path" >/dev/null
    rc_s=$?
    rc_i=0
    if [[ -n "$injection" ]]; then
      "$injection" "$abs_path" >/dev/null
      rc_i=$?
    fi

    local v_label="PASS" s_label="CLEAN"
    case "$rc_v" in
      0) v_label="PASS" ;;
      1) v_label="FAIL-STRUCT"; fail=1 ;;
      2) v_label="FAIL-FORMAT"; fail=1 ;;
      3) v_label="WARN-SEMANTIC" ;;
      *) v_label="UNKNOWN($rc_v)"; fail=1 ;;
    esac
    case "$rc_s" in
      0) s_label="CLEAN" ;;
      1) s_label="SECRET-DETECTED"; fail=1 ;;
      *) s_label="UNKNOWN($rc_s)"; fail=1 ;;
    esac
    log_info pre_push_validate "  $f  validate=$v_label secret=$s_label"
    if (( rc_i == 3 )); then
      log_warn pre_push_validate "  $f  injection=FLAGGED (warn-only)"
    fi
  done <<< "$files"

  if (( fail > 0 )); then
    log_error pre_push_validate "blocking failure on local diff"
    notify high "memory-sync: pre-push validation failed on $HOST_NAME"
    return 1
  fi
  log_info pre_push_validate "all clean"
  return 0
}

# ----- stage 5: fetch remote -----

fetch_remote() {
  if (( DRY_RUN == 1 )); then
    dry_run_echo "git fetch origin"
    log_info fetch_remote "OK (dry-run)"
    return 0
  fi
  if ! git -C "$LOCAL_CLONE" fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1; then
    log_error fetch_remote "git fetch failed"
    notify high "memory-sync: git fetch failed on $HOST_NAME"
    return 6
  fi
  local behind
  behind="$(git -C "$LOCAL_CLONE" rev-list --count "HEAD..origin/${DEFAULT_BRANCH}" 2>/dev/null || echo 0)"
  behind="${behind:-0}"
  log_info fetch_remote "$behind commits behind"
  return 0
}

# ----- stage 6: rebase -----

rebase_local_onto_remote() {
  if (( DRY_RUN == 1 )); then
    dry_run_echo "git rebase --autostash origin/$DEFAULT_BRANCH"
    log_info rebase_local_onto_remote "OK (dry-run)"
    return 0
  fi
  local behind
  behind="$(git -C "$LOCAL_CLONE" rev-list --count "HEAD..origin/${DEFAULT_BRANCH}" 2>/dev/null || echo 0)"
  behind="${behind:-0}"
  if (( behind == 0 )); then
    log_info rebase_local_onto_remote "nothing to rebase (already on origin/$DEFAULT_BRANCH)"
    return 0
  fi
  if git -C "$LOCAL_CLONE" rebase --autostash "origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
    log_info rebase_local_onto_remote "rebased onto origin/$DEFAULT_BRANCH"
    return 0
  fi
  # Conflict path: abort cleanly.
  log_error rebase_local_onto_remote "CONFLICT (rebase aborted)"
  git -C "$LOCAL_CLONE" rebase --abort >/dev/null 2>&1 || true
  notify high "memory-sync: merge conflict on $HOST_NAME (manual resolution required)"
  return 3
}

# ----- stage 7: post-pull validation -----

post_pull_validate() {
  local validate
  local secret
  local injection
  local quarantine_move
  validate="$(resolve_validator validate.sh || true)"
  secret="$(resolve_validator secret-check.sh || true)"
  injection="$(resolve_validator injection-check.sh || true)"
  quarantine_move="$(resolve_validator quarantine-move.sh || true)"
  if [[ -z "$validate" || -z "$secret" ]]; then
    log_error post_pull_validate "validators not found"
    return 6
  fi

  local pass=0 fail=0 quarantined=0
  local f rc_v rc_s

  for f in "$LOCAL_CLONE/memories"/*.md; do
    [[ -f "$f" ]] || continue
    local base
    base="$(basename "$f")"
    [[ "$base" == "MEMORY.md" ]] && continue

    "$validate" "$f" >/dev/null
    rc_v=$?
    "$secret" "$f" >/dev/null
    rc_s=$?
    # injection is warn-only; do not factor into the fail count.
    if [[ -n "$injection" ]]; then
      "$injection" "$f" >/dev/null || true
    fi

    local file_failed=0
    if (( rc_v == 1 || rc_v == 2 )); then
      file_failed=1
    fi
    if (( rc_s == 1 )); then
      file_failed=1
    fi

    if (( file_failed == 1 )); then
      fail=$((fail + 1))
      log_warn post_pull_validate "  $base  validate=$rc_v secret=$rc_s -> auto-quarantine"
      if (( DRY_RUN == 1 )); then
        dry_run_echo "quarantine-move $base"
        quarantined=$((quarantined + 1))
        continue
      fi
      if [[ -n "$quarantine_move" ]]; then
        if "$quarantine_move" "$f" --reason "post-pull validation failed (validate=$rc_v secret=$rc_s) on $HOST_NAME" >/dev/null 2>&1; then
          quarantined=$((quarantined + 1))
        else
          log_error post_pull_validate "  $base  quarantine-move failed"
        fi
      else
        log_error post_pull_validate "quarantine-move.sh missing; cannot auto-quarantine"
      fi
    else
      pass=$((pass + 1))
    fi
  done

  PASS_COUNT="$pass"
  FAIL_COUNT="$fail"
  QUARANTINE_COUNT="$quarantined"

  log_info post_pull_validate "$pass PASS, $fail FAIL, $quarantined quarantined"

  # If we quarantined anything, commit the moves so other machines see them.
  if (( quarantined > 0 )) && (( DRY_RUN == 0 )); then
    if ! git -C "$LOCAL_CLONE" add memories quarantine >/dev/null 2>&1; then
      log_error post_pull_validate "git add failed during auto-quarantine commit"
      return 6
    fi
    if ! git -C "$LOCAL_CLONE" diff --cached --quiet 2>/dev/null; then
      if ! git -C "$LOCAL_CLONE" commit -m "chore: auto-quarantine on post-pull validation" >/dev/null 2>&1; then
        log_error post_pull_validate "git commit failed during auto-quarantine"
        return 6
      fi
      log_info post_pull_validate "committed auto-quarantine moves"
    fi
  fi

  if (( fail > 0 )); then
    notify high "memory-sync: post-pull validation found $fail problems on $HOST_NAME (auto-quarantined $quarantined)"
    return 2
  fi
  return 0
}

# ----- stage 8: regen index -----

regen_index() {
  if (( DRY_RUN == 1 )); then
    dry_run_echo "scripts/regen-index.sh"
    log_info regen_index "OK (dry-run)"
    return 0
  fi
  local regen="$LOCAL_CLONE/scripts/regen-index.sh"
  if [[ ! -x "$regen" ]]; then
    log_warn regen_index "regen-index.sh missing in clone; skipping"
    return 0
  fi
  if ! "$regen" >/dev/null 2>&1; then
    log_error regen_index "regen-index.sh failed"
    return 6
  fi
  # If MEMORY.md drifted, commit it.
  if ! git -C "$LOCAL_CLONE" diff --quiet -- memories/MEMORY.md 2>/dev/null; then
    if ! git -C "$LOCAL_CLONE" add memories/MEMORY.md >/dev/null 2>&1; then
      log_error regen_index "git add MEMORY.md failed"
      return 6
    fi
    if ! git -C "$LOCAL_CLONE" commit -m "chore: regenerate MEMORY.md index" >/dev/null 2>&1; then
      log_error regen_index "git commit MEMORY.md failed"
      return 6
    fi
    log_info regen_index "committed regenerated index"
  else
    log_info regen_index "no drift"
  fi
  return 0
}

# ----- stage 9: push with retry -----

push_with_retry() {
  local ahead
  ahead="$(git -C "$LOCAL_CLONE" rev-list --count "origin/${DEFAULT_BRANCH}..HEAD" 2>/dev/null || echo 0)"
  ahead="${ahead:-0}"
  if (( ahead == 0 )); then
    log_info push_with_retry "nothing to push"
    return 0
  fi
  if (( DRY_RUN == 1 )); then
    dry_run_echo "git push origin $DEFAULT_BRANCH ($ahead commits)"
    PUSH_COUNT="$ahead"
    log_info push_with_retry "OK (dry-run, $ahead commits)"
    return 0
  fi
  if git -C "$LOCAL_CLONE" push origin "$DEFAULT_BRANCH" >/dev/null 2>&1; then
    PUSH_COUNT="$ahead"
    log_info push_with_retry "$ahead commits pushed"
    return 0
  fi
  log_warn push_with_retry "push #1 rejected; retrying via fetch + rebase"

  # Re-run stages 5, 6, 7, 8 then attempt push #2.
  if ! fetch_remote; then
    return 6
  fi
  local rb_rc
  rebase_local_onto_remote
  rb_rc=$?
  if (( rb_rc == 3 )); then
    return 3
  fi
  if (( rb_rc != 0 )); then
    return 6
  fi
  local pp_rc
  post_pull_validate
  pp_rc=$?
  if (( pp_rc == 2 )); then
    return 2
  fi
  if (( pp_rc != 0 )); then
    return "$pp_rc"
  fi
  if ! regen_index; then
    return 6
  fi

  ahead="$(git -C "$LOCAL_CLONE" rev-list --count "origin/${DEFAULT_BRANCH}..HEAD" 2>/dev/null || echo 0)"
  ahead="${ahead:-0}"
  if (( ahead == 0 )); then
    log_info push_with_retry "nothing to push after retry rebase"
    return 0
  fi
  if git -C "$LOCAL_CLONE" push origin "$DEFAULT_BRANCH" >/dev/null 2>&1; then
    PUSH_COUNT="$ahead"
    log_info push_with_retry "$ahead commits pushed (retry)"
    return 0
  fi
  log_error push_with_retry "push #2 also rejected"
  notify high "memory-sync: push failed twice on $HOST_NAME"
  return 4
}

# ----- summary -----

log_summary() {
  local end_ts
  end_ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local elapsed=""
  if [[ -n "${START_EPOCH:-}" ]]; then
    local now_epoch
    now_epoch="$(date +%s)"
    elapsed="$((now_epoch - START_EPOCH))s"
  fi
  log_info summary "ahead=$DIFF_AHEAD_COUNT diff_files=$DIFF_FILES_COUNT pass=$PASS_COUNT fail=$FAIL_COUNT quarantined=$QUARANTINE_COUNT pushed=$PUSH_COUNT elapsed=$elapsed"
}

# ----- argument parsing -----

parse_args() {
  LOCAL_CLONE="${MEMORY_SYNC_CLONE:-$DEFAULT_LOCAL_CLONE}"
  LOG_FILE="${MEMORY_SYNC_LOG:-$DEFAULT_LOG_FILE}"
  LOCK_FILE="${MEMORY_SYNC_LOCK:-$DEFAULT_LOCK_FILE}"
  LOCK_TIMEOUT="$DEFAULT_LOCK_TIMEOUT"
  DRY_RUN=0
  PULL_ONLY=0
  PUSH_ONLY=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
        exit 0
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --pull-only)
        PULL_ONLY=1
        shift
        ;;
      --push-only)
        PUSH_ONLY=1
        shift
        ;;
      --lock-timeout)
        if [[ $# -lt 2 ]]; then
          printf 'error: --lock-timeout requires a value\n' >&2
          exit 64
        fi
        LOCK_TIMEOUT="$2"
        shift 2
        ;;
      --clone-dir)
        if [[ $# -lt 2 ]]; then
          printf 'error: --clone-dir requires a value\n' >&2
          exit 64
        fi
        LOCAL_CLONE="$2"
        shift 2
        ;;
      --log-file)
        if [[ $# -lt 2 ]]; then
          printf 'error: --log-file requires a value\n' >&2
          exit 64
        fi
        LOG_FILE="$2"
        shift 2
        ;;
      --lock-file)
        if [[ $# -lt 2 ]]; then
          printf 'error: --lock-file requires a value\n' >&2
          exit 64
        fi
        LOCK_FILE="$2"
        shift 2
        ;;
      *)
        printf 'error: unknown argument: %s\n' "$1" >&2
        print_help >&2
        exit 64
        ;;
    esac
  done

  if (( PULL_ONLY == 1 )) && (( PUSH_ONLY == 1 )); then
    printf 'error: --pull-only and --push-only are mutually exclusive\n' >&2
    exit 64
  fi
}

# ----- main -----

main() {
  parse_args "$@"

  HOST_NAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
  START_EPOCH="$(date +%s)"

  log_info start "host=$HOST_NAME mode=$( (( DRY_RUN==1 )) && echo dry-run || echo live ) pull_only=$PULL_ONLY push_only=$PUSH_ONLY"

  trap 'release_lock' EXIT
  acquire_lock || exit $?
  validate_repo_state || exit $?

  capture_local_diff

  local rc

  # Pre-push validation (skip in pull-only mode).
  if (( PULL_ONLY == 0 )); then
    pre_push_validate "$DIFF_FILES"
    rc=$?
    if (( rc != 0 )); then
      log_summary
      exit "$rc"
    fi
  fi

  # Pull half (skip in push-only mode).
  if (( PUSH_ONLY == 0 )); then
    fetch_remote
    rc=$?
    if (( rc != 0 )); then log_summary; exit "$rc"; fi

    rebase_local_onto_remote
    rc=$?
    if (( rc != 0 )); then log_summary; exit "$rc"; fi

    post_pull_validate
    rc=$?
    if (( rc != 0 )); then log_summary; exit "$rc"; fi

    regen_index
    rc=$?
    if (( rc != 0 )); then log_summary; exit "$rc"; fi
  fi

  # Push half (skip in pull-only mode).
  if (( PULL_ONLY == 0 )); then
    push_with_retry
    rc=$?
    if (( rc != 0 )); then log_summary; exit "$rc"; fi
  fi

  log_summary
  log_info complete "OK"
  exit 0
}

main "$@"
