---
title: "feat(memory): /memory-review interactive review skill"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/M
  - phase/F-audit
milestone: memory-sync-v1-audit
blocked_by: [B1]
blocks: []
parent_epic: EPIC
---

## What

Implement `/memory-review` Claude Code skill that walks the user through stale, flagged, and duplicate memories from the most recent audit report (#F1). For each entry, user choices: y (verify), n (quarantine), e (edit), s (skip). Skill is user-invocable only (not auto-loaded).

### Scope (in)

- New skill `~/.claude/skills/_internal/memory-review/SKILL.md`
- `disable-model-invocation: true` (user calls explicitly)
- Loads most recent audit report from `claude-memory/audit/`
- Walks entries one at a time, paginated for large reports
- Updates `last-verified` on confirm
- Calls `quarantine-move.sh` on demote
- Opens `$EDITOR` on edit choice
- Summary at end with counts by action

### Scope (out)

- Modifying memory files outside the skill flow (use editor for that)
- Bulk-promote without per-entry confirmation
- Multi-machine coordination (each machine reviews its local view)

## Why

Audit (#F1) surfaces what needs attention but doesn't act. `/memory-review` is the **action layer**: user decides per entry. Without an interactive skill, audit reports accumulate as docs that never get acted on.

The skill is `disable-model-invocation: true` because actions are mutating (promote, demote, edit) and Claude shouldn't decide unilaterally to demote a memory.

### What this unblocks

- Closes the audit → action loop
- Trust-tier promotion lifecycle (#B1) — without action, inferred memories never become verified

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 1 day
- **Target close**: within 1 week of #F1 closing (can develop in parallel after #B1)

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/global/skills/_internal/memory-review/SKILL.md`
- **Skill dir**: directory with SKILL.md + helper scripts if needed

## How

### Approach

A skill is a markdown body with frontmatter. The skill body becomes Claude's instructions when invoked. The skill doesn't need to be a script — it's a procedure Claude executes step-by-step using its tools (Read, Edit, Bash).

The skill instructs Claude to:
1. Find the latest audit report
2. Parse the findings
3. For each finding, present concise summary and ask user
4. Apply the user's choice via shell commands (`memory-notify.sh`, `quarantine-move.sh`, edit)

This is exactly the pattern many existing global skills use (`pr-work`, `issue-work`, etc.).

### Detailed Design

**Skill frontmatter**:
```yaml
---
name: memory-review
description: Interactive review of stale, flagged, and duplicate memories from the latest audit report. Walks entries one at a time with confirm / quarantine / edit / skip choices.
argument-hint: "[--category stale|flagged|duplicate|broken-ref|all] [--limit N]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read Edit Grep Glob Bash
---
```

**Skill body** (excerpt):
```markdown
# /memory-review — Interactive memory triage

This skill helps you review entries flagged by the most recent audit report.

## Procedure

1. Find the most recent audit report:
   ```
   ls -t ~/.claude/memory-shared/audit/*.md | head -1
   ```

2. Parse the report sections per the format from #F1:
   - Stale (`## 2. Stale`)
   - Duplicate suspects (`## 3. Duplicate Suspects`)
   - Broken references (`## 4. Broken References`)
   - Validator findings (`## 1. Validator Findings`)

3. Filter by `--category` argument if provided (default: all).
4. For each entry, present:
   ```
   [stale 1/3] feedback_old_thing.md
   "Why: prior incident with X..."
   last-verified: 2026-01-15 (110 days ago)

   Action: (y) verify  (n) quarantine  (e) edit  (s) skip  (q) quit
   ```

5. Apply user's choice:
   - y: update `last-verified: <today>` in frontmatter
   - n: run `~/.claude/memory-shared/scripts/quarantine-move.sh <file> --reason "/memory-review demoted"`
   - e: open `$EDITOR` on the file; on save, re-run validate.sh; if PASS, update last-verified
   - s: leave unchanged
   - q: stop and emit summary

6. After last entry (or quit), summary:
   ```
   Reviewed 5 entries:
     verified:    3
     quarantined: 1
     edited:      1
     skipped:     0
   ```

## Output formatting

- Each entry: filename, description quote, key audit metadata, then choices
- Pagination: every 5 entries pause and ask "continue / quit"
- Quote-block memory excerpts to distinguish from skill instructions

## Edge cases

- **No audit report found** → "No audit report yet; run audit.sh"
- **`--category` with no matching entries** → "No entries in category X for review"
- **User picks `e` but $EDITOR not set** → fallback to nano; warn if nano absent
- **Edit produces invalid file** → revert via backup; report; mark skipped
- **Quarantine fails** (file permission) → report; continue with next
```

**Frontmatter explained**:
- `disable-model-invocation: true` — only user can invoke; Claude won't trigger this on its own
- `user-invocable: true` — appears in `/` autocomplete
- `allowed-tools` — pre-grants Read / Edit / Grep / Glob / Bash without per-action approval (per Claude Code skills spec)

**State and side effects**:
- Modifies frontmatter `last-verified` on memory files
- Moves memory files between `memories/` and `quarantine/`
- May launch external editor
- No commit (user runs `memory-sync.sh` after to push)

**External dependencies**: claude-memory tools (`quarantine-move.sh`, `validate.sh`).

### Inputs and Outputs

**Input** (user types in Claude Code):
```
/memory-review
```

**Output** (Claude's interactive flow):
```
Found audit report: ~/.claude/memory-shared/audit/2026-05-04.md
Categories: 2 stale, 1 duplicate-suspect, 1 broken-ref

Starting review...

[stale 1/2] feedback_old_thing.md
> "Never enable feature X — prior incident in 2025-Q4..."
> last-verified: 2026-01-15 (110 days ago)
Action: (y) verify  (n) quarantine  (e) edit  (s) skip  (q) quit

> y

[OK] last-verified → 2026-05-08

[stale 2/2] project_legacy.md
...
```

**Input** (with category filter):
```
/memory-review --category stale --limit 10
```

**Input** (no audit yet):
```
/memory-review
```

**Output**:
```
No audit report found at ~/.claude/memory-shared/audit/.
Run ~/.claude/memory-shared/scripts/audit.sh first, or wait for the weekly job.
```

### Edge Cases

- **Audit report from yesterday and today** → use most recent (latest-mtime)
- **Audit report split across multiple files** (week + monthly) → use weekly only for now
- **User invokes mid-session before audit ever ran** → friendly error, suggest manual `audit.sh`
- **User starts review then closes session** → state is per-action (each y/n/e action is committed immediately to file); resume from next-unprocessed-entry on re-invocation, but no automatic resume — user re-invokes
- **Edit choice opens $EDITOR but user closes without saving** → file unchanged; treat as skip
- **Edit produces validate.sh FAIL** → skill warns, asks if user wants to retry edit or skip
- **Quarantine fails because file already in quarantine** → warn, continue
- **`/memory-review --category broken-ref` and broken-ref check was network-skipped** → "no entries in category"
- **Concurrent skill invocation** in two Claude sessions → both modify; later overwrites earlier; not common, document warning
- **Memory file in `quarantine/`** appearing in audit (validator finding) → review can restore via `quarantine-restore.sh` (separate flow, not in v1; document as future)

### Acceptance Criteria

- [ ] SKILL.md created at `global/skills/_internal/memory-review/SKILL.md`
- [ ] **Frontmatter**: `name`, `description`, `argument-hint`, `user-invocable: true`, `disable-model-invocation: true`, `allowed-tools`
- [ ] **Procedure**: finds latest audit report, parses sections, paginates entries
- [ ] **Choices**: y / n / e / s / q implemented per Detailed Design
- [ ] **`--category`**: filters to subset
- [ ] **`--limit N`**: caps reviewed entries
- [ ] **Summary at end**: counts per action
- [ ] **Edge cases handled** per list above
- [ ] **Mutations applied immediately** (each action commits to file before next prompt)
- [ ] After review, prompt: "Run memory-sync.sh to push changes? (y/n)"
- [ ] Documented in `docs/MEMORY_SYNC.md` under "Operations"

### Test Plan

- Generate synthetic audit report with mixed categories
- Invoke `/memory-review`; walk through; verify mutations
- Test `--category stale` filter
- Test edit choice with valid + invalid edits
- Test quit mid-flow → summary correct
- Test no-audit-yet error path

### Implementation Notes

- The skill body is **prose instructions**, not code — Claude reads and follows it. Make it specific enough that Claude doesn't improvise key steps
- Use existing skill patterns from `~/.claude/skills/_internal/` (issue-work, pr-work) — frontmatter style, body structure
- Quote audit excerpts with `>` markdown blockquote so the user sees the original intent of the memory while deciding
- Avoid embedding tool-specific paths in the skill body — use `~/.claude/memory-shared/...` consistently so it works across machines
- "Run memory-sync.sh after?" prompt: optional, but reduces a step the user otherwise needs to remember
- After PR merges, test by user actually invoking `/memory-review` in a session — skill works only when properly registered

### Deliverable

- `global/skills/_internal/memory-review/SKILL.md`
- Optional helper scripts in same dir if procedure needs them
- Update `docs/MEMORY_SYNC.md` "Operations" section
- PR linked to this issue

### Breaking Changes

None.

### Rollback Plan

- Remove skill directory
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #B1
- Blocks: (none)
- Related: #F1 (consumes audit reports), #B4 (calls quarantine-move), #D1 (push changes after)

**Docs**:
- `docs/MEMORY_TRUST_MODEL.md` (#B1) — promotion / demotion rules
- `docs/MEMORY_SYNC.md` (#G3) — operational reference

**Commits/PRs**: (filled at PR time)

**Reference patterns**: existing skills under `~/.claude/skills/_internal/` (issue-work, pr-work)
