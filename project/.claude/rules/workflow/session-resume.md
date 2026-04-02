---
alwaysApply: true
---

# Session Resume State

Save workflow progress so interrupted sessions can be resumed seamlessly.

## When to Write Resume State

Write `.claude/resume.md` in the project directory when:
- A multi-step workflow (issue-work, pr-work) is in progress
- The user signals they need to leave or switch context
- A long-running CI check is pending and the session may end

## Resume File Format

```markdown
# Session Resume State

**Saved**: YYYY-MM-DD HH:MM KST
**Workflow**: issue-work | pr-work | custom

## Context

| Field | Value |
|-------|-------|
| Repository | org/project |
| Issue | #NUMBER - Title |
| Branch | branch-name |
| PR | #NUMBER (if created) |

## Phase

Current phase: [issue-selected | implementing | build-testing | pr-created | ci-monitoring | merging]

## Completed Steps
- [x] Step 1 description
- [x] Step 2 description

## Remaining Steps
- [ ] Step 3 description
- [ ] Step 4 description

## Next Action

Exact next step to take when resuming (be specific).

## Notes

Any context that would be lost without this file.
```

## How to Resume

At session start, if `.claude/resume.md` exists in the working directory:
1. Read the file and present the saved state to the user
2. Ask if they want to continue from where they left off
3. If yes, proceed from the documented "Next Action"
4. After completing the workflow, delete the resume file

## Batch Resume Format

When a batch workflow (`issue-work` or `pr-work` without a specific number) is interrupted,
include the full batch progress table so the next session can resume from the correct item:

```markdown
# Session Resume State

**Saved**: YYYY-MM-DD HH:MM KST
**Workflow**: issue-work (batch) | pr-work (batch)

## Batch Context

| Field | Value |
|-------|-------|
| Batch Mode | single-repo / cross-repo |
| Total Items | N |
| Completed | M |
| Current Item | K |

## Batch Progress

| # | Repo | Item | Mode | Status |
|---|------|------|------|--------|
| 1 | org/repo-a | #12 | solo | DONE (PR #89) |
| 2 | org/repo-a | #8 | team | DONE (PR #90) |
| 3 | org/repo-b | #45 | solo | IN PROGRESS |
| 4 | org/repo-c | #3 | solo | PENDING |

## Next Action

Continue batch from item K: org/repo-b #45. Solo mode. Branch: feat/issue-45-fix-links.
```

When resuming a batch:
1. Read the batch progress table
2. Skip items with status `DONE`
3. Restart the `IN PROGRESS` item from its last known phase
4. Continue with `PENDING` items in order

## Rules

- **One resume file per project** — overwrite if a new workflow starts
- **Delete after completion** — do not leave stale resume files
- **Include only actionable state** — no verbose logs or exploration notes
- **Git-ignore the file** — add `.claude/resume.md` to `.gitignore`
