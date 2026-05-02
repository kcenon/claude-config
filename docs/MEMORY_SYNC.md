# Memory Sync

Cross-machine memory synchronization for `~/.claude/memory-shared`. The sync
engine (`scripts/memory-sync.sh`, #520) performs a bidirectional pull-rebase /
push cycle. This document covers the platform schedulers that invoke it
hourly without user intervention (#527).

## Architecture

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
```

| Platform | Scheduler             | Unit / Plist Path                                            |
|----------|-----------------------|--------------------------------------------------------------|
| macOS    | launchd LaunchAgent   | `~/Library/LaunchAgents/com.kcenon.claude-memory-sync.plist` |
| Linux    | systemd user timer    | `~/.config/systemd/user/memory-sync.{service,timer}`         |

Both schedulers run as the current user (not root) and invoke
`$HOME/.claude/scripts/memory-sync.sh --lock-timeout 30` via `bash -lc` so the
user's interactive PATH (gh, git) is loaded. Lock-timeout 30 prevents pile-up
when a previous run is still active.

## Install

The scheduler is installed by `scripts/install.sh` whenever
`CLAUDE_MEMORY_REPO_URL` is set in the install environment. Without that env
var the function exits silently — users without the memory feature are
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

## Uninstall

```bash
./scripts/install.sh --uninstall-memory-sync
```

This:

- macOS: `launchctl bootout` the agent (with `launchctl unload` fallback) and
  removes the plist.
- Linux: `systemctl --user disable --now memory-sync.timer`, removes the
  service + timer files, and `daemon-reload`s.

The memory repo clone at `~/.claude/memory-shared` is **not** removed; remove
it manually if desired:

```bash
rm -rf ~/.claude/memory-shared
```

## Verification

### macOS

```bash
launchctl list | grep claude-memory-sync
# 0  0  com.kcenon.claude-memory-sync

tail -n 20 /tmp/claude-memory-sync.out
# [2026-05-08T10:00:11Z] sync start (host=...)
# [2026-05-08T10:00:14Z] sync complete in 3s
```

### Linux

```bash
systemctl --user list-timers | grep memory-sync
# NEXT                        LEFT      LAST                        PASSED  UNIT
# 2026-05-08 11:00:00 KST     43min     2026-05-08 10:00:00 KST     17min   memory-sync.timer

tail -n 20 /tmp/claude-memory-sync.out
```

`systemctl --user status memory-sync.timer` shows the timer state; `journalctl
--user -u memory-sync.service` shows execution history.

## Test mode (no destructive scheduler changes)

Both `install_memory_sync` and `uninstall_memory_sync` honor environment
overrides that redirect destination paths and skip the launchctl / systemctl
calls:

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

## Behavior notes

- **macOS sleep**: `StartInterval=3600` is wall-clock based. `RunAtLoad=true`
  ensures an immediate run after wake / login so missed intervals are
  recovered on the next opportunity.
- **Linux sleep**: `OnCalendar=hourly` aligns to the top of the hour;
  `Persistent=true` runs missed events after wake / reboot.
- **Concurrent runs**: `--lock-timeout 30` causes the second invocation to
  wait up to 30s for the first to release its `flock`; if the first run
  exceeds 30s, the second exits with a non-zero "lock not acquired" code and
  the next interval retries.
- **Output rotation**: `/tmp/claude-memory-sync.{out,err}` are rotated by the
  existing `cleanup.sh` weekly job (claude-config convention).
- **No network at scheduled time**: `memory-sync.sh` exits 6; the next
  interval retries naturally.

## Weekly audit (#528)

`scripts/audit.sh` (in claude-memory) is a weekly job that re-runs the three
heuristic validators across the full memory tree, surfaces stale memories
(`last-verified > 90d`), flags duplicate-suspect description pairs, checks
referenced GitHub issues/PRs for "broken-by-closure", and lists memories not
matched by any session-start memory load over the last 4 weeks. Output is
committed to `audit/YYYY-MM-DD.md`.

```
audit.sh                                # generate today's report
audit.sh --dry-run                      # print to stdout, no commit / push
audit.sh --since N                      # access-log window in weeks
audit.sh --stale-days N                 # tune stale threshold (default 90)
audit.sh --similarity-threshold N       # tune duplicate-suspect threshold
audit.sh --output PATH                  # write to alternate path
audit.sh --no-push                      # commit but skip the push step
audit.sh --no-notify                    # skip memory-notify.sh
```

### Exit codes

- `0` -- success (report generated; non-zero findings is still success)
- `1` -- fatal error (unreadable tree, write failure, etc.)
- `2` -- recent report exists (< 6 days old); skipped
- `64` -- usage error

### Idempotency

A run on the same day overwrites the day's report. A run within 6 days of
the previous report exits 2 (skipped) so flapping schedulers do not produce
duplicates. Pass `--dry-run` or `--output` to bypass the skip rule.

### Network and dependency tolerance

- `gh` unavailable or unauthenticated -> broken-references section is marked
  `(skipped)`; other checks proceed.
- Access log (#531) absent -> unused section is marked `(skipped)`.
- `memory-sync.sh` not on PATH -> falls back to plain `git push`.

### Schedule

The intended cadence is Mondays at 09:00 local. Unit files for launchd and
systemd are tracked under `claude-config/scripts/launchd/` and
`claude-config/scripts/systemd/` parallel to the hourly sync (#527); they
are added in a follow-up issue once the script stabilises in manual use.

## Monthly semantic review (#530)

`scripts/semantic-review.sh` is an **optional**, monthly job that asks the
`claude` CLI to scan all active memories for the subtle category that
heuristic checks miss: self-reinforcing instructions, compositional
injection, contradictions, and ambiguous wording. It complements the
heuristic `injection-check.sh` (#509) and feeds findings to `/memory-review`
(#529) for human review.

The spawned `claude` invocation runs with `--allowed-tools Read` and
`--permission-mode plan`, so it cannot Edit, Write, or run Bash even if the
analyzed memories try to inject the reviewer.

Output lands at `~/.claude/memory-shared/audit/semantic-YYYY-MM.md` and is
committed via `memory-sync.sh` as part of the same delivery loop the weekly
audit uses (#528).

### Schedule

| Platform | Unit                                                                    | Cadence                       |
|----------|-------------------------------------------------------------------------|-------------------------------|
| macOS    | `~/Library/LaunchAgents/com.kcenon.claude-semantic-review.plist`        | First Monday of each month    |
| Linux    | `~/.config/systemd/user/semantic-review.{service,timer}`                | First Monday of each month    |

The schedulers are **opt-in** -- they are not staged automatically by
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

### Cost and opt-in note

Each run sends every active memory body to the Claude API via the `claude`
CLI. The script prints the prompt size before invocation so operators can
budget. A typical 17-memory tree fits comfortably under 50 KB; the script
warns when the prompt exceeds 100 KB and recommends batching.

Idempotency: the script exits 2 if a report for the current `YYYY-MM`
already exists and is younger than 25 days, so a misfired scheduler never
double-bills.

## Privacy: memory-access logging (#531)

The `memory-access-logger.sh` PostToolUse Read hook records each memory file
that Claude Code reads during a session. The log lives at
`~/.claude/logs/memory-access.log` and feeds the unused-memory check in the
weekly `audit.sh` (#528).

Each entry records **path only**, never the file contents:

```
2026-05-08T10:23:11Z abc123 read memories/feedback_ci_merge_policy.md
```

Fields are `<ISO8601 UTC timestamp> <session_id> read <relative-path>`. Paths
are stored relative to `~/.claude/memory-shared/` and only paths under
`memory-shared/memories/` are logged (the top-level `MEMORY.md` index is
excluded). The log is local to each machine and never transmitted; the
memory sync engine does not include `~/.claude/logs/`.

The log rotates lazily on each hook invocation: when its size exceeds 1 MiB
OR its calendar month differs from the current one, the active file is moved
to `memory-access.log.YYYY-MM` and a fresh log is started. The hook is
registered with `async: true` in `global/settings.json` so it never blocks
the user's Read flow; any internal failure (jq missing, log unwritable, etc.)
is silently swallowed and exit 0 is returned.

## Operations

### Reviewing the audit report

The hourly sync engine and the weekly audit (#528) surface drift, but neither
mutates memory state on its own. Action happens through the `/memory-review`
interactive skill (`global/skills/_internal/memory-review/SKILL.md`, #529).

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

## Related

- #505 — Cross-machine memory epic
- #509 — Heuristic injection-check (semantic predecessor)
- #520 — `memory-sync.sh` engine
- #524 — `memory-notify.sh` alerting
- #526 — End-to-end manual validation
- #528 — Weekly `audit.sh` report generator (this section)
- #529 — `/memory-review` interactive triage skill (consumes findings)
- #530 — Monthly AI semantic review (this section)
