# Global Command Policies

## Atomic Multi-Phase Execution

When a user specifies multiple phases — "Phase 1/2/3", "up to Phase N", "until all are created", or similar multi-step directives — treat the full plan as a single atomic unit.

- Complete ALL phases before returning control to the user
- Do NOT pause between phases for mid-plan confirmation
- Do NOT ask "shall I continue?" between phases — the user already said yes by specifying the plan
- Only stop early if a real blocker is encountered: missing file, auth error, destructive-action confirmation, or genuinely ambiguous requirement. State the blocker explicitly and wait for resolution
- Progress updates between phases are fine; confirmation prompts are not

This rule exists because long multi-phase requests otherwise incur repeated "continue" prompts as the model pauses mid-plan for phantom confirmation. The user's original plan specification is the only confirmation needed.

## Common Rules

- Git/GitHub output (commits, PRs, issues, release notes): English
- No emojis in commits, PR titles, issue titles
- Commit format: Conventional Commits (`type(scope): description`)
- Use closing keywords (`Closes #N`) in PR descriptions when applicable
- All builds must pass before PR; all CI checks must pass before merge. Verify with `gh pr checks` — never merge when any check shows fail, pending, cancelled, or timed_out. Never rationalize failures as "unrelated" or "pre-existing"
- See `rules/workflow/build-verification.md` for verification patterns
- Batch processing: 2-second pause between items, 0.3-second pause between API calls during discovery
- Batch mode: max 200 repos for cross-repo discovery, max 100 items per repo
- Batch failure: continue to next item on failure, present summary at end

## Iteration Control Schema

Skills that perform iterative work (retry loops, polling loops, multi-round refinement) declare halting semantics in their frontmatter. This elevates the prose rule "if the same approach fails 3 times, stop and propose alternatives" (`global/CLAUDE.md`) to machine-readable, per-skill metadata.

```yaml
max_iterations: <int>          # Hard upper bound on loop iterations
halt_condition: "<expression>" # Legacy: natural language or regex describing success/abort signal
halt_conditions:               # Preferred: structured form (array of {type, expr}); string form also accepted in P1 grace period
  - { type: success, expr: "<expression>" }
  - { type: limit,   expr: "<expression>" }
on_halt: "<action>"            # What to do when a halt condition fires (report, escalate, exit)
```

Required for skills whose body contains a polling loop, retry loop, or multi-round iteration (`issue-work`, `pr-work`, `ci-fix`, `release`, `research`, `fleet-orchestrator`). Optional otherwise.

Prefer regex or symbolic halt conditions over free-form prose when the signal is deterministic (CI status, exit codes). Reserve natural language for cases where interpretation is intrinsically subjective.

`halt_condition` (singular, string) is the legacy key. `halt_conditions` (plural) is the structured replacement: array entries are `{type, expr}` where `type ∈ [success, failure, limit, user, fallback]`. Both keys validate during the P1 grace period; A2/A3 will migrate skills and tighten enforcement.

## Loop-Safety Flag

Every skill declares whether repeated invocation is idempotent — i.e., wrapping it in the harness `/loop` skill would not duplicate external artifacts, spam services, or corrupt state.

```yaml
loop_safe: true | false
```

- `loop_safe: true` — invocations are idempotent, read-only, or self-deduplicating. Safe to wrap in `/loop`. Examples: `research`, `ci-fix` (retry is the mechanism), `doc-index`, `doc-review`, `preflight`.
- `loop_safe: false` — invocations create external artifacts (PRs, issues, releases, branch deletions) or mutate shared state. Wrapping in `/loop` would produce duplicates or destructive cascades. Examples: `issue-work`, `pr-work`, `release`, `branch-cleanup`, `issue-create`, `harness`, `implement-all-levels`, `fleet-orchestrator`.

Rules and anti-patterns: `docs/loop-patterns.md`.

## Workspace Layout

Skills that produce per-invocation artifacts write them to a workspace directory using a numeric phase prefix so the filesystem reflects pipeline order:

```
_workspace/{date}-{n}/NN_<phase>.<ext>
```

- `{date}` — invocation date in `YYYY-MM-DD` form.
- `{n}` — 1-based ordinal for invocations in the same day.
- `NN_` — 2-digit zero-padded phase index (`00_`, `01_`, …, `99_`). The leading zero keeps lexical order aligned with execution order.
- `<phase>` — lowercase snake_case phase name (e.g. `discovery`, `plan`, `implement`, `review`).
- `<ext>` — artifact extension (`md`, `json`, `txt`, `log`, …).

Examples:

```
_workspace/2026-04-26-1/00_discovery.md
_workspace/2026-04-26-1/01_plan.md
_workspace/2026-04-26-1/02_implement.log
_workspace/2026-04-26-1/03_review.md
```

The last `NN_*.ext` file in a workspace is the immediate halt-trace anchor: combined with `halt_conditions` (P1), it pinpoints where iteration stopped and why. Existing artifacts are point-forward only — no migration is required for prior workspaces.

`scripts/check_workspace_prefix.sh` enforces the convention: non-conforming files emit warnings (not failures) during the rollout.

## Severity

Code-review domain skills declare severity in their frontmatter so triage can be automated. Free-form prose previously produced inconsistent merge-block thresholds; the enum collapses that ambiguity.

```yaml
severity: S1 | S2 | S3              # Primary tier this skill triages at
finding_levels: [S1, S2, S3]        # Subset of levels this skill emits findings at
```

| Tier | Meaning | Effect on PR |
|------|---------|--------------|
| `S1` | Block-merge | Reviewer must resolve before merge — no exceptions |
| `S2` | Review-required | Reviewer attention requested; can be acknowledged-and-deferred |
| `S3` | Advisory | Informational only; no action required |

Both fields are optional and apply to code-review domain skills only (e.g. `code-quality`, `security-audit`, `pr-review`). `doc-review` and `release` are explicitly out of scope — they describe gates, not findings, and would create category errors.

`finding_levels` lists every level the skill may surface. A skill with `severity: S2` and `finding_levels: [S1, S2]` triages at S2 by default but can escalate individual findings to S1.

## Tier Preset Schema

Skills whose `SKILL.md` body exceeds 5 KB declare tier presets in their frontmatter so callers can load the skill at a depth that matches the task. The schema exposes three tiers — `light`, `standard`, `deep` — each mapping to a list of reference documents and optional flags that shape runtime behavior.

```yaml
tiers:
  light:
    ref_docs: []              # Minimal context; load only SKILL.md body
    deep_checks: false        # Skip expensive validation passes
    max_files: <int>          # Optional cap on files fetched/inspected
  standard:
    ref_docs: [core]          # Baseline reference set for typical invocations
    deep_checks: false
    max_files: <int>
  deep:
    ref_docs: [core, advanced] # Full reference set for thorough workflows
    deep_checks: true          # Enable exhaustive checks
    max_files: <int>
default_tier: standard        # Tier used when caller omits --tier
```

- `ref_docs` — keys referencing `reference/*.md` files already shipped with the skill. Keys are skill-defined aliases (`core`, `advanced`, `batch`, `team`, etc.) resolved against the skill's own `reference/` directory.
- `deep_checks` — opt-in flag for deeper verification passes (extra lint, full build, integrity checks). Skills that do not distinguish cheap vs expensive passes may omit this field.
- `max_files` — advisory cap on the number of files the skill should enumerate or modify in a single invocation. Omit when the skill is naturally scoped.
- `default_tier` — the tier applied when the caller does not pass `--tier`. Defaults to `standard` unless the skill documents otherwise.

### When to Apply

Required for skills whose `SKILL.md` body exceeds 5 KB (current examples: `issue-work`, `pr-work`). Optional for smaller skills, where a single loading mode suffices.

### Invocation

Callers select a tier with a command-line flag passthrough:

```
/<skill> --tier=light|standard|deep [other args]
```

When `--tier` is omitted, the skill runs at its declared `default_tier`. Unknown tier values fall back to `default_tier` with a warning.

### Cross-reference

See `docs/TOKEN_OPTIMIZATION.md` for token-impact figures and empirical guidance on when each tier is appropriate.
