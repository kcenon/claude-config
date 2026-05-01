---
title: "docs(memory): single-machine migration runbook"
labels:
  - type/docs
  - priority/high
  - area/memory
  - size/S
  - phase/E-migration
milestone: memory-sync-v1-single
blocked_by: [D1, D2, D5]
blocks: [E2, E3]
parent_epic: EPIC
---

## What

Author `docs/MEMORY_SYNC.md` "Single-machine migration" section: a step-by-step runbook with rollback for transitioning from current per-machine memory to the synced `claude-memory` repo. Includes backup, classify, migrate, symlink, validate, and first-sync steps.

### Scope (in)

- Single document section (part of `docs/MEMORY_SYNC.md`, not a standalone doc)
- Linear ordered steps with copy-paste-ready commands
- Pre-flight checklist
- Per-step verification command
- Rollback procedure (revertible in < 1 minute)
- Post-migration validation checklist

### Scope (out)

- Multi-machine onboarding (#G1)
- Audit / review documentation (#F1, #F2)
- Operational troubleshooting beyond migration (#G3)
- Implementation of any tool (this is documentation only)

## Why

Migration is the riskiest moment in the entire system rollout: existing memory exists in one location, new system expects another. A vague runbook leads to data loss. A precise runbook with rollback turns this into a safe, repeatable operation.

This issue produces the **canonical procedure** that #E2 will execute and validate, and that #G1 will adapt for the second-machine onboarding.

### What this unblocks

- #E2 — observation checklist references this runbook
- #E3 — launchd plist installation comes after successful migration
- #G1 — second-machine onboarding builds on this base

## Who

- **Author**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — gates #E2 and #E3
- **Estimate**: ½ day
- **Target close**: within 3 days of #D5 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/docs/MEMORY_SYNC.md` (Single-machine migration section)

## How

### Approach

The runbook is a sequence of phases, each ending with a verification step and a clean rollback point. Commands are copy-paste-ready (no placeholders the user must remember to replace). Tested by following it on a Linux VM (or fresh macOS user account) before merging.

### Detailed Design

**Section structure** in `docs/MEMORY_SYNC.md`:

```markdown
## Single-machine migration

This procedure migrates an existing Claude Code installation from per-machine
memory to the synced claude-memory repo. Tested on macOS 14 and Ubuntu 22.04.

### Pre-flight checklist

- [ ] claude-memory repo exists and is accessible (`gh repo view kcenon/claude-memory`)
- [ ] SSH key registered for signing (#C4 done)
- [ ] memory-sync.sh present in claude-config (#D1 merged)
- [ ] memory-write-guard.sh registered in settings.json (#D2 merged)
- [ ] memory-notify.sh present (#D5 merged)
- [ ] At least 1GB free disk space
- [ ] No active Claude Code session running

### Phase 1 — Backup

Save the existing memory tree before any changes:

    SRC=~/.claude/projects/-Users-raphaelshin-Sources/memory
    BACKUP="$SRC.bak.$(date +%Y%m%d-%H%M%S)"
    cp -R "$SRC" "$BACKUP"
    echo "Backup at: $BACKUP"

Verify:

    diff -r "$SRC" "$BACKUP" || echo "WARN: backup divergent"

### Phase 2 — Clone claude-memory

    git clone git@github.com:kcenon/claude-memory.git ~/.claude/memory-shared

Verify:

    cd ~/.claude/memory-shared
    git log --oneline -1            # should show seed commit from #C1
    ls memories/ | wc -l            # should be 17 if seed contained baseline

### Phase 3 — Install hooks (claude-memory side)

    cd ~/.claude/memory-shared
    ./scripts/install-hooks.sh

Verify:

    ls -la .git/hooks/pre-commit    # should be executable, recent

### Phase 4 — Symlink current memory location to new

    cd ~/.claude/projects/-Users-raphaelshin-Sources/
    mv memory memory.deprecated
    ln -s ~/.claude/memory-shared/memories memory

Verify:

    ls -la memory                   # should show symlink → ~/.claude/memory-shared/memories
    ls memory/                      # should list the 17 memories

### Phase 5 — Test write-guard

In a new Claude Code session:

    Ask Claude to write to:
      ~/.claude/memory-shared/memories/test_write_guard.md
    with synthetic secret content (e.g., "ghp_test1234").

    Expected: write rejected, Claude reports the deny reason.

Cleanup after test:

    rm -f ~/.claude/memory-shared/memories/test_write_guard.md

### Phase 6 — First manual sync

    cd ~/.claude/memory-shared
    ~/.claude/scripts/memory-sync.sh --dry-run    # observe planned actions
    ~/.claude/scripts/memory-sync.sh              # actual sync

Verify:

    ~/.claude/scripts/memory-status.sh
    # should show last-sync recent, 0 pending push/pull

### Phase 7 — Validation

    cd ~/.claude/memory-shared
    ./scripts/validate.sh --all memories/         # 17 PASS, 0 WARN, 0 FAIL
    ./scripts/secret-check.sh --all memories/     # 17 CLEAN
    ./scripts/injection-check.sh --all memories/  # 14 CLEAN, 3 FLAGGED expected

### Rollback

If anything in Phase 4–7 went wrong, restore the original layout:

    cd ~/.claude/projects/-Users-raphaelshin-Sources/
    rm memory                                     # remove symlink
    mv memory.deprecated memory                   # restore original

(claude-memory clone at ~/.claude/memory-shared/ is harmless; can stay or
be removed via `rm -rf`.)

Total rollback time: < 1 minute.

### Cleanup (after observation period — see #E2)

After 7 days of stable operation:

    rm -rf ~/.claude/projects/-Users-raphaelshin-Sources/memory.deprecated
    # backup at $BACKUP can also be deleted, or archived

### Common pitfalls

- **Phase 4 fails with "Operation not permitted"** → check Spotlight is not indexing; retry
- **Phase 5 hook doesn't fire** → check `global/settings.json` PreToolUse Edit | Write matcher list includes memory-write-guard
- **Phase 6 sync exits 5 (lock contention)** → another sync running; wait or check `~/.claude/.memory-sync.lock`
- **Phase 7 validate.sh shows WARN** → backfill (#B2) wasn't applied to seeded memories; investigate via #C1 procedure
- **First sync hangs** → SSH key auth issue; verify `gh auth status` and `ssh -T git@github.com`
```

### Inputs and Outputs

**Input**: Empty section in `docs/MEMORY_SYNC.md`.

**Output**: The section above, integrated into `docs/MEMORY_SYNC.md`.

**Verification**: A reader following the runbook line-by-line on a fresh machine completes migration successfully without asking the author any questions.

### Edge Cases

- **User has multiple `~/.claude/projects/*/memory/` directories** (multiple cwd's tracked) → runbook covers only the canonical one; document multi-project handling as future work
- **User on Linux** → Phase 1 and beyond use POSIX commands; works without modification
- **User on Windows / WSL** → claude-docker context; defer to PowerShell mirror runbook (separate doc; out of scope here, document as such)
- **User runs migration mid-session** → checklist catches this; user closes session and retries
- **Backup directory has same name as previous backup** → `date +%Y%m%d-%H%M%S` includes seconds; collision essentially impossible
- **Hooks already installed from prior attempt** → `install-hooks.sh` is idempotent
- **Symlink already exists** (Phase 4 re-run) → `mv memory memory.deprecated` fails because symlink isn't a real dir; runbook handles via `rm memory` first
- **claude-memory remote unavailable during Phase 2** → clone fails; abort and retry later (no partial state)
- **Phase 4 done but Phase 6 fails** → memory-shared clone exists, symlink intact, but sync broken — rollback Phase 4 to be safe; investigate sync separately

### Acceptance Criteria

- [ ] `docs/MEMORY_SYNC.md` has "Single-machine migration" section
- [ ] Pre-flight checklist with 7 boxes
- [ ] 7 phases with copy-paste commands and verification steps
- [ ] Each phase has a clear "if this fails" path
- [ ] Rollback procedure is < 1 minute
- [ ] Post-migration validation checklist (Phase 7) calls all 3 validators
- [ ] Cleanup section explains when to remove backups (after #E2 observation)
- [ ] Common pitfalls section covers ≥ 5 documented gotchas
- [ ] **Tested end-to-end** by @kcenon on a fresh user account or VM before merge
- [ ] Hyperlinks to relevant tools and issues
- [ ] Linux + macOS commands work (or note where they diverge)

### Test Plan

- @kcenon walks through runbook on a fresh user account (or VM) following only the document
- Each phase's verification command outputs as expected
- Intentional failure injection at Phase 5 → rollback restores cleanly
- Section reads sequentially (no forward references that confuse first-time reader)

### Implementation Notes

- Use `~/.claude/projects/-Users-raphaelshin-Sources/memory` as the canonical example path; note in runbook that path differs per cwd encoding
- Document but do not include placeholder substitution — the runbook should work as-is for @kcenon
- Cross-link to other doc sections for items not specific to migration (e.g., "see Conflict resolution" for sync conflicts)
- Code blocks use 4-space indent (markdown-friendly across renderers)
- Avoid screenshots — text commands age better and are searchable

### Deliverable

- `docs/MEMORY_SYNC.md` updated with "Single-machine migration" section
- PR linked to this issue
- @kcenon's test-run confirmation in PR description

### Breaking Changes

None — documentation only.

### Rollback Plan

Revert PR. Migration commands documented elsewhere as a backup, or extracted to a gist temporarily.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #D1, #D2, #D5
- Blocks: #E2, #E3
- Related: #G1 (multi-machine onboarding extends this)

**Docs**:
- This contributes to `docs/MEMORY_SYNC.md` (which is also produced by #G3)
- `docs/MEMORY_TRUST_MODEL.md` (#B1) — referenced for tier semantics

**Commits/PRs**: (filled at PR time)
