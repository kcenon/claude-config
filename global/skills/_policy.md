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
halt_condition: "<expression>" # Natural language or regex describing success/abort signal
on_halt: "<action>"            # What to do when halt condition fires (report, escalate, exit)
```

Required for skills whose body contains a polling loop, retry loop, or multi-round iteration (`issue-work`, `pr-work`, `ci-fix`, `release`, `research`, `fleet-orchestrator`). Optional otherwise.

Prefer regex or symbolic halt conditions over free-form prose when the signal is deterministic (CI status, exit codes). Reserve natural language for cases where interpretation is intrinsically subjective.

## Loop-Safety Flag

Every skill declares whether repeated invocation is idempotent — i.e., wrapping it in the harness `/loop` skill would not duplicate external artifacts, spam services, or corrupt state.

```yaml
loop_safe: true | false
```

- `loop_safe: true` — invocations are idempotent, read-only, or self-deduplicating. Safe to wrap in `/loop`. Examples: `research`, `ci-fix` (retry is the mechanism), `doc-index`, `doc-review`, `preflight`.
- `loop_safe: false` — invocations create external artifacts (PRs, issues, releases, branch deletions) or mutate shared state. Wrapping in `/loop` would produce duplicates or destructive cascades. Examples: `issue-work`, `pr-work`, `release`, `branch-cleanup`, `issue-create`, `harness`, `implement-all-levels`, `fleet-orchestrator`.

Rules and anti-patterns: `docs/loop-patterns.md`.
