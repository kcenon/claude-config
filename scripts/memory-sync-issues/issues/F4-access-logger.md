---
title: "feat(memory): memory access logger"
labels:
  - type/feature
  - priority/low
  - area/memory
  - size/S
  - phase/F-audit
milestone: memory-sync-v1-audit
blocked_by: [E3]
blocks: []
parent_epic: EPIC
---

## What

Implement `global/hooks/memory-access-logger.sh` — a PostToolUse Read hook that logs each memory file read by Claude during a session. Output to `~/.claude/logs/memory-access.log`. Consumed by `audit.sh` (#F1) for the unused-memory check.

### Scope (in)

- PostToolUse Read hook
- Logs only when `tool_input.file_path` is under `~/.claude/memory-shared/memories/`
- Log entries: ISO timestamp + session_id + file path + tool name
- Monthly log rotation
- No content logging (file path only)
- PowerShell mirror

### Scope (out)

- Logging Edit/Write events (those are recorded in git history already)
- Cross-machine aggregation (each machine logs its own activity)
- Real-time analytics dashboard

## Why

Audit's "unused memory" check (#F1) needs to know which memories were actually used. Without an access log, the check can't run.

Beyond audit, an access log enables future analytics: "which memory is loaded most often?", "did adding memory X reduce the rate of issue Y?". For now, the unused detector is the primary consumer.

The log records **paths only**, never content, so it carries no PII risk beyond the filename pattern (which is already the canonical identifier, not sensitive).

### What this unblocks

- #F1 — unused-memory check has data to operate on (without #F4, that check is skipped)

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: low — `audit.sh` runs without this; this is enhancement
- **Estimate**: ½ day
- **Target close**: within 1 week of #E3 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/global/hooks/memory-access-logger.sh`
- **Settings update**: `global/settings.json` PostToolUse Read matcher
- **PowerShell mirror**: `global/hooks/memory-access-logger.ps1`
- **Log file**: `~/.claude/logs/memory-access.log`

## How

### Approach

PostToolUse Read fires after a successful Read. Hook checks if the path is in the memory tree; if so, append a line to the log. Designed to be **fast and cheap** — no validators, no parsing, just a write.

### Detailed Design

**Hook input** (per Claude Code hook contract):
```json
{
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/Users/raphaelshin/.claude/memory-shared/memories/feedback_xyz.md"
  },
  "session_id": "abc123"
}
```

**Hook output**: empty stdout (PostToolUse doesn't influence the past tool call); exit 0.

**Flow**:
1. Read JSON from stdin
2. Extract `tool_input.file_path` and `session_id`
3. Resolve realpath
4. If path NOT under `$HOME/.claude/memory-shared/memories/` → exit 0
5. Append to log: `<ISO timestamp> <session_id> read <file_path>`
6. Exit 0

**Log format** (one entry per line):
```
2026-05-08T10:23:11Z abc123 read memories/feedback_ci_merge_policy.md
2026-05-08T10:23:14Z abc123 read memories/project_kcenon_label_namespaces.md
```

Path is stored relative to memory-shared (just `memories/<file>`) for compactness and privacy.

**Rotation policy**:
- Monthly rotation: when log file size exceeds 1MB OR is from previous month, rotate to `memory-access.log.YYYY-MM`
- Keep 6 months; older deleted by `cleanup.sh` (existing in claude-config)
- Rotation triggered lazily (each hook invocation checks size)

**State and side effects**:
- Append to log file
- Possibly rotate log
- No memory tree modification

**External dependencies**: bash 3.2+, basic POSIX tools, jq (optional for JSON parsing).

### Inputs and Outputs

**Input** (Claude reads a memory):
```json
{"tool_name":"Read","tool_input":{"file_path":"/Users/raphaelshin/.claude/memory-shared/memories/feedback_ci_merge_policy.md"},"session_id":"abc123"}
```

**Output**: empty stdout, exit 0. Log file gets new line:
```
2026-05-08T10:23:11Z abc123 read memories/feedback_ci_merge_policy.md
```

**Input** (Claude reads a non-memory file):
```json
{"tool_name":"Read","tool_input":{"file_path":"/some/other/file.txt"}}
```

**Output**: empty stdout, exit 0. No log entry.

**Input** (audit consumer):
```
$ awk '{print $4}' ~/.claude/logs/memory-access.log | sort -u
memories/feedback_ci_merge_policy.md
memories/feedback_explicit_option_choices.md
memories/project_kcenon_label_namespaces.md
...
```

### Edge Cases

- **Hook invoked on Read of MEMORY.md** → MEMORY.md is in `memory-shared/` but NOT `memory-shared/memories/` (it's at the top level), so by the realpath check it's not logged; OK
- **Symlinked path** (Read via the symlink at `~/.claude/projects/.../memory/`) → resolve to memory-shared/memories first; log under canonical path
- **Read fails** (file not found) — PostToolUse fires only on success per Claude Code contract; this hook never sees failed reads
- **Concurrent Reads** in same session → multiple log lines; line-atomic append handles this
- **Log file unwritable** (permissions) → silently skip; do NOT fail the hook (would impact tool flow)
- **Log file very large** (e.g., 10MB) → rotation kicks in; if rotation also fails, the log just keeps growing; document
- **Session ID missing** in input → log `unknown` for that field
- **Timestamp clock-skew** → uses local UTC; document if multi-machine logs are aggregated
- **Hook runs but jq not installed** → fall back to grep/sed JSON parsing (existing claude-config pattern)
- **Read tool's `file_path` contains shell metacharacters** → escape via parameter expansion; never `eval`

### Acceptance Criteria

- [ ] Hook script `global/hooks/memory-access-logger.sh` (executable)
- [ ] PowerShell mirror `global/hooks/memory-access-logger.ps1`
- [ ] Registered in `global/settings.json` PostToolUse Read matcher with `async: true`
- [ ] **Path filter**: only logs paths under `$HOME/.claude/memory-shared/memories/`
- [ ] **Realpath resolution** before filter (handles symlinks)
- [ ] **Log format**: `<ISO timestamp> <session_id> read <relative-path>`
- [ ] **Append-only** (line-atomic for typical line size)
- [ ] **Rotation**: monthly OR > 1MB threshold
- [ ] **Performance**: < 5ms typical (hook overhead non-negligible)
- [ ] **Failure isolation**: log write failure does not affect tool flow
- [ ] **No content** logged (only path)
- [ ] Bash 3.2 compatible
- [ ] Documented in `docs/MEMORY_SYNC.md` privacy section
- [ ] Existing `cleanup.sh` rotates old logs (verify integration)

### Test Plan

- Read a memory via Claude Code → log entry appears
- Read a non-memory file → no log entry
- Read 1000 memories in succession → all logged, performance acceptable
- Make log file unwritable (`chmod 000`) → hook continues silently
- Trigger rotation by writing > 1MB synthetic content → rotated to dated file
- macOS + Linux

### Implementation Notes

- **Async**: registered with `async: true` in settings.json so the hook doesn't block the user from seeing Read results
- **Path filter** before any heavy work: cheap test should be first, exit early
- **JSON parsing**: prefer jq, fall back to grep/sed
- **realpath** on macOS may need fallback as in #D2
- **Atomic append**: just `>>` works for single-line writes < PIPE_BUF; no flock needed
- **Rotation logic**: check size with `wc -c` (cheap on macOS/Linux); if exceeded, `mv` to dated file before append
- Existing claude-config `cleanup.sh` rotates `~/.claude/logs/*` weekly — verify the access log fits this pattern; otherwise add to its purge list
- **Privacy note**: file paths are not sensitive; log file is in user's home dir, not synced; not transmitted

### Deliverable

- `global/hooks/memory-access-logger.sh` (executable, ~80 lines)
- `global/hooks/memory-access-logger.ps1`
- `global/settings.json` updated
- `docs/MEMORY_SYNC.md` privacy section updated
- PR linked to this issue

### Breaking Changes

None.

### Rollback Plan

- Remove hook entry from settings.json
- Remove hook script files
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #E3
- Blocks: (none)
- Related: #F1 (consumer)

**Docs**:
- `docs/MEMORY_SYNC.md` privacy section
- Existing `cleanup.sh` log rotation policy

**Commits/PRs**: (filled at PR time)

**Reference pattern**: `claude-config/global/hooks/session-logger.sh` (similar log-and-rotate pattern)
