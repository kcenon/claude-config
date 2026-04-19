# Fleet Orchestrator — Parallel Multi-Repo Directive Execution

> **Type**: Skill documentation
> **Skill location**: `global/skills/fleet-orchestrator/`
> **Related issues**: #366 (this skill), #360 (post-task-checkpoint hook, closed), #361 (atomic multi-phase rule, closed)
> **Related skills**: [`harness`](../global/skills/harness/SKILL.md), [`issue-work`](../global/skills/issue-work/SKILL.md), [`pr-work`](../global/skills/pr-work/SKILL.md)
> **Purpose**: Fan out a single directive across N repositories as parallel worker Agents, with a supervisor that polls a shared manifest and aggregates results.

## Background

The 2026-04-18 `/insights` report documented the "8-system sequential sweep"
pattern appearing in 4+ sessions (vcpkg readiness, 160+ deprecated item removal,
7-project build fixes). Each ran for hours serially. The fleet-orchestrator
compresses wall-clock time by running workers in parallel and isolates failures
so one flaky repo does not block the rest of the sweep.

Tier progression toward this skill:

- **Tier 0** (shipped): lower batch limits, chunked confirmation, inline rule reminders.
- **Tier 1** (shipped): PreToolUse guards for language, merge gate, attribution.
- **Tier 2** (shipped): subagent delegation as the default batch dispatch; `--auto-restart` for process-level resets.
- **Tier 3** (this skill): parallel worker fan-out across repos with shared-state coordination.

This is the "On the Horizon #1" item from the 2026-04-18 report:
**Parallel Multi-Repo Autonomous PR Fleet**.

## Architecture

The skill instantiates the Fan-out/Fan-in + Supervisor pattern from
`harness/reference/agent-design-patterns.md`.

```
                    [Supervisor (main session)]
                     | dispatch      ^ poll every POLL_INTERVAL seconds
                     v               |
       +-------------+---------------+-------------+
       |             |               |             |
   [Worker 1]    [Worker 2]      [Worker 3]    [Worker N]
   repo A        repo B          repo C         repo N
       \             \               /             /
        \            flock-guarded   /            /
         \           writes to       /           /
          \------> fleet-status.json <----------/
```

| Component | Role |
|-----------|------|
| Supervisor | Main session. Input validation, worker fan-out, manifest polling, aggregation, final report. Never edits code itself. |
| Worker (N×) | Fresh `general-purpose` Agent per repo, launched with `run_in_background=true`. Runs issue-work/pr-work on its assigned repo and writes terminal status to the manifest. |
| Manifest | `_workspace/fleet/fleet-status.json`. Single source of truth for fleet state. Guarded by `flock`. Schema: `global/skills/fleet-orchestrator/reference/manifest-schema.json`. |

## Relationship to Existing Skills

| Skill | Role in a fleet run |
|-------|---------------------|
| `harness` | Meta-skill that produced the Fan-out + Supervisor pattern this skill follows. |
| `issue-work` | Each worker delegates its per-repo workflow (branch → PR → CI → merge) to `issue-work --solo`. The worker adds manifest updates around that call. |
| `pr-work` | The retry path when a worker's initial PR fails CI. Invoked by the worker, not directly by the supervisor. |
| `issue-create` | Used by workers when the directive requires a new issue per repo (most audit/cleanup directives do). |

The fleet orchestrator is deliberately a thin supervisor. Each worker reuses
the per-repo workflows that already enforce language, attribution, and CI-gate
rules — the fleet layer only adds the manifest integration and the retry
classifier.

## When to Reach For This Skill

| Situation | Use fleet-orchestrator? |
|-----------|-------------------------|
| Apply the same audit/cleanup/fix across 3+ repos | Yes |
| Sequential sweep currently taking hours | Yes |
| Version bump for a shared internal package across repos | Yes |
| Single repo, single issue | No — use `/issue-work` |
| Schema change that must merge in strict cross-repo order | No — coordinate manually |
| Repos with incompatible toolchains that share nothing but the directive | Marginal — evaluate per case |

## Example Invocations

```
/fleet-orchestrator repo-a repo-b repo-c "Remove all uses of the deprecated foo_bar API"

/fleet-orchestrator @repos.txt "Bump vcpkg baseline to 2026.04"

/fleet-orchestrator --org kcenon "Audit for secrets in CI logs; redact and open an issue"

/fleet-orchestrator repo-a repo-b repo-c "Migrate tests to Catch2 v3" --max-parallel 4 --retry 2 --poll-interval 60

/fleet-orchestrator --org kcenon "Dry run only" --dry-run
```

See `global/skills/fleet-orchestrator/SKILL.md` for the full argument list and
workflow phases.

## Output Artifacts

Every fleet run produces:

| Path | Purpose | Retained after run? |
|------|---------|---------------------|
| `_workspace/fleet/fleet-status.json` | Terminal manifest with per-repo outcomes | Yes (audit trail) |
| `_workspace/fleet/fleet-status.json.lock` | Flock file (empty) | Yes |
| `_workspace/fleet/<repo-slug>/worker.log` | Per-worker phase log | Yes |
| Per-repo PR on GitHub | The actual deliverable | Yes |

The final supervisor report includes per-repo PR URL, CI outcome, and merge
status, and explicitly flags any repo that landed in `draft` state for user
review.

## Failure Isolation

A worker failure never halts peer workers. Each worker writes its terminal
state into its own manifest slot under `flock`; the supervisor treats the
manifest as the single source of truth and reconciles any worker that exited
without writing terminal state by filling in `{status:"failed", error:{class:"worker-crash"}}`.

Three failure classes to know:

| Class | Meaning | Supervisor action |
|-------|---------|-------------------|
| `code-review-needed` | Real code bug exposed by CI; PR left as draft. | Flagged in the final report for user action. |
| `retry-exhausted` | Transient CI failures consumed the retry budget without the worker identifying a root cause. | Flagged in the final report, log path included. |
| `preflight-failed` | Repo-level issue (no push permission, archived). | Repo is moved to `pre_excluded` in the manifest; never counted against fleet success. |

## Dependencies

This skill assumes the following infrastructure is in place:

- **`hooks/post-task-checkpoint.sh`** (issue #360 — closed): prevents worker-side checkpoint clobbers when multiple workers run in parallel.
- **Atomic Multi-Phase Execution rule** in `_policy.md` (issue #361 — closed): keeps workers from pausing mid-PR for confirmation. Without this rule, parallel workers would deadlock on per-phase prompts.
- **`flock` and `jq`**: the manifest update protocol uses both. They are allowlisted in the skill's `allowed-tools` frontmatter.

## References

- Skill entry point: `global/skills/fleet-orchestrator/SKILL.md`
- Worker prompt template: `global/skills/fleet-orchestrator/reference/worker-template.md`
- Manifest schema: `global/skills/fleet-orchestrator/reference/manifest-schema.json`
- Architecture pattern origin: `global/skills/harness/reference/agent-design-patterns.md` (Fan-out/Fan-in, Supervisor sections)
- Motivating report: 2026-04-18 `/insights` "On the Horizon #1" — Parallel Multi-Repo Autonomous PR Fleet
