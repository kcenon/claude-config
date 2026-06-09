# Sub-agent assignment policy

For each of the 29 child issues in the memory-sync EPIC (#505), this document
records which sub-agent type is responsible for the implementation work, plus
the review pass that runs before merge.

## Available sub-agent types

| Type | Capabilities | Used here for |
|---|---|---|
| `documentation-writer` | Read, Write, Edit, Glob | Spec docs, runbooks |
| `test-strategist` | Read, Grep, Glob, Bash, Write, Edit | Test fixture design + runner |
| `general-purpose` | All tools | Code implementation |
| `code-reviewer` | Read, Grep, Glob, Bash, Write, Edit | Review pass |
| `qa-reviewer` | Read, Grep, Glob, Bash, Write, Edit | Cross-boundary contract checks |
| (manual) | — | User-driven work, no agent |

## Assignment rules

1. **type/docs** → `documentation-writer` for spec/runbook authoring
2. **type/test** → `test-strategist` for fixture design and test runner
3. **type/feature** + code → `general-purpose` (needs full Edit/Write/Bash)
4. **type/chore** that is code → `general-purpose`
5. **type/ci** → `general-purpose` (workflow YAML + branch protection)
6. **chore** that requires user judgment → manual (no agent)
7. **observation/test** that requires real machines → manual

## Review pass

Every PR opened by a sub-agent gets a **`code-reviewer` pass** before merge:
- Read the diff, check for security issues, regressions, style fit
- Write findings as a PR comment
- User decides on merge

For PRs that integrate multiple components (D1, F1, G3): also run **`qa-reviewer`**
to verify cross-boundary contracts (sync ↔ validators, audit ↔ trust model).

## Per-task mapping

| Task | Issue | Type | Implementation agent | Review agent |
|---|---|---|---|---|
| #1 A1 | #506 | docs | `documentation-writer` | `code-reviewer` |
| #2 A2 | #507 | feature | `general-purpose` | `code-reviewer` |
| #3 A3 | #508 | feature | `general-purpose` | `code-reviewer` |
| #4 A4 | #509 | feature | `general-purpose` | `code-reviewer` |
| #5 A5 | #510 | test | `test-strategist` | `qa-reviewer` |
| #6 B1 | #511 | docs | `documentation-writer` | `code-reviewer` |
| #7 B2 | #512 | feature | `general-purpose` | `code-reviewer` |
| #8 B3 | #513 | chore | **manual** (user judgment) | — |
| #9 B4 | #514 | feature | `general-purpose` | `code-reviewer` |
| #10 C1 | #515 | chore | `general-purpose` | `code-reviewer` |
| #11 C2 | #516 | feature | `general-purpose` | `code-reviewer` |
| #12 C3 | #517 | feature | `general-purpose` | `code-reviewer` |
| #13 C4 | #518 | chore | `general-purpose` | `code-reviewer` |
| #14 C5 | #519 | ci | `general-purpose` | `code-reviewer` |
| #15 D1 | #520 | feature | `general-purpose` | `code-reviewer` + `qa-reviewer` |
| #16 D2 | #521 | feature | `general-purpose` | `code-reviewer` |
| #17 D3 | #522 | feature | `general-purpose` | `code-reviewer` |
| #18 D4 | #523 | feature | `general-purpose` | `code-reviewer` |
| #19 D5 | #524 | feature | `general-purpose` | `code-reviewer` |
| #20 E1 | #525 | docs | `documentation-writer` | `code-reviewer` |
| #21 E2 | #526 | chore | **manual** (7-day observation) | — |
| #22 E3 | #527 | feature | `general-purpose` | `code-reviewer` |
| #23 F1 | #528 | feature | `general-purpose` | `code-reviewer` + `qa-reviewer` |
| #24 F2 | #529 | feature | `general-purpose` | `code-reviewer` |
| #25 F3 | #530 | feature | `general-purpose` | `code-reviewer` |
| #26 F4 | #531 | feature | `general-purpose` | `code-reviewer` |
| #27 G1 | #532 | docs | `documentation-writer` | `code-reviewer` |
| #28 G2 | #533 | test | **manual** (real machines) | — |
| #29 G3 | #534 | docs | `documentation-writer` | `code-reviewer` + `qa-reviewer` |

## Summary by agent

| Agent | Tasks |
|---|---|
| `documentation-writer` | #1, #6, #20, #27, #29 (5) |
| `test-strategist` | #5 (1) |
| `general-purpose` | 20 tasks |
| **manual** | #8, #21, #28 (3) |

## Workflow per task

1. **Spawn sub-agent** with the task's source markdown as context
2. **Sub-agent creates a feature branch** off `develop`: `feat/memory-XX-<topic>`
3. **Sub-agent commits + pushes + opens PR** against `develop`, links to GitHub issue
4. **Review pass**: spawn the review agent against the PR diff
5. **User decides merge** based on review report
6. **On merge**: TaskUpdate status=completed; dependent tasks unblock

## Sub-agent prompt template

When spawning, the prompt provides:
- Path to the source issue file (e.g., `scripts/memory-sync-issues/issues/A1-spec-correction.md`)
- Path to the spec/dependency files needed
- The expected deliverable
- Instruction to commit + push + open PR (NOT to merge)

Example:
```
Read scripts/memory-sync-issues/issues/A1-spec-correction.md fully.
Author docs/MEMORY_VALIDATION_SPEC.md per the issue's Acceptance Criteria.
The four corrections from the baseline report are documented in
/tmp/claude/memory-validation/baseline/REPORT.md §3 — incorporate them.
After authoring:
  1. Create branch feat/memory-A1-validation-spec off develop
  2. Commit with conventional-commit message
  3. Push and open PR against develop, linking to issue #506
Do NOT merge the PR. Report the PR URL when done.
```

## Versioning

v1.0 — initial policy after EPIC #505 registration (2026-05-01)
