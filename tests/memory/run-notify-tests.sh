#!/bin/bash
# run-notify-tests.sh -- Integration tests for scripts/memory-notify.sh.
#
# Exercises memory-notify.sh against synthetic log/read-mark files in a temp
# dir under /tmp/memory-notify-test-<pid>. The user's real ~/.claude/ tree
# is never touched: every run uses --log-file and --read-mark overrides (or
# the MEMORY_NOTIFY_LOG / MEMORY_NOTIFY_READ_MARK env vars).
#
# Test scenarios (per issue #524 Test Plan):
#   T1   emit critical -> log line appears, exit 0
#   T2   re-emit identical within window -> log unchanged (dedup)
#   T3   emit different severity, same message -> log gets both
#   T4   emit, backdate log entry past dedup window, re-emit -> log gets new entry
#   T5   --list unread shows entries
#   T6   --dismiss -> --list unread shows none
#   T7   --list --all shows entries even after dismiss
#   T8   invalid severity -> exit 1
#   T9   empty message -> exit 2
#   T10  no args -> exit 64
#   T11  alias "high" maps to critical (memory-sync.sh #520 caller compat)
#   T12  message with newlines is collapsed to single line
#   T13  --dismiss <id> only marks that id
#   T14  --help -> exit 0
#
# Bash 3.2 compatible. No `set -e`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NOTIFY_SCRIPT="${REPO_ROOT}/scripts/memory-notify.sh"

TEST_TMP_BASE="${TMPDIR:-/tmp}/memory-notify-test-$$"
PASS_COUNT=0
FAIL_COUNT=0

log() {
  printf '[%s] %s\n' "$(date -u +'%H:%M:%SZ')" "$*"
}

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS: $label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL: $label (expected $expected, got $actual)"
  fi
}

assert_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS: $label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL: $label (missing '$needle')"
    log "    haystack: $haystack"
  fi
}

assert_not_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS: $label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL: $label (unexpectedly contained '$needle')"
  fi
}

mk_test_dir() {
  local d="${TEST_TMP_BASE}/case-$$-${RANDOM}"
  mkdir -p "$d"
  printf '%s' "$d"
}

cleanup_all() {
  rm -rf "$TEST_TMP_BASE" 2>/dev/null || true
}

trap cleanup_all EXIT

# Suppress real OS notifications during tests by neutralising notifier
# commands on PATH for the spawned subprocess. We export a PATH-prefix dir
# of stub no-op commands so the script still detects them but they do
# nothing visible.
make_silent_path() {
  local stub_dir="$1"
  mkdir -p "$stub_dir"
  for cmd in osascript notify-send terminal-notifier; do
    cat > "$stub_dir/$cmd" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$stub_dir/$cmd"
  done
  printf '%s' "$stub_dir"
}

# ----- T1: emit critical succeeds, log gets one line -----
test_T1() {
  log "T1: emit critical -> exit 0, log line appears"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "memory-sync: merge conflict on hostA"
  local rc=$?
  assert_eq "T1 exit code" "0" "$rc"

  if [[ -f "$logf" ]]; then
    local lines
    lines="$(wc -l < "$logf" | tr -d ' ')"
    assert_eq "T1 log line count" "1" "$lines"
    local content
    content="$(cat "$logf")"
    assert_contains "T1 log contains severity" "critical" "$content"
    assert_contains "T1 log contains message" "memory-sync: merge conflict on hostA" "$content"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL: T1 log file not created"
  fi
}

# ----- T2: dedup within window -----
test_T2() {
  log "T2: re-emit identical within window -> dedup (log unchanged)"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "sync delayed"
  local first_lines
  first_lines="$(wc -l < "$logf" | tr -d ' ')"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "sync delayed"
  local rc=$?
  local second_lines
  second_lines="$(wc -l < "$logf" | tr -d ' ')"

  assert_eq "T2 dedup exit code" "0" "$rc"
  assert_eq "T2 line count unchanged" "$first_lines" "$second_lines"
}

# ----- T3: different severity, same message -> two entries -----
test_T3() {
  log "T3: different severity, same message -> log gets both"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" info "audit clean"
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "audit clean"

  local lines
  lines="$(wc -l < "$logf" | tr -d ' ')"
  assert_eq "T3 line count" "2" "$lines"
}

# ----- T4: backdate log entry, re-emit -> new entry -----
test_T4() {
  log "T4: outside dedup window -> log gets new entry"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  # First emit normally.
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "old conflict"
  # Manually replace the timestamp with one 2 hours ago to simulate aging.
  local old_iso
  if date -u -d '2 hours ago' +'%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    old_iso="$(date -u -d '2 hours ago' +'%Y-%m-%dT%H:%M:%SZ')"
  else
    # BSD date (macOS).
    old_iso="$(date -u -v-2H +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '2020-01-01T00:00:00Z')"
  fi
  # Rewrite the file: replace the existing timestamp prefix with old_iso.
  local existing_line
  existing_line="$(head -1 "$logf")"
  local rest="${existing_line#* }"
  printf '%s %s\n' "$old_iso" "$rest" > "$logf"

  # Re-emit; should bypass dedup because old entry is > 1 hour old.
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "old conflict"
  local lines
  lines="$(wc -l < "$logf" | tr -d ' ')"
  assert_eq "T4 line count" "2" "$lines"
}

# ----- T5: --list unread shows entries -----
test_T5() {
  log "T5: --list shows unread entries"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "list test alert"
  local out
  out="$(PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --list)"
  assert_contains "T5 list shows alert message" "list test alert" "$out"
  assert_contains "T5 list shows severity" "critical" "$out"
}

# ----- T6: --dismiss then --list unread -> none -----
test_T6() {
  log "T6: --dismiss clears unread"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "dismiss me"
  # On some systems wc -l gives leading whitespace; the count itself is
  # what matters, not for this test.

  local dis_out
  dis_out="$(PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --dismiss)"
  assert_contains "T6 dismiss reports count" "Dismissed" "$dis_out"

  local list_out
  list_out="$(PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --list)"
  assert_contains "T6 list reports no unread" "No unread alerts" "$list_out"
}

# ----- T7: --list --all shows entries even after dismiss -----
test_T7() {
  log "T7: --list --all shows alerts after dismiss"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "history alert"
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --dismiss >/dev/null

  local out
  out="$(PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --list --all)"
  assert_contains "T7 --all still shows entry" "history alert" "$out"
}

# ----- T8: invalid severity -> exit 1 -----
test_T8() {
  log "T8: invalid severity -> exit 1"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" bogus "hi" 2>/dev/null
  assert_eq "T8 invalid severity exit" "1" "$?"
}

# ----- T9: empty message -> exit 2 -----
test_T9() {
  log "T9: empty message -> exit 2"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "" 2>/dev/null
  assert_eq "T9 empty message exit" "2" "$?"
}

# ----- T10: no args -> exit 64 -----
test_T10() {
  log "T10: no args -> exit 64"
  "$NOTIFY_SCRIPT" 2>/dev/null
  assert_eq "T10 no-args exit" "64" "$?"
}

# ----- T11: high alias maps to critical -----
test_T11() {
  log "T11: severity alias 'high' is accepted (memory-sync.sh #520 compat)"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" high "compat alert"
  assert_eq "T11 high alias exit" "0" "$?"

  local content
  content="$(cat "$logf")"
  assert_contains "T11 alias logged as critical" " critical " "$content"
}

# ----- T12: newlines in message -> single line in log -----
test_T12() {
  log "T12: newlines in message collapse to spaces"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "$(printf 'first\nsecond')"
  local lines
  lines="$(wc -l < "$logf" | tr -d ' ')"
  assert_eq "T12 single line in log" "1" "$lines"
  local content
  content="$(cat "$logf")"
  assert_contains "T12 contains first" "first" "$content"
  assert_contains "T12 contains second" "second" "$content"
}

# ----- T13: --dismiss <id> only marks that id -----
test_T13() {
  log "T13: --dismiss <id> only marks specific id"
  local d
  d="$(mk_test_dir)"
  local stub
  stub="$(make_silent_path "$d/stub")"
  local logf="$d/alerts.log"
  local mark="$d/read-mark"

  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" critical "alpha"
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" warn "beta"

  # Extract first id from the log (alpha entry).
  local alpha_id
  alpha_id="$(awk 'NR==1 {print $3}' "$logf")"
  PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --dismiss "$alpha_id" >/dev/null

  local out
  out="$(PATH="$stub:$PATH" "$NOTIFY_SCRIPT" --log-file "$logf" --read-mark "$mark" --list)"
  assert_not_contains "T13 alpha gone after id-dismiss" "alpha" "$out"
  assert_contains "T13 beta still unread" "beta" "$out"
}

# ----- T14: --help -> exit 0 -----
test_T14() {
  log "T14: --help -> exit 0"
  local out
  out="$("$NOTIFY_SCRIPT" --help)"
  assert_eq "T14 help exit" "0" "$?"
  assert_contains "T14 help mentions usage" "USAGE" "$out"
  assert_contains "T14 help mentions severity" "SEVERITY" "$out"
}

# ----- run all -----

main() {
  if [[ ! -x "$NOTIFY_SCRIPT" ]]; then
    log "ERROR: $NOTIFY_SCRIPT is not executable"
    exit 64
  fi

  rm -rf "$TEST_TMP_BASE" 2>/dev/null || true
  mkdir -p "$TEST_TMP_BASE"

  test_T1
  test_T2
  test_T3
  test_T4
  test_T5
  test_T6
  test_T7
  test_T8
  test_T9
  test_T10
  test_T11
  test_T12
  test_T13
  test_T14

  log "Summary: $PASS_COUNT pass, $FAIL_COUNT fail"
  if (( FAIL_COUNT > 0 )); then
    exit 1
  fi
  exit 0
}

main "$@"
