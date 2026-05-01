#!/bin/bash
# memory-notify.sh -- Centralized notification helper for memory-* scripts.
#
# Used by memory-sync.sh (#520), memory-write-guard.sh (#521), and the
# SessionStart memory-integrity-check.sh (#522) to surface failures to the
# user without burying them in logs. Routes alerts to OS notification
# channels (macOS terminal-notifier / osascript; Linux notify-send) and a
# persistent log read by the integrity-check hook on session start.
#
# Operations:
#   emit (default)   memory-notify.sh <severity> <message>
#   dismiss          memory-notify.sh --dismiss [<id>]
#   list             memory-notify.sh --list [--all|--unread]
#   help             memory-notify.sh --help|-h
#
# Severity (per issue #524):
#   info       informational (e.g., audit completed clean)
#   warn       needs attention (e.g., sync delayed)
#   critical   needs immediate attention (e.g., merge conflict)
#   high       alias for critical (kept for memory-sync.sh #520 callers)
#
# Exit codes:
#   0   emit succeeded (regardless of OS-channel success)
#   1   invalid severity
#   2   message empty
#   64  usage error
#
# Best-effort by design: OS-notification failures and log-write failures do
# not propagate to the caller. The script always exits 0 on a well-formed
# emit so upstream scripts (sync, write-guard) are never broken by missing
# notification dependencies.
#
# Bash 3.2 compatible (macOS default): no associative arrays, no mapfile,
# explicit ${var:-default} guards.

set -u

# ----- defaults -----

DEFAULT_LOG_FILE="$HOME/.claude/logs/memory-alerts.log"
DEFAULT_READ_MARK="$HOME/.claude/.memory-alerts-read-mark"
DEDUP_WINDOW_SECONDS=3600
DEDUP_SCAN_LINES=200

# ----- runtime configuration (mutated by parse_args) -----

LOG_FILE=""
READ_MARK=""

# ----- usage -----

print_help() {
  cat <<'EOF'
memory-notify.sh -- centralized notification helper for memory-* scripts.

USAGE
    memory-notify.sh <severity> <message>            emit an alert
    memory-notify.sh --dismiss [<id>]                mark unread alerts as read
    memory-notify.sh --list [--all|--unread]         list alerts (default unread)
    memory-notify.sh --help | -h                     show this help

SEVERITY
    info        informational (e.g., audit completed clean)
    warn        needs attention but not urgent (e.g., sync delayed)
    critical    needs immediate attention (e.g., merge conflict)
    high        alias for critical (memory-sync.sh #520 caller compatibility)

OPTIONS
    --log-file PATH      override ~/.claude/logs/memory-alerts.log
    --read-mark PATH     override ~/.claude/.memory-alerts-read-mark

EXIT CODES
     0  emit succeeded (regardless of OS-channel success)
     1  invalid severity
     2  message empty
    64  usage error

NOTES
    Dedup: a `<severity, message>` pair re-emitted within 1 hour is silently
    suppressed (no log append, no OS notification).

    OS notification is best-effort: macOS uses terminal-notifier when
    installed, otherwise falls back to osascript. Linux uses notify-send.
    Neither channel failing affects the exit code.

    The persistent log lives at ~/.claude/logs/memory-alerts.log and is
    appended one line per alert in the form:

      <ISO timestamp> <severity> <hash12> <message>

    The SessionStart integrity-check hook (#522) reads this log to surface
    "you missed N alerts" on the next session start.
EOF
}

# ----- helpers -----

# epoch_now -- print current Unix epoch.
epoch_now() {
  date +%s
}

# iso_now -- print current time in ISO 8601 UTC.
iso_now() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

# iso_to_epoch <iso8601-utc> -- convert ISO 8601 (UTC, ending in Z) to epoch.
# Tries GNU date first, falls back to BSD date.
iso_to_epoch() {
  local iso="$1"
  local epoch=""
  # GNU date.
  epoch="$(date -u -d "$iso" +%s 2>/dev/null || true)"
  if [[ -n "$epoch" ]]; then
    printf '%s' "$epoch"
    return 0
  fi
  # BSD date (macOS): strip trailing Z and parse with explicit format.
  local stripped="${iso%Z}"
  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$stripped" +%s 2>/dev/null || true)"
  if [[ -n "$epoch" ]]; then
    printf '%s' "$epoch"
    return 0
  fi
  printf '0'
}

# sha12 <text> -- print first 12 hex chars of SHA-256 of <text>.
sha12() {
  local text="$1"
  local hash=""
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(printf '%s' "$text" | sha256sum 2>/dev/null | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(printf '%s' "$text" | shasum -a 256 2>/dev/null | awk '{print $1}')"
  else
    # Last-resort fallback: not cryptographic, but enough for dedup ids.
    hash="$(printf '%s' "$text" | cksum 2>/dev/null | awk '{printf "%012x", $1}')"
  fi
  printf '%s' "${hash:0:12}"
}

# normalize_severity <input> -- map case-insensitive severity to canonical
# form. Returns 0 with canonical severity on stdout, 1 if invalid.
# Canonical levels are info|warn|critical. The alias `high` maps to
# critical so existing memory-sync.sh #520 callers continue to work.
normalize_severity() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    info|warn|critical)
      printf '%s' "$lower"
      return 0
      ;;
    high)
      printf 'critical'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# escape_message <message> -- collapse newlines/CR to spaces so log entries
# stay single-line. Trims surrounding whitespace.
escape_message() {
  local msg="$1"
  msg="${msg//$'\r'/ }"
  msg="${msg//$'\n'/ }"
  msg="${msg//$'\t'/ }"
  # Trim leading/trailing spaces (bash 3.2 compatible).
  while [[ "$msg" == ' '* ]]; do msg="${msg# }"; done
  while [[ "$msg" == *' ' ]]; do msg="${msg% }"; done
  printf '%s' "$msg"
}

# log_dir -- ensure log directory exists; best-effort.
ensure_log_dir() {
  local dir
  dir="$(dirname "$LOG_FILE")"
  [[ -d "$dir" ]] && return 0
  mkdir -p "$dir" 2>/dev/null || true
}

# is_dup <severity> <hash> -- exit 0 if same severity+hash appears in the
# trailing DEDUP_SCAN_LINES of the log within DEDUP_WINDOW_SECONDS, else 1.
is_dup() {
  local severity="$1"
  local hash="$2"
  [[ -f "$LOG_FILE" ]] || return 1
  local now
  now="$(epoch_now)"
  local line ts iso line_severity line_hash line_epoch
  # Read the tail. tail returns nothing on empty file -- no error.
  local tail_out
  tail_out="$(tail -n "$DEDUP_SCAN_LINES" "$LOG_FILE" 2>/dev/null || true)"
  [[ -z "$tail_out" ]] && return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Format: <ISO> <severity> <hash12> <message>
    ts="${line%% *}"
    local rest="${line#* }"
    line_severity="${rest%% *}"
    rest="${rest#* }"
    line_hash="${rest%% *}"
    if [[ "$line_severity" == "$severity" && "$line_hash" == "$hash" ]]; then
      line_epoch="$(iso_to_epoch "$ts")"
      if (( line_epoch > 0 )) && (( now - line_epoch < DEDUP_WINDOW_SECONDS )); then
        return 0
      fi
    fi
  done <<< "$tail_out"
  return 1
}

# os_notify <severity> <message> -- best-effort OS-channel notification.
# All errors swallowed; never affects exit status.
os_notify() {
  local severity="$1"
  local message="$2"
  local title="Claude Memory"
  local subtitle="$severity"

  # Detect macOS first (Darwin).
  if [[ "$(uname 2>/dev/null || printf '')" == "Darwin" ]]; then
    if command -v terminal-notifier >/dev/null 2>&1; then
      terminal-notifier -title "$title" -subtitle "$subtitle" -message "$message" >/dev/null 2>&1 || true
      return 0
    fi
    if command -v osascript >/dev/null 2>&1; then
      # Escape double quotes and backslashes for AppleScript string literals.
      local esc_msg esc_subtitle
      esc_msg="${message//\\/\\\\}"
      esc_msg="${esc_msg//\"/\\\"}"
      esc_subtitle="${subtitle//\\/\\\\}"
      esc_subtitle="${esc_subtitle//\"/\\\"}"
      osascript -e "display notification \"$esc_msg\" with title \"$title\" subtitle \"$esc_subtitle\"" >/dev/null 2>&1 || true
      return 0
    fi
    return 0
  fi

  # Linux: notify-send if available and a session bus is reachable.
  if command -v notify-send >/dev/null 2>&1; then
    local urgency="normal"
    case "$severity" in
      info)     urgency="low" ;;
      warn)     urgency="normal" ;;
      critical) urgency="critical" ;;
    esac
    notify-send --urgency="$urgency" "$title: $severity" "$message" >/dev/null 2>&1 || true
    return 0
  fi
  return 0
}

# ----- emit -----

emit_alert() {
  local severity_raw="$1"
  local message_raw="$2"

  local severity
  severity="$(normalize_severity "$severity_raw" || true)"
  if [[ -z "$severity" ]]; then
    printf 'error: invalid severity: %s (expected info|warn|critical)\n' "$severity_raw" >&2
    return 1
  fi

  local message
  message="$(escape_message "$message_raw")"
  if [[ -z "$message" ]]; then
    printf 'error: message empty\n' >&2
    return 2
  fi

  local hash
  hash="$(sha12 "${severity}:${message}")"

  ensure_log_dir

  if is_dup "$severity" "$hash"; then
    # Silent dedup; honour Caller-Friendly contract.
    return 0
  fi

  local ts
  ts="$(iso_now)"
  local line="${ts} ${severity} ${hash} ${message}"

  # Append to log (best-effort). Append is line-atomic for messages
  # smaller than PIPE_BUF on POSIX.
  if [[ -n "$LOG_FILE" ]]; then
    if ! printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null; then
      printf '%s\n' "$line" >&2
    fi
  fi

  os_notify "$severity" "$message"
  return 0
}

# ----- dismiss -----

dismiss_alerts() {
  local id="${1:-}"
  ensure_log_dir
  local mark_dir
  mark_dir="$(dirname "$READ_MARK")"
  mkdir -p "$mark_dir" 2>/dev/null || true

  if [[ -z "$id" ]]; then
    # Mark everything currently in the log as read.
    local count=0
    if [[ -f "$LOG_FILE" ]]; then
      count="$(unread_count_internal)"
    fi
    # Atomic write via temp file + mv.
    local tmp="${READ_MARK}.tmp.$$"
    if printf '%s\n' "$(iso_now)" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$READ_MARK" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
    printf 'Dismissed %s unread alert(s).\n' "$count"
    return 0
  fi

  # Per-id dismiss: append the id to the read-mark side-file so list
  # filtering can skip it. Format: one id per line under a separate file
  # to avoid clobbering the all-dismiss timestamp.
  local id_file="${READ_MARK}.ids"
  if [[ -f "$id_file" ]] && grep -Fxq "$id" "$id_file" 2>/dev/null; then
    printf 'Alert %s already dismissed.\n' "$id"
    return 0
  fi
  if printf '%s\n' "$id" >> "$id_file" 2>/dev/null; then
    printf 'Dismissed alert %s.\n' "$id"
  else
    printf 'error: could not write read-mark id file: %s\n' "$id_file" >&2
  fi
  return 0
}

# unread_count_internal -- count alerts in the log not yet dismissed.
# Used by dismiss-all to report a count, and by --list --unread to filter.
unread_count_internal() {
  [[ -f "$LOG_FILE" ]] || { printf '0'; return 0; }
  local mark_epoch=0
  if [[ -s "$READ_MARK" ]]; then
    local mark_iso
    mark_iso="$(head -1 "$READ_MARK" 2>/dev/null || printf '')"
    mark_epoch="$(iso_to_epoch "$mark_iso")"
    mark_epoch="${mark_epoch:-0}"
  fi
  local id_file="${READ_MARK}.ids"
  local n=0
  local line ts hash entry_epoch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ts="${line%% *}"
    local rest="${line#* * }"
    hash="${rest%% *}"
    entry_epoch="$(iso_to_epoch "$ts")"
    entry_epoch="${entry_epoch:-0}"
    if (( entry_epoch <= mark_epoch )); then
      continue
    fi
    if [[ -f "$id_file" ]] && grep -Fxq "$hash" "$id_file" 2>/dev/null; then
      continue
    fi
    n=$((n + 1))
  done < "$LOG_FILE"
  printf '%s' "$n"
}

# ----- list -----

# time_ago_from_epoch <epoch> -- human-friendly relative time.
time_ago_from_epoch() {
  local epoch="$1"
  [[ -z "$epoch" || "$epoch" == "0" ]] && { printf 'unknown'; return; }
  local now diff
  now="$(epoch_now)"
  diff=$((now - epoch))
  if (( diff < 0 )); then diff=0; fi
  if (( diff < 60 )); then
    printf '%ss ago' "$diff"
  elif (( diff < 3600 )); then
    printf '%s min ago' "$((diff / 60))"
  elif (( diff < 86400 )); then
    printf '%s hr ago' "$((diff / 3600))"
  else
    printf '%s day ago' "$((diff / 86400))"
  fi
}

list_alerts() {
  local mode="$1"  # all|unread
  if [[ ! -f "$LOG_FILE" ]]; then
    printf 'No alerts.\n'
    return 0
  fi

  local mark_epoch=0
  if [[ "$mode" == "unread" && -s "$READ_MARK" ]]; then
    local mark_iso
    mark_iso="$(head -1 "$READ_MARK" 2>/dev/null || printf '')"
    mark_epoch="$(iso_to_epoch "$mark_iso")"
    mark_epoch="${mark_epoch:-0}"
  fi
  local id_file="${READ_MARK}.ids"

  local printed=0
  local line ts severity hash msg entry_epoch
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ts="${line%% *}"
    local rest="${line#* }"
    severity="${rest%% *}"
    rest="${rest#* }"
    hash="${rest%% *}"
    msg="${rest#* }"

    if [[ "$mode" == "unread" ]]; then
      entry_epoch="$(iso_to_epoch "$ts")"
      entry_epoch="${entry_epoch:-0}"
      if (( entry_epoch <= mark_epoch )); then
        continue
      fi
      if [[ -f "$id_file" ]] && grep -Fxq "$hash" "$id_file" 2>/dev/null; then
        continue
      fi
    fi

    entry_epoch="$(iso_to_epoch "$ts")"
    local ago
    ago="$(time_ago_from_epoch "$entry_epoch")"
    printf '[%s] %-12s %-8s %s\n' "$hash" "$ago" "$severity" "$msg"
    printed=$((printed + 1))
  done < "$LOG_FILE"

  if (( printed == 0 )); then
    if [[ "$mode" == "unread" ]]; then
      printf 'No unread alerts.\n'
    else
      printf 'No alerts.\n'
    fi
  fi
  return 0
}

# ----- argument parsing -----

parse_args() {
  LOG_FILE="${MEMORY_NOTIFY_LOG:-$DEFAULT_LOG_FILE}"
  READ_MARK="${MEMORY_NOTIFY_READ_MARK:-$DEFAULT_READ_MARK}"

  if [[ $# -eq 0 ]]; then
    print_help >&2
    exit 64
  fi

  # First, scan for global options that may appear before the operation.
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-file)
        if [[ $# -lt 2 ]]; then
          printf 'error: --log-file requires a value\n' >&2
          exit 64
        fi
        LOG_FILE="$2"
        shift 2
        ;;
      --read-mark)
        if [[ $# -lt 2 ]]; then
          printf 'error: --read-mark requires a value\n' >&2
          exit 64
        fi
        READ_MARK="$2"
        shift 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${#positional[@]}" -eq 0 ]]; then
    print_help >&2
    exit 64
  fi

  case "${positional[0]}" in
    -h|--help)
      print_help
      exit 0
      ;;
    --dismiss)
      local id="${positional[1]:-}"
      if [[ "${#positional[@]}" -gt 2 ]]; then
        printf 'error: --dismiss accepts at most one id\n' >&2
        exit 64
      fi
      dismiss_alerts "$id"
      exit 0
      ;;
    --list)
      local mode="unread"
      local i=1
      while (( i < ${#positional[@]} )); do
        case "${positional[$i]}" in
          --all)    mode="all" ;;
          --unread) mode="unread" ;;
          *)
            printf 'error: unknown --list option: %s\n' "${positional[$i]}" >&2
            exit 64
            ;;
        esac
        i=$((i + 1))
      done
      list_alerts "$mode"
      exit 0
      ;;
    -*)
      printf 'error: unknown option: %s\n' "${positional[0]}" >&2
      print_help >&2
      exit 64
      ;;
    *)
      # Positional emit form: <severity> <message>
      if [[ "${#positional[@]}" -lt 2 ]]; then
        printf 'error: emit requires <severity> <message>\n' >&2
        exit 64
      fi
      local severity="${positional[0]}"
      # Join remaining positionals into a single message in case the caller
      # forgot to quote. This is a convenience; recommended usage is to quote.
      local message
      if [[ "${#positional[@]}" -eq 2 ]]; then
        message="${positional[1]}"
      else
        message="${positional[*]:1}"
      fi
      emit_alert "$severity" "$message"
      exit $?
      ;;
  esac
}

# ----- main -----

main() {
  parse_args "$@"
}

main "$@"
