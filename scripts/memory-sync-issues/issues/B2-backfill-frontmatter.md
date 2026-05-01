---
title: "feat(memory): backfill-frontmatter.sh adds source-machine/created-at/trust-level"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/M
  - phase/B-trust
milestone: memory-sync-v1-trust
blocked_by: [B1]
blocks: [B3]
parent_epic: EPIC
---

## What

One-shot tool that adds Phase 2 frontmatter fields (`source-machine`, `created-at`, `trust-level`, `last-verified`) to existing memory files that lack them. Idempotent, dry-run by default, auto-creates timestamped backups.

### Scope (in)

- Single bash script with `--dry-run` (default), `--execute`, `--target-dir`
- Adds missing fields only — never overwrites existing values
- Auto-backup `<file>.bak.<UTCstamp>` before any in-place modification
- Reports per-file added fields
- Type-based default for `trust-level` per #B1 migration rules

### Scope (out)

- Modifying body content
- Removing or renaming existing fields
- Cross-machine sync — runs locally on whichever machine owns the memory at backfill time

## Why

All 17 baseline memories lack the four Phase 2 fields. validate.sh emits 17 WARN-SEMANTIC. Without backfill, every sync, audit, and integrity check would emit the same warnings forever. Backfill is the one-time bridge between v0 (pre-spec) and v1 (Phase 2 fields required) memory layouts.

### What this unblocks

- #B3 — initial classification can be applied via this tool's defaults plus user overrides
- #C1 — bootstrap of claude-memory repo expects fully-populated frontmatter
- All consumers of `trust-level` and `last-verified` (write-guard, audit, /memory-review)

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 1 day
- **Target close**: within 1 week of #B1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree** (final): `kcenon/claude-memory/scripts/backfill-frontmatter.sh` after #C1
- **Work tree** (interim): `kcenon/claude-config/scripts/memory/backfill-frontmatter.sh`

## How

### Approach

Reuse the frontmatter parser from #A2's `validate.sh`. Walk each `*.md` in target dir, check which Phase 2 fields are missing, append them in canonical order before the closing `---`. Default values come from machine context and #B1's migration table.

### Detailed Design

**Script signature**:
```
backfill-frontmatter.sh [--dry-run | --execute] [--target-dir DIR] [--no-backup]
```

**Defaults**:
- `--dry-run` ON unless `--execute` passed
- `--target-dir` defaults to current directory (`memories/` typically)

**Exit codes**:
- `0` — success (or dry-run completed)
- `1` — at least one file failed to write
- `2` — bad target directory or no `.md` files found
- `64` — usage error

**Internal flow** (per file):
1. Skip `MEMORY.md`
2. Run validate.sh's frontmatter parser → get current keys
3. Compute missing fields:
   - `source-machine` → `$(hostname -s)`
   - `created-at` → file mtime in ISO 8601 UTC: `date -u -r "$(stat -f %m FILE)" '+%Y-%m-%dT%H:%M:%SZ'` (macOS) / equivalent on Linux
   - `trust-level` → from #B1 migration table by type
   - `last-verified` → today's UTC date `+%Y-%m-%d`
4. If `--dry-run`: print "would add: ..." and continue
5. If `--execute`:
   a. Copy `FILE` to `FILE.bak.YYYYMMDDTHHMMSS` (unless `--no-backup`)
   b. Find closing `---` line number
   c. Insert missing fields (canonical order) just before that line
   d. Verify result parses with validate.sh

**Canonical field order** (when inserting new fields, keep this order; existing files may have different order — preserve theirs):
```
name: ...
description: ...
type: ...
source-machine: ...
created-at: ...
trust-level: ...
last-verified: ...
when_to_use: ...    (if present)
```

**State and side effects**:
- Modifies `*.md` files in place (when `--execute`)
- Creates `*.bak.<stamp>` backups
- Stdout: per-file "added: <fields>" report
- Idempotent: re-running adds nothing if all fields present

**External dependencies**: bash 3.2+, `stat`, `date`, `hostname`, `validate.sh` (sourced for parser, or invoked as helper).

### Inputs and Outputs

**Input** (dry-run, default):
```
$ ./backfill-frontmatter.sh --target-dir /tmp/claude/memory-validation/sample-memories
```

**Output**:
```
[DRY-RUN] feedback_ci_merge_policy.md: would add source-machine, created-at, trust-level=verified, last-verified
[DRY-RUN] user_github.md: would add source-machine, created-at, trust-level=verified, last-verified
...
[DRY-RUN] project_steamliner_doc_approval.md: would add source-machine, created-at, trust-level=verified, last-verified

Summary: 17 files would be modified, 0 already complete
Run with --execute to apply.
```
Exit code: `0`

**Input** (execute):
```
$ ./backfill-frontmatter.sh --execute --target-dir ./memories
```

**Output**:
```
[OK] feedback_ci_merge_policy.md: added source-machine, created-at, trust-level=verified, last-verified
       backup: feedback_ci_merge_policy.md.bak.20260501T091500
[OK] ...

Summary: 17 modified, 17 backups created, 0 errors
```
Exit code: `0`

**Input** (idempotent re-run):
```
$ ./backfill-frontmatter.sh --execute --target-dir ./memories
```

**Output**:
```
[SKIP] feedback_ci_merge_policy.md: already complete
[SKIP] user_github.md: already complete
...

Summary: 0 modified, 0 backups, 0 errors
```
Exit code: `0`

**Input** (custom defaults via env):
```
$ MACHINE_NAME=mac-mini-home ./backfill-frontmatter.sh --execute
```

### Edge Cases

- **File missing closing `---`** → skip with warning; user runs validate.sh first
- **File with frontmatter that already has all 4 Phase 2 fields** → skip silently; report "already complete"
- **File with one field present, three missing** → adds only the missing three, in canonical order
- **`stat` syntax differs (macOS vs Linux)** → detect via `uname` and use platform-specific invocation
- **No write permission on target file** → report error, continue with next file, exit 1 at end
- **Backup creation fails (disk full)** → abort that file, do not modify original
- **`--no-backup` + write fails midway** → file may be in inconsistent state; document this risk; recommend git commit before backfill
- **`hostname -s` returns FQDN on some Linux setups** → use `hostname -s` and accept whatever returns; user can override with env var `MACHINE_NAME`
- **type field is invalid** (e.g., `misc`) → can't determine `trust-level` default; skip with warning
- **Multiple memories with the exact same `created-at`** (mtime resolution) → acceptable; not a uniqueness key

### Acceptance Criteria

- [ ] Script `scripts/backfill-frontmatter.sh` (executable)
- [ ] **Default mode**: `--dry-run` (must be explicit `--execute` to write)
- [ ] **Idempotent**: re-running on already-complete files reports SKIP, modifies nothing
- [ ] **Auto-backup** on `--execute` (unless `--no-backup`): `<file>.bak.<UTCstamp>`
- [ ] **Field defaults**
  - [ ] `source-machine` = `$(hostname -s)` overridable via `MACHINE_NAME` env
  - [ ] `created-at` = file mtime in ISO 8601 UTC
  - [ ] `trust-level` = per #B1 migration table (user/feedback/project → verified, reference → inferred)
  - [ ] `last-verified` = today's UTC date
- [ ] **Preserves existing field order**; new fields inserted in canonical position before closing `---`
- [ ] **macOS bash 3.2 + Linux bash 5.x** both work
- [ ] **macOS `stat` and Linux `stat`** both handled
- [ ] After running on 17 baseline copies, validate.sh produces 1 PASS + 17 PASS (no warnings remaining)
- [ ] Reports per-file added fields
- [ ] Summary line at end: counts of modified, skipped, errors
- [ ] Help text on `--help`
- [ ] Script `+x`, shebang `#!/bin/bash`

### Test Plan

- Run `--dry-run` on 17 baseline copies → reports 17 "would add"
- Run `--execute` on 17 baseline copies → 17 modified, 17 backups, all subsequent validate.sh runs are PASS
- Re-run `--execute` → 17 SKIP, 0 modified
- Run on file missing closing `---` → skip with warning
- Run on file with no write permission → exit 1 with error message
- macOS + Linux both pass

### Implementation Notes

- **Avoid in-place edit via `sed -i`** — macOS `sed -i ''` vs GNU `sed -i` divergence is a known footgun; use temp file + `mv` instead
- File mtime → ISO 8601 UTC: macOS `date -u -r "$(stat -f %m FILE)" '+%Y-%m-%dT%H:%M:%SZ'`; Linux `date -u -d "@$(stat -c %Y FILE)" '+%Y-%m-%dT%H:%M:%SZ'` — detect platform with `uname`
- Insertion strategy: read file into 3 segments (pre-frontmatter, frontmatter, body), append new fields to frontmatter segment, concatenate, write to temp, atomic rename
- `validate.sh` should be available at `${SCRIPT_DIR}/validate.sh` (siblings); use `dirname "$0"` to find it
- Test atomicity: kill -9 the script mid-write → file should still be valid (temp file approach guarantees this)
- Avoid `awk` write-redirection (bash-write-guard) — use bash + `cat` + `mv`

### Deliverable

- `scripts/backfill-frontmatter.sh` (executable, ~150 lines)
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — operates only on files missing Phase 2 fields.

### Rollback Plan

Backups (`*.bak.<stamp>`) restore by `mv`. Document this in script's `--help` output.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #B1
- Blocks: #B3
- Related: #A2 (parser reuse), #C1 (consumer)

**Docs**:
- `docs/MEMORY_TRUST_MODEL.md` (#B1) — migration table source
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1) — frontmatter rules

**Commits/PRs**: (filled at PR time)
