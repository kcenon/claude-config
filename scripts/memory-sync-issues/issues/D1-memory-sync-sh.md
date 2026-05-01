---
title: "feat(memory): memory-sync.sh bidirectional sync with integrated validation"
labels:
  - type/feature
  - priority/high
  - area/memory
  - size/L
  - phase/D-engine
milestone: memory-sync-v1-engine
blocked_by: [C5]
blocks: [E1, D4, D5]
parent_epic: EPIC
---

## What

Implement `scripts/memory-sync.sh` — bidirectional sync between local memory clone (`~/.claude/memory-shared/`) and `kcenon/claude-memory` remote. Validates local diff before push, validates pulled changes after pull, regenerates `MEMORY.md` index, handles conflicts by aborting and notifying. Designed for unattended hourly execution by launchd / systemd.

### Scope (in)

- Single bash script, runnable manually or scheduled
- Lock file (`flock`) to prevent concurrent runs
- Pre-push validation: validate.sh + secret-check.sh on local diff
- Pull via `git fetch && rebase --autostash`
- Post-pull validation: re-run all 3 validators on full tree (catches anything the other machine pushed before validators existed there)
- `regen-index.sh` after merge
- Push with single retry on remote-changed
- Logs to `~/.claude/logs/memory-sync.log`
- Conflict notification via callable hook to #D5

### Scope (out)

- Real-time sync (file watcher) — out of scope
- Merge-conflict resolution beyond abort+notify (resolution requires user judgment)
- Multi-account support
- Encrypting transport (git over SSH already handles this)

## Why

`memory-sync.sh` is the heart of the multi-machine system. It must be **safe under all failure modes** — partial network, corrupted local clone, divergent histories, validation failure mid-flight. The cost of getting this wrong is data loss across all machines.

Five-layer defense intersects here: this script is layers 3 (sync-pre-push) and 4 (sync-post-pull). The other layers (write-time, pre-commit, audit) protect entry points; this script protects the transport.

### What this unblocks

- #E1 — single-machine migration runbook calls this script
- #E3 — launchd / systemd scheduler invokes this script
- #D4 — `memory-status.sh` reads logs from this script
- #G2 — multi-machine conflict tests exercise this script
- General multi-machine operation

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — central component of the entire system
- **Estimate**: 1.5 days
- **Target close**: within 2 weeks of #C5 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/scripts/memory-sync.sh`
- **Local clone**: `~/.claude/memory-shared/` (created by `memory-bootstrap.sh` from #E1)
- **Logs**: `~/.claude/logs/memory-sync.log`
- **Lock**: `~/.claude/.memory-sync.lock`

## How

### Approach

A linear pipeline of clearly-named stages, each with explicit failure handling. Heavy use of `set -u` and explicit error checking. Each stage logs entry/exit. On any non-recoverable failure, the script aborts cleanly and notifies via #D5.

### Detailed Design

**Script signature**:
```
memory-sync.sh                                    # default: full sync
memory-sync.sh --dry-run                          # show what would happen, no writes
memory-sync.sh --pull-only                        # fetch + rebase, no push
memory-sync.sh --push-only                        # validate + push, no pull
memory-sync.sh --lock-timeout SEC                 # default 30s
memory-sync.sh --help
```

**Exit codes**:
- `0` — success
- `1` — pre-push validation failed (local change rejected)
- `2` — post-pull validation failed (remote brought in a bad memory)
- `3` — merge conflict (rebase aborted)
- `4` — push failed (still after retry)
- `5` — lock contention (another sync running)
- `6` — git operation failed (other than above)
- `64` — usage error

**Stage flow**:
```
1. acquire_lock()              # flock; exit 5 on contention
2. validate_repo_state()       # is it a git repo, on main, etc.
3. capture_local_diff()        # what local commits/files differ from origin/main
4. pre_push_validate()         # validate.sh + secret-check.sh on local diff (exit 1 if fail)
5. fetch_remote()              # git fetch origin (exit 6 if network fail)
6. rebase_local_onto_remote()  # git rebase --autostash (exit 3 on conflict, abort)
7. post_pull_validate()        # all 3 validators on full tree (exit 2 if fail; quarantine offenders)
8. regen_index()               # regen-index.sh; commit if drift
9. push_with_retry()           # git push; on remote-changed retry once via fetch+rebase+push (exit 4 if fails twice)
10. release_lock()
11. log_summary()
```

**Pre-push validation detail** (stage 4):
- Iterate files changed in `git diff origin/main..HEAD --name-only -- 'memories/*.md' 'quarantine/*.md'`
- Run `validate.sh` on each; abort on exit ≥ 1 (block)
- Run `secret-check.sh` on each; abort on exit 1 (block)
- `injection-check.sh` is run for warning only; flagged files go through but log warning
- Abort flow: notify via #D5, exit 1, no push attempt

**Post-pull validation detail** (stage 7):
- Run all 3 validators on full `memories/` tree (not just diff — defense in depth)
- On any blocking failure: file(s) responsible are auto-moved to `quarantine/` via `quarantine-move.sh` (#B4) with reason "post-pull validation failed: <details>"
- Commit the quarantine move with subject `chore: auto-quarantine on post-pull validation`
- Push that quarantine commit so other machines see the offender as quarantined
- Exit 2 with severity-high notification

**Conflict handling detail** (stage 6):
- `git rebase --autostash origin/main`
- If conflict: `git rebase --abort`, exit 3, notify with "merge conflict — manual resolution required"
- Documented action for user: read docs/MEMORY_SYNC.md "Conflict resolution" section, manually resolve, then re-run sync

**Push retry logic** (stage 9):
- First attempt: `git push origin main`
- If "rejected — non-fast-forward" (remote moved): re-run stages 5-8 (fetch+rebase+post-pull+regen), then attempt push #2
- If push #2 fails: exit 4, notify

**State and side effects**:
- Modifies the local clone (commits, push)
- Writes to log file
- May produce notifications via #D5
- May call `quarantine-move.sh` (touches files)

**External dependencies**: bash 3.2+, git, flock, validate.sh / secret-check.sh / injection-check.sh / regen-index.sh / quarantine-move.sh from claude-memory.

### Inputs and Outputs

**Input** (clean sync):
```
$ ./memory-sync.sh
```

**Output** (typical, abridged):
```
[2026-05-01T10:00:11Z] sync start (host=macbook-pro)
[2026-05-01T10:00:11Z] stage acquire_lock: OK
[2026-05-01T10:00:11Z] stage validate_repo_state: OK (branch=main)
[2026-05-01T10:00:11Z] stage capture_local_diff: 1 commits ahead, 2 files changed
[2026-05-01T10:00:12Z] stage pre_push_validate
                       memories/feedback_new_rule.md  validate=PASS secret=CLEAN
                       memories/project_xyz.md        validate=PASS secret=CLEAN
[2026-05-01T10:00:13Z] stage fetch_remote: 0 commits behind
[2026-05-01T10:00:13Z] stage rebase_local_onto_remote: nothing to rebase (already on origin/main)
[2026-05-01T10:00:13Z] stage post_pull_validate: 17 PASS, 0 FAIL, 0 quarantined
[2026-05-01T10:00:13Z] stage regen_index: no drift
[2026-05-01T10:00:14Z] stage push_with_retry: 1 commit pushed
[2026-05-01T10:00:14Z] sync complete in 3s
```
Exit: `0`

**Output** (pre-push fail):
```
[...] stage pre_push_validate
       memories/feedback_leak.md  validate=PASS secret=SECRET-DETECTED
           [!] token pattern at line 5
[...] sync ABORT: pre-push validation failed
[...] notify: "memory-sync: pre-push validation failed on macbook-pro"
```
Exit: `1`

**Output** (post-pull fail with auto-quarantine):
```
[...] stage post_pull_validate
       memories/feedback_strange.md  validate=PASS secret=SECRET-DETECTED
           [!] non-owner email: someone@external.com
[...] auto-quarantine: feedback_strange.md → quarantine/
[...] commit: auto-quarantine on post-pull validation
[...] stage push_with_retry: 1 commit pushed (quarantine action)
[...] sync ABORT: post-pull validation found problems (auto-quarantined 1)
[...] notify (severity=high): "post-pull validation found problems"
```
Exit: `2`

**Output** (conflict):
```
[...] stage rebase_local_onto_remote
       CONFLICT (content): memories/feedback_ci_merge_policy.md
[...] git rebase --abort
[...] sync ABORT: merge conflict; manual resolution required
[...] notify (severity=high): "memory-sync: merge conflict on macbook-pro"
```
Exit: `3`

**Output** (lock contention):
```
[...] stage acquire_lock: FAILED (another sync running, lock=...)
```
Exit: `5`

### Edge Cases

- **First-ever run on a machine** → `~/.claude/memory-shared/` may not exist; script refuses with diagnostic pointing to #E1 bootstrap procedure
- **Local clone diverges multiple commits ahead AND behind** → rebase replays local on top; if conflict, abort
- **Network down during fetch** → exit 6 with retry suggestion; launchd will retry next hour
- **Remote ref-spec rejected** (rare) → exit 6, notify
- **Branch is not `main`** (someone checked out a feature branch locally) → exit 6 with diagnostic
- **Detached HEAD** → exit 6 with diagnostic
- **Uncommitted local changes when starting** → `--autostash` handles; if stash conflict on un-stash, exit 3
- **Disk full during commit** → git error; exit 6
- **Lock file stale** (process killed without releasing) → flock detects via PID; if PID dead, takes lock; document
- **Multiple machines pushing simultaneously** → first wins; second's push fails non-FF; retry via stages 5-9 once; if still fails, exit 4
- **Sync runs when no local changes and no remote changes** → all stages no-op, exits 0 silently (don't spam log)
- **Symbolic link from `~/.claude/projects/.../memory` to `~/.claude/memory-shared/memories`** (set up by #E1) → script operates on memory-shared; symlink transparently passes through

### Acceptance Criteria

- [ ] Script `scripts/memory-sync.sh` (executable)
- [ ] **Lock file** (`~/.claude/.memory-sync.lock`) prevents concurrent runs; exits 5 on contention
- [ ] **Pre-push validation** runs `validate.sh` + `secret-check.sh` on local diff; aborts on blocking failure (exit 1)
- [ ] **Post-pull validation** runs all 3 validators on full tree; auto-quarantines offenders (#B4); exits 2
- [ ] **Conflict handling**: `rebase --abort` + exit 3 + notify
- [ ] **Push retry**: 1 retry on non-FF; exit 4 if both attempts fail
- [ ] **Index regeneration**: calls `regen-index.sh` after merge; commits result if drift
- [ ] **Log file**: append-only, timestamped, structured per stage
- [ ] **Notification**: calls hook from #D5 with severity per failure type
- [ ] **Modes**: `--dry-run`, `--pull-only`, `--push-only`, `--help`
- [ ] **Exit codes** match Detailed Design table
- [ ] Bash 3.2 + bash 5.x both work
- [ ] Performance: clean sync (no diff) completes in < 5 seconds
- [ ] **End-to-end test**: synthetic local change, sync, see remote update; synthetic bad change, sync, see abort
- [ ] All file modifications atomic (temp + mv)

### Test Plan

- Clean local + clean remote → no-op sync, exit 0
- Local 1 ahead, remote 0 → push succeeds
- Local 0, remote 1 ahead → pull succeeds
- Local 1 ahead, remote 1 ahead, no conflict → rebase + push succeeds
- Local 1 ahead, remote 1 ahead, conflict → abort + exit 3
- Local commit contains secret → pre-push abort + exit 1
- Remote commit contains secret (synthetic via direct push to remote) → post-pull abort + auto-quarantine + exit 2
- Concurrent sync (run twice in parallel) → second exits 5
- Push race (push from machine A simultaneously) → retry succeeds or exits 4 cleanly
- macOS bash 3.2 + Linux bash 5.x both pass

### Implementation Notes

- **flock idiom**: `exec 9>"$LOCK"; flock -n 9 || { echo "..."; exit 5; }` — guarantees release on script exit even if killed
- **Logging**: helper `log()` writes to both stdout and log file with timestamp prefix
- **Stage helpers**: each stage is a function returning exit code; main orchestrates and decides on early-abort
- **Auto-stash semantics**: `git rebase --autostash` stashes uncommitted, rebases, unstashes; failures during unstash leave changes in stash list — `git stash list | grep "$(date +%Y-%m-%d)"` to recover
- **Notification call**: `~/.claude/scripts/memory-notify.sh "<severity>" "<message>"` (created in #D5); if missing, fall back to log only
- **Don't `set -e`** — explicit return-code checks per stage are clearer for this complex flow
- **Test mode** (`--dry-run`): all `git push`, `git commit`, `git mv` replaced with `echo "[dry-run] would: ..."` — but reads still happen
- **Time precision**: ISO 8601 UTC for log timestamps (`date -u +%Y-%m-%dT%H:%M:%SZ`)
- Avoid `awk` write-redirection (bash-write-guard) — bash + temp file pattern

### Deliverable

- `scripts/memory-sync.sh` (executable, ~400 lines including stage functions)
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — net-new script. Existing `~/.claude/memory-shared/` (if any) is untouched on first run; #E1 sets it up.

### Rollback Plan

- Disable launchd / systemd scheduler (separate issue #E3)
- Manual sync via `git pull` / `git push` works without this script
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C5
- Blocks: #E1, #D4, #D5
- Related: #B4 (quarantine-move consumer), #C2 (regen-index consumer), #A2/#A3/#A4 (validator consumers), #G2 (test scenarios)

**Docs**:
- `docs/MEMORY_SYNC.md` (#G3) — operational details
- `docs/THREAT_MODEL.md` (#G3) — five-layer defense

**Commits/PRs**: (filled at PR time)
