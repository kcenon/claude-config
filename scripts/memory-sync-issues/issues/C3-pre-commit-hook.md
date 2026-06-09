---
title: "feat(memory): pre-commit hook in claude-memory repo"
labels:
  - type/feature
  - priority/high
  - area/memory
  - size/S
  - phase/C-bootstrap
milestone: memory-sync-v1-bootstrap
blocked_by: [C2]
blocks: [C5, D1]
parent_epic: EPIC
---

## What

Install a `pre-commit` git hook in `claude-memory` repo that runs `validate.sh` + `secret-check.sh` on staged `*.md` files, checks `MEMORY.md` index drift via `regen-index.sh --check`, and runs `injection-check.sh` as warning. Blocks the commit on any blocking-failure (validate ≤ 2, secret-check 1, index drift).

### Scope (in)

- `.git/hooks/pre-commit` script in claude-memory repo
- Installer script `scripts/install-hooks.sh` that copies the hook into `.git/hooks/`
- Hook scope: only staged files under `memories/` and `quarantine/`
- Block on validate FAIL or secret-check finding or MEMORY.md drift
- Warn (don't block) on injection-check flag
- Documentation in claude-memory README

### Scope (out)

- Hooks for other git events (commit-msg, pre-push) — out of scope here
- PreToolUse equivalent for Claude (#D2 separately)
- Server-side enforcement (#C5 GitHub Actions handles that)

## Why

Local pre-commit is the **last line of defense before push**. Once a secret reaches the remote it cannot be unsent. Once a malformed memory reaches the remote it propagates to all machines on next sync. The pre-commit gate ensures every commit author has run the validators and seen the verdict before the commit lands.

Bypassing via `--no-verify` is allowed but logged in the hook's stderr — server-side check (#C5) catches anything that bypassed the local hook.

### What this unblocks

- #D1 — sync engine can rely on every commit having passed validators
- Confidence that any memory pulled from remote during sync was at minimum locally validated by its author

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — secrets reaching remote are unrecoverable
- **Estimate**: ½ day
- **Target close**: within 3 days of #C2 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-memory`
- **Files**:
  - `hooks/pre-commit` (the hook source, tracked in repo)
  - `scripts/install-hooks.sh` (installer)
  - `.git/hooks/pre-commit` (installed copy, gitignored)

## How

### Approach

The hook source is tracked in `hooks/pre-commit` (so all clones see it). Installer copies it into `.git/hooks/pre-commit` because git doesn't auto-install. README instructs first-time clone to run `scripts/install-hooks.sh`. After installation, every `git commit` triggers the hook.

### Detailed Design

**`hooks/pre-commit` script flow**:
1. Get staged files: `git diff --cached --name-only --diff-filter=AM`
2. Filter to staged `memories/*.md` and `quarantine/*.md`
3. If filtered list is empty → exit 0 (nothing memory-related staged)
4. For each staged memory file:
   a. Run `validate.sh <file>` — block on exit 1 or 2
   b. Run `secret-check.sh <file>` — block on exit 1
   c. Run `injection-check.sh <file>` — warn on exit 3, do not block
5. Run `regen-index.sh --check` — block on exit 1 (drift)
6. Print summary
7. Exit 0 if no blocking failure, 1 otherwise

**`scripts/install-hooks.sh` flow**:
1. Verify in claude-memory repo (`.git` dir present, repo name check)
2. Copy `hooks/pre-commit` to `.git/hooks/pre-commit`
3. `chmod +x .git/hooks/pre-commit`
4. Print confirmation

**State and side effects**:
- Hook runs on every commit; modifies nothing in repo
- Installer modifies `.git/hooks/pre-commit` (one file, one machine)
- Hook stderr logs use of `--no-verify` if detected via `GIT_HOOK_BYPASSED` env (set by some shells; best-effort)

**External dependencies**: bash 3.2+, git, the validators in `scripts/`.

### Inputs and Outputs

**Input** (clean commit):
```
$ git add memories/feedback_new_rule.md
$ git commit -m "feat: add new feedback rule"
```

**Output**:
```
[pre-commit] checking 1 memory file
[pre-commit] feedback_new_rule.md
              validate:        PASS
              secret-check:    CLEAN
              injection-check: CLEAN
[pre-commit] MEMORY.md index: up to date
[pre-commit] OK

[main 3a4b5c6] feat: add new feedback rule
```

**Input** (blocked by secret):
```
$ git add memories/project_leak.md
$ git commit -m "..."
```

**Output**:
```
[pre-commit] checking 1 memory file
[pre-commit] project_leak.md
              validate:        PASS
              secret-check:    SECRET-DETECTED
                  [!] non-owner email: leaker@example.com
[pre-commit] BLOCKED — fix the issues or `git commit --no-verify` to bypass (logged)
```
Exit: `1`. Commit refused.

**Input** (warned, not blocked):
```
$ git add memories/feedback_strict_rule.md
$ git commit -m "feat: add strict policy"
```

**Output**:
```
[pre-commit] checking 1 memory file
[pre-commit] feedback_strict_rule.md
              validate:        PASS
              secret-check:    CLEAN
              injection-check: FLAGGED
                  [?] high density of absolute commands (4 occurrences)
[pre-commit] MEMORY.md index: up to date
[pre-commit] OK (with warnings)
```
Exit: `0`. Commit succeeds.

**Input** (drift):
```
$ git add memories/feedback_new.md
$ git commit -m "..."
```

**Output**:
```
[pre-commit] checking 1 memory file
[pre-commit] feedback_new.md   (all checks PASS/CLEAN)
[pre-commit] MEMORY.md index: DRIFT
              --- a/MEMORY.md
              +++ b/MEMORY.md
              ...
[pre-commit] BLOCKED — run `scripts/regen-index.sh` and stage MEMORY.md
```
Exit: `1`.

### Edge Cases

- **Staged file outside `memories/` and `quarantine/`** → ignored by hook
- **Staged delete of a memory** → hook accepts; index regen reflects deletion
- **Staged rename of a memory** → both old and new paths examined
- **Hook script itself not executable** → git silently skips; install-hooks.sh `chmod +x` is critical
- **`scripts/validate.sh` not on PATH and not a sibling** → hook tries `${REPO_ROOT}/scripts/validate.sh`; falls back to PATH; fails with diagnostic if neither
- **User runs `git commit --no-verify`** → hook never runs; documented as bypassable; #C5 catches
- **First clone of repo (hook not yet installed)** → README first-step says run `scripts/install-hooks.sh`
- **Hook performance** → 17 files × 3 validators = ~50 invocations × ~50 ms each = 2.5s typical; acceptable
- **Concurrent commits in same repo** → git serializes, no concurrency issue
- **`MEMORY.md` itself is staged** → hook validates it via regen-check
- **Frontmatter parse error in middle of multi-file commit** → hook reports per-file, all errors visible before block

### Acceptance Criteria

- [ ] `hooks/pre-commit` (tracked) executes the flow in Detailed Design
- [ ] `scripts/install-hooks.sh` copies hook to `.git/hooks/pre-commit` and sets +x
- [ ] **Filter**: hook only acts on staged `memories/*.md` and `quarantine/*.md`
- [ ] **Block on**: validate.sh exit ≥ 1, secret-check.sh exit 1, regen-index.sh --check exit 1
- [ ] **Warn but don't block on**: injection-check.sh exit 3
- [ ] **Bypass logging**: `--no-verify` use logged to stderr (best-effort)
- [ ] Output format: per-file verdict + summary line
- [ ] Hook exits 0 only if no blocking failure
- [ ] **Performance**: < 5 seconds for 17-file commit
- [ ] Bash 3.2 compatible
- [ ] README in claude-memory updated with first-time install instruction
- [ ] Synthetic tests: clean commit succeeds, secret commit blocked, injection commit warns and succeeds, drift commit blocked

### Test Plan

- Stage clean memory → commit succeeds with summary
- Stage memory with token → commit blocked
- Stage memory with absolute-command-density → commit succeeds with warning
- Stage memory without running regen-index.sh → drift detected, commit blocked
- `git commit --no-verify` → bypasses hook (verify it works)
- Re-run install-hooks.sh → idempotent (overwrites cleanly)
- macOS + Linux both pass

### Implementation Notes

- Hook script must be POSIX-compatible at the shebang (some setups use `/bin/sh`); use `#!/bin/bash` since validators require bash anyway
- Locating sibling scripts: `REPO_ROOT="$(git rev-parse --show-toplevel)"` then `${REPO_ROOT}/scripts/validate.sh`
- Don't `set -e` in the hook — multi-validator output is more useful when each runs independently
- Use `tput colors` to detect color support; output color only if interactive
- `--no-verify` cannot be reliably detected (git doesn't set an env var); the "logged" requirement is best-effort — could be implemented via comparing pre-commit hook execution against post-commit log file
- Hook is installed per-clone (not per-machine); each clone needs install-hooks.sh run once
- For shared installer convention: claude-config has `hooks/install-hooks.sh` for its own hooks; mirror that script structure for consistency

### Deliverable

- `hooks/pre-commit` (tracked in claude-memory repo, ~150 lines)
- `scripts/install-hooks.sh` (~30 lines)
- README updated with install instruction
- PR linked to this issue

### Breaking Changes

None — additive only.

### Rollback Plan

Remove `.git/hooks/pre-commit` to disable. Revert PR to remove from repo.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C2
- Blocks: #D1
- Related: #C5 (server-side mirror), #D2 (PreToolUse equivalent for Claude)

**Docs**:
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1) — exit-code contract
- `docs/MEMORY_TRUST_MODEL.md` (#B1) — quarantine semantics

**Commits/PRs**: (filled at PR time)

**Reference pattern**: `claude-config/hooks/install-hooks.sh`
