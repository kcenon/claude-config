# Memory Sync — Operations Guide

**Version**: 1.0.0
**Last updated**: 2026-05-01
**Status**: Active
**Issue**: [#534](https://github.com/kcenon/claude-config/issues/534)
**Epic**: [#505](https://github.com/kcenon/claude-config/issues/505)

---

## Table of Contents

1. [What This Is](#1-what-this-is)
2. [Architecture](#2-architecture)
3. [Installation](#3-installation)
4. [Single-Machine Migration](#4-single-machine-migration)
5. [Adding a New Machine](#5-adding-a-new-machine)
6. [Daily Operations](#6-daily-operations)
7. [Validators](#7-validators)
8. [Trust Tiers](#8-trust-tiers)
9. [Audit](#9-audit)
10. [Privacy: Memory-Access Logging](#10-privacy-memory-access-logging)
11. [Conflict Resolution](#11-conflict-resolution)
12. [Rollback Procedures](#12-rollback-procedures)
13. [SSH Commit Signing](#13-ssh-commit-signing)
14. [Uninstall](#14-uninstall)
15. [Test Mode](#15-test-mode)
16. [Troubleshooting](#16-troubleshooting)
17. [Glossary](#17-glossary)
18. [Versioning](#18-versioning)
19. [Related](#19-related)

---

## 1. What This Is

Memory sync keeps Claude Code's auto-memory consistent across multiple
machines using a private git-backed store with validation, signed commits,
and a three-tier trust model.

The shared store lives at `~/.claude/memory-shared/` on every participating
machine, with the canonical copy at the private GitHub repository
[`kcenon/claude-memory`](https://github.com/kcenon/claude-memory). A platform
scheduler (launchd on macOS, systemd user timer on Linux) runs the sync
engine [`memory-sync.sh`](../scripts/memory-sync.sh) hourly without user
intervention.

Five overlapping defense layers protect against contaminated memory
propagating across machines (see
[`THREAT_MODEL.md`](./THREAT_MODEL.md#4-defense-layers-overview)). Three
validators (`validate.sh`, `secret-check.sh`, `injection-check.sh`)
implement those layers; the
[`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) document is the
authoritative contract. A trust model
([`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md)) gates which memories
auto-apply to sessions.

---

## 2. Architecture

```
+------------+        +-----------------------+        +-----------------+
| launchd /  |  -->   | memory-sync.sh        |  -->   | git remote      |
| systemd    |        | (--lock-timeout 30)   |        | claude-memory   |
| (hourly)   |        +-----------------------+        +-----------------+
+------------+                  |
                                v
                        +---------------------+
                        | ~/.claude/          |
                        |   memory-shared/    |
                        +---------------------+
                                |
                                v
                +-----------------------------------+
                | memory-write-guard.sh (PreToolUse)|
                | memory-integrity-check (Session)  |
                | memory-access-logger (PostRead)   |
                +-----------------------------------+
                                |
                                v
                        +---------------------+
                        | Claude Code session |
                        +---------------------+
```

| Platform | Scheduler             | Unit / Plist Path                                            |
|----------|-----------------------|--------------------------------------------------------------|
| macOS    | launchd LaunchAgent   | `~/Library/LaunchAgents/com.kcenon.claude-memory-sync.plist` |
| Linux    | systemd user timer    | `~/.config/systemd/user/memory-sync.{service,timer}`         |

Both schedulers run as the current user (not root) and invoke
`$HOME/.claude/scripts/memory-sync.sh --lock-timeout 30` via `bash -lc` so
the user's interactive PATH (gh, git) is loaded. Lock-timeout 30 prevents
pile-up when a previous run is still active.

### Component map

| Component | Path | Phase |
|-----------|------|-------|
| Sync engine | [`scripts/memory-sync.sh`](../scripts/memory-sync.sh) | D ([#520](https://github.com/kcenon/claude-config/issues/520)) |
| Diagnostic CLI | [`scripts/memory-status.sh`](../scripts/memory-status.sh) | D ([#523](https://github.com/kcenon/claude-config/issues/523)) |
| Notifier | [`scripts/memory-notify.sh`](../scripts/memory-notify.sh) | D ([#524](https://github.com/kcenon/claude-config/issues/524)) |
| Write-guard hook | [`global/hooks/memory-write-guard.sh`](../global/hooks/memory-write-guard.sh) | D ([#521](https://github.com/kcenon/claude-config/issues/521)) |
| Integrity check hook | [`global/hooks/memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh) | D ([#522](https://github.com/kcenon/claude-config/issues/522)) |
| Access logger hook | [`global/hooks/memory-access-logger.sh`](../global/hooks/memory-access-logger.sh) | F ([#531](https://github.com/kcenon/claude-config/issues/531)) |
| Quarantine restore | [`scripts/memory/quarantine-restore.sh`](../scripts/memory/quarantine-restore.sh) | B ([#514](https://github.com/kcenon/claude-config/issues/514)) |
| Backfill helper | [`scripts/memory/backfill-frontmatter.sh`](../scripts/memory/backfill-frontmatter.sh) | B ([#512](https://github.com/kcenon/claude-config/issues/512)) |
| SSH signing setup | [`scripts/memory/setup-ssh-signing.sh`](../scripts/memory/setup-ssh-signing.sh) | C ([#518](https://github.com/kcenon/claude-config/issues/518)) |
| Validators | (in `claude-memory` repo) `scripts/{validate,secret-check,injection-check}.sh` | A ([#507–#509](https://github.com/kcenon/claude-config/issues/507)) |
| Audit | (in `claude-memory` repo) `scripts/audit.sh` | F ([#528](https://github.com/kcenon/claude-config/issues/528)) |
| Semantic review | [`scripts/semantic-review.sh`](../scripts/semantic-review.sh) | F ([#530](https://github.com/kcenon/claude-config/issues/530)) |

---

## 3. Installation

The scheduler is installed by `scripts/install.sh` whenever
`CLAUDE_MEMORY_REPO_URL` is set in the install environment. Without that
env var the function exits silently — users without the memory feature are
unaffected.

```bash
CLAUDE_MEMORY_REPO_URL=git@github.com:<owner>/claude-memory.git \
    ./scripts/install.sh
```

The function also clones `$CLAUDE_MEMORY_REPO_URL` into
`~/.claude/memory-shared` on first install, then runs the memory repo's
`scripts/install-hooks.sh` if present.

### Manual install (after global config is already in place)

If you skipped memory sync at first install and want to enable it later, set
the env var and re-run:

```bash
CLAUDE_MEMORY_REPO_URL=git@github.com:<owner>/claude-memory.git \
    ./scripts/install.sh
# choose option 1 (global only)
```

The install is idempotent: re-running re-stages the plist / unit files and
re-activates the scheduler cleanly.

### Verification

#### macOS

```bash
launchctl list | grep claude-memory-sync
# 0  0  com.kcenon.claude-memory-sync

tail -n 20 /tmp/claude-memory-sync.out
# [2026-05-08T10:00:11Z] sync start (host=...)
# [2026-05-08T10:00:14Z] sync complete in 3s
```

#### Linux

```bash
systemctl --user list-timers | grep memory-sync
# NEXT                        LEFT      LAST                        PASSED  UNIT
# 2026-05-08 11:00:00 KST     43min     2026-05-08 10:00:00 KST     17min   memory-sync.timer

tail -n 20 /tmp/claude-memory-sync.out
```

`systemctl --user status memory-sync.timer` shows the timer state;
`journalctl --user -u memory-sync.service` shows execution history.

### Behavior notes

- **macOS sleep**: `StartInterval=3600` is wall-clock based.
  `RunAtLoad=true` ensures an immediate run after wake / login so missed
  intervals are recovered on the next opportunity.
- **Linux sleep**: `OnCalendar=hourly` aligns to the top of the hour;
  `Persistent=true` runs missed events after wake / reboot.
- **Concurrent runs**: `--lock-timeout 30` causes the second invocation to
  wait up to 30s for the first to release its `flock`; if the first run
  exceeds 30s, the second exits with a non-zero "lock not acquired" code
  and the next interval retries.
- **Output rotation**: `/tmp/claude-memory-sync.{out,err}` are rotated by
  the existing `cleanup.sh` weekly job (claude-config convention).
- **No network at scheduled time**: `memory-sync.sh` exits 6; the next
  interval retries naturally.

---

## 4. Single-Machine Migration

Converting an existing single-machine Claude Code installation from
per-machine local memory to the shared store is a multi-phase procedure.
Rather than duplicate it here, follow the canonical runbook:

> **See: [`MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) — Single-Machine
> Migration Runbook ([#525](https://github.com/kcenon/claude-config/issues/525))**

The migration runbook covers nine phases: backup, frontmatter backfill,
trust-level baseline review, clone + hook install, project-memory symlink,
write-guard verification, first manual sync, post-migration validation, and
post-flight session health check. Each phase has copy-paste commands and a
verification command that proves success.

After migration, the seven-day stabilization observation lives in
[`MEMORY_STABILIZATION_CHECKLIST.md`](./MEMORY_STABILIZATION_CHECKLIST.md)
([#526](https://github.com/kcenon/claude-config/issues/526)).

---

## 5. Adding a New Machine

Onboarding a second (or Nth) machine after the primary is stable follows a
shorter procedure than the initial migration: the canonical store already
exists; the new machine just clones it.

The high-level sequence is:

1. **Pre-flight**: confirm `git`, `gh`, and SSH access to
   `kcenon/claude-memory` work on the new machine.
2. **SSH signing**: run `scripts/memory/setup-ssh-signing.sh` to generate a
   per-machine signing key and register it with GitHub. See
   [Section 13](#13-ssh-commit-signing) for details.
3. **Install**: run `scripts/install.sh` with `CLAUDE_MEMORY_REPO_URL`
   set. This clones the shared store and stages the scheduler.
4. **First sync**: invoke `memory-sync.sh` manually to confirm pull-rebase
   succeeds and the local clone matches the remote.
5. **Verify hooks**: confirm `memory-write-guard.sh` is registered in
   `settings.json` (the install script handles this) and that
   `memory-integrity-check.sh` runs at SessionStart with no warnings.
6. **Stabilization window**: run the
   [`MEMORY_STABILIZATION_CHECKLIST.md`](./MEMORY_STABILIZATION_CHECKLIST.md)
   procedure for seven consecutive days before relying on the new machine
   for primary work.

The detailed runbook for second-machine onboarding lives in
[#532](https://github.com/kcenon/claude-config/issues/532) (in progress at
the time of v1.0.0 publication of this guide).

---

## 6. Daily Operations

### Manual sync

The scheduler runs hourly, but manual sync is always available:

```bash
~/.claude/scripts/memory-sync.sh
```

Common flags:

```bash
~/.claude/scripts/memory-sync.sh --lock-timeout 30   # wait up to 30s for lock
~/.claude/scripts/memory-sync.sh --dry-run           # show what would happen
```

Exit codes (per [#520](https://github.com/kcenon/claude-config/issues/520)
acceptance criteria):

| Code | Meaning |
|------|---------|
| 0    | success |
| 1    | pre-push validation failed (local commits rejected) |
| 2    | post-pull validation failed (incoming commits quarantined) |
| 3    | merge conflict (rebase aborted; manual resolution required) |
| 4    | push failed (still after one retry) |
| 5    | lock contention (another sync is running) |
| 6    | git operation failed (typically network) |
| 64   | usage error |

### Reading `memory-status.sh` output

The diagnostic CLI prints a one-screen summary by default and accepts
`--detail` for per-machine activity, audit history, tier-by-type matrix,
and stale entries:

```bash
~/.claude/scripts/memory-status.sh           # brief
~/.claude/scripts/memory-status.sh --detail  # detailed
~/.claude/scripts/memory-status.sh --json    # machine-readable
```

Exit codes:

| Code | Meaning |
|------|---------|
| 0    | healthy |
| 1    | warnings (stale memories, unread alerts, pending push/pull) |
| 2    | errors (clone missing, repo invalid) |
| 64   | usage error |

The CLI is **read-only**: never mutates the clone, never triggers sync,
never writes the alerts log or read-mark.

### Acting on `memory-integrity-check` warnings at SessionStart

The SessionStart hook
([`memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh),
[#522](https://github.com/kcenon/claude-config/issues/522)) is silent when
the system is healthy. Output appears under the `[memory]` prefix when:

- Last sync exceeded 24 hours (drift warning, see
  [`THREAT_MODEL.md`](./THREAT_MODEL.md#5-threat-r1--sync-silent-failure)).
- Unread alerts exist in `~/.claude/logs/memory-alerts.log`.
- A memory file is older than 90 days without re-verification (stale).
- Quarantined files exist.

Recommended response:

```bash
# investigate the warning surface
~/.claude/scripts/memory-status.sh --detail

# read alerts the hook flagged
~/.claude/scripts/memory-notify.sh --list --unread

# trigger a manual sync if last-sync is stale
~/.claude/scripts/memory-sync.sh

# launch /memory-review for stale or quarantined items
# (within Claude Code session)
```

The hook never blocks the session (`exit 0` on all paths) and is
constrained to a 500ms hard cap to keep SessionStart responsive.

---

## 7. Validators

Three validators implement the structural, secret-detection, and
injection-detection layers of the
[5-layer defense](./THREAT_MODEL.md#4-defense-layers-overview). They live in
the `claude-memory` repository and are invoked by the write-guard,
pre-commit, sync, and audit pipelines.

| Validator | Purpose | Blocking exit codes |
|-----------|---------|---------------------|
| `validate.sh` | Structural and format validity (frontmatter schema, body rules, filename pattern) | 1 (FAIL-STRUCT), 2 (FAIL-FORMAT) |
| `secret-check.sh` | PII and credential pattern scan | 1 (SECRET-DETECTED) |
| `injection-check.sh` | Suspicious-pattern flagger | None — warn-only (exit 3 = allow with feedback) |

The authoritative contract for all three — including frontmatter schema,
field semantics, exit-code behavior, and the owner-identity allowlist —
is [`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md).

The warn-only stance for `injection-check.sh` is deliberate: heuristic
pattern matching against natural language has an inherent false-positive
rate, and blocking on it would make legitimate documentation about
prompt-injection patterns impossible to write. Genuine injection content
is caught by the monthly semantic review and surfaced to `/memory-review`.

---

## 8. Trust Tiers

Three tiers gate auto-application of memories to sessions:

| Tier | Auto-applies | Marker shown | Created when |
|------|--------------|--------------|--------------|
| `verified` | Yes | None | User explicitly approves; passes validation |
| `inferred` | Yes, with marker | `[inferred]` prefix | Claude infers a memory-worthy rule from a session |
| `quarantined` | No | N/A — never applied | Validation fails post-pull, or user moves manually |

The lifecycle, state transitions, frontmatter representation, and storage
layout are specified in [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md).
The trust-tier dimension is **orthogonal** to validation: a memory may pass
all validators and still be `inferred` (untrusted for auto-application),
and a `verified` memory may later fail revalidation (in which case
validation is authoritative and the tier is demoted).

Operator actions are documented in
[`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 6:

- **promote** `inferred` → `verified` after manual review
- **demote** `verified` → `inferred` if confidence drops
- **quarantine** any tier → `quarantined` for forensic retention
- **restore** `quarantined` → `verified` via
  [`scripts/memory/quarantine-restore.sh`](../scripts/memory/quarantine-restore.sh)
  (file must pass all validators before restoration; `quarantined` always
  lands at `verified` per the spec — there is no partial restore)

---

## 9. Audit

### Weekly audit ([#528](https://github.com/kcenon/claude-config/issues/528))

`scripts/audit.sh` (in `claude-memory`) is a weekly job that re-runs the
three heuristic validators across the full memory tree, surfaces stale
memories (`last-verified > 90d`), flags duplicate-suspect description
pairs, checks referenced GitHub issues/PRs for "broken-by-closure", and
lists memories not matched by any session-start memory load over the last
4 weeks. Output is committed to `audit/YYYY-MM-DD.md`.

```bash
audit.sh                                # generate today's report
audit.sh --dry-run                      # print to stdout, no commit / push
audit.sh --since N                      # access-log window in weeks
audit.sh --stale-days N                 # tune stale threshold (default 90)
audit.sh --similarity-threshold N       # tune duplicate-suspect threshold
audit.sh --output PATH                  # write to alternate path
audit.sh --no-push                      # commit but skip the push step
audit.sh --no-notify                    # skip memory-notify.sh
```

#### Exit codes

- `0` — success (report generated; non-zero findings is still success)
- `1` — fatal error (unreadable tree, write failure, etc.)
- `2` — recent report exists (< 6 days old); skipped
- `64` — usage error

#### Idempotency

A run on the same day overwrites the day's report. A run within 6 days of
the previous report exits 2 (skipped) so flapping schedulers do not
produce duplicates. Pass `--dry-run` or `--output` to bypass the skip rule.

#### Network and dependency tolerance

- `gh` unavailable or unauthenticated → broken-references section is marked
  `(skipped)`; other checks proceed.
- Access log ([#531](https://github.com/kcenon/claude-config/issues/531))
  absent → unused section is marked `(skipped)`.
- `memory-sync.sh` not on PATH → falls back to plain `git push`.

#### Schedule

The intended cadence is Mondays at 09:00 local. Unit files for launchd and
systemd are tracked under `claude-config/scripts/launchd/` and
`claude-config/scripts/systemd/` parallel to the hourly sync ([#527](https://github.com/kcenon/claude-config/issues/527));
they are added in a follow-up issue once the script stabilises in manual
use.

### Monthly semantic review ([#530](https://github.com/kcenon/claude-config/issues/530))

[`scripts/semantic-review.sh`](../scripts/semantic-review.sh) is an
**optional**, monthly job that asks the `claude` CLI to scan all active
memories for the subtle category that heuristic checks miss:
self-reinforcing instructions, compositional injection, contradictions,
and ambiguous wording. It complements the heuristic `injection-check.sh`
([#509](https://github.com/kcenon/claude-config/issues/509)) and feeds
findings to `/memory-review`
([#529](https://github.com/kcenon/claude-config/issues/529)) for human
review.

The spawned `claude` invocation runs with `--allowed-tools Read` and
`--permission-mode plan`, so it cannot Edit, Write, or run Bash even if
the analyzed memories try to inject the reviewer.

Output lands at `~/.claude/memory-shared/audit/semantic-YYYY-MM.md` and is
committed via `memory-sync.sh` as part of the same delivery loop the
weekly audit uses ([#528](https://github.com/kcenon/claude-config/issues/528)).

#### Schedule

| Platform | Unit                                                                    | Cadence                       |
|----------|-------------------------------------------------------------------------|-------------------------------|
| macOS    | `~/Library/LaunchAgents/com.kcenon.claude-semantic-review.plist`        | First Monday of each month    |
| Linux    | `~/.config/systemd/user/semantic-review.{service,timer}`                | First Monday of each month    |

The schedulers are **opt-in** — they are not staged automatically by
`install.sh`. Operators who want the monthly job copy the unit files into
the locations above and activate them by hand:

```bash
# macOS
cp scripts/launchd/com.kcenon.claude-semantic-review.plist \
   ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.kcenon.claude-semantic-review.plist

# Linux
cp scripts/systemd/semantic-review.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now semantic-review.timer
```

Manual runs are supported any time:

```bash
~/.claude/scripts/semantic-review.sh           # generate
~/.claude/scripts/semantic-review.sh --dry-run # preview the prompt
```

#### Cost and opt-in note

Each run sends every active memory body to the Claude API via the
`claude` CLI. The script prints the prompt size before invocation so
operators can budget. A typical 17-memory tree fits comfortably under
50 KB; the script warns when the prompt exceeds 100 KB and recommends
batching.

Idempotency: the script exits 2 if a report for the current `YYYY-MM`
already exists and is younger than 25 days, so a misfired scheduler never
double-bills.

### `/memory-review` interactive review

The `/memory-review` skill
([#529](https://github.com/kcenon/claude-config/issues/529)) is the
operator-facing entry point that paginates audit findings, semantic-review
findings, and quarantined items. The hourly sync engine and the weekly
audit ([#528](https://github.com/kcenon/claude-config/issues/528)) surface
drift, but neither mutates memory state on its own. Action happens through
this skill (`global/skills/_internal/memory-review/SKILL.md`).

Within a Claude Code session:

```
/memory-review                                    # Walk all categories
/memory-review --category stale --limit 10        # Stale entries only
```

For each finding the skill prompts:

| Choice | Effect |
|--------|--------|
| `y` | Update `last-verified` to today and re-validate |
| `n` | Move the file to `quarantine/` via `quarantine-move.sh` |
| `e` | Open `$EDITOR`; on save, re-validate and update `last-verified` |
| `s` | Leave unchanged |
| `q` | Stop the loop and emit the summary |

After the loop the skill offers to run `memory-sync.sh` so the local
mutations propagate to the other machines.

The skill is `disable-model-invocation: true` — Claude does not trigger it
unprompted. Run it after the weekly audit lands a fresh report or whenever
`memory-notify.sh` flags drift.

---

## 10. Privacy: Memory-Access Logging

The [`memory-access-logger.sh`](../global/hooks/memory-access-logger.sh)
PostToolUse Read hook records each memory file that Claude Code reads
during a session. The log lives at `~/.claude/logs/memory-access.log` and
feeds the unused-memory check in the weekly `audit.sh`
([#528](https://github.com/kcenon/claude-config/issues/528)).

Each entry records **path only**, never the file contents:

```
2026-05-08T10:23:11Z abc123 read memories/feedback_ci_merge_policy.md
```

Fields are `<ISO8601 UTC timestamp> <session_id> read <relative-path>`.
Paths are stored relative to `~/.claude/memory-shared/` and only paths
under `memory-shared/memories/` are logged (the top-level `MEMORY.md`
index is excluded). The log is local to each machine and never
transmitted; the memory sync engine does not include `~/.claude/logs/`.

The log rotates lazily on each hook invocation: when its size exceeds
1 MiB OR its calendar month differs from the current one, the active file
is moved to `memory-access.log.YYYY-MM` and a fresh log is started. The
hook is registered with `async: true` in `global/settings.json` so it
never blocks the user's Read flow; any internal failure (jq missing, log
unwritable, etc.) is silently swallowed and exit 0 is returned.

### Privacy summary

- Access log records file paths only, never content.
- Repo is private; data does not leave `kcenon`'s GitHub.
- Local logs do not sync between machines.
- Frontmatter records source machine and author for provenance, but never
  free-text PII beyond the email patterns recognized in the
  [owner-identity allowlist](./MEMORY_VALIDATION_SPEC.md#6-owner-identity-allowlist).

---

## 11. Conflict Resolution

When `memory-sync.sh` aborts on conflict (exit 3, "merge conflict — rebase
aborted"), follow this procedure:

1. **Inspect the failing files**:

   ```bash
   tail -n 50 ~/.claude/logs/memory-sync.log
   cd ~/.claude/memory-shared
   git status
   ```

   The sync engine aborts the rebase before mutating, so the working tree
   is the pre-rebase state. The log identifies which incoming files
   conflict with which local commits.

2. **Decide which side wins** using the rules table below.

3. **Manually resolve**:

   ```bash
   cd ~/.claude/memory-shared
   git rebase origin/main                    # restart the rebase
   # ... resolve each conflict marker by file ...
   git add memories/<resolved-file>.md
   git rebase --continue
   ```

4. **Re-run sync**:

   ```bash
   ~/.claude/scripts/memory-sync.sh
   ```

### Resolution rules

| Conflict shape | Action | Rationale |
|----------------|--------|-----------|
| Frontmatter only (e.g., `last-verified` differs) | Take newer date | Newer verification is more authoritative |
| Body content differs, both sides intentional | Manual merge | Substantive disagreement; resolve by reading both sides |
| `MEMORY.md` index | Re-generate via `regen-index.sh` | Generated artifact; merging is meaningless |
| `audit/YYYY-MM-DD.md` (same day) | Take newer commit | Audit is idempotent; later run is current |
| Quarantine entry | Take both — files are uniquely named | No collision in practice |
| File deleted on one side, modified on other | Manual decision | Was the deletion intentional? Investigate first |

### When to abort instead of resolving

Abort and consult before resolving when:

- More than 3 files conflict (high risk of inconsistent decisions).
- The conflict involves frontmatter `trust-level` or `quarantined-at` —
  trust-tier transitions deserve manual review per
  [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) Section 3.
- Both sides made substantial overlapping body changes — likely indicates
  divergent feature work that needs discussion, not merge.

```bash
cd ~/.claude/memory-shared
git rebase --abort
git diff --name-only --diff-filter=U   # report conflict surface
```

---

## 12. Rollback Procedures

### Single-machine rollback

To return one machine to the pre-sync state (per-machine local memory
only) without disrupting other machines, follow the rollback procedure in
[`MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md#13-rollback-procedure):

1. Stop the scheduler:

   ```bash
   ./scripts/install.sh --uninstall-memory-sync
   ```

2. Remove the symlink and restore the original local memory directory
   (the migration runbook backs it up at Phase 1).

3. Optionally remove the shared clone:

   ```bash
   rm -rf ~/.claude/memory-shared
   ```

The shared store on GitHub and on other machines is unaffected. The
machine that rolled back simply stops participating in sync.

### Whole-system rollback

To return the entire fleet to per-machine memory:

1. Run the single-machine rollback on every participating machine.
2. Optionally archive the `claude-memory` repository on GitHub (do **not**
   delete — it is the only canonical history).
3. Remove `CLAUDE_MEMORY_REPO_URL` from any install scripts and CI.

The `claude-memory` repository remains as a forensic record of the
attempt.

### Disaster recovery (repository loss)

See [`THREAT_MODEL.md` R7](./THREAT_MODEL.md#11-threat-r7--github-outage--repo-loss).
Local clones on every machine are full mirrors; restoring a lost
repository is `git push --force-with-lease` from any clone to a
re-created remote.

---

## 13. SSH Commit Signing

Every machine that pushes commits to `kcenon/claude-memory` **must** sign
those commits with an SSH key. Branch protection on `main` enforces this;
unsigned commits are rejected at the server.

The per-machine setup, rotation, and compromise procedures are documented
in [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md). At a glance:

### Initial setup

```bash
cd /path/to/kcenon/claude-config
./scripts/memory/setup-ssh-signing.sh
```

The script verifies `git >= 2.34`, locates an SSH public key (preferring
`id_ed25519`), backs up `~/.gitconfig`, and configures `gpg.format=ssh`,
`user.signingkey`, `commit.gpgsign=true`, `tag.gpgsign=true`. It also
prints the public key fingerprint for registration in GitHub →
Settings → SSH and GPG keys → "Authentication key" + "Signing key".

### Rotation procedure

When a machine's signing key reaches end of useful life or is replaced:

1. Generate a new key on the machine (`ssh-keygen -t ed25519`).
2. Register the new public key in GitHub as both authentication and
   signing.
3. Update `user.signingkey` to point at the new key:
   `git config --global user.signingkey ~/.ssh/id_ed25519.pub`.
4. Verify with `git commit --allow-empty -m "test: signing rotation"` and
   `git log --show-signature -1`.
5. Optionally remove the old public key from GitHub after a grace window.

### Compromise procedure

When a signing key may be compromised:

1. **Immediate**: revoke the public key from GitHub
   (Settings → SSH and GPG keys).
2. Generate a new key per the rotation procedure.
3. Run `git log --show-signature` against `claude-memory` to identify any
   commits signed by the compromised key after compromise time.
4. Move suspect files to quarantine via
   [`scripts/memory/quarantine-move.sh`](../scripts/memory/quarantine-move.sh)
   for forensic review.
5. If the compromised machine is recoverable, audit local hook
   configuration and `settings.json` for tampering before re-bootstrapping
   sync.

The branch protection requirement (signed commits on `main`) means a
compromised key without local commit access cannot land malicious commits;
the attacker must also have shell access on the compromised machine.

---

## 14. Uninstall

```bash
./scripts/install.sh --uninstall-memory-sync
```

This:

- macOS: `launchctl bootout` the agent (with `launchctl unload` fallback)
  and removes the plist.
- Linux: `systemctl --user disable --now memory-sync.timer`, removes the
  service + timer files, and `daemon-reload`s.

The memory repo clone at `~/.claude/memory-shared` is **not** removed;
remove it manually if desired:

```bash
rm -rf ~/.claude/memory-shared
```

To uninstall on a single machine while keeping sync running on others,
this command is sufficient — the shared remote and other machines are
untouched.

---

## 15. Test Mode

Both `install_memory_sync` and `uninstall_memory_sync` honor environment
overrides that redirect destination paths and skip the `launchctl` /
`systemctl` calls:

```bash
LAUNCHD_TARGET_DIR=/tmp/test-launchd \
    CLAUDE_MEMORY_REPO_URL=... \
    ./scripts/install.sh
# Stages plist at /tmp/test-launchd/com.kcenon.claude-memory-sync.plist
# Does NOT call launchctl bootstrap.

SYSTEMD_USER_DIR=/tmp/test-systemd \
    CLAUDE_MEMORY_REPO_URL=... \
    ./scripts/install.sh
# Stages units at /tmp/test-systemd/memory-sync.{service,timer}
# Does NOT call systemctl enable.
```

These overrides exist so CI runners and dev sandboxes can exercise the
install path without modifying real launchd / systemd state.

---

## 16. Troubleshooting

### "memory-sync.sh exits 5 (lock contention)"

A previous sync is still running and holds the lock for longer than the
`--lock-timeout` window. Check:

```bash
ps -ef | grep memory-sync.sh | grep -v grep
ls -la /tmp/claude-memory-sync.lock 2>&1   # Linux
ls -la "$HOME/.claude/.memory-sync.lock" 2>&1
```

If a stale lock file remains from a killed prior invocation:

```bash
rm -f "$HOME/.claude/.memory-sync.lock"
~/.claude/scripts/memory-sync.sh
```

If the previous invocation is genuinely still running (e.g., very large
pull during the onboarding window), wait for it to complete; the next
hourly cycle will retry.

### "Last sync 28h ago — sync may be stuck"

The SessionStart hook reports last-sync age. A reading above 24 hours
indicates the scheduler dropped one or more cycles. Diagnose:

```bash
~/.claude/scripts/memory-status.sh --detail
tail -n 50 /tmp/claude-memory-sync.out
tail -n 50 /tmp/claude-memory-sync.err

# macOS — is the agent loaded?
launchctl list | grep claude-memory-sync

# Linux — is the timer enabled and active?
systemctl --user status memory-sync.timer
journalctl --user -u memory-sync.service --since "1 day ago"
```

Common causes: laptop slept through every scheduled tick (the scheduler
will catch up at next wake via `RunAtLoad` / `Persistent`), the agent was
unloaded by another process, network was unavailable for the entire 24h
window. A manual `~/.claude/scripts/memory-sync.sh` run forces an
immediate sync and resets the warning.

### "Auto-quarantine on post-pull validation"

A file from another machine failed the layer-4 (post-pull) validators and
was moved to `~/.claude/memory-shared/quarantine/`. Sync continues for
the rest of the tree; only the offending file is isolated. To inspect
and act:

```bash
ls -la ~/.claude/memory-shared/quarantine/
cat ~/.claude/memory-shared/quarantine/<filename>.md

# determine which validator flagged it
~/.claude/scripts/memory-notify.sh --list --unread
```

If the quarantine was a false positive:

```bash
~/.claude/scripts/memory/quarantine-restore.sh \
    quarantine/<filename>.md
# the script re-runs all validators; restoration only proceeds on pass
```

If the quarantine reveals genuine contamination, leave the file in
quarantine for the forensic record and follow up with the machine that
authored the commit.

### "Merge conflict — manual resolution required" (exit 3)

See [Section 11 — Conflict Resolution](#11-conflict-resolution).

### "memory-write-guard hook blocked write"

The PreToolUse hook
([`memory-write-guard.sh`](../global/hooks/memory-write-guard.sh)) refused
a Claude Code Edit/Write call against a memory file. The hook prints the
specific validator and finding in the deny response. Common patterns:

- **Secret-detected**: the proposed content matches a token/PII pattern.
  Inspect the diff Claude was attempting; if legitimate (e.g., a
  documentation example of a leaked-token shape), rephrase to use a
  fenced code block with a placeholder.
- **Validate.sh exit 1/2**: structural or format error in the proposed
  frontmatter. The most common cause is a missing required field after
  schema migration; see
  [`MEMORY_VALIDATION_SPEC.md` Section 3](./MEMORY_VALIDATION_SPEC.md#3-frontmatter-schema).

The hook never blocks non-memory paths. If a write to an unrelated path
is being denied, that is a hook bug — file an issue.

### "claude-memory push refused: signed commits required"

Branch protection requires signed commits. The push from this machine was
unsigned. Verify configuration:

```bash
git config --get gpg.format          # expect: ssh
git config --get user.signingkey     # expect: path to .pub
git config --get commit.gpgsign      # expect: true
git log --show-signature -1          # expect: "Good "ssh-..." signature"
```

If signing is unconfigured, run
`./scripts/memory/setup-ssh-signing.sh`. If signed but the public key is
not registered in GitHub, register it under
Settings → SSH and GPG keys with `Type: Signing key`.

### Common pitfalls cross-reference

[`MEMORY_MIGRATION.md` Section 15](./MEMORY_MIGRATION.md#15-common-pitfalls)
catalogs setup-time pitfalls (symlink direction, missing
`CLAUDE_MEMORY_REPO_URL`, hooks not registered). [`MEMORY_TRUST_MODEL.md`
Section 9](./MEMORY_TRUST_MODEL.md#9-migration-of-existing-memories) covers
trust-tier transition gotchas.

---

## 17. Glossary

| Term | Definition |
|------|------------|
| **verified** | A memory the operator has explicitly approved. Auto-applies to all sessions. See [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md). |
| **inferred** | A memory Claude wrote based on session inference. Auto-applies with an `[inferred]` marker, awaiting operator promotion to `verified`. |
| **quarantined** | A memory isolated from auto-application. Reached via post-pull validation failure or explicit `quarantine-move.sh`. Never auto-applies. |
| **backfill** | Adding required frontmatter fields (`source-machine`, `created-at`, `trust-level`) to existing memory files via [`scripts/memory/backfill-frontmatter.sh`](../scripts/memory/backfill-frontmatter.sh). Idempotent. |
| **write-guard** | The PreToolUse hook ([`memory-write-guard.sh`](../global/hooks/memory-write-guard.sh)) that runs validators against proposed Claude Code Edit/Write calls before disk write. Layer 1 of the 5-layer defense. |
| **index drift** | A divergence between the generated `MEMORY.md` index and the underlying `memories/*.md` files. Surfaces as a warning during sync; resolved by `regen-index.sh`. |
| **5-layer defense** | The defense-in-depth design: write-guard → pre-commit → sync-pre-push → sync-post-pull → weekly audit. See [`THREAT_MODEL.md`](./THREAT_MODEL.md#4-defense-layers-overview). |
| **shared store** | The local clone at `~/.claude/memory-shared/` mirroring `kcenon/claude-memory`. |
| **lock-timeout** | Maximum time in seconds the sync engine waits for an existing `flock` to release before exiting with code 5. Default 30s for scheduled invocations. |
| **last-verified** | A frontmatter field recording when the operator last confirmed a memory's content is current. Drives the 90-day stale check in `audit.sh`. |
| **broken-by-closure** | An audit finding: a memory references a GitHub issue or PR that has since been closed; the memory may be obsolete. |

---

## 18. Versioning

This document follows semantic versioning aligned with the system as a
whole.

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-05-01 | Initial publication. Consolidates fragments from [#525](https://github.com/kcenon/claude-config/issues/525), [#527](https://github.com/kcenon/claude-config/issues/527), [#528](https://github.com/kcenon/claude-config/issues/528), [#530](https://github.com/kcenon/claude-config/issues/530), [#531](https://github.com/kcenon/claude-config/issues/531). Adds conflict resolution, rollback, troubleshooting, glossary. Pairs with [`THREAT_MODEL.md`](./THREAT_MODEL.md) v1.0.0. |

Subsequent versions:

- **PATCH** — typos, link fixes, command output examples updated.
- **MINOR** — new section, new troubleshooting entry, new operational
  procedure that does not change existing behavior.
- **MAJOR** — breaking change in scheduler, validator contract, or trust
  model that requires operator action.

---

## 19. Related

- [`THREAT_MODEL.md`](./THREAT_MODEL.md) — security analysis (companion)
- [`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) — validator contract
- [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) — trust tier semantics
- [`MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) — single-machine migration
- [`MEMORY_STABILIZATION_CHECKLIST.md`](./MEMORY_STABILIZATION_CHECKLIST.md) — single-machine stabilization
- [`MEMORY_TRUST_BASELINE.md`](./MEMORY_TRUST_BASELINE.md) — initial trust-level decisions
- [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md) — per-machine signing
- Epic [#505](https://github.com/kcenon/claude-config/issues/505) — cross-machine memory sync

### Issues by phase

- Phase A (validation): [#506](https://github.com/kcenon/claude-config/issues/506)–[#510](https://github.com/kcenon/claude-config/issues/510)
- Phase B (trust): [#511](https://github.com/kcenon/claude-config/issues/511)–[#514](https://github.com/kcenon/claude-config/issues/514)
- Phase C (bootstrap): [#515](https://github.com/kcenon/claude-config/issues/515)–[#519](https://github.com/kcenon/claude-config/issues/519)
- Phase D (engine): [#520](https://github.com/kcenon/claude-config/issues/520)–[#524](https://github.com/kcenon/claude-config/issues/524)
- Phase E (single-machine): [#525](https://github.com/kcenon/claude-config/issues/525)–[#527](https://github.com/kcenon/claude-config/issues/527)
- Phase F (audit): [#528](https://github.com/kcenon/claude-config/issues/528)–[#531](https://github.com/kcenon/claude-config/issues/531)
- Phase G (multi-machine): [#532](https://github.com/kcenon/claude-config/issues/532)–[#534](https://github.com/kcenon/claude-config/issues/534)
