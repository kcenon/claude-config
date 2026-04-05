# Batch Mode Instructions

Complete batch mode workflow for processing multiple GitHub issues sequentially.
Covers discovery, priority sorting, auto size estimation, plan approval, sequential execution, and summary reporting.

---

Process multiple issues sequentially. Each issue is handled using the existing Solo or Team workflow.

### B-0. Batch Discovery

**For `single-repo` mode** (project name given, no issue number):

```bash
ALL_ISSUES=$(gh issue list --repo $ORG/$PROJECT --state open --limit 100 \
  --json number,title,labels,createdAt,body -q 'sort_by(.createdAt)')
```

**For `cross-repo` mode** (no arguments):

```bash
# Discover repos
if [[ -n "$ORG" ]]; then
    REPOS=$(gh repo list "$ORG" --json nameWithOwner,isArchived \
      --jq '[.[] | select(.isArchived == false)] | .[].nameWithOwner' --limit 200)
else
    USER=$(gh api user --jq '.login')
    REPOS=$(gh repo list "$USER" --json nameWithOwner,isArchived \
      --jq '[.[] | select(.isArchived == false)] | .[].nameWithOwner' --limit 200)
fi

# Collect issues from each repo (0.3s rate-limit pause)
ALL_ISSUES=[]
for REPO in $REPOS; do
    ISSUES=$(gh issue list --repo $REPO --state open --limit 50 \
      --json number,title,labels,createdAt,body)
    # Append with repo context: each issue gets a "repo" field
    sleep 0.3
done
```

### B-1. Global Priority Sorting and Filtering

Assign each issue a numeric priority score:

| Label | Score |
|-------|-------|
| `priority/critical` | 0 |
| `priority/high` | 1 |
| `priority/medium` | 2 |
| `priority/low` | 3 |
| No priority label | 4 |

Sort ALL_ISSUES by: score ascending → `createdAt` ascending → repo name ascending.

Apply filters:
- `--priority <level>`: exclude issues below the specified priority level
- `--limit N`: take only the first N items after sorting (default: 20, max: 50)

If no issues found after filtering, report "No open issues found matching criteria" and exit.

### B-2. Auto Size/Mode Estimation per Item

For each issue in the batch, estimate size and decide solo vs team **without prompting the user**.

**Weighted scoring matrix:**

| Factor | Weight | Solo Signal (0) | Team Signal (1) |
|--------|--------|-----------------|-----------------|
| Size label | 3 | `size/XS`, `size/S`, or none | `size/M`, `size/L`, `size/XL` |
| Description length | 1 | < 500 characters | >= 500 characters |
| Acceptance criteria count | 2 | < 3 checkbox items | 4+ checkbox items |
| Subtask references | 2 | No "Part of" or checklist | Contains "Part of" or task checklist |

**Decision**: Sum the weights where Team Signal matches. If total >= 4 → `team`, otherwise → `solo`.

**Override**: If `--solo` or `--team` flag was passed globally, apply that mode to ALL items.

### B-3. Batch Plan Summary and Approval

Present the batch plan as a table. Use `AskUserQuestion` for a single approval:

```markdown
## Batch Plan: issue-work

| # | Repo | Issue | Title | Priority | Est. Size | Mode |
|---|------|-------|-------|----------|-----------|------|
| 1 | org/repo-a | #12 | Fix login crash | critical | S | solo |
| 2 | org/repo-a | #8 | Add OAuth support | high | M | team |
| 3 | org/repo-b | #45 | Update README links | medium | XS | solo |
...

**Total items**: 12 (9 solo, 3 team)
```

- **Question**: "Batch plan ready. N items to process. Approve?"
- **Header**: "Batch"
- **Options**:
  1. "Approve and start (Recommended)" — proceed with batch execution
  2. "Modify plan" — user can exclude items or change modes, then re-display
  3. "Cancel" — abort batch

If `--dry-run` is set, display the plan and exit without prompting.

### B-4. Sequential Execution Loop

Process each item one at a time:

```
for each item in approved batch plan:
    1. Log progress: "[N/TOTAL] Starting: $REPO #$ISSUE_NUMBER — $TITLE ($MODE)"

    2. Set context variables for this item:
       - $ORG, $PROJECT from repo
       - $ISSUE_NUMBER from item
       - $EXEC_MODE from estimated mode (solo or team)

    3. Execute the single-item workflow:
       - If solo: run Solo Mode Steps 1-12
       - If team: run Team Mode Steps T-1 through T-6
       Ensure TeamDelete() is called after each team-mode item.

    4. Record result:
       - SUCCESS: PR URL and merge status
       - FAILED: error description (after 3 retries)
       - SKIPPED: if issue was closed/assigned during batch

    5. Write batch progress to .claude/resume.md (for session recovery)

    6. Log completion: "[N/TOTAL] Completed: $REPO #$ISSUE_NUMBER — $RESULT"

    7. Pause 2 seconds between items (rate limiting)
```

**Failure handling per item:**
- Build/test/CI failure after 3 retries → mark FAILED, create draft PR if code was written, continue to next
- Team mode failure → fallback to solo for THIS item, then continue
- MAX_TEAMS exceeded → force solo for this item
- Issue closed by someone else during batch → mark SKIPPED, continue

### B-5. Batch Summary Report

After all items are processed, present a summary:

```markdown
## Batch Execution Summary

| # | Repo | Issue | Title | Mode | Result | PR |
|---|------|-------|-------|------|--------|----|
| 1 | org/repo-a | #12 | Fix login crash | solo | Merged | #89 |
| 2 | org/repo-a | #8 | Add OAuth support | team | Merged | #90 |
| 3 | org/repo-b | #45 | Update README links | solo | FAILED | -- |

**Success**: 11/12
**Failed**: 1/12

### Failed Items
- org/repo-b #45: Build failure — missing dependency `libfoo`. Manual intervention needed.
```

Delete `.claude/resume.md` after successful batch completion.
