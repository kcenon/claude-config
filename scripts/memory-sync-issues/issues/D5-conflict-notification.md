---
title: "feat(memory): conflict alerting channel"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/S
  - phase/D-engine
milestone: memory-sync-v1-engine
blocked_by: [D1]
blocks: [D3, E1]
parent_epic: EPIC
---

## What

Implement `scripts/memory-notify.sh` — a centralized notification helper used by `memory-sync.sh` (#D1), `memory-write-guard.sh` (#D2), and `memory-integrity-check.sh` (#D3) to surface failures without burying them in logs. Routes alerts to OS notification channels and a persistent log.

### Scope (in)

- Single bash script, executable
- Three severity levels: `info`, `warn`, `critical`
- Channels:
  - macOS: `terminal-notifier` if installed, fallback `osascript display notification`
  - Linux: `notify-send`
  - Universal: append to `~/.claude/logs/memory-alerts.log`
- Persistent log read by `memory-integrity-check.sh` (#D3) at SessionStart
- Dedup: same `<severity, message>` within 1 hour suppressed
- `--dismiss <id>` clears alerts as read

### Scope (out)

- Push notifications to mobile / external services
- Email alerts
- Slack / Discord integrations
- Long-term alert metrics

## Why

Without a centralized notify helper, each upstream caller (sync, write-guard, integrity-check) would re-implement OS detection and dedup. Worse, alerts would scatter across multiple channels and log files, making "what's broken right now" hard to answer.

The persistent log + dedup design ensures that:

1. A flapping failure (sync fails every hour) doesn't spam OS notifications — first alert pops, subsequent dedups
2. Alerts persist across sessions (user can leave for the weekend, return, see what happened)
3. SessionStart hook (#D3) surfaces "you missed N alerts" the next time Claude Code starts

### What this unblocks

- #D1 — sync engine emits notifications
- #D2 — write-guard surfaces internal errors
- #D3 — integrity-check displays unread alerts

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 1 week of #D1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/scripts/memory-notify.sh`
- **Persistent log**: `~/.claude/logs/memory-alerts.log`
- **Read-mark**: `~/.claude/.memory-alerts-read-mark`

## How

### Approach

Two operations: emit (default) and dismiss. Emit appends to log (always), then attempts OS notification (best-effort). Dedup keyed on hash of `<severity, message>` within trailing 1-hour window.

### Detailed Design

**Script signature**:
```
memory-notify.sh <severity> <message>            # emit
memory-notify.sh --dismiss [<id>]                # mark read (all or specific)
memory-notify.sh --list [--all|--unread]         # list alerts (default unread)
memory-notify.sh --help
```

**Severity levels**:
- `info` — informational (e.g., "audit completed clean")
- `warn` — needs attention but not urgent (e.g., "sync delayed")
- `critical` — needs immediate attention (e.g., "merge conflict")

**Exit codes**:
- `0` — emit succeeded (regardless of OS-channel success)
- `1` — invalid severity
- `2` — message empty
- `64` — usage error

**Emit flow**:
1. Validate severity ∈ {info, warn, critical}
2. Compute message hash (SHA-256 of `<severity>:<message>`, first 12 chars)
3. Check log for same hash within last 1 hour → if present, exit 0 silently (deduped)
4. Append to log: `<ISO timestamp> <severity> <hash> <message>` (single line, message escaped)
5. OS notification (best-effort, ignore failure):
   - macOS: `terminal-notifier -title "Claude Memory" -subtitle "<severity>" -message "<message>"` (fallback `osascript`)
   - Linux: `notify-send "Claude Memory: <severity>" "<message>"`
6. Exit 0

**Dismiss flow**:
- `--dismiss` (no arg): mark all current unread alerts as read
- `--dismiss <id>`: mark specific alert (by hash from `--list`) as read
- Implementation: write current epoch to read-mark file (for "all"), or maintain per-id read marks

**List flow**:
- Default `--unread`: tail of log since `read-mark` epoch
- `--all`: full log, paginated by `head/tail`
- Output one line per alert with id (hash) and time-ago

**Log format** (one entry per line):
```
2026-05-01T10:23:45Z critical 1a2b3c4d5e6f memory-sync: merge conflict on macbook-pro
2026-05-01T10:30:11Z warn     2b3c4d5e6f70 memory-sync: pre-push validation failed
```

**Dedup window**: 3,600 seconds. Log scan: `tail -n 200 log | awk -F' ' '$3 == hash && (now - epoch) < 3600'` semantics in pure bash.

**State and side effects**:
- Appends to `~/.claude/logs/memory-alerts.log`
- Writes/reads `~/.claude/.memory-alerts-read-mark`
- Best-effort OS notification call (silent failure)

**External dependencies**: bash 3.2+, `shasum` (macOS) or `sha256sum` (Linux), `terminal-notifier` (optional macOS), `notify-send` (optional Linux).

### Inputs and Outputs

**Input** (emit critical):
```
$ ./memory-notify.sh critical "memory-sync: merge conflict on macbook-pro"
```

**Output** (terminal notification appears + log line written):
```
(no stdout; success implicit)
```
Exit: `0`

**Input** (emit duplicate within 1 hour):
```
$ ./memory-notify.sh critical "memory-sync: merge conflict on macbook-pro"
```

**Output**: silent dedup (not appended, no notification re-fired).

**Input** (list unread):
```
$ ./memory-notify.sh --list
```

**Output**:
```
[1a2b3c4d5e6f] 47 min ago   critical  memory-sync: merge conflict on macbook-pro
[2b3c4d5e6f70] 23 min ago   warn      memory-sync: pre-push validation failed
```

**Input** (dismiss all):
```
$ ./memory-notify.sh --dismiss
```

**Output**:
```
Dismissed 2 unread alerts.
```

**Input** (programmatic call from sync engine):
```
$ ./memory-notify.sh warn "memory-sync: pre-push validation failed: feedback_leak.md token detected"
```

### Edge Cases

- **Log file missing** → create on first emit; no error
- **Log file unwritable** → emit to stderr only, exit 0 (don't fail caller)
- **Read-mark missing** → all alerts considered unread
- **No `terminal-notifier` on macOS** → fall back to `osascript -e 'display notification ...'`
- **No `notify-send` on Linux** → log only, no OS popup; documented
- **No DBUS / running display server** (Linux SSH session) → `notify-send` will fail; caught silently
- **Severity with weird casing** ("CRITICAL") → lowercased for validation
- **Message with newlines** → strip/replace with spaces for log; OS notifications often render only first line anyway
- **Message with shell metacharacters** → escape via parameter expansion; never `eval`
- **Concurrent emits** → log append is line-atomic on POSIX (write < PIPE_BUF); no flock needed for typical message sizes
- **Hash collision** (extremely unlikely in 12-char window) → user sees deduped legitimate alert; acceptable tradeoff
- **Read-mark older than log entries** → all entries read as unread (correct)
- **Dedup window crosses midnight** → epoch arithmetic handles correctly
- **`--dismiss` with non-existent id** → no-op, exit 0

### Acceptance Criteria

- [ ] Script `scripts/memory-notify.sh` (executable)
- [ ] **Severity levels** info / warn / critical, validated
- [ ] **OS notification** macOS (terminal-notifier or osascript) and Linux (notify-send) — best-effort
- [ ] **Persistent log** `~/.claude/logs/memory-alerts.log` append-only, single-line entries
- [ ] **Dedup**: same `<severity, message>` within 1 hour suppressed
- [ ] **Dismiss**: `--dismiss` updates read-mark
- [ ] **List**: `--list [--all|--unread]` shows alerts
- [ ] **Best-effort OS notification**: failure does not affect exit code
- [ ] **Caller-friendly**: never fails caller's flow (always exit 0 unless usage error)
- [ ] Bash 3.2 + Linux compatible
- [ ] Documented in `docs/MEMORY_SYNC.md` (#G3)

### Test Plan

- Emit critical → log line appears + macOS notification (or fallback)
- Re-emit identical message within minute → log unchanged, no second notification
- Emit different severity, same message → log gets both
- Wait > 1 hour, re-emit identical → log gets new entry
- `--list` shows entries
- `--dismiss` → list shows none unread
- macOS + Linux both work

### Implementation Notes

- **Hash**: `printf '%s' "<severity>:<message>" | shasum -a 256 | cut -c1-12` on macOS; `sha256sum` on Linux
- **Detect macOS**: `[[ "$(uname)" == "Darwin" ]]`
- **terminal-notifier check**: `command -v terminal-notifier >/dev/null`
- **osascript fallback**: `osascript -e "display notification \"$msg\" with title \"Claude Memory\" subtitle \"$severity\""`
- **Append-only log**: `>>` is line-atomic for messages under PIPE_BUF (~4KB)
- **Dedup scan**: read last 100 lines (`tail -n 100`), parse epoch, find same hash with `(now - epoch) < 3600`
- **Time formatting in `--list`**: helper `time_ago_seconds <secs>` → "47 min ago"
- **Avoid `awk` redirection** — pure bash + grep + tail
- **Read-mark format**: single line, ISO datetime; updated atomically via temp file + mv

### Deliverable

- `scripts/memory-notify.sh` (executable, ~200 lines)
- Help text via `--help`
- Updated `docs/MEMORY_SYNC.md` (cross-issue with #G3)
- PR linked to this issue

### Breaking Changes

None.

### Rollback Plan

- Stop callers from invoking it (revert their PRs)
- Remove the script
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #D1
- Blocks: #D3
- Related: #D2 (caller), #F1 (caller), #G3 (operational doc)

**Docs**:
- `docs/MEMORY_SYNC.md` (#G3)

**Commits/PRs**: (filled at PR time)
