---
title: "feat(memory): memory-status.sh diagnostic CLI"
labels:
  - type/feature
  - priority/low
  - area/memory
  - size/S
  - phase/D-engine
milestone: memory-sync-v1-engine
blocked_by: [D1]
blocks: []
parent_epic: EPIC
---

## What

Implement `scripts/memory-status.sh` — on-demand CLI for detailed memory state. Brief default output (counts + last sync), `--detail` for per-machine activity table and audit history, `--json` for machine-readable output.

### Scope (in)

- Single bash script, executable
- Three modes: brief (default), detail, json
- Machine activity table from git log (per-machine commit counts and last-push times)
- Audit summary from `audit/` directory
- Status of pending push/pull commits
- Bash 3.2 compatible

### Scope (out)

- Modifying state (this is read-only diagnostic)
- Triggering sync or audit
- Interactive UI

## Why

The SessionStart hook (#D3) shows a brief health summary, but only when triggered by session start. For ad-hoc diagnostic ("why didn't my change reach the other machine?", "is the audit job actually running?"), a CLI is needed.

`--json` mode allows the data to be consumed by future tooling (status badges in shell prompts, alerting integrations) without re-implementing the metadata aggregation logic.

### What this unblocks

- Operational visibility for #G2 testing
- Future shell-prompt status integration

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: low
- **Estimate**: ½ day
- **Target close**: within 1 week of #D1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/scripts/memory-status.sh`

## How

### Approach

Read-only aggregator that joins data from: memory tree (counts by tier), git log (sync activity), audit dir (recent reports), alerts log (recent failures). Each source has a small dedicated function; output formatters compose.

### Detailed Design

**Script signature**:
```
memory-status.sh                  # brief
memory-status.sh --detail         # full table
memory-status.sh --json           # machine-readable
memory-status.sh --help
```

**Brief output**:
```
Repository: ~/.claude/memory-shared
Branch: main (up to date with origin/main)
Last sync: 2026-05-01T00:23:11Z (37 min ago)
Memories: 17 (verified:13, inferred:3, quarantined:1)
Pending push: 0 commits
Pending pull: 0 commits
Last audit: 2026-04-29 (Monday) — 2 stale, 0 conflicts, 1 unused
Recent alerts: 0
```

**Detail output** (additional sections):
```
Active machines (last 30 days):
  macbook-pro     last-push: 2h ago     commits: 14
  mac-mini-home   last-push: 5h ago     commits:  6
  linux-laptop    last-push: 12h ago    commits:  2

Audit history (last 4 reports):
  2026-04-29: 2 stale, 0 conflicts, 1 unused, 0 quarantine review
  2026-04-22: 1 stale, 0 conflicts, 0 unused, 0 quarantine review
  2026-04-15: 0 stale, 0 conflicts, 2 unused, 0 quarantine review
  2026-04-08: 0 stale, 1 conflict, 0 unused, 0 quarantine review

Trust-level distribution by type:
            verified  inferred  quarantined
  user             1         0            0
  feedback         5         0            0
  project          7         3            1
  reference        0         0            0

Stale entries (last-verified > 90d):
  feedback_old_thing.md (last-verified: 2026-01-15)

Recent unread alerts: (none)
```

**JSON output**:
```json
{
  "repo": "/Users/raphaelshin/.claude/memory-shared",
  "branch": "main",
  "tracking_status": "up_to_date",
  "last_sync": {
    "iso": "2026-05-01T00:23:11Z",
    "ago_seconds": 2200,
    "host": "macbook-pro"
  },
  "memories": {
    "total": 17,
    "by_tier": {"verified": 13, "inferred": 3, "quarantined": 1},
    "by_type": {"user": 1, "feedback": 5, "project": 11, "reference": 0}
  },
  "pending": {"push": 0, "pull": 0},
  "stale": ["feedback_old_thing.md"],
  "machines": [
    {"name": "macbook-pro", "last_push_ago_seconds": 7200, "commits_30d": 14}
  ],
  "audit": {
    "last_iso": "2026-04-29",
    "last_findings": {"stale": 2, "conflicts": 0, "unused": 1, "quarantine_review": 0}
  },
  "unread_alerts": 0
}
```

**Computation**:
- `git status --porcelain=v2 --branch` → tracking status, ahead/behind counts
- `git log -1 --format='%cI %an'` → last sync time + author (machine via author convention from #D1)
- `git log --since='30 days ago' --format='%an' | sort | uniq -c` → per-machine commit counts
- `git log --pretty=format:'%cI %an' --since='30 days ago'` → last-push per machine via deduplication
- Memory counts → per #D3 logic (frontmatter read)
- Audit history → list `audit/*.md`, parse summary line per file
- Alerts → tail of `~/.claude/logs/memory-alerts.log`

**State and side effects**: read-only.

**External dependencies**: bash 3.2+, git, jq (for `--json` mode preferred but optional fallback to bash string-building).

### Inputs and Outputs

**Input** (brief):
```
$ ./memory-status.sh
```

**Output**: as in Detailed Design "Brief output". Exit 0.

**Input** (detail):
```
$ ./memory-status.sh --detail
```

**Output**: includes Brief + the additional sections.

**Input** (JSON, piped to jq):
```
$ ./memory-status.sh --json | jq '.last_sync.ago_seconds'
2200
```

**Input** (memory-shared not present):
```
$ ./memory-status.sh
[error] ~/.claude/memory-shared not found; run memory-bootstrap.sh
```
Exit: `1`

### Edge Cases

- **No commits yet** (fresh repo, just-cloned) → "Last sync: never (no commits yet)"
- **Git log returns nothing for 30-day window** → "Active machines (last 30 days): (none)"
- **Audit dir missing** → "Last audit: never"
- **Alerts log missing** → "Recent alerts: 0"
- **`jq` not installed and `--json` requested** → fall back to a hand-built JSON string (more brittle but functional)
- **Machine names with spaces** (rare, but possible) — JSON-escape; brief mode just shows as-is
- **Per-machine activity calculation when commit author convention isn't followed** → degrades to "<unknown>" rows; documented
- **Output piped to non-tty** → no color codes
- **Output piped to a pager** → output is < 1 page typical; pager not auto-invoked
- **Frontmatter parse failure on a memory** → skipped from counts; logged to stderr; doesn't fail the command

### Acceptance Criteria

- [ ] Script `scripts/memory-status.sh` (executable)
- [ ] **Brief mode**: counts, last sync, pending push/pull, last audit summary, unread alerts
- [ ] **Detail mode**: brief + machine activity table + audit history + tier-by-type matrix + stale list
- [ ] **JSON mode**: structured per Detailed Design schema; valid JSON
- [ ] **No state modification** (read-only verified by manual inspection)
- [ ] Bash 3.2 compatible
- [ ] **`jq` optional**: works without jq for non-JSON modes; degrades JSON output gracefully
- [ ] Help text via `--help`
- [ ] Performance: < 300ms typical for brief, < 800ms for detail
- [ ] Output piped to file/pipe works (no terminal-specific codes leak)
- [ ] Documented in `docs/MEMORY_SYNC.md` (#G3)

### Test Plan

- Run on a healthy clone → brief output correct
- Run with --detail → all extra sections present
- Run with --json → output valid JSON (verify with `jq .`)
- Run before any sync → "Last sync: never"
- Run after audit job → "Last audit" shows real findings
- macOS + Linux

### Implementation Notes

- **Per-machine inference**: convention is sync commits use `<commit>: ... from <hostname>` author or commit message; #D1 should standardize this convention so this script can mine it. Document as cross-link.
- **Time-ago formatting**: helper `time_ago_seconds 7200` → "2h ago"; standard library pattern
- **JSON building without jq**: use `printf` with `%s` substitution; escape strings via `${var//\"/\\\"}` for quote escaping; acceptable for modest data
- **Color**: use `tput setaf` only if `[ -t 1 ]` (interactive); otherwise plain
- **Trim long names** (e.g., 25-char machine names) for table alignment in detail mode
- **Avoid `awk` redirections** — pure bash + grep + git
- **Read alerts log** efficiently: `tail -n 100` not full file (logs grow)

### Deliverable

- `scripts/memory-status.sh` (executable, ~250 lines)
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — net-new tool.

### Rollback Plan

Revert PR.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #D1
- Blocks: (none)
- Related: #D3 (shares aggregation logic), #D5 (reads alerts log), #F1 (reads audit dir)

**Docs**:
- `docs/MEMORY_SYNC.md` (#G3) — operational reference

**Commits/PRs**: (filled at PR time)
