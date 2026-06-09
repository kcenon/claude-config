---
title: "docs(memory): second-machine onboarding runbook"
labels:
  - type/docs
  - priority/medium
  - area/memory
  - size/S
  - phase/G-rollout
milestone: memory-sync-v1-multi
blocked_by: [F1, C4]
blocks: [G2]
parent_epic: EPIC
---

## What

Author the "Adding a new machine" section of `docs/MEMORY_SYNC.md`. Step-by-step runbook for onboarding the second (or Nth) machine: bootstrap one-liner, SSH signing key registration, install verification, first-sync verification.

### Scope (in)

- Single section in `docs/MEMORY_SYNC.md`
- Bootstrap procedure assuming claude-config is already installed
- SSH signing key registration steps (per-machine)
- First-sync verification commands
- Common pitfalls section
- Cross-link to existing single-machine runbook (#E1)

### Scope (out)

- Multi-machine conflict scenario testing (#G2)
- Final operational doc (#G3) — though this section will live there
- Single-machine migration (#E1, already done)

## Why

The system is now battle-tested on the primary machine via #E2. To realize the full value (sync across machines), other machines need to come online safely. The onboarding runbook ensures a second machine joins with verified provenance (SSH signing) and doesn't accidentally diverge during its first hour.

The biggest risk is **a second machine diverging from primary before its first sync** — e.g., user expects memory to be present on the new machine before the clone completes, gets confused, manually creates conflicting files. A clear runbook prevents this.

### What this unblocks

- #G2 — multi-machine tests need at least 2 machines onboarded
- Adding the 3rd / 4th machine in the future (same procedure)

## Who

- **Author**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 1 week of #F1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/docs/MEMORY_SYNC.md` ("Adding a new machine" section)

## How

### Approach

Mirrors the structure of #E1's single-machine runbook but starts from a different premise: claude-memory **already has content** (the primary's data). The new machine's job is to receive, not to seed. This changes some steps and commands.

### Detailed Design

**Section structure**:

```markdown
## Adding a new machine

This procedure onboards an additional machine to the synced memory system after
the primary has been stable for 7+ days (#E2 passed).

### Pre-flight

- [ ] Primary machine fully migrated and stable (#E1 + #E2 done)
- [ ] claude-config repo cloned on new machine: `~/Sources/claude-config/`
- [ ] gh CLI authenticated: `gh auth status` shows logged in
- [ ] git ≥ 2.34 (for SSH signing): `git --version`
- [ ] No existing `~/.claude/memory-shared/` (this is fresh onboarding)

### Phase 1 — Set up SSH signing on this machine

Run the helper from #C4:

    ~/Sources/claude-config/scripts/setup-ssh-signing.sh

Then visit https://github.com/settings/ssh/new and add the printed public key
as a Signing key (not Auth key).

Verify:

    git -C ~/Sources/claude-config commit -S --allow-empty -m "ssh-signing-test"
    git -C ~/Sources/claude-config log --show-signature -1
    git -C ~/Sources/claude-config reset --hard HEAD~1     # remove the test commit

### Phase 2 — Install with memory sync enabled

    cd ~/Sources/claude-config
    CLAUDE_MEMORY_REPO_URL=git@github.com:kcenon/claude-memory.git \
      ./scripts/install.sh --profile global-only

Verify:

    ls -la ~/.claude/memory-shared/.git           # clone present
    ls ~/.claude/memory-shared/memories/ | wc -l  # should match primary's count
    launchctl list | grep claude-memory-sync      # macOS scheduler loaded
      # OR
    systemctl --user list-timers | grep memory-sync  # Linux scheduler

### Phase 3 — First sync (manual, observed)

    ~/.claude/scripts/memory-sync.sh --dry-run    # see planned actions
    ~/.claude/scripts/memory-sync.sh              # actual sync

Expected: nothing to push (this machine has no local changes), 0 to pull (already
fresh-cloned). Sync completes in seconds.

Verify:

    ~/.claude/scripts/memory-status.sh
    # last sync recent, 0 pending, machine recognized

### Phase 4 — Test write path

In a Claude Code session on the NEW machine:

    Ask Claude to add a memory describing this machine's hostname.

    Expected:
    - memory-write-guard.sh validates and allows
    - File appears in ~/.claude/memory-shared/memories/
    - Run memory-sync.sh to push
    - Within 1 hour, primary machine's memory-status.sh sees the new commit

### Phase 5 — Verify primary picked up the change

On the PRIMARY machine, after waiting up to 1 hour OR running memory-sync.sh
manually:

    ~/.claude/scripts/memory-status.sh --detail
    # active machines table should now list new machine with last-push recent
    ls ~/.claude/memory-shared/memories/ | grep <new-memory-name>

### Phase 6 — Symlink current Claude Code memory location

(Same as #E1 Phase 4, but the new machine may not have an existing memory dir.)

If `~/.claude/projects/-Users-<user>-Sources/memory/` exists:

    cd ~/.claude/projects/-Users-<user>-Sources/
    mv memory memory.deprecated
    ln -s ~/.claude/memory-shared/memories memory

If it doesn't exist (fresh Claude Code install on the new machine):

    mkdir -p ~/.claude/projects/-Users-<user>-Sources/
    ln -s ~/.claude/memory-shared/memories ~/.claude/projects/-Users-<user>-Sources/memory

### Common pitfalls

- **Phase 2 clone fails with permission denied** → SSH key not registered for git
  push (only signing); add as Auth key OR use HTTPS clone URL with token
- **Phase 4 write-guard fails to fire** → hook not registered; verify
  `~/.claude/settings.json` PreToolUse Edit | Write matcher includes
  memory-write-guard.sh
- **Phase 5 doesn't see new commit on primary** → primary's launchd may not have
  triggered; run `memory-sync.sh` manually on primary to fast-forward
- **Phase 6 cwd encoding differs** between machines (different home path) → each
  machine has its own encoded-cwd path; the symlink target is the same
  `~/.claude/memory-shared/memories` but the source path varies per machine
- **First sync says "fatal: refusing to merge unrelated histories"** → never
  happens with fresh clone; if it does, claude-memory was re-initialized at
  some point — investigate before proceeding
- **SSH signing key registered as Auth key only** → commits will fail to verify
  on push; re-add as Signing key explicitly

### Verification end-to-end

After all phases:

| Check | Command | Expected |
|---|---|---|
| Repo cloned | `git -C ~/.claude/memory-shared rev-parse HEAD` | matches primary's HEAD |
| Scheduler loaded | `launchctl list \| grep claude-memory-sync` (macOS) | non-empty |
| Sync logs | `tail ~/.claude/logs/memory-sync.log` | recent successful entry |
| Status | `~/.claude/scripts/memory-status.sh` | last sync recent, no alerts |
| Bidirectional | (write on new, see on primary; write on primary, see on new) | within 1 hour |
```

### Inputs and Outputs

**Input**: empty section in `docs/MEMORY_SYNC.md`.

**Output**: completed section per Detailed Design.

**Verification**: @kcenon onboards a real second machine following only the document, completes successfully without asking questions.

### Edge Cases

- **New machine on different OS than primary** (e.g., primary macOS, new Linux) → both schedulers documented; pick correct one per platform
- **GitHub MFA challenge** at first push → handled outside this doc; mention briefly
- **Slow network on first clone** → tolerable; document timeout via `git config --global http.lowSpeedTime 600`
- **Multiple users on the same machine** → out of scope (single-user system); brief note
- **Sync fails immediately on new machine** → consult #E1 rollback (delete clone, retry)
- **New machine's hostname matches primary's** → audit table merges them (incorrect attribution); document and recommend unique hostnames before onboarding

### Acceptance Criteria

- [ ] Section "Adding a new machine" added to `docs/MEMORY_SYNC.md`
- [ ] 6 phases with copy-paste commands and verification per Detailed Design
- [ ] Pre-flight checklist with 5 boxes
- [ ] Common pitfalls section with ≥ 5 documented gotchas
- [ ] End-to-end verification table at the end
- [ ] Cross-link from / to single-machine migration section (#E1)
- [ ] **Tested by onboarding a real second machine** by @kcenon before merge
- [ ] Linux + macOS commands work or note where they diverge

### Test Plan

- @kcenon onboards a real Linux VM (or second physical machine) following only the document
- Each phase's verification command outputs as expected
- Bidirectional sync verified across the two machines

### Implementation Notes

- Reuse the doc patterns from #E1 — same heading style, command formatting, rollback positioning
- The rollback for second-machine onboarding is "delete the clone" (machine simply leaves the system); much simpler than primary rollback
- Cross-link to #C4 for SSH key procedure rather than duplicating
- After this issue lands, the doc is ready for #G3's broader operational doc consolidation

### Deliverable

- `docs/MEMORY_SYNC.md` updated with "Adding a new machine" section
- PR linked to this issue
- @kcenon's onboarding-test confirmation in PR description

### Breaking Changes

None — documentation only.

### Rollback Plan

Revert PR.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #F1, #C4
- Blocks: #G2
- Related: #E1 (single-machine sibling), #C4 (SSH signing setup), #E3 (install integration)

**Docs**:
- `docs/MEMORY_SYNC.md` (this contributes a section)

**Commits/PRs**: (filled at PR time)
