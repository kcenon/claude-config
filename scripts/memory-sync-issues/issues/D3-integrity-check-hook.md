---
title: "feat(memory): SessionStart hook displays memory health summary"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/S
  - phase/D-engine
milestone: memory-sync-v1-engine
blocked_by: [C5]
blocks: []
parent_epic: EPIC
---

## What

Implement `global/hooks/memory-integrity-check.sh` — a SessionStart hook that prints a brief memory state summary at the beginning of each Claude Code session: total / verified / inferred / quarantined counts, last sync time and source machine, recently-added entries, stale entries (`last-verified > 90d`).

### Scope (in)

- SessionStart hook in claude-config
- Reads `~/.claude/memory-shared/` metadata only — no network, no validators
- Performance target: < 300ms
- Silent if all healthy AND no recent additions (no spam at every session start)
- Surfaces D5's pending notifications if any
- PowerShell mirror

### Scope (out)

- Running validators (those are scheduled jobs / hooks for write events)
- Triggering sync (separate scheduler)
- Interactive review (#F2)

## Why

The user has no other regular signal that memory is in good state. Without this hook, problems surface only when something goes wrong (sync conflict, audit report). A brief at-session summary makes silent drift visible:

- "Last sync 26 hours ago" → hourly sync stopped, investigate
- "2 inferred entries added today" → a recent memory needs your confirmation
- "1 stale entry" → 90+ day verification due

It's the equivalent of glancing at the dashboard before driving.

### What this unblocks

- General operational hygiene
- Reduces audit-finding surprise

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 1 week of #C5 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/global/hooks/memory-integrity-check.sh`
- **Settings update**: `global/settings.json` SessionStart matcher
- **PowerShell mirror**: `global/hooks/memory-integrity-check.ps1`

## How

### Approach

Read frontmatter of all memory files (cheap), aggregate counts by tier, derive last-sync time from git log (`git log -1 --format=%cd`), check `last-verified` field per memory for staleness. Print summary if anything actionable; silent otherwise.

### Detailed Design

**Hook input**: SessionStart hooks receive minimal JSON (per Claude Code hook contract); this hook ignores input.

**Hook output**: stdout text, displayed to user at session start.

**Computation flow**:
1. If `~/.claude/memory-shared/` missing → exit 0 silently (system not deployed yet)
2. Count files in `memories/` by `trust-level` field
3. Count files in `quarantine/`
4. Read git log: `git -C ~/.claude/memory-shared log -1 --format=%ct,%H,%an` to get last-sync time + commit
5. For each `memories/*.md` with `last-verified > 90d ago` → stale list
6. For each `memories/*.md` with `created-at < 24h ago` → recent list
7. Read `~/.claude/logs/memory-alerts.log` (#D5) for unread alerts
8. Decide whether to print:
   - If alerts present → always print
   - If recent additions present → always print
   - If stale > 0 → always print
   - If last-sync > 24h ago → always print
   - Else → silent (return 0 with no stdout)
9. Print summary

**Output format** (when not silent):
```
[memory] 17 entries (verified:13, inferred:3, quarantined:1)
[memory] last sync 37 min ago (host: macbook-pro)
[memory] 2 added in last 24h: feedback_xyz, project_abc — review with /memory-review
[memory] 1 stale (last-verified > 90d): feedback_old_thing
[memory] 1 unread alert: post-pull validation found problems on 2026-04-30
```

**Output format** (silent — exit 0 with no stdout, common case)

**Performance budget**: 17 files × small read = < 50ms; git log = < 100ms; total < 200ms.

**State and side effects**:
- Read-only on memory tree
- No network
- No validator invocation
- No git commits

**External dependencies**: bash 3.2+, git, basic POSIX tools.

### Inputs and Outputs

**Input**: SessionStart event (JSON ignored).

**Output** (silent — healthy):
```
(no stdout)
```
Exit: `0`

**Output** (recent activity):
```
[memory] 17 entries (verified:14, inferred:2, quarantined:1)
[memory] last sync 22 min ago (host: macbook-pro)
[memory] 1 added in last 24h: feedback_pr_size_limit — review with /memory-review
```

**Output** (stale + sync stale):
```
[memory] 17 entries (verified:13, inferred:3, quarantined:1)
[memory] ⚠ last sync 28h ago (host: mac-mini-home) — sync may be stuck
[memory] 1 stale (last-verified > 90d): feedback_old_thing — review with /memory-review
```

**Output** (unread alert):
```
[memory] 17 entries (verified:14, inferred:2, quarantined:1)
[memory] last sync 14 min ago (host: macbook-pro)
[memory] ⚠ 1 unread alert: post-pull validation found problems on 2026-04-30
       run /memory-review or check ~/.claude/logs/memory-alerts.log
```

### Edge Cases

- **First-ever Claude Code session before #E1 migration** → memory-shared dir missing → silent exit 0
- **`memories/` empty** → "[memory] 0 entries" + last-sync info; mostly silent
- **`last-verified` field missing on a verified memory** → counted as stale (per #B1 spec)
- **Git command fails** (corrupted local clone) → print warning "[memory] cannot read git log; check ~/.claude/memory-shared/"
- **Hook delays session start** → strict 300ms budget; if exceeded, print warning and continue (don't actually delay user)
- **Multiple unread alerts** → print count + most recent message; user runs `/memory-review` for full list
- **Time zone interpretation** of dates → all in UTC for consistency
- **Symlink to memory tree** (per #E1) → traverse via realpath; works
- **Frontmatter parse failure on a file** → skip that file in counts, log warning to stderr (not stdout, so doesn't pollute session start)
- **Concurrent SessionStart hooks** (multiple Claude Code processes) → harmless; each hook independent

### Acceptance Criteria

- [ ] Hook script `global/hooks/memory-integrity-check.sh` (executable)
- [ ] PowerShell mirror `global/hooks/memory-integrity-check.ps1`
- [ ] Registered in `global/settings.json` SessionStart
- [ ] Reads memory-shared dir; silent if missing
- [ ] Counts by trust-level: verified / inferred / quarantined
- [ ] Reports last-sync time + source machine from git log
- [ ] Reports memories added in last 24h
- [ ] Reports stale memories (`last-verified > 90d`)
- [ ] Reports unread alerts from `~/.claude/logs/memory-alerts.log` (#D5)
- [ ] **Silent unless** any of: recent activity / stale / sync > 24h / unread alerts
- [ ] **Performance**: < 300ms typical, hard cap 500ms (warns at cap)
- [ ] No validator invocation (pure metadata read)
- [ ] No network
- [ ] Bash 3.2 compatible
- [ ] Test: simulate stale memory → output mentions stale; simulate fresh state → silent

### Test Plan

- Healthy state, all recent → silent
- Last sync 25h ago → warns
- Inject memory with `last-verified: 2026-01-01` → stale warning
- Add memory with current `created-at` → recent activity warning
- Touch alert log file → "1 unread alert"
- Performance: time 100 invocations, average < 300ms
- macOS + Linux

### Implementation Notes

- **Frontmatter read**: reuse the parser pattern from #A2 — single-line YAML key:value extraction via `grep`/`sed`
- **Date math** for "24h ago" / "90 days ago": use `date +%s` epoch comparison; portable across macOS/Linux
- **Stale threshold**: 90 days = 7,776,000 seconds; constant
- **Recent threshold**: 24h = 86,400 seconds
- **Unread alerts**: assume alerts log file format `<ISO date> <severity> <message>` per line; tail the file for last entry; "unread" tracked via marker file `~/.claude/.memory-alerts-read-mark` (epoch second of last read)
- **Output prefix `[memory]`** matches existing claude-config hook pattern (`[hook-name]` is conventional)
- **`⚠` symbol** for warnings (Unicode, terminal-friendly)
- **Hook must not error fatally** — fail-quiet on any internal issue, log to stderr, return 0; SessionStart must never block session
- Avoid `awk` write-redirection (bash-write-guard) — pure read

### Deliverable

- `global/hooks/memory-integrity-check.sh` (executable, ~120 lines)
- `global/hooks/memory-integrity-check.ps1`
- `global/settings.json` updated
- PR linked to this issue

### Breaking Changes

None.

### Rollback Plan

- Remove hook from `global/settings.json`
- Remove hook script files
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C5
- Blocks: (none direct; supports overall operations)
- Related: #D1 (sync produces commits this hook reads), #D5 (alerts log this hook reads), #B1 (trust-level semantics)

**Docs**:
- `docs/MEMORY_TRUST_MODEL.md` (#B1)
- `docs/MEMORY_SYNC.md` (#G3) — operational reference

**Commits/PRs**: (filled at PR time)

**Reference pattern**: `claude-config/global/hooks/instructions-loaded-reinforcer.sh`
