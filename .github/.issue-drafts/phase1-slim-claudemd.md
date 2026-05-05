## What

Refactor `global/CLAUDE.md` to match the shape of `project/CLAUDE.md` (55 lines, pure routing index) and `enterprise/CLAUDE.md` (5 lines): keep only a routing index plus a small always-on invariants block.

Scope: only `global/CLAUDE.md`. Do not touch `project/CLAUDE.md` (already conformant) or `enterprise/CLAUDE.md`.

## Why

Current `global/CLAUDE.md` measurement:

- 70 lines total; ~50 lines (~71%) are concrete procedural rules, not routing.
- Several sections duplicate content that already has dedicated files, meaning they load on every session regardless of whether the topic is relevant:

| Current section | Already present in |
|-----------------|-------------------|
| `gh CLI Sandbox Policy` (7 lines) | `docs/SANDBOX_TLS.md` §gh Caveat |
| `GitHub / CI` CI polling details (~11 lines) | `skills/pr-work/SKILL.md` |
| `Build & Test` (4 lines) | `rules/workflow/build-verification.md` |
| `Standard Workflows` (~10 lines) | `skills/issue-work`, `skills/pr-work`, `skills/release`, `skills/branch-cleanup` |
| Merge conflict rules (3 lines) | `rules/workflow/git-conflict-resolution.md` |

`project/CLAUDE.md` and `enterprise/CLAUDE.md` already demonstrate the target shape. After skill-layer work (#401 tier presets, #400 input injection) landed, the harness layer is the remaining always-on surface to trim.

## Who

- Owner: @kcenon
- Reviewers: harness / skill-system maintainers

## When

phase-1 of the harness-optimization epic (filed separately in this sub-issue's sibling).

## Where

- `global/CLAUDE.md` (rewrite)
- `global/skills/_shared/invariants.md` (possible reuse for the always-on block)
- No new rule files required; all targets already exist.

## How

### Technical Approach

1. Identify always-on guardrails that genuinely govern cross-cutting behavior and cannot be moved to on-demand skills. Keep these in `global/CLAUDE.md` as a compact block:
   - 3-fail rule (stop and propose alternatives)
   - AI attribution / emoji policy (commit, PR, issue)
   - Protected-branch direct-push ban (`main`, `develop`)
   - CI gate definition ("task is NOT complete if CI has any failure")
   - Auto-restart batch semantics (1-line pointer to skill)
2. Replace the remaining procedural sections with routing entries that point to the existing rule file or skill.
3. For each removed paragraph, verify in the PR description that a living equivalent exists in the target file.

### Acceptance Criteria

- [ ] `global/CLAUDE.md` body is ≤ 30 lines (excluding frontmatter / version footer).
- [ ] Always-on invariants block is ≤ 12 lines.
- [ ] PR description includes a verification table: `removed paragraph → target file/line`.
- [ ] Session-start token count drops by at least 30% compared to pre-refactor baseline (capture before/after in PR).
- [ ] No rule or workflow is silently dropped (spot-check by running `scripts/sync.sh` on a test directory and confirming the referenced files resolve).

### Non-goals

- Do not modify `project/CLAUDE.md` or `enterprise/CLAUDE.md`.
- Do not rename or move rule files; only update routing pointers.
- Do not introduce new skills; reuse existing ones.

## Related

- Part of #439 (harness-optimization epic).
- Builds on #401 (tier presets) and #400 (input injection) — same motivation at a different layer.
- Complements #398 (skills-layer optimization).
