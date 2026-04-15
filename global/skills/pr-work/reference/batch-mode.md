# Batch Mode Instructions

Complete batch mode workflow for processing multiple failing PRs sequentially. Each PR is handled using the existing Solo or Team workflow.

## B-0. Batch Discovery

**For `single-repo` mode** (project name given, no PR number):

```bash
# List all open PRs
ALL_PRS=$(gh pr list --repo $ORG/$PROJECT --state open --limit 100 \
  --json number,title,headRefName,createdAt)

# Filter to PRs with failed CI checks
FAILING_PRS=[]
for PR in $ALL_PRS; do
    CHECKS=$(gh pr checks $PR_NUMBER --repo $ORG/$PROJECT --json name,state,conclusion \
      -q '[.[] | select(.conclusion == "failure")] | length')
    if [[ "$CHECKS" -gt 0 ]]; then
        # Add to FAILING_PRS with failure count
    fi
    sleep 0.3
done
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

# For each repo, find PRs with failing CI
FAILING_PRS=[]
for REPO in $REPOS; do
    PRS=$(gh pr list --repo $REPO --state open --limit 50 \
      --json number,title,headRefName,createdAt)
    for PR in $PRS; do
        CHECKS=$(gh pr checks $PR_NUMBER --repo $REPO --json name,state,conclusion \
          -q '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null)
        if [[ "$CHECKS" -gt 0 ]]; then
            # Add to FAILING_PRS with repo context and failure count
        fi
    done
    sleep 0.3
done
```

## B-1. Failure Severity Sorting

Assign each failing PR a severity score:

| Signal | Score |
|--------|-------|
| Multiple failed workflows | 0 (most urgent) |
| Single failed workflow, build error | 1 |
| Single failed workflow, test error | 2 |
| Single failed workflow, lint/style error | 3 |

Sort FAILING_PRS by: score ascending -> `createdAt` ascending -> repo name ascending.

Apply `--limit N` (default: 5, max: 10). Values above 10 require `--force-large` to bypass the safe-batch cap. The cap exists because rule drift becomes empirically visible around items 15-25 in long batches; keeping batches at 5 by default preserves rule fidelity, and large runs require explicit operator acknowledgment. If no failing PRs found, report "No open PRs with failed CI found" and exit.

## B-2. Auto Size/Mode Estimation per Item

For each PR, decide solo vs team **without prompting the user**.

**Weighted scoring matrix:**

| Factor | Weight | Solo Signal (0) | Team Signal (1) |
|--------|--------|-----------------|-----------------|
| Failed workflow count | 3 | 1 | 2+ |
| Error category count | 2 | Single category | Multiple categories |
| Previous fix attempts | 2 | 0 pushes after first failure | 1+ pushes (recurring) |
| Error log complexity | 1 | < 20 lines of error output | 20+ lines |

**Decision**: Sum the weights where Team Signal matches. If total >= 4 -> `team`, otherwise -> `solo`.

**Override**: If `--solo` or `--team` flag was passed globally, apply that mode to ALL items.

## B-3. Batch Plan Summary and Approval

Present the batch plan as a table. Use `AskUserQuestion` for a single approval:

```markdown
## Batch Plan: pr-work

| # | Repo | PR | Title | Failed Checks | Severity | Mode |
|---|------|----|-------|---------------|----------|------|
| 1 | org/repo-a | #42 | feat: add auth | 3 | build+test | team |
| 2 | org/repo-a | #38 | fix: null check | 1 | test | solo |
| 3 | org/repo-b | #15 | docs: update API | 1 | lint | solo |
...

**Total items**: 8 (6 solo, 2 team)
```

- **Question**: "Batch plan ready. N failing PRs to process. Approve?"
- **Header**: "Batch"
- **Options**:
  1. "Approve and start (Recommended)" -- proceed with batch execution
  2. "Modify plan" -- user can exclude items or change modes
  3. "Cancel" -- abort batch

If `--dry-run` is set, display the plan and exit without prompting.

## B-4. Sequential Execution Loop

Process each item one at a time:

```
PROCESSED=0
for each item in approved batch plan:
    1. Log progress: "[N/TOTAL] Starting: $REPO PR #$PR_NUMBER -- $TITLE ($MODE)"

    2. Set context variables for this item:
       - $ORG, $PROJECT from repo
       - $PR_NUMBER from item
       - $EXEC_MODE from estimated mode (solo or team)

    3. Execute the single-item workflow:
       - If solo: run Solo Mode Steps 1-11
       - If team: run Team Mode Steps T-1 through T-6
       Ensure TeamDelete() is called after each team-mode item.

    4. Record result:
       - SUCCESS: all CI checks passing after fix
       - FAILED: CI still failing after 3 retry attempts
       - SKIPPED: PR was closed/merged during batch

    5. Write batch progress to .claude/resume.md (for session recovery)

    6. Log completion: "[N/TOTAL] Completed: $REPO PR #$PR_NUMBER -- $RESULT"

    7. Pause 2 seconds between items (rate limiting)

    8. PROCESSED=$((PROCESSED + 1))
       Chunked confirmation gate (see B-4.1) -- fires every CONFIRM_INTERVAL
       items and only when more items remain.
```

## B-4.1. Chunked Confirmation Gate

After every `CONFIRM_INTERVAL` items (default 5), and only while items remain in the batch, halt execution and prompt the user via `AskUserQuestion`. Skip the gate entirely when `--no-confirm` was passed.

```
if [[ "$NO_CONFIRM" != "true" ]] \
   && (( PROCESSED % CONFIRM_INTERVAL == 0 )) \
   && (( PROCESSED < TOTAL )); then
    decision=$(AskUserQuestion
        question="Processed ${PROCESSED}/${TOTAL} PRs. Continue, pause, or cancel?"
        header="Batch gate"
        options=(
            "Continue (Recommended)" "Resume the next chunk of ${CONFIRM_INTERVAL} PRs."
            "Pause and save resume state" "Write .claude/resume.md and exit; the next session can pick up from item $((PROCESSED + 1))."
            "Cancel batch" "Stop now without writing resume state. Already-fixed PRs stay fixed."
        )
    )
    case "$decision" in
        Pause*) write_resume_md_for_batch; exit 0 ;;
        Cancel*) exit 0 ;;
        Continue*) : ;;  # fall through to next item
    esac
fi
```

**Why the gate matters beyond user control**: Each `AskUserQuestion` prompt produces a fresh user message in the conversation. That message acts as an attention anchor -- when the model responds, recently-buried `CLAUDE.md` rules and skill instructions regain salience. The gate doubles as both an interactive checkpoint and a context-refresh mechanism for long-running batches, which is particularly valuable in `pr-work` where each item involves dense CI log analysis.

**Resume state on pause**: When the user chooses "Pause", write `.claude/resume.md` per the `session-resume` workflow. Use the **Batch Workflow Resume Format** described in `workflow/reference/session-resume-templates.md` so a future session can pick up at item `$((PROCESSED + 1))`.

**`--no-confirm` use cases**:
- CI-driven `pr-work` invocations where a separate orchestrator monitors the run
- Recovery scripts that retry transient CI failures programmatically
- `--dry-run` follow-up runs already pre-approved by the operator

In interactive sessions, leave it off -- the attention-refresh side effect is one of the strongest available drift mitigations for long PR-fixing batches.

**Failure handling per item:**
- CI failure after 3 retries -> mark FAILED, add escalation comment to PR, continue to next
- Team mode failure -> fallback to solo for THIS item, then continue
- MAX_TEAMS exceeded -> force solo for this item
- PR merged/closed by someone else -> mark SKIPPED, continue

## B-5. Batch Summary Report

After all items are processed, present a summary:

```markdown
## Batch Execution Summary

| # | Repo | PR | Title | Mode | Result |
|---|------|----|-------|------|--------|
| 1 | org/repo-a | #42 | feat: add auth | team | CI Passing |
| 2 | org/repo-a | #38 | fix: null check | solo | CI Passing |
| 3 | org/repo-b | #15 | docs: update API | solo | FAILED |

**Success**: 7/8
**Failed**: 1/8

### Failed Items
- org/repo-b #15: Lint failure persists -- `clang-format` version mismatch. Manual fix needed.
```

Delete `.claude/resume.md` after successful batch completion.
