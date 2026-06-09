# Memory Sync — Single-Machine Stabilization Checklist

**Version**: 1.0.0
**Last updated**: 2026-05-01
**Status**: Active
**Issue**: [#526](https://github.com/kcenon/claude-config/issues/526)
**Epic**: [#505](https://github.com/kcenon/claude-config/issues/505)

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Pre-flight](#2-pre-flight)
3. [Daily Routine (~5 minutes)](#3-daily-routine-5-minutes)
4. [Daily Log Template](#4-daily-log-template)
5. [Pass / Fail Criteria](#5-pass--fail-criteria)
6. [Anomaly Procedure](#6-anomaly-procedure)
7. [Closing the Observation](#7-closing-the-observation)
8. [Versioning](#8-versioning)

---

## 1. Purpose

This checklist runs immediately after a single-machine operator completes the
[migration runbook](./MEMORY_MIGRATION.md) ([#525](https://github.com/kcenon/claude-config/issues/525))
and before the scheduler in [#527](https://github.com/kcenon/claude-config/issues/527)
is left fully unattended. It is the single-machine half of the epic acceptance
criterion in [#505](https://github.com/kcenon/claude-config/issues/505):

> Two machines running stable sync for 14 consecutive days with no critical
> alerts.

The window covered here is **seven (7) consecutive days** on the primary
machine, per the issue body. After two machines (this one + #532) each pass
their seven-day window, the epic gate is satisfied.

### In scope

- Daily verification routine the operator runs each day.
- A ledger format for recording per-day pass/fail state.
- Pass / fail thresholds that decide go / no-go for #527 scheduler trust and
  for #532 second-machine onboarding.
- A rollback trigger that defers to the procedure already in
  [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) Section 13.

### Out of scope

- Implementation work — observation only.
- Multi-machine validation
  ([#532](https://github.com/kcenon/claude-config/issues/532)).
- Long-term audit, which is delivered separately
  ([#528](https://github.com/kcenon/claude-config/issues/528)).
- Operational troubleshooting beyond the anomaly trigger
  ([#534](https://github.com/kcenon/claude-config/issues/534)).

---

## 2. Pre-flight

Before starting Day 1, confirm:

- [ ] [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) phases 1–9 all
      completed and verified.
- [ ] First manual sync succeeded
      ([Phase 7](./MEMORY_MIGRATION.md#9-phase-7--first-manual-sync), exit
      code `0`).
- [ ] `~/.claude/scripts/memory-status.sh` exits `0` on the migrated machine.
- [ ] `~/.claude/logs/memory-sync.log` and `~/.claude/logs/memory-alerts.log`
      exist and are readable.
- [ ] You record Day 1's date below.
- [ ] If `[#527](https://github.com/kcenon/claude-config/issues/527)` is
      installed, that is fine; this checklist works with manual or scheduled
      sync. If only manual, schedule yourself a reminder to run
      `~/.claude/scripts/memory-sync.sh` at least once per day.

If any item is unchecked, return to the migration runbook.

---

## 3. Daily Routine (~5 minutes)

Run this every day for seven days. Each step has an explicit pass condition;
record only "pass" or "fail" (with a note) in the ledger, not free-form prose.

### Step 1 — Status snapshot

    ~/.claude/scripts/memory-status.sh --detail

**Pass** when the output shows all of:

- `status: ok`
- `last-sync` within the last 90 minutes (manual sync acceptable; the 90 min
  budget is intentionally tight to catch silent stalls — extend to 6 hours if
  scheduler is not yet active per #527)
- `pending: push=0 pull=0`
- No `unread alerts` line, or unread count is `0`

**Fail** when any of the above is missing. Exit code `0` confirms healthy;
exit code `1` is warn (record but continue if root cause is identified within
the day); exit code `2` is error (treat as Day failure, see
[Section 6](#6-anomaly-procedure)).

### Step 2 — Log chronology

    tail -50 ~/.claude/logs/memory-sync.log | grep -E '^[0-9]'

**Pass** when:

- At least one sync entry exists in the last 24 hours.
- No line contains `ABORT` or `FAIL` or `ERROR` severity.

**Fail** when no sync entry has run for > 24 hours, or any `ABORT` line is
present. Investigate the abort line before declaring the day a fail —
benign aborts are possible (e.g., user-initiated kill while running) and
warrant a note rather than a fail, but they must be explained.

### Step 3 — Alerts log

    tail -20 ~/.claude/logs/memory-alerts.log

**Pass** when:

- File is empty, or contains only `INFO`-severity entries.
- No `ERROR` or `CRITICAL` line is present.
- Total `WARN` count for the week stays below 5 (per the issue body).

**Fail** when an unresolved `ERROR` or `CRITICAL` entry exists, or the
running `WARN` total reaches 5.

### Step 4 — Synthetic clean write test

In an active Claude Code session, ask Claude to write a small valid memory
file with the four Phase 2 frontmatter fields (`source-machine`, `created-at`,
`trust-level`, `last-verified`) and a one-line body. Use a unique filename
per day (e.g., `stabilization-day-N.md`).

**Pass** when:

- Write succeeds (PreToolUse `memory-write-guard.sh` returns `allow`).
- File exists in `~/.claude/memory-shared/memories/`.
- Subsequent `memory-sync.sh` (manual or scheduled) pushes it to the
  remote within the same day.

**Fail** when the write is rejected by the guard despite valid content, or
the file never reaches the remote.

### Step 5 — Synthetic reject test

In the same session, ask Claude to write a memory containing a synthetic
secret pattern. Use the same template as the migration runbook
[Phase 6](./MEMORY_MIGRATION.md#8-phase-6--verify-the-write-guard-hook):

    ---
    type: reference
    description: synthetic write-guard test
    trust-level: inferred
    ---

    # Test
    A synthetic GitHub PAT for the guard test: ghp_TEST1234TEST1234TEST1234TEST1234

**Pass** when:

- The PreToolUse hook denies the write with a deny reason mentioning
  `secret-check`.
- The file does **not** exist on disk:

      test -e ~/.claude/memory-shared/memories/test_write_guard.md && \
        echo "FAIL: file exists" || echo "OK: blocked"

**Fail** when the file lands on disk. This is a critical failure — see
[Section 6](#6-anomaly-procedure).

### Step 6 — Read test

Ask Claude to read the file you wrote in Step 4.

**Pass** when:

- The file content is returned unchanged.
- The session loads it via the symlink at
  `~/.claude/projects/<encoded-cwd>/memory/<filename>.md`.

**Fail** when the file cannot be loaded, content is corrupted, or the
symlink is broken (compare `readlink memory` to the canonical
`~/.claude/memory-shared/memories`).

### Step 7 — Remote CI check (lightweight)

    gh run list --repo kcenon/claude-memory --limit 5 --json status,conclusion,workflowName

**Pass** when the most recent workflow run for `validate.yml` has
`conclusion: success`. CI runs are triggered by data-side commits; if you
pushed today via Step 4, this confirms the seeded validators agree with
your write.

**Fail** when the most recent run is `failure` or stuck `in_progress` for
> 30 minutes. Investigate the run log; do not treat "no recent runs" as
fail unless you also pushed in Step 4.

---

## 4. Daily Log Template

Copy this table into the body of [#526](https://github.com/kcenon/claude-config/issues/526)
and fill it in each day. Mark each cell `pass`, `fail`, or `skip` (with a
note explaining skip).

| Day | Date       | Status | Logs   | Alerts | Write | Reject | Read  | CI    | Notes                          |
|-----|------------|--------|--------|--------|-------|--------|-------|-------|--------------------------------|
| 1   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 2   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 3   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 4   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 5   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 6   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |
| 7   | YYYY-MM-DD |        |        |        |       |        |       |       |                                |

Column legend (matches Section 3 step numbers):

| Column | Step | Tool / pass condition                                                                    |
|--------|------|------------------------------------------------------------------------------------------|
| Status | 1    | `memory-status.sh --detail` exits `0`                                                    |
| Logs   | 2    | No `ABORT`/`FAIL` in `memory-sync.log`; sync run < 24h                                   |
| Alerts | 3    | No `ERROR`/`CRITICAL` in `memory-alerts.log`; weekly WARN < 5                            |
| Write  | 4    | Synthetic clean write succeeds and pushes                                                |
| Reject | 5    | Synthetic secret write blocked; file not on disk                                         |
| Read   | 6    | Test file readable via symlink, content unchanged                                        |
| CI     | 7    | Last `validate.yml` run on `claude-memory` is `success`                                  |

---

## 5. Pass / Fail Criteria

### Week-level pass

All of the following:

- 7 of 7 daily rows recorded with `pass` in every column except notes.
- 0 `ABORT` lines across the week's `memory-sync.log` tail samples.
- < 5 unread alerts total at week's end (`WARN` only; no `ERROR`/`CRITICAL`).
- No reject-test regression on any day.
- No symlink breakage on any day.

### Week-level fail (any one triggers rollback)

- Sync stale > 6 hours despite manual `memory-sync.sh` invocation.
- Validator incorrectly rejects a legitimate memory (false-positive denial)
  — an `inferred`-tier file with all four Phase 2 fields is the canonical
  test case.
- Symlink to the memory tree breaks (`readlink memory` no longer points at
  `~/.claude/memory-shared/memories`).
- Any critical-severity alert ([#524](https://github.com/kcenon/claude-config/issues/524))
  remains unresolved at end of day.
- Reject test (Step 5) fails on any day — secret leak past the guard.

### Day-level skip

A skip is recorded (not a fail) when:

- You are away from the machine for a full day with no Claude session active.
- Network is unreachable for the entire day (sync postponed; rest of routine
  may still be partially performed).
- A Claude Code update is mid-rollout and the session refuses to start.

A skip extends the observation window by one day; it does not reset the
counter. Two consecutive skips invalidate the week and require restart.

---

## 6. Anomaly Procedure

If any failure condition is hit:

1. **Stop further write activity** immediately.

2. **Capture state**:

       ~/.claude/scripts/memory-status.sh --json > /tmp/anomaly-snapshot.json
       cp ~/.claude/logs/memory-sync.log /tmp/memory-sync-anomaly.log
       cp ~/.claude/logs/memory-alerts.log /tmp/memory-alerts-anomaly.log

3. **Document in [#526](https://github.com/kcenon/claude-config/issues/526)**:

   - Day number and timestamp.
   - The failing column(s).
   - Verbatim output of the offending command.
   - Snapshot path.

4. **Decide**:

   - **Investigate-and-continue** — root cause is identifiable and isolated
     (e.g., transient network failure on a single sync). Document, fix, and
     continue Day N+1 without resetting.
   - **Rollback** — root cause indicates structural failure (validator
     misclassification, write-guard bypass, symlink corruption,
     unrecoverable rebase conflict). Execute the rollback procedure in
     [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) Section 13.

5. **On rollback**: this issue stays **open**. Reset Day counter to 0; restart
   observation only after the underlying defect is fixed (file follow-up
   issues against [#520](https://github.com/kcenon/claude-config/issues/520) /
   [#521](https://github.com/kcenon/claude-config/issues/521) /
   [#524](https://github.com/kcenon/claude-config/issues/524) /
   [#534](https://github.com/kcenon/claude-config/issues/534) as needed).

The rollback procedure itself is canonical in the migration runbook; do not
duplicate it here.

---

## 7. Closing the Observation

### On 7 consecutive clean days (go)

1. Add a closing comment to [#526](https://github.com/kcenon/claude-config/issues/526)
   in the form:

       ## Stabilization complete

       Seven days of clean operation. Authorizing #527 scheduler to remain
       installed and #532 second-machine onboarding to begin.

       | Day | Date       | Result |
       |-----|------------|--------|
       | 1   | YYYY-MM-DD | pass   |
       | ... | ...        | ...    |
       | 7   | YYYY-MM-DD | pass   |

       Total `WARN` alerts: N (< 5).
       Total `ERROR`/`CRITICAL` alerts: 0.

2. Close [#526](https://github.com/kcenon/claude-config/issues/526) as
   `completed`.

3. Run the cleanup steps in
   [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) Section 14
   (delete `memory.deprecated`, archive `$BACKUP`, sweep `*.bak.*` files).

4. Mark [#532](https://github.com/kcenon/claude-config/issues/532) as
   unblocked.

### On rollback (no-go)

- This issue stays open with a comment explaining the failure and the path
  forward.
- File follow-up issues for any tool defects discovered during observation.
- Restart the seven-day window after the underlying defect is fixed and
  re-migration completes.

### On gaps revealed in [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md)

If observation reveals doc gaps in the migration runbook (missing pre-flight
item, ambiguous phase, broken command), file a follow-up issue or PR against
[#525](https://github.com/kcenon/claude-config/issues/525). Do not modify
the runbook in this checklist's PR — keep the scope surgical.

---

## 8. Versioning

This checklist is versioned independently of the tools it observes.

- **1.0.0** (2026-05-01) — initial seven-day single-machine routine for
  Phase E.

When the routine changes (new step, new pass condition, deleted column),
bump the minor version. Wording-only fixes bump the patch version.

The companion documents are versioned separately:

- [`docs/MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) — migration runbook.
- [`docs/MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) —
  validator contract.
- [`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) — trust tier
  semantics.
- [`docs/MEMORY_TRUST_BASELINE.md`](./MEMORY_TRUST_BASELINE.md) — per-file
  baseline decisions.
- [`docs/MEMORY_SYNC.md`](./MEMORY_SYNC.md) — scheduler architecture
  ([#527](https://github.com/kcenon/claude-config/issues/527)).
