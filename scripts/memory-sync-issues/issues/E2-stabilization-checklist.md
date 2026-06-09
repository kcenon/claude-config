---
title: "chore(memory): single-machine stabilization observation checklist"
labels:
  - type/chore
  - priority/medium
  - area/memory
  - size/XS
  - phase/E-migration
milestone: memory-sync-v1-single
blocked_by: [E1]
blocks: [E3, F1]
parent_epic: EPIC
---

## What

Define and execute a 7-day observation checklist for the primary machine immediately after migration (#E1). Daily verification of sync health, no false-positive denials, and stable launchd execution. Issue closes only after 7 consecutive clean days OR a documented anomaly that triggered rollback.

### Scope (in)

- 7-day daily checklist (one row per day in this issue's body)
- Clear pass/fail criteria per day
- Anomaly rollback procedure cross-reference
- Final go/no-go decision for #E3 (scheduler installation)

### Scope (out)

- Implementation work — this is an observation period
- Multi-machine validation (#G2)
- Long-term audit (#F1 weekly)

## Why

The migration runbook (#E1) gets the system into a working state at one moment in time. Stable operation requires the system to keep working unattended over days, including across:

- Hourly launchd / systemd executions (need #E3 first, but observation includes manual sync)
- Sleep / wake cycles
- Network interruptions
- Edits to memory during normal use

A 7-day observation window catches issues that a one-time test misses — silent log corruption, drift in sync timing, edge cases triggered by accumulated state.

If observation fails, the system is rolled back without expanding to other machines. This issue is the **gate** between Phase E (single-machine) and Phase F/G (audit + multi-machine).

### What this unblocks

- #E3 — scheduler installation only after observation passes
- #F1 — audit job is one of the things observed
- #G1 — second-machine onboarding only after primary is stable

## Who

- **Observer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 7 days passive observation; ~5 minutes/day active
- **Target close**: 7 days after #E1 closing (or earlier on rollback)

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Observed system**: primary machine (`hostname -s`)
- **Tools**:
  - `memory-status.sh` (#D4) for daily snapshot
  - `~/.claude/logs/memory-sync.log` for chronology
  - `~/.claude/logs/memory-alerts.log` for issues

## How

### Approach

Each day, observer runs a small verification routine and records pass/fail in this issue's body. Failure triggers rollback (per #E1 procedure) and re-evaluation. Success after Day 7 unblocks #E3.

### Detailed Design

**Daily verification routine** (~5 minutes):

```
1. Run: ~/.claude/scripts/memory-status.sh --detail
   Confirm:
   - Last sync within 90 minutes (manual sync acceptable in this phase)
   - 0 pending push and 0 pending pull
   - No unread alerts

2. Check: ~/.claude/logs/memory-sync.log
   Confirm:
   - At least 1 sync entry in last 24h
   - No "ABORT" lines

3. Try: write a synthetic clean memory via Claude Code
   Confirm:
   - Write succeeds
   - File appears in memories/
   - Subsequent sync pushes it

4. Try: write synthetic invalid memory (with secret pattern)
   Confirm:
   - Write rejected by memory-write-guard.sh
   - File NOT created

5. Try: read a memory via Claude Code
   Confirm:
   - File loads from memories/ via symlink
   - Content unchanged
```

**Daily log** (table to fill in this issue's body):

| Day | Date | Sync OK | Logs Clean | Write Test | Reject Test | Read Test | Notes |
|---|---|---|---|---|---|---|---|
| 1 | 2026-05-XX | | | | | | |
| 2 | 2026-05-XX | | | | | | |
| 3 | ... | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |
| 6 | | | | | | | |
| 7 | | | | | | | |

**Pass criteria**:
- 7 of 7 days all "Sync OK", "Logs Clean", "Write Test ✓", "Reject Test ✓", "Read Test ✓"
- 0 sync.log ABORT entries across the week
- < 5 unread alerts total across the week (warn-level acceptable, no critical-level unresolved)

**Fail criteria** (any one triggers rollback):
- Sync stale > 6 hours despite manual `memory-sync.sh` invocation
- Validators incorrectly reject a legitimate memory (false-positive denial)
- Symlink to memory tree breaks
- Any critical-severity alert (#D5) unresolved

**Anomaly procedure**:
1. Stop further write activity
2. Capture state: `memory-status.sh --json > /tmp/anomaly-snapshot.json`
3. Document in this issue's body
4. Decide: investigate-and-continue OR rollback (#E1 rollback section)
5. If rollback: reset Day counter; restart observation after fix

### Inputs and Outputs

**Input**: Migration completed per #E1.

**Output**: This issue's body filled in with daily results table; closing comment with go/no-go decision.

**Verification commands** (per day):
```
$ ~/.claude/scripts/memory-status.sh --detail
$ tail -50 ~/.claude/logs/memory-sync.log | grep -E '^[0-9]'
$ tail -20 ~/.claude/logs/memory-alerts.log
```

### Edge Cases

- **User skips a day** (forgets) → Day not counted; restart at Day 1 OR document gap and continue if no events occurred. Default: restart for safety.
- **Day 5 succeeds but Day 6 fails minor warn** → user discretion: continue if root-caused and resolved within day; restart if it indicates instability
- **Manual sync needed multiple times in a day** → indicates scheduler readiness should be revisited; not a fail by itself, but noted
- **Network down for an entire day** → sync test postponed; rest of routine still possible; document the day as "limited verification"
- **User on vacation** → observation pauses; closing comment notes the duration; system unattended is OK if it's just sitting

### Acceptance Criteria

- [ ] This issue's body contains the daily checklist table
- [ ] All 7 days filled in with Pass/Fail per column
- [ ] 7 consecutive clean days OR rollback documented
- [ ] On rollback: this issue stays open; new comment explains the failure
- [ ] On success: closing comment authorizes #E3 to proceed
- [ ] If observation reveals doc gaps in #E1 → file follow-up issue or PR
- [ ] If observation reveals tool bugs → file follow-up issues for #D1 / #D2 / etc.

### Test Plan

- The observation IS the test. No separate test plan beyond defining the routine.

### Implementation Notes

- This issue is intentionally lightweight on automation — the observation period is for **manual confirmation**, the kind of judgment that automation can't replace
- If automation eventually grows (e.g., a daily cron summary), it goes in #F1 audit, not here
- Resist the urge to start #E3 (scheduler) before observation completes; the whole point is "no surprises in unattended state"
- Anomaly rollback is documented in #E1; this issue references but doesn't duplicate

### Deliverable

- This issue's body completed across 7 days
- Closing comment with go/no-go decision

### Breaking Changes

None — observation only.

### Rollback Plan

Per #E1 rollback section. After rollback, this issue stays open; once fixed, restart Day 1.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #E1
- Blocks: #E3, #F1
- Related: #D1, #D2, #D5 (the systems being observed), #G1 (depends on this passing)

**Docs**:
- `docs/MEMORY_SYNC.md` (#E1) — migration & rollback

**Commits/PRs**: (filled if any follow-up PRs are filed)
