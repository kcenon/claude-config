# Team Mode Instructions

Complete team mode workflow with 3-team architecture (dev, reviewer, doc-writer),
feedback loops, CI failure handling, fallback procedures, and cleanup.

---

Three-team workflow with feedback loop: Development team implements, Review team validates
and manages PR, Documentation team updates docs. The review team drives a cyclic feedback
loop — sending change requests back to the dev team until quality gates pass.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Phase control │
         │ CI monitoring │
         │ Merge decision│
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│ Dev  │◄──│Review│   │ Doc  │
│ Team │──►│ Team │   │ Team │
└──────┘   └──────┘   └──────┘
  dev     reviewer    doc-writer

  Dev ──► Review: "Implementation done, ready for review"
  Review ──► Dev: "Change requests: [list]"  (feedback loop)
  Dev ──► Doc: "Implementation scope: [files]"
  Review ──► Lead: "Approved, ready for PR"
```

### T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-4 (Issue Selection, Size Evaluation, Git Setup, Assignment).
These steps require sequential execution and must complete before parallelization.

Prepare shared context for all teammates:
- `$ORG`, `$PROJECT`, `$ISSUE_NUMBER`, `$BRANCH_NAME`, `$BRANCH_TYPE`
- Issue body and acceptance criteria (fetched via `gh issue view`)

### T-2. Create Team and Tasks

```
TeamCreate(team_name="issue-$ISSUE_NUMBER", description="Implement #$ISSUE_NUMBER in $ORG/$PROJECT")
```

Create tasks with dependencies:

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Analyze codebase and plan implementation | dev | — | A |
| 2 | Analyze issue requirements and define review criteria | reviewer | — | A |
| 3 | Implement code changes | dev | 1 | B |
| 4 | Write/update tests for implementation | dev | 3 | B |
| 5 | Build and verify all tests pass locally | dev | 4 | B |
| 6 | Review: gap analysis (issue vs implementation) | reviewer | 2, 5 | C |
| 7 | Review: code quality, security, performance | reviewer | 5 | C |
| 8 | Update documentation (README, API docs, CHANGELOG) | doc-writer | 5 | C |
| 9 | Apply review change requests (if any) | dev | 6, 7 | D |
| 10 | Re-review after changes (if Task 9 was needed) | reviewer | 9 | D |
| 11 | Push, create PR, and post review summary | reviewer | 8, 10 | E |
| 12 | Monitor CI and merge | lead | 11 | E |

**Key dependency flow:**
- Phase A: Dev analyzes code ∥ Reviewer analyzes issue (parallel)
- Phase B: Dev implements + tests + verifies (sequential within dev)
- Phase C: Reviewer reviews ∥ Doc-writer updates docs (parallel, both after dev)
- Phase D: Dev fixes review findings → Reviewer re-reviews (feedback loop)
- Phase E: Reviewer creates PR → Lead monitors CI and merges

### T-3. Spawn Teammates

**Dev Team** (implementation + fixes):

```
Agent(
  name="dev",
  team_name="issue-$ISSUE_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the development team for issue #$ISSUE_NUMBER in $ORG/$PROJECT.
    Branch: $BRANCH_NAME
    Repository: https://github.com/$ORG/$PROJECT

    Your responsibilities:
    1. Task 1: Analyze the existing codebase — check code style (.clang-format,
       .editorconfig), file patterns, and conventions. Plan implementation approach.
    2. Task 3: Implement the code changes following existing style strictly.
       Keep changes minimal and focused on the issue requirements.
    3. Task 4: Write or update tests for your implementation.
       Follow existing test patterns and frameworks in the project.
    4. Task 5: Run the complete build and test suite. Verify all tests pass.
    5. Task 9: If the reviewer sends change requests, apply the requested fixes.
       Each fix should be a separate commit referencing the review finding.

    Rules:
    - Validate incrementally: build after each logical change
    - Follow existing code style strictly
    - Commit format: type(scope): description (English only, no emojis)
    - No Claude/AI references in commits
    - When Task 5 is done, send a message to reviewer:
      'Implementation complete. Files changed: [list]. Ready for review.'

    Build verification strategy:
    - < 30s builds: run inline (synchronous)
    - 30s+ builds: run in background with log polling
    If toolchain is unavailable locally, report what needs CI verification.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (gap analysis + code review + PR management):

```
Agent(
  name="reviewer",
  team_name="issue-$ISSUE_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the review team for issue #$ISSUE_NUMBER in $ORG/$PROJECT.
    Branch: $BRANCH_NAME
    Repository: https://github.com/$ORG/$PROJECT

    Your responsibilities:
    1. Task 2: Read the issue requirements and acceptance criteria thoroughly.
       Define a review checklist: what must be true for this issue to be 'done'.
       Identify edge cases and potential gaps.
    2. Task 6 (Gap Analysis): After dev completes, compare the implementation
       against the original issue requirements:
       - Are all acceptance criteria met?
       - Are there missing edge cases?
       - Does the implementation scope match the issue scope (no over/under-engineering)?
    3. Task 7 (Code Review): Review the changed code for:
       - Code quality: DRY, SOLID, readability
       - Security: OWASP top 10, input validation
       - Performance: algorithm efficiency, N+1 queries, memory leaks
       - Existing code impact: does the change break existing behavior?
       Classify findings: Critical / Major / Minor / Info
    4. Task 10 (Re-review): If change requests were sent to dev (Task 9),
       verify the fixes address each finding. Only approve when all Critical
       and Major findings are resolved.
    5. Task 11 (PR Creation): When approved, create the PR:
       - Push: git push -u origin $BRANCH_NAME
       - Create PR with Closes #$ISSUE_NUMBER
       - PR body: include review summary, all findings and their resolution
       - English only, no AI references

    Feedback loop rules:
    - If findings exist, send change requests to dev via SendMessage:
      'Change requests: 1. [finding + expected fix] 2. [finding + expected fix]'
    - Then create Task 9 for dev with the change request details
    - Max 2 review rounds. After 2 rounds, approve with remaining Minor items
      noted in the PR description.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (doc updates):

```
Agent(
  name="doc-writer",
  team_name="issue-$ISSUE_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the documentation team for issue #$ISSUE_NUMBER in $ORG/$PROJECT.
    Branch: $BRANCH_NAME
    Repository: https://github.com/$ORG/$PROJECT

    Your responsibilities:
    1. Task 8: After dev completes implementation (Task 5), update documentation:
       - README.md: if new features, CLI flags, or configuration added
       - API documentation: if endpoints or interfaces changed
       - CHANGELOG.md: add entry under 'Unreleased' section
       - Code comments: for complex logic in changed files only
       - Architecture docs: if structural changes were made

    Rules:
    - Only update docs that are affected by the implementation
    - Do not create new documentation files unless necessary
    - Match existing documentation style and structure
    - Commit format: docs(scope): description (English only, no emojis)
    - No Claude/AI references in commits

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

### T-4. Workflow Phases (Lead coordinates)

Lead monitors progress via `TaskList` and orchestrates the phases:

**Phase A — Parallel Analysis:**
1. Dev analyzes codebase (Task 1) ∥ Reviewer analyzes issue requirements (Task 2)
2. These run simultaneously — no dependency between them

**Phase B — Implementation (Dev):**
1. Wait for Task 1 to complete
2. Dev implements code (Task 3) → writes tests (Task 4) → verifies (Task 5)
3. When Task 5 completes, dev sends implementation summary to reviewer

**Phase C — Review + Documentation (parallel):**
1. Wait for Task 5 to complete
2. Reviewer executes gap analysis (Task 6) and code review (Task 7) — can be parallel or sequential
3. Doc-writer updates documentation (Task 8) — runs in parallel with review
4. Reviewer classifies findings and decides: approve or request changes

**Phase D — Feedback Loop (if needed):**

```
Reviewer has findings?
  │
  ├─ No Critical/Major → Approve (skip Task 9, 10)
  │                       Minor items noted in PR description
  │
  └─ Has Critical/Major → Send change requests to dev
                           │
                           ▼
                    Dev applies fixes (Task 9)
                           │
                           ▼
                    Reviewer re-reviews (Task 10)
                           │
                    ┌──────┴──────┐
                    │             │
                 Approved    Still issues?
                    │        (max 2 rounds,
                    ▼         then approve
                 Task 11      with notes)
```

- Max 2 review rounds to prevent infinite loops
- After round 2, reviewer approves with remaining Minor items documented in PR

**Phase E — PR and Merge:**
1. Reviewer creates PR (Task 11) with full review summary
2. Lead monitors CI (Task 12): non-blocking polling, 30s intervals, 10min max
3. On all checks pass: `gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash --delete-branch`
4. Close related issues and epics (Steps 11-12 from Solo Mode)
5. Post implementation comment to issue

### T-5. CI Failure Handling

If CI fails after PR creation:

1. Lead analyzes CI logs: `gh run view <RUN_ID> --repo $ORG/$PROJECT --log-failed`
2. Create fix task for dev: "Fix CI failure: [error description]"
3. After dev fixes, reviewer does a quick re-review of the CI fix only
4. Lead pushes and re-monitors CI
5. Max 3 CI fix attempts (same as Solo Mode). After 3: escalate.

### T-6. Cleanup

```
# Shutdown all teammates
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})

# Delete team
TeamDelete()
```

### T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Assess what was completed:
   - If implementation is done but review didn't start → offer Solo continuation from Step 8 (PR)
   - If review found issues but dev didn't fix → report findings, offer Solo fix
   - If nothing meaningful completed → offer full Solo restart from Step 5
3. Preserve all commits made by teammates on the branch
