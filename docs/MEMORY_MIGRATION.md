# Memory Sync — Single-Machine Migration Runbook

**Version**: 1.0.0
**Last updated**: 2026-05-01
**Status**: Active
**Issue**: [#525](https://github.com/kcenon/claude-config/issues/525)
**Epic**: [#505](https://github.com/kcenon/claude-config/issues/505)

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Pre-flight Checklist](#2-pre-flight-checklist)
3. [Phase 1 — Backup](#3-phase-1--backup)
4. [Phase 2 — Backfill Local Frontmatter](#4-phase-2--backfill-local-frontmatter)
5. [Phase 3 — Trust-Level Baseline Review](#5-phase-3--trust-level-baseline-review)
6. [Phase 4 — Clone claude-memory and Install Hooks](#6-phase-4--clone-claude-memory-and-install-hooks)
7. [Phase 5 — Symlink Project Memory to the Shared Clone](#7-phase-5--symlink-project-memory-to-the-shared-clone)
8. [Phase 6 — Verify the Write-Guard Hook](#8-phase-6--verify-the-write-guard-hook)
9. [Phase 7 — First Manual Sync](#9-phase-7--first-manual-sync)
10. [Phase 8 — Post-Migration Validation](#10-phase-8--post-migration-validation)
11. [Phase 9 — Post-Flight (Session Health)](#11-phase-9--post-flight-session-health)
12. [Schedule (Forward Reference)](#12-schedule-forward-reference)
13. [Rollback Procedure](#13-rollback-procedure)
14. [Cleanup (After Observation Period)](#14-cleanup-after-observation-period)
15. [Common Pitfalls](#15-common-pitfalls)
16. [Versioning](#16-versioning)

---

## 1. Purpose and Scope

This runbook converts a single-machine Claude Code installation from per-machine
local memory only to local memory **plus** sync against the
[`kcenon/claude-memory`](https://github.com/kcenon/claude-memory) repository.

It is the canonical procedure that
[#526](https://github.com/kcenon/claude-config/issues/526) executes during the
seven-day observation window and that
[#532](https://github.com/kcenon/claude-config/issues/532) extends for
second-machine onboarding.

### In scope

- A linear sequence of phases with copy-paste-ready commands.
- A pre-flight checklist confirming all upstream Phase A–D deliverables.
- Per-phase verification commands that prove the step succeeded.
- A rollback procedure that restores the original layout in under one minute.
- A post-migration validation checklist exercising every validator.
- Pointers to scheduled-sync installation ([#527](https://github.com/kcenon/claude-config/issues/527))
  and to operational troubleshooting ([#534](https://github.com/kcenon/claude-config/issues/534)).

### Out of scope

- Multi-machine onboarding ([#532](https://github.com/kcenon/claude-config/issues/532)).
- Audit and review documentation
  ([#528](https://github.com/kcenon/claude-config/issues/528),
  [#529](https://github.com/kcenon/claude-config/issues/529)).
- Post-migration troubleshooting beyond the pitfalls listed in
  [Section 15](#15-common-pitfalls)
  ([#534](https://github.com/kcenon/claude-config/issues/534)).
- Implementation work on any tool — every script invoked here already exists
  on `develop`.

### Tested platforms

- macOS 14 (Sonoma) — primary author environment.
- Ubuntu 22.04 LTS — Linux validation target.
- Windows / WSL — out of scope; track in
  [#534](https://github.com/kcenon/claude-config/issues/534).

### Conventions

- Code blocks use four-space indentation so they render consistently in every
  Markdown viewer.
- The canonical example path used throughout is
  `~/.claude/projects/-Users-raphaelshin-Sources/memory`. The directory name
  is the cwd-encoded form Claude Code uses for the author's primary work tree;
  yours will differ — substitute the path printed by `ls ~/.claude/projects/`.
- The shared clone always lives at `~/.claude/memory-shared/`.
  `scripts/memory-sync.sh`, `scripts/memory-status.sh`, and the SessionStart
  hook all default to this location.
- Commands assume `bash`. They are POSIX-portable except where called out.

---

## 2. Pre-flight Checklist

Confirm every box before running [Phase 1](#3-phase-1--backup). The checklist
maps to the upstream Phase A–D deliverables.

- [ ] **claude-memory repo exists** ([#515](https://github.com/kcenon/claude-config/issues/515))
  — `gh repo view kcenon/claude-memory` returns a description and default branch `main`.
- [ ] **SSH commit signing configured** ([#518](https://github.com/kcenon/claude-config/issues/518))
  — `git config --global gpg.format` returns `ssh`, and your signing key is listed at
  GitHub → Settings → SSH and GPG keys → Signing Keys.
  See [`docs/SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md).
- [ ] **`gh` authenticated for SSH** —
  `gh auth status` reports a logged-in user, and
  `ssh -T git@github.com` returns "Hi `<handle>`! You've successfully authenticated."
- [ ] **`scripts/memory-sync.sh` present** ([#520](https://github.com/kcenon/claude-config/issues/520),
  PR [#547](https://github.com/kcenon/claude-config/pull/547))
  — `~/.claude/scripts/memory-sync.sh --help` prints the usage block.
- [ ] **`memory-write-guard.sh` registered** ([#521](https://github.com/kcenon/claude-config/issues/521))
  — `grep memory-write-guard ~/.claude/settings.json` returns at least one match
  inside the `PreToolUse` block (matcher `Edit|Write|Read`).
- [ ] **SessionStart integrity hook registered** ([#522](https://github.com/kcenon/claude-config/issues/522))
  — `grep memory-integrity-check ~/.claude/settings.json` returns one match inside
  the `SessionStart` block.
- [ ] **`scripts/memory-status.sh` present** ([#523](https://github.com/kcenon/claude-config/issues/523))
  — `~/.claude/scripts/memory-status.sh --help` prints the usage block.
- [ ] **`scripts/memory-notify.sh` present** ([#524](https://github.com/kcenon/claude-config/issues/524))
  — `~/.claude/scripts/memory-notify.sh --help` prints the usage block.
- [ ] **At least 1 GB free disk space** —
  `df -h ~/.claude` shows ≥ 1 GB Available.
- [ ] **No active Claude Code session** —
  No window, tmux pane, or background process has Claude Code attached.
  The PreToolUse hook only sees writes during your migration if no other
  session is also writing.

If any box is unchecked, stop and remediate. The remainder of the runbook
assumes every upstream artifact is in place.

---

## 3. Phase 1 — Backup

**Goal**: Capture an immutable copy of the existing memory tree before any
mutation. This is the safety net for the rollback in
[Section 13](#13-rollback-procedure).

### Commands

    SRC=~/.claude/projects/-Users-raphaelshin-Sources/memory
    BACKUP="$SRC.bak.$(date +%Y%m%dT%H%M%SZ)"
    cp -R "$SRC" "$BACKUP"
    echo "Backup at: $BACKUP"

### Verify

    diff -r "$SRC" "$BACKUP" && echo "OK: backup identical"

The `diff -r` must print only the success message. Any extra output means
the copy is divergent — abort and re-run `cp` before continuing.

### If this fails

- "No such file or directory" on `$SRC` — your encoded cwd is different.
  Run `ls ~/.claude/projects/` and substitute the matching directory name.
- "Operation not permitted" on macOS — Spotlight may be holding files;
  pause indexing for `~/.claude` (`mdutil -i off ~/.claude`) and retry.

---

## 4. Phase 2 — Backfill Local Frontmatter

**Goal**: Ensure every local memory file carries the Phase 2 frontmatter
fields (`source-machine`, `created-at`, `trust-level`, `last-verified`)
before it joins the shared clone. The validator in
[Phase 8](#10-phase-8--post-migration-validation) requires them.

The backfill script writes per-file backups (`<file>.bak.<UTCstamp>`) by
default; the [Phase 1](#3-phase-1--backup) tree-level backup is the
outer safety net.

### Dry-run first

    cd "$SRC"
    ~/.claude/scripts/memory/backfill-frontmatter.sh --dry-run --target-dir .

Inspect the report. Files already carrying all four Phase 2 fields are
listed `SKIP`; the remainder show the proposed additions per
[`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 9.

### Apply

    ~/.claude/scripts/memory/backfill-frontmatter.sh --execute --target-dir .

### Verify

    ~/.claude/scripts/memory/validate.sh --all . | tail -5

Expected: `0 FAIL`. `WARN-SEMANTIC` is acceptable for files where
`last-verified` is absent (which is correct for `inferred` entries — see
[`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 9).

### If this fails

- `FAIL-STRUCT` on a specific file → check it has both opening (`---`) and
  closing (`---`) frontmatter delimiters; the backfill skips files with
  malformed frontmatter rather than guessing.
- `FAIL-FORMAT` for `trust-level` → the existing value is outside the enum
  in [`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 7;
  fix manually then re-run validation.

---

## 5. Phase 3 — Trust-Level Baseline Review

**Goal**: Acknowledge the per-file trust decisions recorded in
[`docs/MEMORY_TRUST_BASELINE.md`](./MEMORY_TRUST_BASELINE.md). The decision
table is the canonical record; this phase only verifies you have read it
and that any changes you want to make are applied before [Phase 7](#9-phase-7--first-manual-sync).

### Read the decision record

    less ~/.claude/docs/MEMORY_TRUST_BASELINE.md

Pay particular attention to Section 3 (Per-File Decision Table) and
Section 4 (any quarantine candidates).

### Reconcile with your local files

If you wish to change a tier (`verified` → `inferred`, `inferred` →
`quarantined`, …), edit the affected file's frontmatter directly:

    # Example: demote a file to inferred
    sed -i.editbak 's/^trust-level: verified$/trust-level: inferred/' \
      ~/.claude/projects/-Users-raphaelshin-Sources/memory/<file>.md

Then re-run validation to confirm the change is well-formed:

    ~/.claude/scripts/memory/validate.sh \
      ~/.claude/projects/-Users-raphaelshin-Sources/memory/<file>.md

### Move quarantined files

For any file you classified `quarantined`:

    ~/.claude/scripts/memory/quarantine-move.sh \
      ~/.claude/projects/-Users-raphaelshin-Sources/memory/<file>.md

Quarantined files are excluded from sync until restored via
`quarantine-restore.sh`.

### Verify

The total count of memory files plus quarantined files must equal the
original count from [Phase 1](#3-phase-1--backup):

    ls "$SRC" | wc -l
    ls "$SRC/../quarantine" 2>/dev/null | wc -l   # may be empty/absent
    ls "$BACKUP" | wc -l
    # original count == surviving + quarantined

---

## 6. Phase 4 — Clone claude-memory and Install Hooks

**Goal**: Establish the local clone of `kcenon/claude-memory` at
`~/.claude/memory-shared/` and install the data-side `pre-commit` hook
that runs the validators before every commit.

### Clone

    git clone git@github.com:kcenon/claude-memory.git ~/.claude/memory-shared

### Install the data-side hook

The repository ships with `scripts/install-hooks.sh` which installs
`pre-commit` (validator + secret-check + injection-check) and configures
SSH-signed commits per
[`docs/SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md).

    cd ~/.claude/memory-shared
    ./scripts/install-hooks.sh

### Verify

    cd ~/.claude/memory-shared
    git log --oneline -1                 # expect the seed commit from #515
    ls memories/ | wc -l                 # expect the seeded baseline count
    ls -la .git/hooks/pre-commit         # expect executable, recent mtime

### Tracker-side PreToolUse hook (already registered)

`memory-write-guard.sh` was registered in `global/settings.json` under
[#521](https://github.com/kcenon/claude-config/issues/521). Re-confirm:

    grep memory-write-guard ~/.claude/settings.json

If the grep returns nothing, copy the registration from
`~/.claude/global/settings.json` (the canonical source) into your
local `settings.json` before continuing.

### If this fails

- Clone fails with `Permission denied (publickey)` → `gh auth status`
  reports an HTTPS-only login. Re-run `gh auth login`, choose SSH, and
  upload the key.
- `install-hooks.sh` reports "command not found: shellcheck" — install
  it (`brew install shellcheck` / `apt install shellcheck`); the hook
  invokes it during pre-commit on its own scripts.
- The seed commit count differs from your expectation — confirm against
  the latest [`#515` PR comment](https://github.com/kcenon/claude-config/issues/515)
  rather than this runbook.

---

## 7. Phase 5 — Symlink Project Memory to the Shared Clone

**Goal**: Redirect Claude Code's memory reads/writes from the per-project
directory to the shared clone, transparently and reversibly.

### Stage the swap

    cd ~/.claude/projects/-Users-raphaelshin-Sources/
    mv memory memory.deprecated

### Move classified files into the clone

Copy your reviewed files (excluding any that you quarantined in
[Phase 3](#5-phase-3--trust-level-baseline-review)) into
`~/.claude/memory-shared/memories/`:

    cp -n memory.deprecated/*.md ~/.claude/memory-shared/memories/

`-n` (no-clobber) ensures we never overwrite a seeded file accidentally.
Compare counts and resolve any collisions manually before continuing.

### Create the symlink

    ln -s ~/.claude/memory-shared/memories memory

### Verify

    ls -la memory                         # expect: symlink → ~/.claude/memory-shared/memories
    ls memory/ | head                     # expect: your migrated files appear
    readlink memory                       # expect: /Users/<you>/.claude/memory-shared/memories

### Commit the migrated files

    cd ~/.claude/memory-shared
    git add memories/
    git status
    git commit -S -m "feat(memory): migrate single-machine baseline"

The `pre-commit` hook installed in [Phase 4](#6-phase-4--clone-claude-memory-and-install-hooks)
will run all three validators. If any reports `FAIL`, fix the offending
file (or move it to quarantine) and re-stage.

### If this fails

- "ln: File exists" → your previous attempt left a symlink in place.
  `rm memory` then re-run `ln -s …`. Do not `mv` over an existing symlink
  — it will rename the symlink itself, not the target.
- pre-commit fails with `FAIL-FORMAT` → re-run `validate.sh` and fix the
  reported field; the hook will not bypass.
- Commit fails with "gpg failed to sign the data" → SSH signing is
  misconfigured. Re-check
  [`docs/SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md) Section 3.

---

## 8. Phase 6 — Verify the Write-Guard Hook

**Goal**: Confirm `memory-write-guard.sh` rejects unsafe writes against
the new path. This is a smoke test only — the hook is already registered
in `global/settings.json`.

### Open a new Claude Code session

The guard is a `PreToolUse` hook; it only fires inside an active session.

### Issue a deliberately unsafe write

Ask Claude (in chat) to write the following content to
`~/.claude/memory-shared/memories/test_write_guard.md`:

    ---
    type: reference
    description: synthetic write-guard test
    trust-level: inferred
    ---

    # Test
    A synthetic GitHub PAT for the guard test: ghp_TEST1234TEST1234TEST1234TEST1234

### Expected outcome

The write must be **rejected**. Claude reports a deny reason similar to
"`memory-write-guard.sh` blocked write: secret-check matched
`ghp_[A-Za-z0-9]{36}`". The file must not exist on disk.

### Verify

    test -e ~/.claude/memory-shared/memories/test_write_guard.md && \
      echo "FAIL: file exists" || echo "OK: blocked"

### Cleanup

    rm -f ~/.claude/memory-shared/memories/test_write_guard.md

(Run only if `test -e` somehow succeeds — under correct configuration the
file never lands.)

### If this fails

- The file lands on disk → the write-guard is not in `PreToolUse`.
  Re-check the registration:

      grep -A2 memory-write-guard ~/.claude/settings.json

  The hook command must be `~/.claude/hooks/memory-write-guard.sh` with
  matcher `Edit|Write|Read`.
- The hook fires but "denies" only with a warning → confirm the hook
  exits non-zero on detection (`bash -x ~/.claude/hooks/memory-write-guard.sh`
  with a sample stdin payload).

---

## 9. Phase 7 — First Manual Sync

**Goal**: Perform the inaugural bidirectional sync. This is the moment the
local clone and the remote `main` branch agree.

### Dry-run

    ~/.claude/scripts/memory-sync.sh --dry-run

The dry-run prints the planned actions (validate, fetch, rebase, validate,
push) without writing. A successful preview ends with
`INFO release_lock: OK`. Sample output from a healthy clone:

    [2026-05-01T23:38:28Z] INFO start: host=<host> mode=dry-run pull_only=0 push_only=0
    [2026-05-01T23:38:28Z] INFO acquire_lock: OK (flock pid=<pid>)
    [2026-05-01T23:38:28Z] INFO validate_repo_state: OK (branch=main)
    [2026-05-01T23:38:28Z] INFO capture_local_diff: 1 ahead, 0 changed files (HEAD only)
    [2026-05-01T23:38:28Z] INFO pre_push_validate: OK (validate.sh PASS, secret-check CLEAN)
    [2026-05-01T23:38:28Z] INFO fetch_remote: OK (no new refs)
    [2026-05-01T23:38:28Z] INFO release_lock: OK
    [2026-05-01T23:38:28Z] INFO complete: dry-run; no writes performed

If the dry-run reports `validate_repo_state: not a git repo` (the same
diagnostic as `memory-status.sh` returns when the clone is missing),
return to [Phase 4](#6-phase-4--clone-claude-memory-and-install-hooks).

### Real sync

    ~/.claude/scripts/memory-sync.sh

Successful exit code is `0`. Other codes from `memory-sync.sh --help`:

| Code | Meaning |
|---|---|
| `1` | pre-push validation failed |
| `2` | post-pull validation failed |
| `3` | merge conflict (rebase aborted) |
| `4` | push failed after one retry |
| `5` | lock contention (another sync is running) |
| `6` | git operation failed (other) |
| `64` | usage error |

### Verify

    ~/.claude/scripts/memory-status.sh

A healthy first sync shows `status: ok`, `last-sync` within the last few
minutes, and `pending: push=0 pull=0`. Exit code `0` confirms healthy.

### If this fails

- Exit `1` (pre-push validation) → some local file violates the schema
  or contains a secret. Run `validate.sh --all memories/` and
  `secret-check.sh --all memories/` directly to identify, fix, and
  re-sync.
- Exit `3` (merge conflict) → the rebase aborted cleanly. Investigate
  with `git log --oneline origin/main` and either `git rebase
  origin/main` manually or open an issue per
  [#534](https://github.com/kcenon/claude-config/issues/534).
- Exit `5` (lock contention) → another sync is in progress; wait or
  inspect `~/.claude/.memory-sync.lock`.

---

## 10. Phase 8 — Post-Migration Validation

**Goal**: Run every validator against the populated clone to certify the
data layer is internally consistent before scheduled syncs begin.

### Commands

    cd ~/.claude/memory-shared
    ~/.claude/scripts/memory/validate.sh --all memories/
    ~/.claude/scripts/memory/secret-check.sh --all memories/
    ~/.claude/scripts/memory/injection-check.sh --all memories/

### Expected results

- `validate.sh` — every file `PASS`. `WARN-SEMANTIC` is acceptable when
  the file's trust-level is `inferred` (no `last-verified` is correct).
- `secret-check.sh` — every file `CLEAN`. Any `FINDING` blocks; remediate
  before continuing.
- `injection-check.sh` — `CLEAN` or `FLAGGED`. `FLAGGED` is warn-only
  per the script's exit-code contract; review the flagged content but do
  not panic. Compare against the seeded baseline count from
  [`docs/MEMORY_TRUST_BASELINE.md`](./MEMORY_TRUST_BASELINE.md) Section 3
  to set expectations.

### If this fails

- `validate.sh` `FAIL-STRUCT` on a file post-sync — the rebase merged in a
  malformed file from elsewhere. Use `git log -p memories/<file>` to
  identify the offending commit and `quarantine-move.sh` if appropriate.
- `secret-check.sh` `FINDING` — a secret leaked despite the write-guard.
  Treat as an incident: see
  [`scripts/memory-sync-issues/INCIDENT-2026-05-01.md`](../scripts/memory-sync-issues/INCIDENT-2026-05-01.md)
  for the response template.

---

## 11. Phase 9 — Post-Flight (Session Health)

**Goal**: Confirm the SessionStart hook, the memory-status CLI, and the
notification CLI all see a healthy clone after migration.

### SessionStart hook output

Open a new Claude Code session and watch for the SessionStart message
emitted by `memory-integrity-check.sh`. A healthy clone is **silent** —
the hook prints nothing when last-sync is < 24 h, no quarantined files
appear, and there are no unread alerts. If you see any `[memory]` line,
read it: a stale-sync warning means schedule
[#527](https://github.com/kcenon/claude-config/issues/527) hasn't taken
over yet (expected at this stage).

### `memory-status.sh`

    ~/.claude/scripts/memory-status.sh
    ~/.claude/scripts/memory-status.sh --detail
    ~/.claude/scripts/memory-status.sh --json

Healthy summary: `status: ok`, recent last-sync, zero pending push/pull.
Exit code `0` confirms healthy. Exit `1` is warn-only (stale entries,
unread alerts); exit `2` is an error (clone missing, repo invalid).

For comparison, on a system without the clone the JSON form returns:

    $ ~/.claude/scripts/memory-status.sh --json
    {"error":"clone_missing","clone":"/home/<you>/.claude/memory-shared"}

This is the diagnostic to expect **before** Phase 4 runs — if you still
see it after [Phase 7](#9-phase-7--first-manual-sync), the symlink or the
clone is in the wrong location.

### `memory-notify.sh`

The notification CLI is a passive consumer — it only fires when alerts
land in `~/.claude/logs/memory-alerts.log`. After a clean migration the
file should be empty or contain only `INFO` entries. To smoke-test:

    ~/.claude/scripts/memory-notify.sh --help
    tail -n0 -F ~/.claude/logs/memory-alerts.log    # Ctrl-C when done

A healthy migration produces no `WARN` or `ERROR` lines.

---

## 12. Schedule (Forward Reference)

Manual `memory-sync.sh` runs cover the migration window itself. Background
syncing on a fixed cadence is delivered separately by
[#527](https://github.com/kcenon/claude-config/issues/527) (launchd plist
on macOS, systemd timer on Linux). Until #527 lands, run the script
manually before and after long sessions, and watch for the SessionStart
stale-sync warning described in
[Phase 9](#11-phase-9--post-flight-session-health).

The handoff is intentional: this runbook validates the data layer; #527
adds the scheduling layer on top.

---

## 13. Rollback Procedure

**Goal**: Restore the original layout in under one minute. This procedure
is the safety net for any failure between [Phase 5](#7-phase-5--symlink-project-memory-to-the-shared-clone)
and [Phase 8](#10-phase-8--post-migration-validation).

### Commands

    cd ~/.claude/projects/-Users-raphaelshin-Sources/
    rm memory                          # remove the symlink (not -rf!)
    mv memory.deprecated memory        # restore the original directory

If [Phase 2](#4-phase-2--backfill-local-frontmatter) modified files in
place and you want to revert those edits as well, replace the directory
with the [Phase 1](#3-phase-1--backup) backup:

    rm -rf memory
    cp -R "$BACKUP" memory             # $BACKUP from Phase 1

### Verify

    ls -la memory                      # expect: regular directory, not symlink
    diff -r memory "$BACKUP" && echo OK

The shared clone at `~/.claude/memory-shared/` is harmless after
rollback. You may leave it in place for a future retry, or remove it:

    rm -rf ~/.claude/memory-shared

Total rollback time on a healthy filesystem: well under 60 seconds.

### If rollback itself fails

- "rm: memory: Operation not permitted" → an active Claude Code session
  has the symlink open. Quit the session and retry.
- The backup at `$BACKUP` is gone — fall back to `git log` in
  `~/.claude/memory-shared/` and reconstruct from the `memories/`
  directory there. The shared clone is the canonical record once
  [Phase 7](#9-phase-7--first-manual-sync) succeeded once.

---

## 14. Cleanup (After Observation Period)

**Goal**: Reclaim disk space after the seven-day observation window in
[#526](https://github.com/kcenon/claude-config/issues/526) closes
without incident.

### After 7 days of stable operation

    rm -rf ~/.claude/projects/-Users-raphaelshin-Sources/memory.deprecated

The Phase 1 backup at `$BACKUP` may also be deleted:

    rm -rf "$BACKUP"

…or archived for long-term retention:

    tar -czf ~/.claude/archive/memory-baseline-$(date +%Y%m%d).tar.gz "$BACKUP"
    rm -rf "$BACKUP"

### Per-file backfill backups

The backfill script in [Phase 2](#4-phase-2--backfill-local-frontmatter)
created `<file>.bak.<UTCstamp>` per modified file. After
[#526](https://github.com/kcenon/claude-config/issues/526) closes:

    find ~/.claude/memory-shared/memories -name '*.bak.*' -delete

### Do not delete

- `~/.claude/memory-shared/` — this is the new canonical store.
- `.git/` inside the shared clone — required for sync.

---

## 15. Common Pitfalls

| Symptom | Likely cause | Resolution |
|---|---|---|
| `Phase 5` `mv` fails: "Operation not permitted" | macOS Spotlight is indexing | `mdutil -i off ~/.claude`, retry, then re-enable |
| `Phase 6` write-guard does not fire | `memory-write-guard.sh` not in `PreToolUse` `Edit\|Write\|Read` matcher | Compare `~/.claude/settings.json` against `~/.claude/global/settings.json` and copy the registration |
| `Phase 7` exits `5` (lock contention) | Another sync is running, or stale lock from a crash | `lsof ~/.claude/.memory-sync.lock`; if no process, remove the lock file and retry |
| `Phase 7` exits `1` (pre-push validate) | Local files violate schema or contain a secret | Run `validate.sh --all` and `secret-check.sh --all` to find the file; fix or quarantine |
| `Phase 8` `validate.sh` reports `WARN-SEMANTIC` only | `inferred`-tier files lack `last-verified`, which is correct | No action; this is by design per [`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 9 |
| First sync hangs indefinitely | SSH key not registered with `gh` | `gh auth status`; `ssh -T git@github.com`; re-run `gh auth login` and choose SSH if needed |
| `Phase 9` SessionStart prints `stale: last sync > 24h` | [#527](https://github.com/kcenon/claude-config/issues/527) scheduling not yet installed | Expected during migration; manual `memory-sync.sh` runs clear it. Once #527 lands, the warning self-clears |
| `memory-status.sh` returns `clone_missing` JSON | Symlink or clone in wrong location | Re-verify `readlink memory` points at `~/.claude/memory-shared/memories` and that `~/.claude/memory-shared/.git` exists |

---

## 16. Versioning

This runbook is versioned independently of the tools it invokes.

- **1.0.0** (2026-05-01) — initial single-machine procedure for Phase E.

When the procedure changes (new pre-flight item, new phase, deleted phase),
bump the minor version and add a row above. Bug-fix or wording-only edits
bump the patch version without a row.

The companion documents are versioned separately:

- [`docs/MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) — validator
  contract.
- [`docs/MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) — trust tier
  semantics.
- [`docs/MEMORY_TRUST_BASELINE.md`](./MEMORY_TRUST_BASELINE.md) — per-file
  baseline decisions.
- [`docs/SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md) — signing setup.

Future companion documents (out of scope here):

- `docs/MEMORY_SYNC.md` — operational reference and troubleshooting
  ([#534](https://github.com/kcenon/claude-config/issues/534)).
- `docs/THREAT_MODEL.md` — five-layer threat model
  ([#534](https://github.com/kcenon/claude-config/issues/534)).
