---
title: "feat(memory): quarantine directory mechanism"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/S
  - phase/B-trust
milestone: memory-sync-v1-trust
blocked_by: [B1]
blocks: [C1, C2, C3, F1]
parent_epic: EPIC
---

## What

Implement the storage-side mechanism for the `quarantined` trust level: directory layout, transport rules during sync, and a restore CLI to move a quarantined file back to active memories after re-validation.

### Scope (in)

- Directory convention: `claude-memory/quarantine/`
- `MEMORY.md` index excludes `quarantine/` content from the active list, but lists quarantined entries in a separate section
- Sync transports `quarantine/` files (so the quarantine state propagates to all machines) — quarantine is not "do not sync"
- `quarantine-move.sh` and `quarantine-restore.sh` CLIs
- Auto-move on failed validation (consumed by #D2 write-guard)
- 30/60/90-day lifecycle markers (consumed by #F1 audit)

### Scope (out)

- Audit job that surfaces stale quarantine entries (#F1)
- Interactive review UI (#F2)
- Auto-archive after 90 days (specified here, implemented in #F1)

## Why

Without a quarantine layer, the only options for suspicious memory are "keep it active" (risky) or "delete it" (lossy). Quarantine adds a third option: preserved, non-applied, reviewable. This is essential for false-positive recovery — if validators incorrectly demote a legitimate memory, the user can review and restore.

### What this unblocks

- #C2 — index generator excludes quarantine from active memories
- #C3 — pre-commit hook can recommend (or auto) quarantine on validation fail
- #D2 — write-guard hook auto-moves on validation fail
- #F1 — weekly audit checks quarantine staleness
- #F2 — `/memory-review` lists quarantine candidates for restore or archive

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 3 days of #B1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree** (final): `kcenon/claude-memory/{quarantine/, scripts/quarantine-{move,restore}.sh}` after #C1
- **Work tree** (interim): `kcenon/claude-config/scripts/memory/`

## How

### Approach

Quarantine is a **directory move**, not a flag-only state. Files in `quarantine/` are treated as inactive by index generators and consumers. Two CLIs handle the move and restore. Validation failure paths in other hooks call into these CLIs rather than re-implementing the move.

### Detailed Design

**Directory layout** (in claude-memory repo):
```
claude-memory/
├── memories/             # active (verified, inferred)
├── quarantine/           # quarantined
├── archive/              # auto-archive after 90 days (created by #F1)
│   └── 2026-08/
└── scripts/
    ├── quarantine-move.sh
    └── quarantine-restore.sh
```

**`quarantine-move.sh` signature**:
```
quarantine-move.sh <file> [--reason "<text>"] [--no-edit]
```
- Moves `file` from `memories/` to `quarantine/`
- Updates frontmatter: `trust-level: quarantined`, adds `quarantined-at: <ISO date>`, adds `quarantine-reason: <text>`
- Returns 0 on success, 1 on failure (file not found, write error)

**`quarantine-restore.sh` signature**:
```
quarantine-restore.sh <file> [--reason "<text>"]
```
- Re-runs validate.sh + secret-check.sh + injection-check.sh on the file
- If any blocking check fails: refuses to restore, exit 2
- If all pass: moves to `memories/`, sets `trust-level: verified`, updates `last-verified: today`, removes `quarantined-at` and `quarantine-reason` fields
- Returns 0 on success, 1 on usage error, 2 on revalidation failure

**Sync transport rule**:
- `memory-sync.sh` (#D1) does NOT skip `quarantine/`
- Reason: a memory quarantined on machine A must propagate to machine B so B doesn't independently surface it as "missing"
- Both machines see identical quarantine state

**Frontmatter additions** (only for quarantined files):
```yaml
quarantined-at: 2026-05-01T09:30:00Z
quarantine-reason: "secret-check.sh detected non-owner email"
quarantined-by: macbook-pro     # source-machine that did the move
```

**Lifecycle markers** (consumed by #F1):
- 0–30 days: passive
- 30–60 days: audit suggests `/memory-review` action
- 60–90 days: audit warns; ready for archive
- 90+ days: audit recommends `quarantine-archive.sh` (deferred to #F1)

**State and side effects**:
- `quarantine-move.sh`: moves file, modifies frontmatter, no body changes
- `quarantine-restore.sh`: moves file, modifies frontmatter, runs validators
- Both: produce a git change visible to next `memory-sync.sh`

**External dependencies**: bash 3.2+, validate.sh / secret-check.sh / injection-check.sh on PATH or sibling.

### Inputs and Outputs

**Input** (move):
```
$ ./quarantine-move.sh memories/feedback_suspicious.md --reason "injection-check flagged"
```

**Output**:
```
[OK] feedback_suspicious.md → quarantine/feedback_suspicious.md
     reason: injection-check flagged
     quarantined-at: 2026-05-01T09:30:00Z
```
Exit code: `0`

**Input** (restore success):
```
$ ./quarantine-restore.sh quarantine/feedback_suspicious.md --reason "false positive confirmed"
```

**Output**:
```
[VALIDATING] feedback_suspicious.md
  validate.sh:    PASS
  secret-check.sh: CLEAN
  injection-check.sh: CLEAN
[OK] quarantine/feedback_suspicious.md → memories/feedback_suspicious.md
     last-verified: 2026-05-01
```
Exit code: `0`

**Input** (restore fails revalidation):
```
$ ./quarantine-restore.sh quarantine/feedback_still_bad.md
```

**Output**:
```
[VALIDATING] feedback_still_bad.md
  validate.sh:    PASS
  secret-check.sh: SECRET-DETECTED
    [!] non-owner email: leaker@example.com
[REFUSED] revalidation failed; remains in quarantine
```
Exit code: `2`

### Edge Cases

- **File already in `quarantine/` when `quarantine-move.sh` is called** → no-op, exit 0
- **File not in `memories/` (typo)** → exit 1, "file not found"
- **`quarantine/` directory does not exist** → script creates it before first move
- **Restore conflicts with same-name file already in `memories/`** → refuse with exit 1; user resolves manually
- **`quarantine-reason` contains shell metacharacters** → escaped via bash quoting; never `eval`'d
- **Move during active sync** → file lock not enforced; advise user not to manually quarantine during sync (sync should always finish < 30s)
- **Frontmatter parse fails** → exit 1, "cannot read frontmatter"; do not move
- **`MEMORY.md` somehow ends up in `quarantine/`** → never happens via tooling; if manual, `regen-index.sh` (#C2) ignores it
- **Sync conflict on quarantine directory** → resolved as any other file conflict per #D1 strategy
- **30-day audit marker triggers and user does nothing** → audit re-emits warning the next week; never auto-archives without user action (per spec)

### Acceptance Criteria

- [ ] Directory layout: `claude-memory/quarantine/` exists, gitignored only if empty
- [ ] **`quarantine-move.sh`**
  - [ ] Moves file from `memories/` to `quarantine/`
  - [ ] Updates frontmatter: `trust-level: quarantined`, adds `quarantined-at`, `quarantine-reason`, `quarantined-by`
  - [ ] Idempotent: re-running on already-quarantined file is no-op
- [ ] **`quarantine-restore.sh`**
  - [ ] Runs all 3 validators before restoring
  - [ ] Refuses on any blocking failure (validate.sh ≤ 2, secret-check.sh = 1)
  - [ ] On success: moves to `memories/`, sets `trust-level: verified`, updates `last-verified`, removes quarantine fields
- [ ] Sync (#D1) transports `quarantine/` content (not skipped)
- [ ] Index generator (#C2) lists quarantined entries in a separate section, not the active list
- [ ] Lifecycle markers documented for #F1 audit consumer (30/60/90 day thresholds)
- [ ] Documented in `docs/MEMORY_TRUST_MODEL.md` (#B1) — adds storage-layer details
- [ ] Both scripts: bash 3.2 compatible, `+x`, shebang, `--help`
- [ ] No body content modification — only frontmatter

### Test Plan

- Move a synthetic memory; verify directory move + frontmatter changes
- Re-run move on already-quarantined → no-op
- Restore a clean memory → succeeds, fields removed
- Restore a still-tainted memory (synthetic with secret) → refused
- Concurrent move and restore on same file (race) → second one fails cleanly (file moved)
- macOS + Linux both pass

### Implementation Notes

- Use `git mv` if scripts run inside a git working tree, else plain `mv` — auto-detect
- Frontmatter manipulation reuses parser from #A2 / #B2 — extract a shared lib if duplicated 3+ times
- `quarantined-at` is the timestamp the file moved to `quarantine/`, not when validation failed (those may differ if move is delayed)
- Restore should NOT silently re-promote to `verified` if `last-verified` is missing — set it to today
- Avoid `awk` redirections (bash-write-guard) — bash + temp file + `mv`

### Deliverable

- `scripts/quarantine-move.sh` (executable)
- `scripts/quarantine-restore.sh` (executable)
- Update to `docs/MEMORY_TRUST_MODEL.md` documenting storage layer
- PR linked to this issue

### Breaking Changes

None — net-new mechanism.

### Rollback Plan

Revert PR. Manually move quarantined files back if any.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #B1
- Blocks: #C2, #C3, #F1
- Related: #D1 (sync transport), #D2 (auto-quarantine on write fail), #F2 (interactive review)

**Docs**:
- `docs/MEMORY_TRUST_MODEL.md` (#B1)

**Commits/PRs**: (filled at PR time)
