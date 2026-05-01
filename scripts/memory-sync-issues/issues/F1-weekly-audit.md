---
title: "feat(memory): weekly audit.sh report generator"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/M
  - phase/F-audit
milestone: memory-sync-v1-audit
blocked_by: [E2, E3, B4]
blocks: [F3, G1]
parent_epic: EPIC
---

## What

Implement `scripts/audit.sh` — weekly job that re-runs all 3 validators on full memory tree, surfaces stale memories (`last-verified > 90d`), finds duplicate-suspected memories, verifies that referenced issues/PRs/files still exist, finds memories never accessed in the past N weeks. Output committed to `audit/YYYY-MM-DD.md` in claude-memory. User notified with summary count.

### Scope (in)

- Single bash script, executable
- Scheduled invocation (Mondays 09:00 via launchd / systemd)
- 5 audit categories: validator-rerun, stale, duplicate, broken-references, unused
- Markdown report committed to `audit/YYYY-MM-DD.md`
- User notification via #D5 with summary count
- Skips if previous report < 6 days old (idempotent under flapping schedules)

### Scope (out)

- Auto-quarantining audit findings (audit only reports; user actions via #F2)
- AI-based semantic review (#F3)
- Per-machine activity reports (those are in `memory-status.sh` #D4)

## Why

Validators catch immediate failures. They don't catch slow rot:

- A memory that was valid when written becomes stale after 90 days because the referenced incident is forgotten
- Two memories drift toward describing the same thing from slightly different angles
- A memory references `issue #424` that has since been closed and forgotten — the memory is now misleading
- A memory is never matched by any session's description-keyword scan — it's dead weight in the index

Weekly audit surfaces these patterns, batched into one report so user reviews them on their schedule rather than mid-task.

### What this unblocks

- #F2 — `/memory-review` skill consumes audit reports
- #F3 — semantic review reads audit reports as starting points
- #G1 — multi-machine state visible via centralized audit reports

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 1 day
- **Target close**: within 1 week of #E3 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-memory/scripts/audit.sh`
- **Output**: `kcenon/claude-memory/audit/YYYY-MM-DD.md`
- **Scheduler**: launchd plist / systemd timer in claude-config

## How

### Approach

The audit script orchestrates 5 independent checks, aggregates findings into a markdown report, commits to `audit/`, and notifies. Each check is a self-contained function so future additions / removals are easy.

### Detailed Design

**Script signature**:
```
audit.sh                                # generate report for today
audit.sh --dry-run                      # show what would be checked, no commit
audit.sh --since N                      # access window (default: 4 weeks)
audit.sh --output <path>                # write to alternate path
audit.sh --help
```

**Exit codes**:
- `0` — success (report generated, even if findings non-zero)
- `1` — fatal error (cannot read memory tree, cannot write report, etc.)
- `2` — recent report exists (< 6 days old); skipped
- `64` — usage error

**Audit checks**:

1. **Validator rerun**: validate.sh + secret-check.sh + injection-check.sh on `memories/` and `quarantine/`
   - Surface any new findings vs last week's report (delta)

2. **Stale**: memories where `last-verified > 90 days ago`
   - List file, name, last-verified, days-stale

3. **Duplicate suspect**: memories whose `description` field shares ≥ 5 distinguishing keywords (after stop-word removal)
   - List candidate pairs

4. **Broken references**: scan body for patterns
   - `issue #N` / `PR #N` / `pull #N` → check via `gh issue view` / `gh pr view` (auth permitting)
     - If CLOSED with no comment activity in 6mo → flag
     - If 404 → flag (deleted)
   - File paths matching `[a-zA-Z0-9_/.-]+\.(md|sh|py|ts|js|cpp|h)` → if relative-looking, check existence in nearby repos (best-effort)
     - If clearly external (`src/auth/login.ts` and no such file in any kcenon repo) → flag
   - Tolerant: only flags HIGH-confidence broken refs; ambiguous cases logged but not flagged

5. **Unused**: memories whose description tokens never matched any session-start memory-load over the past N weeks
   - Requires #F4 access logger; if absent, this check is skipped with note in report

**Report format** (`audit/YYYY-MM-DD.md`):
```markdown
# Memory Audit — 2026-05-04 (Monday)

Run host: macbook-pro

## Summary

| Category | Count |
|---|---|
| Validator findings | 0 |
| Stale | 2 |
| Duplicate suspects | 1 pair |
| Broken references | 1 |
| Unused | 0 |

## 1. Validator Findings

(none)

## 2. Stale (last-verified > 90 days)

- [feedback_old_thing](memories/feedback_old_thing.md) — last-verified 2026-01-15 (110 days ago)
- [project_legacy](memories/project_legacy.md) — last-verified 2026-01-20 (105 days ago)

## 3. Duplicate Suspects

| Pair | Shared keywords |
|---|---|
| feedback_ci_merge_policy / feedback_never_merge_with_ci_failure | "Never merge", "CI", "failure", "policy" |

## 4. Broken References

- `feedback_old_thing.md` references `issue #424` (CLOSED 2026-02-01 with no recent activity)

## 5. Unused (last 4 weeks of access logs)

(none — all memories had at least one matching session in the window)

## Recommended actions

- Run `/memory-review` to triage stale entries
- Review duplicate-suspect pair; consider merging or deleting
- Decide whether the memory referencing closed issue #424 still has standalone value
```

**Notification call** (#D5):
```
memory-notify.sh info "weekly audit: 2 stale, 1 duplicate, 1 broken ref"
```
Or `warn` if any new validator finding (which would have been auto-quarantined by sync's post-pull check, but audit re-confirms).

**State and side effects**:
- Reads memory tree
- Writes `audit/YYYY-MM-DD.md` (only one per day; idempotent with `--since`)
- Commits + pushes the report (via `git -C ... commit && memory-sync.sh --push-only`)
- Calls `memory-notify.sh`

**External dependencies**: bash 3.2+, gh (for issue/PR existence checks), validate.sh / secret-check.sh / injection-check.sh, optionally #F4 access log.

### Inputs and Outputs

**Input** (default):
```
$ ./audit.sh
```

**Output**:
```
[audit] running validator rerun on 17 memories... 0 findings
[audit] stale check (>90d): 2 entries
[audit] duplicate-suspect check: 1 pair
[audit] broken-references check: 1 (referenced issue #424 closed)
[audit] unused check: skipped (#F4 access log not available)
[audit] writing audit/2026-05-04.md
[audit] committing & pushing
[audit] notifying user
[audit] done in 12s
```
Exit: `0`

**Input** (recent report exists):
```
$ ./audit.sh
[audit] last report 2026-05-04.md is 2 days old; skipping
```
Exit: `2`

**Input** (dry-run):
```
$ ./audit.sh --dry-run
```

**Output**: same checks run, no commit, report printed to stdout.

### Edge Cases

- **Network down** → broken-references check skipped (gh fails); other checks proceed; report notes skipped section
- **Memory tree empty** → all checks return 0 findings; report still generated
- **`audit/` directory missing** → created on first run
- **Duplicate-suspect threshold tuning**: 5 shared keywords may produce noise; document and provide `--similarity-threshold N` flag for tuning
- **Broken-reference false positives**: a CLOSED issue is not always "broken"; the check uses 6mo-no-activity heuristic; document this
- **Unused check without access log** (#F4 not done) → graceful skip with note
- **Audit while sync is running** → flock; audit waits or exits 5
- **Audit produces no findings (all clean)** → report still committed; notification at info-severity
- **Same-day re-run after first** → second run sees report exists; exits 2
- **`--since` with very long window** (e.g., 52 weeks) → access log scan time grows; document; recommend ≤ 8 weeks
- **Reference to issue in private repo without gh access** → skipped with note in report

### Acceptance Criteria

- [ ] Script `scripts/audit.sh` (executable, in claude-memory)
- [ ] **5 audit checks** implemented per Detailed Design
- [ ] **Idempotency**: skips if last report < 6 days old (exit 2)
- [ ] **Report format** matches spec: summary table + 5 sections + recommended actions
- [ ] **Output**: `audit/YYYY-MM-DD.md`
- [ ] **Commit & push** the report (uses memory-sync.sh --push-only or direct git)
- [ ] **Notify** via #D5 with summary
- [ ] `--dry-run` does not commit
- [ ] `--since N` controls unused-check window
- [ ] **Bash 3.2 compatible**
- [ ] **Performance**: < 60 seconds typical (<5s per check excluding network)
- [ ] **Scheduling**: launchd / systemd unit added (parallel structure to #E3)
- [ ] First report committed during this issue's PR for regression test

### Test Plan

- Inject known stale memory (set last-verified 100d ago) → audit reports
- Inject duplicate-suspect pair → audit reports
- Inject memory referencing nonexistent gh issue → audit reports broken ref
- Run twice in same week → second exits 2 (skipped)
- Network down → broken-ref skipped, other checks continue
- macOS + Linux

### Implementation Notes

- Reuse frontmatter parser from #A2 / #B2
- `gh issue view <N>` returns non-zero on 404 — check exit code, not output
- `gh issue view <N> --json state,closedAt` for state + closed date
- 6mo-no-activity heuristic: `gh issue view N --json state,updatedAt`; if state=CLOSED and updatedAt > 6mo old → flag
- Duplicate suspect via tokenizer: lowercase, strip stop words, count shared tokens between description pairs; threshold 5 keeps noise low
- Stop words list: minimal English (`the`, `a`, `is`, etc.); not internationalized
- Audit calls `memory-sync.sh --push-only` rather than direct git push to avoid duplicating push logic
- For #F4 access log integration: read `~/.claude/logs/memory-access.log`; group by memory file path; if no entries in window → flagged
- Avoid `awk` redirections — use `grep`, `sort`, bash regex

### Deliverable

- `scripts/audit.sh` (executable, ~300 lines)
- launchd / systemd unit files for weekly scheduling
- Sample first audit report committed via PR
- Update `docs/MEMORY_SYNC.md` with audit operations section
- PR linked to this issue

### Breaking Changes

None — additive.

### Rollback Plan

- Disable scheduler (launchctl unload / systemctl --user disable)
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #E2, #E3, #B4
- Blocks: #F3, #G1
- Related: #F2 (consumes reports), #F4 (access log feeder), #D5 (notification)

**Docs**:
- `docs/MEMORY_SYNC.md` (#G3)

**Commits/PRs**: (filled at PR time)
