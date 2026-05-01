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

## Related

- #505 — Cross-machine memory epic
- #520 — `memory-sync.sh` engine
- #524 — `memory-notify.sh` alerting
- #526 — End-to-end manual validation
- #528 — Weekly audit (uses the same scheduler integration pattern)
