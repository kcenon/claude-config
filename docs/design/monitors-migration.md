# Design Proposal: monitors.json Migration

> **Status**: Proposal (no implementation)
> **Audience**: claude-config maintainers
> **Spec source**: <https://code.claude.com/docs/en/plugins>

## Background

Claude Code's plugin spec defines `monitors/monitors.json` as a first-class plugin component. A monitor is a long-running command whose stdout streams into the session as notifications under the harness lifecycle (start, stop, restart on resume). Distinct from `Bash --run-in-background`, which is per-call and not declarative.

claude-config does **not** use `monitors.json`. The plugin surface (`plugin/`) declares none. Long-running observation today flows through (1) inline `gh pr checks` polling inside skills, (2) `Bash --run-in-background` + `Monitor` at runtime, (3) GitHub Actions for `tests/batch_drift_*`.

## Current State (grep evidence)

Searches across `global/`, `scripts/`, `tests/` for canonical loop patterns:

| Pattern | Result |
|---------|--------|
| `tail -F` | 0 hits |
| `while true` | 0 hits |
| `tail -f` (lower-case) | 1 hit — `tests/hooks/test-bash-sensitive-read-guard.sh:77`, an `assert_deny "tail -f .env.local"` fixture; not a migration candidate |

A broader sweep for polling loops (`gh pr checks` + `sleep`) surfaces these in-skill candidates:

| Path:line | Pattern |
|-----------|---------|
| `global/skills/_internal/pr-work/SKILL.md:390` | "non-blocking polling (30s intervals, 10min max)" |
| `global/skills/_internal/pr-work/reference/batch-mode.md:17-22` | `gh pr checks ... ; sleep 0.3` per-PR loop |
| `global/skills/_internal/pr-work/reference/batch-mode.md:45-51` | `gh pr checks ... ; sleep 0.3` cross-repo loop |
| `global/skills/_internal/pr-work/reference/build-verification.md:74` | `sleep 5` post-push wait |
| `global/skills/_internal/issue-work/reference/batch-mode.md:38` | `sleep 0.3` batch-mode loop |
| `global/skills/_internal/issue-work/SKILL.md:440` | `sleep 8` post-push wait |

These are SKILL.md *prose instructions* for the model to execute, not standalone shell loops. The distinction matters for migration.

## monitors.json Schema

Per the plugin spec, the schema is an array of monitor objects:

```json
[
  {
    "name": "<unique-id>",
    "command": "<shell command, stdout = notification stream>",
    "description": "<one-line UI label>"
  }
]
```

Optional fields: `when` (trigger condition) and `${VAR}` substitution in `command`. Monitors are plugin-scoped and load only when their plugin is loaded.

## Pros

- First-class lifecycle: harness starts/stops; no `--run-in-background` orchestration.
- Native chat surface: notifications render inline; no log-tailing.
- Declarative dedup: declared once, reused across sessions.
- Restart on resume: session-resume re-attaches automatically.

## Cons / Blockers

| Cost | Notes |
|------|-------|
| **Plugin scope only** | Monitors live in `plugin/`; `global/` candidates can't trivially declare one. |
| Stdout filtering | Raw `gh pr checks` spams the session; each monitor needs a grep/jq pipeline emitting one line per state change. |
| Sync vs. async | SKILL.md polling is read back synchronously *during* the run. Monitor notifications arrive asynchronously and break that contract. |
| No file transcript | Notifications are ephemeral; skills that re-parse their own output need redesign. |
| Per-PR parameterisation | `gh pr checks $PR_NUM` needs `${PR_NUM}`. If unsupported per-invocation, the monitor must watch all open PRs and filter — noisier. |

## Migration Candidates

| # | Candidate | ROI | Notes |
|---|-----------|-----|-------|
| 1 | None today | — | No plugin-scoped polling exists; grep finds zero `tail -F`/`while true`. |
| 2 | (Future) `pr-ci-status` monitor in `plugin/` | Medium | Would replace per-skill polling, but `plugin/` has no CI-watching surface today. |
| 3 | (Future) `permission-denials` monitor tailing `~/.claude/logs/permission-denials.jsonl` | Low | Depends on sister proposal `permission-event-hooks.md`; only useful once volume exists. |

### Do Not Migrate

| Pattern | Reason |
|---------|--------|
| `gh pr checks` polling in `pr-work` SKILL.md | Synchronous read-back is part of the skill contract |
| `sleep N` post-push waits in `build-verification.md` | One-shot delays — `Bash --run-in-background` handles this |
| `tests/batch_drift_*` | GitHub Actions, not session-scoped |
| `global/hooks/lib/timeout-wrapper.sh:77` `sleep 1` | Internal timeout primitive |

## Decision Matrix

| Option | Risk | Value | Verdict |
|--------|------|-------|---------|
| A. Migrate existing patterns now | High (no real candidates; complexity for negative gain) | None | Not recommended |
| B. Add `monitors.json` to `plugin/` for new use cases only | Low | Medium (enables future monitors without disturbing globals) | Conditional yes |
| C. Document `monitors.json` as future-state guidance | None | Low (preserves status quo, keeps door open) | **Recommended** |
| D. Do nothing | None | None | Inferior to (C) |

### Recommendation

**Option C — future-state guidance only.** The grep evidence is decisive: no `tail -F`/`while true` to migrate, and existing `gh pr checks` polling belongs to skill control flow, not background observation. Migration would break the synchronous contract.

Concretely: add a section to `docs/plugin-vs-global.md` (or a new `monitors-future-state.md`) describing when a plugin-scoped feature should reach for `monitors.json`. Migrate no existing pattern. Revisit Option B if a real background-notification need emerges.

## Out of Scope

- Implementation. If approved, open an issue via `issue-create`.
- Designing the hypothetical `pr-ci-status` monitor — premature.
- Touching `tests/batch_drift_*` (CI-scoped).

---
*Version 1.0 (2026-04-30). Proposal for review by claude-config maintainers.*
