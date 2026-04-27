# Team Mode Instructions

Three-team workflow with feedback loop for CI/CD failure resolution. Dev team fixes code, Review team validates fixes and manages PR, Doc team updates documentation if behavior changes.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

## Team Architecture

```
         Lead (Coordinator)
         +--------------+
         | CI monitoring |
         | Merge decision|
         +------+-------+
                |
   +------------+------------+
   v            v            v
+------+   +------+   +------+
| Dev  |<--+Review|   | Doc  |
| Team +-->| Team |   | Team |
+------+   +------+   +------+
  dev     reviewer    doc-writer

  Review --> Dev: "Fix validated, but also fix [issue]" (feedback loop)
  Dev --> Review: "Fix applied, ready for re-review"
  Review --> Lead: "All fixes validated, ready for merge"
```

## T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (PR Information Retrieval, Failed Workflow Analysis).
Collect the list of failed workflows and their error categories.

Prepare shared context for all teammates:
- `$ORG`, `$PROJECT`, `$PR_NUMBER`, `$HEAD_BRANCH`
- Failed workflow names and error summaries

## T-2. Create Team and Tasks

```
TeamCreate(team_name="pr-fix-$PR_NUMBER", description="Fix CI failures for PR #$PR_NUMBER")
```

Create tasks with dependencies:

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Analyze all failed workflows and categorize errors | reviewer | -- | A |
| 2 | Post failure analysis comment to PR | reviewer | 1 | A |
| 3 | Fix identified issues (attempt 1) | dev | 1 | B |
| 4 | Verify fix locally (build + test) | dev | 3 | B |
| 5 | Review: validate fix correctness and completeness | reviewer | 4 | C |
| 6 | Update docs/comments if fix changes behavior | doc-writer | 4 | C |
| 7 | Apply review change requests (if any) | dev | 5 | D |
| 8 | Re-review after changes (if Task 7 was needed) | reviewer | 7 | D |
| 9 | Push and monitor CI | lead | 5 or 8, 6 | E |

## T-3. Spawn Teammates

**Dev Team** (code fixing):

```
Agent(
  name="dev",
  team_name="pr-fix-$PR_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the dev team for fixing CI failures on PR #$PR_NUMBER in $ORG/$PROJECT.
    Branch: $HEAD_BRANCH

    Your responsibilities:
    1. Task 3: Read the reviewer's failure analysis and apply code fixes.
       Each fix should be a separate commit.
    2. Task 4: Verify locally -- run build and tests to confirm the fix works.
    3. Task 7: If reviewer sends change requests after reviewing your fix,
       apply the requested changes and re-verify locally.

    Rules:
    - Commit format: fix(scope): description (English only, no emojis)
    - No Claude/AI references in commits
    - Validate incrementally: build after each fix
    - Do NOT retry the same build without changes -- diagnose first

    Build verification strategy:
    - < 30s builds: run inline (synchronous)
    - 30s+ builds: run in background with log polling

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (failure analysis + fix validation + PR management):

```
Agent(
  name="reviewer",
  team_name="pr-fix-$PR_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the review team for PR #$PR_NUMBER in $ORG/$PROJECT.
    Branch: $HEAD_BRANCH

    Your responsibilities:
    1. Task 1: Analyze all failed CI workflows.
       For each failure: identify workflow name, job, step, root cause, error category.
       Categorize: build-error | test-failure | lint-error | type-error | link-error | other.
       Propose specific fixes with file paths.
    2. Task 2: Post failure analysis comment to the PR (English only).
       Include: failed workflows table, root cause analysis, proposed fixes.
    3. Task 5: After dev applies fixes, review the changes:
       - Does the fix address the root cause (not just symptoms)?
       - Could the fix introduce regressions?
       - Is the fix minimal and focused?
       - Are there additional issues dev should fix?
       Classify findings: Critical / Major / Minor / Info.
    4. Task 8: If change requests were sent to dev, verify the fixes
       address each finding. Approve when all Critical/Major items resolved.

    Feedback loop rules:
    - If findings exist, send change requests to dev via SendMessage:
      'Change requests: 1. [finding + expected fix] 2. ...'
    - Max 2 review rounds. After round 2, approve with remaining items noted.

    Sanitize sensitive data before posting to PR: API keys, internal IPs, PII.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (docs update if behavior changes):

```
Agent(
  name="doc-writer",
  team_name="pr-fix-$PR_NUMBER",
  subagent_type="general-purpose",
  prompt="You are the documentation team for PR #$PR_NUMBER in $ORG/$PROJECT.
    Branch: $HEAD_BRANCH

    Your responsibilities:
    1. Task 6: After dev fixes CI issues, check if any fix changes behavior:
       - If a test expectation was changed: update relevant documentation
       - If an API response was modified: update API docs
       - If a configuration changed: update README or config docs
       - If no behavior change: mark task as completed with 'No doc updates needed'

    Rules:
    - Only update docs affected by the fix
    - Commit format: docs(scope): description (English only, no emojis)
    - No Claude/AI references in commits
    - Match existing documentation style

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

## T-4. Workflow Phases (Lead coordinates)

**Phase A -- Failure Analysis (Reviewer):**
1. Reviewer analyzes all failed CI workflows (Task 1)
2. Reviewer posts failure analysis comment to PR (Task 2)

**Phase B -- Fix Implementation (Dev):**
1. Dev reads reviewer's analysis and applies fixes (Task 3)
2. Dev verifies locally with build + tests (Task 4)

**Phase C -- Review + Documentation (parallel):**
1. Reviewer validates fix correctness and completeness (Task 5)
2. Doc-writer checks if docs need updating (Task 6)
3. These run in parallel -- both depend on Task 4 completing

**Phase D -- Feedback Loop (if needed):**

```
Reviewer has Critical/Major findings?
  |
  +- No -> Approve (skip Tasks 7, 8)
  |
  +- Yes -> Send change requests to dev
            |
            v
     Dev applies changes (Task 7)
            |
            v
     Reviewer re-reviews (Task 8)
            |
     +------+------+
     |             |
  Approved    Still issues?
     |        (max 2 rounds,
     v         then approve
   Task 9      with notes)
```

**Phase E -- Push and CI (Lead):**
1. Wait for reviewer approval and doc-writer completion
2. Push changes: `git push origin "$HEAD_BRANCH"`
3. Monitor CI: non-blocking polling, 30s intervals, 10min max
4. On all checks pass: `gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash --delete-branch`

**If CI fails again (max 3 total attempts):**
- Create new analysis task for reviewer
- Create new fix task for dev
- Repeat the cycle

**If max attempts (3) exceeded:**
- Lead executes escalation (same as Solo Mode Step 11)
- Add `needs-manual-review` label to PR

## T-5. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

## T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Report what was completed (which fixes applied, which CI runs passed)
3. Offer to continue in Solo Mode from the current attempt number
