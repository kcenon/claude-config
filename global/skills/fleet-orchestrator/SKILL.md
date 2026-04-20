---
name: fleet-orchestrator
description: "Fan out a single high-level directive (audit, deprecation cleanup, fix, migration, version bump) across an arbitrary list of repositories as parallel Agent workers, with a supervisor that polls a shared manifest, renders a live status table, and aggregates final results. Use when the user says 'apply X across repos', 'audit N repositories', 'sweep every repo', 'run the same fix in all projects', 'parallel multi-repo', 'fleet-wide change', or provides a list of repositories with a single directive. Preferred over running issue-work in each repo sequentially."
argument-hint: "<repos-spec> <directive-spec> [--max-parallel N] [--retry N] [--poll-interval SEC] [--dry-run] [--reanchor-interval N]"
user-invocable: true
disable-model-invocation: false
allowed-tools: "Bash(gh *), Bash(flock *), Bash(jq *)"
max_iterations: 10
halt_condition: "All repos reach a terminal worker status (done, failed-after-retries, skipped), OR --max-parallel worker pool drains with no pending items"
on_halt: "Render final fleet-status table with per-repo outcome and exit"
---

# Fleet Orchestrator -- Parallel Multi-Repo Directive Executor

A supervisor skill that applies one directive across many repositories concurrently.
Each repository is handled by an independent worker Agent; progress and outcomes
flow through a single JSON manifest (`fleet-status.json`) updated with `flock` for
atomic, race-free writes.

## When to Use This Skill

- Applying the same change (audit, cleanup, migration, dependency bump, policy update) to N repos.
- The user wants wall-clock compression — eight repos serialized take hours, fanned out take the length of the slowest one.
- Failure isolation matters — one flaky repo must not block the other seven.
- The directive is uniform enough that per-repo customization is minor (each worker still adapts to its repo's code style and issue landscape).

Do NOT use this skill when:

- There is only one repo — use `/issue-work` directly.
- The directive requires tight cross-repo coordination (e.g., a schema change that must merge in strict order) — sequence it manually.
- Repos have incompatible toolchains and the supervisor cannot meaningfully aggregate their outcomes.

## Execution Mode: Sub-agent (Parallel) with Supervisor

Agent teams are capped at one active team per session. Fleet work needs N independent
workers running concurrently with run-to-completion semantics, so we use the sub-agent
mode (`Agent(..., run_in_background=true)`) plus a file-based manifest for coordination.

Data passing strategy:

| Layer | Mechanism | Why |
|-------|-----------|-----|
| Shared state | `_workspace/fleet/fleet-status.json` | One JSON blob, race-free via `flock`, readable by every worker and the supervisor |
| Per-worker artifacts | `_workspace/fleet/{repo-slug}/` | Per-worker scratch, logs, diff snapshots — preserved for audit |
| Supervisor → worker | `Agent` prompt (one-shot) | Each worker gets the spec and its `repo` slot at launch; no runtime re-parameterization |
| Worker → supervisor | Manifest writes | Supervisor polls; workers never call back |

## Agent Configuration

| Role | `subagent_type` | `model` | `run_in_background` | Purpose |
|------|----------------|---------|----------------------|---------|
| supervisor | (main session) | n/a | n/a | Input validation, worker fan-out, manifest polling, aggregation |
| worker (one per repo) | `general-purpose` | `opus` | `true` | Executes the directive on its assigned repo, updates manifest |

All workers use the same worker prompt template (`reference/worker-template.md`).
The supervisor never edits code itself — it only dispatches, monitors, and reports.

## Architecture

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

## Workflow

### Phase 1: Input Resolution and Validation

The skill accepts inputs in three forms; pick the first that matches:

| Input form | Example | How to parse |
|------------|---------|--------------|
| Inline list | `repo-a repo-b repo-c "fix all TODOs"` | Positional args: repos until a non-repo-like token, then the directive |
| File list | `@repos.txt "fix all TODOs"` | Read `repos.txt`, one `owner/repo` per line |
| Org-wide | `--org kcenon "fix all TODOs"` | `gh repo list <org> --json nameWithOwner,isArchived --jq '[.[] \| select(.isArchived == false)] \| .[].nameWithOwner'` |

Validation rules:

1. Every repo must resolve to `owner/repo` form. Reject entries without a `/`.
2. Deduplicate repos.
3. Verify each repo exists and the current user has write access: `gh api "repos/{owner}/{repo}" --jq .permissions.push`.
4. Repos failing step 3 are moved to a `pre-excluded` list in the manifest with a reason, not dispatched.
5. The directive must be non-empty. If empty, prompt the user for it (one-shot).
6. If `N > --max-parallel`, workers are launched in waves of `--max-parallel`. Default: 8 (conservative; most Macs handle this comfortably).

### Phase 2: Manifest Initialization

Create `_workspace/fleet/` and write the initial manifest:

```bash
FLEET_ID="fleet-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "_workspace/fleet"
MANIFEST="_workspace/fleet/fleet-status.json"

# Seed the manifest. Use jq to build the structure to guarantee valid JSON.
jq -n \
  --arg fleet_id "$FLEET_ID" \
  --arg started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg directive "$DIRECTIVE" \
  --argjson repos "$REPOS_JSON" \
  '{
     schema_version: "1.0.0",
     fleet_id: $fleet_id,
     started_at: $started_at,
     directive: $directive,
     max_parallel: '$MAX_PARALLEL',
     max_retries: '$MAX_RETRIES',
     workers: ($repos | map({
       repo: .,
       status: "queued",
       started_at: null,
       updated_at: null,
       pr_url: null,
       ci_conclusion: null,
       merge_status: null,
       retry_count: 0,
       error: null,
       phase: "queued"
     })),
     summary: null
   }' > "$MANIFEST"
```

> Full schema: `reference/manifest-schema.json` (JSON Schema Draft 2020-12).
> Changes to the manifest shape must bump `schema_version` in both the seed
> above and the schema file.

### Phase 3: Fan-out Worker Dispatch

Launch workers up to `--max-parallel` at a time. The `Agent` tool with
`run_in_background=true` returns immediately, so all N calls go out in a
single message:

```
For each repo in the first wave (size min(N, MAX_PARALLEL)):
    Agent(
        subagent_type: "general-purpose",
        model: "opus",
        run_in_background: true,
        description: "Fleet worker: <repo>",
        prompt: <render reference/worker-template.md with substitutions>
    )
```

Template substitutions for each worker (load `reference/worker-template.md` and
replace these tokens before passing as `prompt`):

| Token | Value |
|-------|-------|
| `{{REPO}}` | `owner/repo` |
| `{{DIRECTIVE}}` | The full directive text |
| `{{MANIFEST_PATH}}` | Absolute path to `fleet-status.json` |
| `{{MAX_RETRIES}}` | Retry cap for transient CI failures |
| `{{FLEET_ID}}` | For log correlation |

Record each dispatched worker's task ID in a local map so the supervisor can
call `TaskOutput(block=false)` on it when polling.

When a worker finishes and `workers[i].status` becomes `completed` or `failed`,
the supervisor picks the next queued repo and dispatches a new worker (maintains
`--max-parallel` throughput).

### Phase 4: Supervisor Polling Loop

Every `--poll-interval` seconds (default 120):

1. Read the manifest atomically:
   ```bash
   flock -s "$MANIFEST.lock" -c "cat $MANIFEST" | jq .
   ```
2. Render a status table to the user (see the template in **Status Table Rendering** below).
3. For each worker task ID, call `TaskOutput(block=false, timeout=2000)`. If the
   task has exited, reconcile its status in the manifest (belt-and-suspenders:
   the worker should have already written its terminal status).
4. Dispatch a new worker if there is a queued repo and capacity.
5. Terminate the loop when every worker is in `completed` or `failed`.

**Do NOT** use blocking `TaskOutput(block=true)` — it would freeze the supervisor
and prevent monitoring peer workers.

**Stuck-worker detection**: if `updated_at` for any running worker is older than
`10 × poll_interval`, flag it as `stuck` in the rendered table but do not kill
it — the worker may be legitimately running a long build. Escalate to the user
only after `20 × poll_interval` of silence.

### Phase 5: Aggregation and Reporting

Once all workers have terminated:

1. Read the final manifest.
2. Compute the `summary` block:
   ```jsonc
   {
     "total": N,
     "merged": <count status=completed AND merge_status=merged>,
     "draft": <count merge_status=draft>,
     "failed": <count status=failed>,
     "skipped": <count status=skipped>,
     "duration_seconds": <ended_at - started_at>
   }
   ```
3. Write `summary` back to the manifest (flock-guarded).
4. Render the final aggregated report (see **Final Report** below).
5. Do NOT delete `_workspace/fleet/` — keep it for the audit trail.

### Phase 6: Cleanup

- Cancel any still-running background tasks (should be none, but defensive).
- Print the absolute path to `_workspace/fleet/fleet-status.json` so the user
  can inspect it later.
- If any worker ended in `failed` with `error.class == "code-review-needed"`,
  list those repos explicitly for user attention.

## Status Table Rendering

Each poll cycle renders this table (omit workers still in `queued` if the
fleet is large, or cap at 20 rows):

```markdown
## Fleet Status — fleet-20260420-071500

Elapsed: 00:12:34 | Active: 5 / 8 | Queued: 2 | Completed: 6 | Failed: 0

| # | Repo | Phase | PR | CI | Merge | Retries | Last update |
|---|------|-------|-----|-----|-------|---------|-------------|
| 1 | kcenon/repo-a | merged | #89 | success | merged | 0 | 00:11:20 ago |
| 2 | kcenon/repo-b | ci-monitoring | #90 | in_progress | — | 1 | 00:00:42 ago |
| 3 | kcenon/repo-c | implementing | — | — | — | 0 | 00:00:18 ago |
| 4 | kcenon/repo-d | failed | #91 (draft) | failure | — | 3 | 00:03:55 ago |
| 5 | kcenon/repo-e | queued | — | — | — | 0 | — |
```

`Phase` values mirror the worker's state machine (see worker template).

## Final Report

```markdown
## Fleet Execution Report — fleet-20260420-071500

Directive: <short form of the directive>

| Metric | Value |
|--------|-------|
| Repos dispatched | 8 |
| Merged | 6 |
| Draft (awaiting manual review) | 1 |
| Failed | 1 |
| Duration | 00:27:14 |

### Per-Repo Outcomes

| Repo | Result | PR | CI | Notes |
|------|--------|----|-----|-------|
| kcenon/repo-a | merged | https://github.com/kcenon/repo-a/pull/89 | success | — |
| kcenon/repo-b | merged | https://github.com/kcenon/repo-b/pull/90 | success | Retried once (flaky lint) |
| kcenon/repo-c | merged | https://github.com/kcenon/repo-c/pull/41 | success | — |
| kcenon/repo-d | draft | https://github.com/kcenon/repo-d/pull/91 | failure | 3 retries exhausted; user review needed |
| kcenon/repo-e | failed | — | — | Pre-excluded: no push permission |
| ... | ... | ... | ... | ... |

### Action Required

- `kcenon/repo-d` — CI failure after 3 retries. Log: `_workspace/fleet/repo-d/retry-3.log`.

Manifest: `_workspace/fleet/fleet-status.json`
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| One worker crashes without writing terminal status | Supervisor detects exit via `TaskOutput`, writes `{status:"failed", error:{class:"worker-crash"}}` on its behalf |
| Manifest write races | `flock` around every write; readers use `-s` (shared) lock for consistency |
| Transient CI failure (test flake, runner timeout) | Worker retries up to `--max-retries` with exponential backoff (30s, 120s, 300s) |
| Genuine code failure | Worker converts PR to draft, writes `error.class="code-review-needed"`, exits cleanly; supervisor flags in the final report |
| Manifest file corrupted | Fatal error — supervisor halts, prints the last good backup (worker should snapshot to `fleet-status.json.N` after every N writes) |
| Repo pre-flight fails (no push, archived) | Added to `pre-excluded` list in the manifest, never dispatched |
| Supervisor run interrupted mid-fleet | Resume is manual: re-invoke the skill with `--resume <fleet-id>`; it re-reads the manifest and re-launches workers in non-terminal states |

## Test Scenarios

### Normal Flow

1. User invokes with 8 repos and a directive.
2. Phase 1 validates all 8; none are pre-excluded.
3. Phase 2 writes an 8-entry manifest, all queued.
4. Phase 3 dispatches 8 workers in parallel.
5. Phase 4 polls every 120s; workers transition queued → running → completed.
6. One worker retries a flaky CI run, succeeds on retry.
7. Phase 5 aggregates: 8 merged, 0 failed.
8. Final report printed; `_workspace/fleet/` retained.

Expected outcome: manifest shows all 8 with `status="completed"` and `merge_status="merged"`.

### Failure Isolation Flow

1. User invokes with 8 repos.
2. Worker 3 hits a genuine compile error on retry 3.
3. Worker 3 converts its PR to draft, writes `error.class="code-review-needed"`, exits with status `failed`.
4. Workers 1, 2, 4-8 continue unaffected.
5. Phase 5 reports 7 merged, 1 draft-awaiting-review.

Expected outcome: worker 3's failure does not stop peer workers; final report explicitly flags worker 3 for user action.

### Pre-flight Exclusion Flow

1. User invokes with 10 repos; 2 are archived.
2. Phase 1 excludes the 2 archived repos, lists them in the manifest with `pre-excluded: "archived"`.
3. Phase 2-5 operate on the 8 live repos.

Expected outcome: final report lists the 2 pre-excluded repos separately from the 8 dispatched.

## Dependencies and Related Skills

- **`hooks/post-task-checkpoint.sh`** (issue #360 — closed): ensures worker-side
  checkpoints don't overwrite each other. The fleet orchestrator leans on this
  for cross-worker file safety inside `_workspace/`.
- **Atomic Multi-Phase Execution rule** (issue #361 — closed, in `_policy.md`):
  keeps workers from stopping mid-PR for confirmation.
- **`harness`**: the meta-skill that produced this pattern. Fleet orchestrator
  is an instance of Fan-out/Fan-in + Supervisor from `harness/reference/agent-design-patterns.md`.
- **`issue-work`**: the per-repo workflow each worker executes. The worker template
  is a thin wrapper that adds manifest updates around `issue-work`'s Solo mode.
- **`pr-work`**: the retry path when a worker's initial PR fails CI.

## References

- **Worker prompt template**: `reference/worker-template.md` — what each per-repo worker does step-by-step.
- **Manifest schema**: `reference/manifest-schema.json` — the authoritative JSON Schema for `fleet-status.json`.
- **Documentation**: `docs/fleet-orchestrator.md` — user-facing overview, examples, and the "On the Horizon" context that motivated this skill.

## Output Checklist

After a fleet run, confirm:

- [ ] `_workspace/fleet/fleet-status.json` exists and validates against the schema.
- [ ] Every repo has a terminal status (`completed`, `failed`, or `skipped`).
- [ ] `summary` block is populated.
- [ ] Final report matches the manifest counts.
- [ ] Failed repos are called out explicitly for user action.
- [ ] `_workspace/fleet/` is preserved for audit.

## Reanchoring Loop Invariants

`--reanchor-interval N` (default 5, `0` disables) controls how often the Core invariants block from `global/skills/_shared/invariants.md` is emitted during the supervisor's status-polling loop.

Loop bind point: every N manifest-poll cycles. A fleet run covering 20+ repos produces enough accumulated worker outputs that the supervisor's attention drifts from the canonical rules; re-anchoring keeps the English-only, squash-merge, and CI-gate invariants in the recent context when aggregating results and deciding per-repo terminal state.
