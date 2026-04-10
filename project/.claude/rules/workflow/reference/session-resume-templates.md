---
alwaysApply: false
---

# Session Resume Templates

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/session-resume-templates`.

## Single Workflow Resume Format

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

## Batch Workflow Resume Format

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

## Resuming a Batch

1. Read the batch progress table
2. Skip items with status `DONE`
3. Restart the `IN PROGRESS` item from its last known phase
4. Continue with `PENDING` items in order
