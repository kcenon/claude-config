## What

Apply two meta-principles to the claude-config **harness layer** (the content that every session loads regardless of task):

1. **Thin harness, fat skills** — `global/CLAUDE.md` becomes a routing index; procedural rules live in `rules/**/*.md` and `skills/**/SKILL.md`.
2. **Self-improvement audit** — mechanize the first principle so regressions are detected automatically, reusing existing tooling rather than forking a new one.

This is a sibling epic to #398 at a different layer. #398 optimizes skill-internal token usage (tier presets, halt conditions, input injection). This epic optimizes the always-on harness that wraps every session.

## Why

Measurement of the current harness:

- `global/CLAUDE.md`: 70 lines, ~50 of which (~71%) are concrete procedural rules, not routing.
- `project/CLAUDE.md`: 55 lines, pure routing index — already conformant (target shape).
- `enterprise/CLAUDE.md`: 5 lines — already conformant.
- Several `global/CLAUDE.md` sections duplicate content that already has dedicated files (`docs/SANDBOX_TLS.md`, `rules/workflow/build-verification.md`, `rules/workflow/git-conflict-resolution.md`, `skills/pr-work`, `skills/issue-work`, `skills/release`, `skills/branch-cleanup`).
- These duplicated paragraphs load in every session regardless of whether the topic is relevant, inflating always-on token cost.
- #401 introduced tier presets at the skill level. The analogous mechanism at the harness level is "routing-only + always-on invariants block".
- `scripts/validate_skills.sh` (342 lines) already implements validation infrastructure. A new audit invariant should extend it, not duplicate it.

Expected outcome: ≥ 30% reduction in session-start token cost, enforced by automation so the reduction sticks.

## Who

- Owner: @kcenon
- Reviewers: harness / skill-system maintainers

## When

- phase-1 (1–2 days): #437 slim `global/CLAUDE.md`
- phase-2 (1 week): #438 extend `validate_skills.sh`
- phase-3 (deferred): optional self-improvement skill once phase-1/2 validate the patterns. Not filed yet.

No hard deadline.

## Where

- `global/CLAUDE.md`
- `global/skills/_shared/invariants.md` (possible reuse for the always-on block)
- `scripts/validate_skills.sh` and `.ps1` (extend)
- `bootstrap.sh`, `bootstrap.ps1`, `scripts/sync.sh`, `scripts/sync.ps1` (wiring)
- `docs/TOKEN_OPTIMIZATION.md` (document before/after and threshold rationale)

## How

### Sub-issues

- [x] #437 — slim `global/CLAUDE.md` to routing-only + always-on invariants block (phase-1) — merged via #440
- [x] #438 — extend `validate_skills.sh` to audit CLAUDE.md routing invariant and skill frontmatter drift (phase-2a, bash) — merged via #441
- [x] #442 — mirror the audit in `validate_skills.ps1` (phase-2b, PowerShell) — merged via #443

### Acceptance Criteria

- [ ] `global/CLAUDE.md` body ≤ 30 lines; always-on invariants block ≤ 12 lines.
- [ ] Every removed paragraph has a verified equivalent elsewhere, documented in the phase-1 PR.
- [ ] Extended audit runs in bootstrap, sync, and a CI workflow; regressions fail the audit.
- [ ] `docs/TOKEN_OPTIMIZATION.md` captures before/after token counts and the threshold knobs.
- [ ] Phase-3 explicitly deferred, merged, or withdrawn with reason recorded in this epic.

### Non-goals

- Do not modify `project/CLAUDE.md` or `enterprise/CLAUDE.md` (already conformant).
- Do not create a new audit script; extend `validate_skills.sh`.
- Do not restructure skills (that belongs to #398 and its sub-issues).

## Related

- Sibling of #398 (skills layer); complementary not overlapping.
- Builds on #401 (tier presets) — same "declare the contract, then validate" pattern.
- Builds on #400 (input injection) and #403 (loop_safe) — same drift-prevention motivation.
