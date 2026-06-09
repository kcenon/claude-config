---
title: "feat(memory): launchd plist and install_memory_sync() integration"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/S
  - phase/E-migration
milestone: memory-sync-v1-single
blocked_by: [E1, E2]
blocks: [F1, F4]
parent_epic: EPIC
---

## What

Provide platform schedulers for hourly invocation of `memory-sync.sh`: macOS launchd plist + Linux systemd timer + service. Integrate installation into `claude-config/scripts/install.sh` via a new `install_memory_sync()` function that gets called when `CLAUDE_MEMORY_REPO_URL` is set.

### Scope (in)

- macOS: `scripts/launchd/com.kcenon.claude-memory-sync.plist` (1-hour interval)
- Linux: `scripts/systemd/memory-sync.service` + `memory-sync.timer` (1-hour OnCalendar)
- `install_memory_sync()` function in `scripts/install.sh`
- Uninstall procedure documented in `docs/MEMORY_SYNC.md`
- Idempotent install (re-run safe)

### Scope (out)

- Windows scheduler (claude-docker context — handled separately if needed)
- Custom intervals (1 hour is fixed for v1)
- launchd-on-network-change triggers (future enhancement)

## Why

The system has been validated end-to-end manually in #E2. To deliver actual ongoing sync, an OS scheduler must invoke `memory-sync.sh` regularly without user intervention. launchd / systemd are stable, OS-native, low-overhead.

Integrating with `install.sh` ensures any machine that picks up claude-config from a fresh install can opt into memory sync via a single env var, not a separate manual procedure.

### What this unblocks

- Hourly unattended sync — the actual deployed state
- #F1 — weekly audit can be scheduled similarly once this works
- #G1 — second-machine onboarding leverages the same install integration

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 3 days of #E2 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**:
  - `kcenon/claude-config/scripts/launchd/com.kcenon.claude-memory-sync.plist`
  - `kcenon/claude-config/scripts/systemd/memory-sync.service`
  - `kcenon/claude-config/scripts/systemd/memory-sync.timer`
  - `kcenon/claude-config/scripts/install.sh` (+= `install_memory_sync()`)

## How

### Approach

Two platform-specific scheduler artifacts. Install function detects platform and dispatches. Uninstall is symmetric (`uninstall_memory_sync()`). Both plist and timer call `memory-sync.sh` directly with `--lock-timeout 30` so concurrent triggers are safely serialized.

### Detailed Design

**macOS launchd plist** (`scripts/launchd/com.kcenon.claude-memory-sync.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>          <string>com.kcenon.claude-memory-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>$HOME/.claude/scripts/memory-sync.sh --lock-timeout 30</string>
  </array>
  <key>StartInterval</key>  <integer>3600</integer>
  <key>RunAtLoad</key>      <true/>
  <key>StandardOutPath</key><string>/tmp/claude-memory-sync.out</string>
  <key>StandardErrorPath</key><string>/tmp/claude-memory-sync.err</string>
</dict>
</plist>
```

**Linux systemd service** (`scripts/systemd/memory-sync.service`):
```ini
[Unit]
Description=Claude memory sync
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -lc '%h/.claude/scripts/memory-sync.sh --lock-timeout 30'
StandardOutput=append:/tmp/claude-memory-sync.out
StandardError=append:/tmp/claude-memory-sync.err
```

**Linux systemd timer** (`scripts/systemd/memory-sync.timer`):
```ini
[Unit]
Description=Hourly Claude memory sync

[Timer]
OnCalendar=hourly
Persistent=true
Unit=memory-sync.service

[Install]
WantedBy=timers.target
```

**`install.sh` integration**:
```bash
install_memory_sync() {
  if [[ -z "${CLAUDE_MEMORY_REPO_URL:-}" ]]; then
    echo "[install] CLAUDE_MEMORY_REPO_URL not set; skipping memory sync setup"
    return 0
  fi

  if [[ ! -d "$HOME/.claude/memory-shared/.git" ]]; then
    echo "[install] cloning memory repo from $CLAUDE_MEMORY_REPO_URL"
    git clone "$CLAUDE_MEMORY_REPO_URL" "$HOME/.claude/memory-shared"
    (cd "$HOME/.claude/memory-shared" && ./scripts/install-hooks.sh)
  fi

  case "$(uname)" in
    Darwin)
      install_launchd_agent
      ;;
    Linux)
      install_systemd_timer
      ;;
    *)
      echo "[install] platform $(uname) not supported for memory sync; skipping scheduler"
      ;;
  esac
}

install_launchd_agent() {
  local plist="$HOME/Library/LaunchAgents/com.kcenon.claude-memory-sync.plist"
  cp scripts/launchd/com.kcenon.claude-memory-sync.plist "$plist"
  launchctl unload "$plist" 2>/dev/null || true   # idempotent
  launchctl load "$plist"
  echo "[install] launchd agent loaded"
}

install_systemd_timer() {
  local user_dir="$HOME/.config/systemd/user"
  mkdir -p "$user_dir"
  cp scripts/systemd/memory-sync.service "$user_dir/"
  cp scripts/systemd/memory-sync.timer "$user_dir/"
  systemctl --user daemon-reload
  systemctl --user enable --now memory-sync.timer
  echo "[install] systemd user timer enabled"
}

uninstall_memory_sync() {
  case "$(uname)" in
    Darwin)
      local plist="$HOME/Library/LaunchAgents/com.kcenon.claude-memory-sync.plist"
      [[ -f "$plist" ]] && launchctl unload "$plist" && rm "$plist"
      ;;
    Linux)
      systemctl --user disable --now memory-sync.timer 2>/dev/null || true
      rm -f "$HOME/.config/systemd/user/memory-sync."{service,timer}
      systemctl --user daemon-reload
      ;;
  esac
  echo "[uninstall] memory sync scheduler removed"
}
```

**Behavior**:
- 1-hour interval; first run at load (`RunAtLoad=true` macOS, `Persistent=true` Linux for missed runs after sleep)
- Output to `/tmp/claude-memory-sync.{out,err}` (rotated by `cleanup.sh` weekly per existing claude-config patterns)
- Lock timeout 30s prevents pile-up if a sync stalls

**Uninstall verification**:
- macOS: `launchctl list | grep claude-memory-sync` → empty
- Linux: `systemctl --user list-timers | grep memory-sync` → empty

**State and side effects**:
- Installs files in `~/Library/LaunchAgents/` (macOS) or `~/.config/systemd/user/` (Linux)
- Modifies launchd / systemd state (loads agent / enables timer)
- Idempotent: re-running unloads → reloads cleanly
- Uninstall reverses cleanly

**External dependencies**: launchctl (macOS) or systemctl (Linux); both ship with the OS.

### Inputs and Outputs

**Input** (install on macOS, with env set):
```
$ CLAUDE_MEMORY_REPO_URL=git@github.com:kcenon/claude-memory.git \
    ./scripts/install.sh --profile global-only
```

**Output**:
```
[install] cloning memory repo from git@github.com:kcenon/claude-memory.git
[install] launchd agent loaded
```

**Input** (verify scheduling):
```
$ launchctl list | grep claude-memory-sync
0  0  com.kcenon.claude-memory-sync
$ tail /tmp/claude-memory-sync.out
[2026-05-08T10:00:11Z] sync start (host=macbook-pro)
[...]
[2026-05-08T10:00:14Z] sync complete in 3s
```

**Input** (Linux, with env set):
```
$ CLAUDE_MEMORY_REPO_URL=git@github.com:kcenon/claude-memory.git \
    ./scripts/install.sh --profile global-only
```

**Output**:
```
[install] cloning memory repo from git@github.com:kcenon/claude-memory.git
[install] systemd user timer enabled
$ systemctl --user list-timers
NEXT                        LEFT      LAST                        PASSED  UNIT
2026-05-08 11:00:00 KST     43min     2026-05-08 10:00:00 KST     17min   memory-sync.timer
```

**Input** (uninstall):
```
$ ./scripts/install.sh --uninstall-memory-sync
[uninstall] memory sync scheduler removed
```

### Edge Cases

- **Env var unset** → install_memory_sync returns silently; skip path
- **Repo already cloned** → skip clone, still install scheduler
- **launchd agent already loaded** → unload + reload (idempotent)
- **systemd timer already enabled** → `enable --now` re-enables cleanly
- **User logs out / reboots** → launchd: agent re-loads at login (LaunchAgent semantics); systemd timer: persists across reboots if enabled
- **`StartInterval` may not survive sleep** → `RunAtLoad=true` ensures immediate run on wake
- **systemd `Persistent=true`** → timer runs missed events after wake/reboot
- **Wrong shell PATH inside launchd** → use `bash -lc` (login shell) so user's gh / git are found
- **/tmp file growth** → cleanup.sh existing in claude-config rotates these
- **No network at scheduled time** → memory-sync.sh exits 6; next interval retries
- **Manual launchctl unload mid-sync** → currently running script completes (lock held), next interval doesn't run (agent unloaded); intentional behavior

### Acceptance Criteria

- [ ] `scripts/launchd/com.kcenon.claude-memory-sync.plist` created with 1-hour interval
- [ ] `scripts/systemd/memory-sync.service` + `.timer` created with 1-hour OnCalendar
- [ ] `install_memory_sync()` function added to `scripts/install.sh`
- [ ] `uninstall_memory_sync()` symmetric counterpart
- [ ] Install detects platform via `uname` and dispatches correctly
- [ ] Install is **idempotent** (re-run is safe)
- [ ] Skip when `CLAUDE_MEMORY_REPO_URL` unset
- [ ] Output paths `/tmp/claude-memory-sync.{out,err}` (rotated by existing cleanup.sh)
- [ ] **Verified on macOS**: agent loads, runs, sync.log shows hourly entries
- [ ] **Verified on Linux**: timer enables, systemctl --user list-timers shows it, sync.log shows hourly entries
- [ ] Uninstall verified: agent unloaded / timer disabled cleanly
- [ ] Documented in `docs/MEMORY_SYNC.md` install section

### Test Plan

- macOS: install via env var; wait < 1 hour; verify sync.log entry from launchd execution
- Linux: install via env var; observe `systemctl --user list-timers`; wait < 1 hour; verify sync.log
- Run install twice → idempotent (no errors, no duplicate registrations)
- Uninstall → scheduler stops, no further sync.log entries
- Manual `memory-sync.sh` invocation while scheduler is also active → flock prevents concurrent run

### Implementation Notes

- launchd `StartInterval=3600` triggers every hour; clock-skew compensated by absolute interval (not aligned to clock-hour). Acceptable for memory sync.
- systemd `OnCalendar=hourly` aligns to top of hour; document the difference if observed
- Both schedulers run as the user (not root); claude-memory clone is in `$HOME` so this is correct
- `bash -lc` ensures `~/.bashrc` / `~/.zshrc` PATH (gh, git) is loaded
- `/tmp/claude-memory-sync.{out,err}` rotation: existing `cleanup.sh` in claude-config rotates `/tmp/claude*` weekly; verify
- Avoid `awk` redirection in any shell scripts
- For unattended: `--lock-timeout 30` in the invocation prevents queueing when previous run is stuck — exits 5 silently and waits for next interval

### Deliverable

- launchd plist
- systemd service + timer
- `install_memory_sync()` and `uninstall_memory_sync()` in `scripts/install.sh`
- `docs/MEMORY_SYNC.md` updated with install / uninstall instructions
- PR linked to this issue

### Breaking Changes

None — opt-in via env var. Users without `CLAUDE_MEMORY_REPO_URL` are unaffected.

### Rollback Plan

- `./scripts/install.sh --uninstall-memory-sync`
- Or manually: `launchctl unload ...` / `systemctl --user disable --now memory-sync.timer`

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #E1, #E2
- Blocks: #F1 (audit job uses similar scheduler integration)
- Related: #G1 (multi-machine onboarding leverages same install path)

**Docs**:
- `docs/MEMORY_SYNC.md` install/uninstall section

**Commits/PRs**: (filled at PR time)
