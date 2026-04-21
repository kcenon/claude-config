# Loop-Safety Patterns for Skills

Convention for the `loop_safe` frontmatter field in `global/skills/*/SKILL.md`.

> **Loading**: This doc is not auto-loaded. Load with `@load: docs/loop-patterns` when reviewing or classifying skill loop-safety.

## Why This Flag Exists

The harness-level `/loop` skill wraps any command in a polling or self-pacing loop. A naive user running `/loop issue-work` would create a new PR on every iteration; `/loop release` would attempt to cut a new tag each cycle. `loop_safe` makes this safety property explicit in skill metadata so the `/loop` harness can refuse — or warn on — skills that are not idempotent.

## Rules

1. **Default to `loop_safe: false`.** Only mark `true` when you have actively reasoned that repeated invocation produces no external artifacts and no destructive cascade.
2. **External artifacts = not loop-safe.** Creates issues, PRs, releases, tags, comments, branches, or destroys resources → `false`.
3. **Retry is the mechanism → safe.** If the skill's happy path already involves retrying the same action (e.g., `ci-fix` re-pushes a codified fix until CI is green), it is already self-deduplicating and belongs in `true`.
4. **Read-only or synthesis → safe.** Skills that only read files, run searches, produce reports, or rebuild deterministic outputs from unchanged inputs (doc indexes, review reports, preflight checks) → `true`.
5. **When in doubt, mark `false`.** False is the safe default; upgrading to `true` is an explicit reasoning step documented in the skill body.

## Examples

### Example 1 — `loop_safe: true` (research)

```yaml
name: research
loop_safe: true
```

**Why**: Each run writes a report file. A second run with the same topic either overwrites the same report (idempotent) or produces a new report file with a timestamped name (no cascade). No external services mutated. No GitHub state changed. Wrapping `/loop research "topic X"` produces repeated refreshes of the same topic — wasteful, but not destructive.

### Example 2 — `loop_safe: false` (issue-work)

```yaml
name: issue-work
loop_safe: false
```

**Why**: Each run creates a branch, commits, opens a PR, monitors CI, merges, and closes an issue. Repeated invocation on the same issue would fail fast (issue already closed), but invocation inside `/loop` with auto-issue-selection would continuously chew through the backlog without a user in the loop — creating PRs and merging them with no oversight. Destructive in aggregate.

### Example 3 — `loop_safe: true` (ci-fix)

```yaml
name: ci-fix
loop_safe: true
```

**Why**: `ci-fix` classifies a failing workflow into one of three patterns and pushes a codified remediation. If the fix succeeds, subsequent invocations find no failing runs and halt (safe). If the fix fails, re-classification either picks a different pattern (also safe — each fix is a distinct commit, not a duplicate) or escalates to the user. The skill's entire contract assumes retry is natural; wrapping it in `/loop` simply automates the retry cadence.

## Anti-Patterns

### Anti-Pattern 1 — "It's mostly read-only"

A skill reads 100 files and writes 1 summary file. The 1% write is enough to make it `loop_safe: false` if that write target is shared state (e.g., a report committed to the repo). Only mark `true` when writes are to throwaway locations or are deterministic re-computations.

### Anti-Pattern 2 — "Retry inside the skill, so /loop is also fine"

Self-retry inside a skill handles transient failures during one invocation. It does NOT imply safety under external looping. Example: `pr-work` retries CI up to 3 times per run, but `/loop pr-work` would re-attempt merges on a merged PR (noisy at best, forced re-merge at worst). `loop_safe: false`.

### Anti-Pattern 3 — "The happy path is idempotent"

Idempotence under the happy path is not sufficient. Consider failure modes: partial state, interruption mid-run, concurrent invocation. A skill that leaves a branch pushed but not merged after a failure is not loop-safe — the second invocation would see the branch, possibly re-push on top of it, and create a divergent history.

## Classification Summary

Current `global/skills/` state:

| `loop_safe: true` | `loop_safe: false` |
|-------------------|---------------------|
| `ci-fix` | `branch-cleanup` |
| `doc-index` | `fleet-orchestrator` |
| `doc-review` | `harness` |
| `preflight` | `implement-all-levels` |
| `research` | `issue-create` |
|  | `issue-work` |
|  | `pr-work` |
|  | `release` |

5 safe, 8 not-safe. When adding a new skill, update this table.

## Related

- Schema: `global/skills/_policy.md` § Loop-Safety Flag
- Iteration control: `global/skills/_policy.md` § Iteration Control Schema
- Shared invariants for long loops: `global/skills/_shared/invariants.md`
