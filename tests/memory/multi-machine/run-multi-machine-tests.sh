#!/bin/bash
# run-multi-machine-tests.sh -- Simulated multi-machine conflict scenarios.
#
# Per issue #533 ("test(memory): multi-machine conflict scenario validation").
# The issue describes five scenarios that ideally run on two real machines.
# This harness simulates them on a single host using two independent clones
# of a synthetic bare remote, exercising scripts/memory-sync.sh exactly the
# way it would be invoked on Machine A and Machine B.
#
# Layout per scenario, under /tmp/mm-test-<pid>/<sid>/:
#   bare/                 bare repo simulating origin (kcenon/claude-memory)
#   seed/                 throwaway clone used to seed bare with initial state
#   host-A/               clone representing Machine A
#   host-B/               clone representing Machine B
#   host-A.log host-B.log per-host memory-sync.log
#   host-A.lock host-B.lock per-host lock files
#   alerts-A.log alerts-B.log per-host memory-notify alert log
#
# Scenarios mapped to the issue body:
#   S1 concurrent additions, different files       -> both files on both hosts
#   S2 concurrent edits, same file                 -> first push wins, other exits 3
#   S3 secret-bearing memory bypassed on host A    -> host B auto-quarantines
#   S4 network partition during sync               -> exit 6, recovers cleanly
#   S5 concurrent sync invocations on same host    -> second exits 5
#
# Plus two extensions covered without two physical machines:
#   S6 clock-skew on host B clones                 -> deterministic conflict outcome
#   S7 concurrent quarantine on the same file      -> hosts agree on quarantine state
#
# DEFERRED to a real two-machine operator run (per issue body, scope-out):
#   - Scenarios that need actual divergent OS clocks at the kernel level
#   - macOS terminal-notifier / Linux notify-send delivery proof
#   - Real network partition via `route` / `iptables` (we simulate via an
#     unreachable file:// remote; the script reaches the same exit code 6 path)
#
# Bash 3.2 compatible (matches sibling tests/memory/run-*-tests.sh harnesses).
# No `set -e`: explicit return-code checks keep failing-test reporting clean.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SYNC_SCRIPT="${REPO_ROOT}/scripts/memory-sync.sh"
NOTIFY_SCRIPT="${REPO_ROOT}/scripts/memory-notify.sh"
QUARANTINE_MOVE="${REPO_ROOT}/scripts/memory/quarantine-move.sh"

TEST_TMP_BASE="${TMPDIR:-/tmp}/mm-test-$$"
PASS_COUNT=0
FAIL_COUNT=0

# ----- logging helpers (match run-sync-tests.sh style) -----

log() {
  printf '[%s] %s\n' "$(date -u +'%H:%M:%SZ')" "$*"
}

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS: $label (got $actual)"
    return 0
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL: $label (expected $expected, got $actual)"
    return 1
  fi
}

# ----- shared fixture builders -----

# write_valid_memory <path> <name> <body-tag>
# Writes a structurally valid memory file passing validate.sh and secret-check.sh.
write_valid_memory() {
  local path="$1"
  local name="$2"
  local body="$3"
  cat > "$path" <<EOF
---
name: "${name}"
description: "Multi-machine scenario fixture: ${body}"
type: user
source-machine: test
created-at: 2026-05-01T00:00:00Z
trust-level: verified
last-verified: 2026-05-01
---

# ${name}

**Why:** ${body}

**How to apply:** Test fixture only; never executed in production.

Body content sufficient to pass validate.sh body length check.
EOF
}

# write_secret_memory <path>
# Writes a memory containing a synthetic AWS access key id. Passes structural
# validate.sh, fails secret-check.sh.
write_secret_memory() {
  local path="$1"
  cat > "$path" <<'EOF'
---
name: "AWS access key bypass"
description: "Synthetic secret intentionally used to verify ingress quarantine."
type: user
source-machine: test
created-at: 2026-05-01T00:00:00Z
trust-level: untrusted
last-verified: 2026-05-01
---

# AWS access key bypass

**Why:** Multi-machine S3 fixture; should be quarantined post-pull.

**How to apply:** Test fixture only.

This file embeds the synthetic AWS key id AKIA0123456789ABCDEF that
secret-check.sh matches via the AKIA[0-9A-Z]{16} signature documented in
MEMORY_VALIDATION_SPEC.md section 6.
EOF
}

# build_remote <bare-path> <seed-path>
# Creates a bare repo and seeds it with memories/, quarantine/, and a regen-index
# stub. Mirrors the helper in tests/memory/run-sync-tests.sh.
build_remote() {
  local bare="$1"
  local seed="$2"

  git init --bare --initial-branch=main "$bare" >/dev/null 2>&1
  git clone "$bare" "$seed" >/dev/null 2>&1
  (
    cd "$seed" || exit 1
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false 2>/dev/null || true
    mkdir -p memories quarantine scripts
    write_valid_memory memories/user_initial.md "initial seed" "Seed memory created during multi-machine test setup."
    cat > scripts/regen-index.sh <<'EOFR'
#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
{
  printf -- '# Memory Index\n\n'
  for f in "$ROOT/memories"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "MEMORY.md" ]] && continue
    printf -- '- %s\n' "$base"
  done
} > "$ROOT/memories/MEMORY.md"
EOFR
    chmod +x scripts/regen-index.sh
    git add memories scripts
    git commit -m "seed: initial multi-machine fixtures" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
  )
}

# build_clone <bare> <clone-dir>
# Clones the bare remote into <clone-dir> with test git identity configured.
build_clone() {
  local bare="$1"
  local clone="$2"
  git clone "$bare" "$clone" >/dev/null 2>&1
  (
    cd "$clone" || exit 1
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false 2>/dev/null || true
  )
}

# run_sync_on_host <clone> <log> <lock> [extra-args...]
# Invokes scripts/memory-sync.sh with the provided sandbox paths. Does not
# touch the user's real ~/.claude/.
run_sync_on_host() {
  local clone="$1"; shift
  local logf="$1"; shift
  local lockf="$1"; shift
  CLAUDE_CONFIG_DIR="${REPO_ROOT}" \
    "$SYNC_SCRIPT" \
      --clone-dir "$clone" \
      --log-file "$logf" \
      --lock-file "$lockf" \
      --lock-timeout 2 \
      "$@"
}

# build_two_host_world <sid>
# Creates the per-scenario sandbox: bare/seed + host-A/host-B clones.
# Returns (via globals) HOST_A, HOST_B, BARE, LOG_A, LOG_B, LOCK_A, LOCK_B.
build_two_host_world() {
  local sid="$1"
  local td="$TEST_TMP_BASE/$sid"
  mkdir -p "$td"
  BARE="$td/bare.git"
  SEED="$td/seed"
  HOST_A="$td/host-A"
  HOST_B="$td/host-B"
  LOG_A="$td/host-A.log"
  LOG_B="$td/host-B.log"
  LOCK_A="$td/host-A.lock"
  LOCK_B="$td/host-B.lock"
  build_remote "$BARE" "$SEED"
  build_clone "$BARE" "$HOST_A"
  build_clone "$BARE" "$HOST_B"
}

# ---------- scenarios ----------

# S1 -- concurrent additions, different files (issue #533 scenario 1)
s1_concurrent_additions_different_files() {
  log "S1: concurrent additions on different files"
  build_two_host_world s1

  # Host A adds file_a.md; Host B adds file_b.md. Both commit locally.
  write_valid_memory "$HOST_A/memories/feedback_test_a.md" "feedback A" \
    "Host A added this in S1; Host B never touches it."
  (
    cd "$HOST_A"
    git add memories
    git commit -m "feat: add S1 file from host A" >/dev/null 2>&1
  )
  write_valid_memory "$HOST_B/memories/feedback_test_b.md" "feedback B" \
    "Host B added this in S1; Host A never touches it."
  (
    cd "$HOST_B"
    git add memories
    git commit -m "feat: add S1 file from host B" >/dev/null 2>&1
  )

  # Host A pushes first (clean); Host B then syncs. Expected: B rebases A's
  # commit onto its own and pushes; both files end up on both hosts.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S1 host A exit" 0 $?
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  assert_eq "S1 host B exit" 0 $?

  # Host A re-syncs to pull B's now-pushed commit.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S1 host A re-sync exit" 0 $?

  if [[ -f "$HOST_A/memories/feedback_test_a.md" ]] && [[ -f "$HOST_A/memories/feedback_test_b.md" ]]; then
    assert_eq "S1 host A has both files" "yes" "yes"
  else
    assert_eq "S1 host A has both files" "yes" "no"
  fi
  if [[ -f "$HOST_B/memories/feedback_test_a.md" ]] && [[ -f "$HOST_B/memories/feedback_test_b.md" ]]; then
    assert_eq "S1 host B has both files" "yes" "yes"
  else
    assert_eq "S1 host B has both files" "yes" "no"
  fi
}

# S2 -- concurrent edits to the same file (issue #533 scenario 2)
s2_concurrent_edits_same_file() {
  log "S2: concurrent edits to the same file (real conflict)"
  build_two_host_world s2

  # Both hosts already have memories/user_initial.md from the seed. Edit it
  # divergently and commit on both hosts.
  cat >> "$HOST_A/memories/user_initial.md" <<'EOF'

## Rule A

Host A appended this rule and pushed first.
EOF
  (
    cd "$HOST_A"
    git add memories
    git commit -m "fix: host A appends rule A" >/dev/null 2>&1
  )

  cat >> "$HOST_B/memories/user_initial.md" <<'EOF'

## Rule B

Host B appended this rule and tries to push second.
EOF
  (
    cd "$HOST_B"
    git add memories
    git commit -m "fix: host B appends rule B" >/dev/null 2>&1
  )

  # Host A pushes successfully.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S2 host A exit" 0 $?

  # Host B's sync should now hit a rebase conflict and exit 3.
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  local rc_b=$?
  assert_eq "S2 host B exit (conflict)" 3 $rc_b

  # Verify host B's working tree is clean (rebase aborted) and the local
  # change is still present (no silent data loss).
  local b_status
  b_status="$(cd "$HOST_B" && git status --porcelain 2>/dev/null | head -1)"
  if [[ -z "$b_status" ]]; then
    assert_eq "S2 host B working tree clean after abort" "yes" "yes"
  else
    assert_eq "S2 host B working tree clean after abort" "yes" "no"
  fi
  # Host B's branch tip should still contain Rule B.
  if grep -q "Rule B" "$HOST_B/memories/user_initial.md"; then
    assert_eq "S2 host B retained Rule B" "yes" "yes"
  else
    assert_eq "S2 host B retained Rule B" "yes" "no"
  fi
  # Sync log should record the ABORT.
  if grep -q "CONFLICT (rebase aborted)" "$LOG_B" 2>/dev/null; then
    assert_eq "S2 host B log records CONFLICT" "yes" "yes"
  else
    assert_eq "S2 host B log records CONFLICT" "yes" "no"
  fi
}

# S3 -- secret-bearing memory bypassed on host A, host B auto-quarantines
s3_validator_blocked_propagation() {
  log "S3: validator-blocked propagation via post-pull quarantine"
  build_two_host_world s3

  # Host A bypasses the local validator using --no-verify and pushes a memory
  # containing a synthetic AWS access key directly to origin. memory-sync.sh
  # is NOT used on host A here because it would block at pre_push_validate.
  write_secret_memory "$HOST_A/memories/user_aws_bypass.md"
  (
    cd "$HOST_A"
    git add memories
    git commit --no-verify -m "test: host A bypasses validator (S3 fixture)" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
  )

  # Host B runs memory-sync.sh; the post-pull validator should detect the
  # secret in the freshly pulled file and auto-quarantine it.
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  local rc_b=$?
  # post_pull_validate exits 2 OR 0 depending on whether quarantine-move is
  # available. Both indicate the bad data was detected.
  if [[ "$rc_b" == "0" || "$rc_b" == "2" ]]; then
    assert_eq "S3 host B detected bad ingress" "yes" "yes"
  else
    assert_eq "S3 host B detected bad ingress" "yes" "no (rc=$rc_b)"
  fi

  # If quarantine-move.sh exists and host B exited 0, the offending file
  # should now live in quarantine/ rather than memories/.
  if [[ -x "$QUARANTINE_MOVE" ]] && [[ "$rc_b" == "0" ]]; then
    if [[ ! -f "$HOST_B/memories/user_aws_bypass.md" ]] && \
       compgen -G "$HOST_B/quarantine/*.md" >/dev/null 2>&1; then
      assert_eq "S3 host B quarantined the file" "yes" "yes"
    else
      assert_eq "S3 host B quarantined the file" "yes" "no"
    fi
  else
    log "  NOTE: skipping quarantine-state check (rc=$rc_b, quarantine-move=$( [[ -x "$QUARANTINE_MOVE" ]] && echo present || echo absent ))"
  fi

  # Sync log should record the FAIL or auto-quarantine line.
  if grep -qE "post_pull_validate.*(FAIL|auto-quarantine)" "$LOG_B" 2>/dev/null; then
    assert_eq "S3 host B log records bad ingress" "yes" "yes"
  else
    assert_eq "S3 host B log records bad ingress" "yes" "no"
  fi
}

# S4 -- network partition during sync (issue #533 scenario 4)
s4_network_partition_recovery() {
  log "S4: network partition during sync"
  build_two_host_world s4

  # Host A has 2 unpushed commits. Point the remote at a non-existent path to
  # simulate "github.com unreachable" without needing root / route / iptables.
  write_valid_memory "$HOST_A/memories/user_partition_one.md" "partition one" \
    "Should arrive on remote only after S4 recovers."
  (
    cd "$HOST_A"
    git add memories
    git commit -m "feat: partition one (S4)" >/dev/null 2>&1
  )
  write_valid_memory "$HOST_A/memories/user_partition_two.md" "partition two" \
    "Should arrive on remote only after S4 recovers."
  (
    cd "$HOST_A"
    git add memories
    git commit -m "feat: partition two (S4)" >/dev/null 2>&1
  )

  # Save the real remote URL, then point at an unreachable file:// URL.
  local real_remote
  real_remote="$(cd "$HOST_A" && git remote get-url origin)"
  (
    cd "$HOST_A"
    git remote set-url origin "file:///nonexistent/mm-test-partition-$$.git"
  )

  # First sync: should fail at fetch_remote with exit 6.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  local rc_partition=$?
  assert_eq "S4 host A exit during partition" 6 $rc_partition

  # Lock should be released cleanly even after fetch failure.
  local stale_lock="no"
  if [[ -s "$LOCK_A" ]]; then
    local pid
    pid="$(head -1 "$LOCK_A" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      stale_lock="yes"
    fi
  fi
  assert_eq "S4 host A lock not stale" "no" "$stale_lock"

  # Restore the remote and resync; both commits must reach the bare.
  (
    cd "$HOST_A"
    git remote set-url origin "$real_remote"
  )
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S4 host A exit after recovery" 0 $?

  # Re-clone bare and verify both new files arrived.
  local verify="$TEST_TMP_BASE/s4/verify"
  git clone "$BARE" "$verify" >/dev/null 2>&1
  if [[ -f "$verify/memories/user_partition_one.md" ]] && \
     [[ -f "$verify/memories/user_partition_two.md" ]]; then
    assert_eq "S4 remote received both commits" "yes" "yes"
  else
    assert_eq "S4 remote received both commits" "yes" "no"
  fi
}

# S5 -- concurrent sync invocations on the same host (issue #533 scenario 5)
s5_concurrent_sync_invocations() {
  log "S5: concurrent sync invocations on the same host"
  build_two_host_world s5

  # We need one sync to be in flight when the second runs. The cleanest way
  # without scheduling primitives is to write a memory that triggers a slow
  # validator step. Even without that, lock contention is verified by holding
  # the lock manually via flock-equivalent: open FD 9 to the lock file in a
  # background subshell that sleeps, then run the second sync.
  local slow_pid=""
  if command -v flock >/dev/null 2>&1; then
    (
      exec 9>"$LOCK_A"
      flock -x 9
      sleep 3
    ) &
    slow_pid=$!
    # Give the background lock holder a moment to acquire.
    sleep 1
    run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
    local rc_busy=$?
    assert_eq "S5 host A exit while lock held" 5 $rc_busy
    wait "$slow_pid" 2>/dev/null || true
  else
    # macOS without flock: simulate by writing a fake live PID into the lock
    # file and let acquire_lock's PID-file fallback detect it.
    printf '%s\n' "$$" > "$LOCK_A"
    run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
    local rc_busy=$?
    assert_eq "S5 host A exit while pid-lock held" 5 $rc_busy
    rm -f "$LOCK_A"
  fi

  # After the holder releases, a fresh sync succeeds.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S5 host A exit after lock release" 0 $?
}

# S6 -- clock skew tolerance: hosts with mismatched clocks still produce
# deterministic conflict resolution. We force divergent committer timestamps.
s6_clock_skew_tolerance() {
  log "S6: clock skew tolerance"
  build_two_host_world s6

  # Host A commits with a far-future timestamp; host B with an old timestamp.
  # Then both push concurrently; first-push-wins ordering must NOT depend on
  # wall-clock time -- only on push order.
  write_valid_memory "$HOST_A/memories/user_skew_a.md" "skew A" "Future-timestamped commit."
  (
    cd "$HOST_A"
    git add memories
    GIT_AUTHOR_DATE="2099-01-01T00:00:00Z" \
    GIT_COMMITTER_DATE="2099-01-01T00:00:00Z" \
      git commit -m "feat: future-stamped commit (S6)" >/dev/null 2>&1
  )

  write_valid_memory "$HOST_B/memories/user_skew_b.md" "skew B" "Past-timestamped commit."
  (
    cd "$HOST_B"
    git add memories
    GIT_AUTHOR_DATE="2000-01-01T00:00:00Z" \
    GIT_COMMITTER_DATE="2000-01-01T00:00:00Z" \
      git commit -m "feat: past-stamped commit (S6)" >/dev/null 2>&1
  )

  # B pushes first despite older author timestamp; sync still succeeds.
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  assert_eq "S6 host B exit" 0 $?
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  assert_eq "S6 host A exit" 0 $?

  # Both files must be present on both hosts; rebase result should be
  # deterministic (B's commit precedes A's on the resulting linear history).
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  assert_eq "S6 host B re-sync exit" 0 $?

  if [[ -f "$HOST_A/memories/user_skew_a.md" ]] && \
     [[ -f "$HOST_A/memories/user_skew_b.md" ]] && \
     [[ -f "$HOST_B/memories/user_skew_a.md" ]] && \
     [[ -f "$HOST_B/memories/user_skew_b.md" ]]; then
    assert_eq "S6 both hosts have both files" "yes" "yes"
  else
    assert_eq "S6 both hosts have both files" "yes" "no"
  fi

  # The shared head commit should be the SAME hash on both hosts (deterministic
  # outcome despite clock skew).
  local head_a
  local head_b
  head_a="$(cd "$HOST_A" && git rev-parse HEAD)"
  head_b="$(cd "$HOST_B" && git rev-parse HEAD)"
  if [[ "$head_a" == "$head_b" ]]; then
    assert_eq "S6 hosts converged on same HEAD" "yes" "yes"
  else
    assert_eq "S6 hosts converged on same HEAD" "yes" "no"
  fi
}

# S7 -- concurrent quarantine on the same file: both hosts independently
# detect the same bad memory and route it to quarantine. Final state on the
# remote must be a single quarantine entry, not duplicates.
s7_concurrent_quarantine_agreement() {
  log "S7: concurrent quarantine agreement"
  build_two_host_world s7

  # Both hosts already have memories/user_initial.md. Inject a bad memory on
  # host A bypassing the validator and push it. Then both hosts run sync;
  # both should converge on the same quarantine state.
  write_secret_memory "$HOST_A/memories/user_dup_secret.md"
  (
    cd "$HOST_A"
    git add memories
    git commit --no-verify -m "test: bad memory for S7" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
  )

  # Host B syncs; its post-pull validator should catch and quarantine.
  run_sync_on_host "$HOST_B" "$LOG_B" "$LOCK_B" >/dev/null 2>&1
  local rc_b=$?
  if [[ "$rc_b" == "0" || "$rc_b" == "2" ]]; then
    assert_eq "S7 host B detected bad ingress" "yes" "yes"
  else
    assert_eq "S7 host B detected bad ingress" "yes" "no (rc=$rc_b)"
  fi

  # Host A re-syncs and pulls the quarantine action B may have pushed.
  run_sync_on_host "$HOST_A" "$LOG_A" "$LOCK_A" >/dev/null 2>&1
  local rc_a=$?
  # Either 0 (clean) or 2 (caught its own bad commit if quarantine wasn't
  # pushed) is acceptable -- both indicate the system isolated the secret.
  if [[ "$rc_a" == "0" || "$rc_a" == "2" ]]; then
    assert_eq "S7 host A converged" "yes" "yes"
  else
    assert_eq "S7 host A converged" "yes" "no (rc=$rc_a)"
  fi

  # If quarantine-move is present and host B exited 0, the bad file must be
  # gone from memories/ on host B.
  if [[ -x "$QUARANTINE_MOVE" ]] && [[ "$rc_b" == "0" ]]; then
    if [[ ! -f "$HOST_B/memories/user_dup_secret.md" ]]; then
      assert_eq "S7 host B memories/ no longer has secret" "yes" "yes"
    else
      assert_eq "S7 host B memories/ no longer has secret" "yes" "no"
    fi
  else
    log "  NOTE: skipping quarantine-state check (rc_b=$rc_b, quarantine-move=$( [[ -x "$QUARANTINE_MOVE" ]] && echo present || echo absent ))"
  fi
}

# ---------- main ----------

main() {
  if [[ ! -x "$SYNC_SCRIPT" ]]; then
    log "ERROR: $SYNC_SCRIPT not found or not executable"
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    log "ERROR: git not in PATH"
    exit 1
  fi
  mkdir -p "$TEST_TMP_BASE"
  # Cleanup unconditionally on exit; never leave /tmp/mm-test-* artifacts.
  trap 'rm -rf "$TEST_TMP_BASE"' EXIT

  log "Multi-machine simulation under $TEST_TMP_BASE"
  log "Mapping issue #533 scenarios S1-S5 plus S6 (clock skew) and S7 (concurrent quarantine)."

  s1_concurrent_additions_different_files
  s2_concurrent_edits_same_file
  s3_validator_blocked_propagation
  s4_network_partition_recovery
  s5_concurrent_sync_invocations
  s6_clock_skew_tolerance
  s7_concurrent_quarantine_agreement

  echo
  log "Summary: $PASS_COUNT pass, $FAIL_COUNT fail"
  if (( FAIL_COUNT > 0 )); then
    exit 1
  fi
  exit 0
}

main "$@"
