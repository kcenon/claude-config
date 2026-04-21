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
- `--limit N`: take only the first N items after sorting (default: 5, max: 10)
  - Values above 10 require `--force-large` to bypass the safe-batch cap. The cap exists because rule drift becomes empirically visible around items 15-25 in long batches; keeping batches at 5 by default preserves rule fidelity, and large runs require explicit operator acknowledgment.

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

### B-4.0. Per-Item Rule Reminder

Before starting work on each item, emit the Core invariants block from `global/skills/_shared/invariants.md` as a fresh tool result so the rules sit in the recent attention window instead of being buried by accumulating context.

Use this exact template (substitute `${PROCESSED+1}` and `${TOTAL}`). The five bullet lines are the canonical Core block — when they change, update `global/skills/_shared/invariants.md` first, then this template:

```
[Item ${PROCESSED+1}/${TOTAL}] Required rules:
- PR title/body, commit messages, issue comments: English only
- Commit format: type(scope): description (no Claude/AI attribution, no emojis)
- ABSOLUTE CI GATE: gh pr checks must show every check passing before merge
- Branch: feature off develop, squash merge back via PR
- 3-fail rule: stop and propose alternatives after 3 identical failures
```

**Why inline instead of @load**: A `@load: reference/...` call at batch start surfaces the doc once, after which the model's attention drifts as tool results accumulate. Inlining the same invariants per iteration makes them part of the most recent tool output every time, which is where attention is strongest. The short bullet list keeps the cumulative cost linear in batch size but still tiny (≈25 tokens per item).

**No reference loads inside the loop**: Do not call `@load: reference/error-handling.md`, `@load: reference/comment-templates.md`, or any other reference file from inside the per-item loop. If the single-item workflow needs a reference doc, the Solo/Team workflow loads it on its own — keep the loop free of additional loads so the inline reminder remains the most recent context anchor.

### B-4. Sequential Execution Loop

Process each item one at a time. The default dispatch strategy is **subagent delegation**: each item is handed off to a fresh `general-purpose` Agent so the parent's attention pool is not polluted by gh outputs, build logs, and file reads. Pass `--inline` at the command line to use the legacy single-context loop instead.

#### B-4.a. Default — Subagent Delegation

```
PROCESSED=0
RESULTS=[]   # Parent-side queue: only {item_id, repo, title, mode, status, pr_url, ci_conclusion}

for each item in approved batch plan:
    1. Log progress: "[N/TOTAL] Dispatching: $REPO #$ISSUE_NUMBER — $TITLE ($MODE)"

    2. Delegate the full single-item workflow to a fresh subagent:

       Agent(
           subagent_type: "general-purpose",
           description: "Process $REPO #$ISSUE_NUMBER",
           prompt: """
               Execute /issue-work $REPO $ISSUE_NUMBER --$MODE with full CLAUDE.md compliance.

               Required rules (do not skip — canonical source: global/skills/_shared/invariants.md Core block):
               - PR title/body, commit messages, issue comments: English only
               - Commit format: type(scope): description (no Claude/AI attribution, no emojis)
               - ABSOLUTE CI GATE: gh pr checks must show every check passing before merge
               - Branch: feature off develop, squash merge back via PR
               - 3-fail rule: stop and propose alternatives after 3 identical failures

               Run Solo Mode Steps 1-12 (or Team Mode T-1 through T-6 for team mode). If team
               mode, you MUST call TeamDelete() after completing the item.

               Report under 100 words as a single JSON line:
               {"item": "$REPO#$ISSUE_NUMBER", "status": "merged|failed|skipped",
                "pr_url": "https://github.com/...", "ci_conclusion": "success|failure|timeout",
                "reason": "<short reason if not merged>"}
           """
       )

    3. Parse the subagent's final JSON line and append it to RESULTS.
       Do NOT retain the full subagent transcript — the 100-word summary IS the parent-side record.

    4. Write batch progress to .claude/resume.md (for session recovery)

    5. Log completion: "[N/TOTAL] Completed: $REPO #$ISSUE_NUMBER — $status"

    6. Pause 2 seconds between items (rate limiting)

    7. PROCESSED=$((PROCESSED + 1))
       Chunked confirmation gate (see B-4.1) — fires every CONFIRM_INTERVAL
       items and only when more items remain.
```

**Why delegation is the default**: Subagents start with a fresh system prompt + CLAUDE.md attention pool. Item 30 in a delegated batch has the same context discipline as item 1 in a brand-new session. This is the most structurally robust mitigation short of process-level isolation, and it reuses Claude Code's built-in subagent infrastructure.

**Parent-side state budget**: ~100 words per item. A 30-item delegated batch costs the parent ~3K tokens of queue state, versus ~150K tokens of accumulated tool output in an inline batch of the same size. The `RESULTS` queue is the single source of truth for the B-5 summary.

**Inside the subagent**: The subagent runs the single-item Solo or Team workflow verbatim, including its own `TeamDelete()` cleanup for team-mode items. It does not know it is part of a batch, so it cannot be distracted by prior items.

#### B-4.b. Legacy — Inline Execution (`--inline` flag)

When `$INLINE_MODE == "true"`, fall back to processing each item directly in the parent context:

```
PROCESSED=0
for each item in approved batch plan:
    1. Log progress: "[N/TOTAL] Starting: $REPO #$ISSUE_NUMBER — $TITLE ($MODE)"

    1a. Emit inline rule reminder (see B-4.0). Do NOT @load any reference
        files inside the loop — the per-item reminder replaces that role.

    2. Set context variables for this item:
       - $ORG, $PROJECT from repo
       - $ISSUE_NUMBER from item
       - $EXEC_MODE from estimated mode (solo or team)

    3. Execute the single-item workflow directly in the parent context:
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

    8. PROCESSED=$((PROCESSED + 1))
       Chunked confirmation gate (see B-4.1) — fires every CONFIRM_INTERVAL
       items and only when more items remain.
```

Use `--inline` for tiny batches (≤3 items) or when several issues share a root cause and inter-item context is actually a feature, not a bug.

#### B-4.c. Delegation vs Inline Trade-offs

| Dimension | Subagent delegation (default) | Inline (`--inline`) |
|-----------|-------------------------------|---------------------|
| Parent context growth per item | ~100 words (fixed) | ~5K tokens (accumulating) |
| Rule compliance at item 30 | Matches item 1 | Drift visible around items 15-25 |
| Token overhead vs inline | +10-15% (subagent startup cost) | Baseline |
| Inter-item context | None (each item fresh) | Preserved (can reference prior fixes) |
| Team-mode cleanup | Subagent owns `TeamDelete()` | Parent owns `TeamDelete()` |
| Failure blast radius | Isolated to subagent | Can corrupt parent state |
| Best for | Batches >3 items, long runs | Tiny batches, related fixes sharing context |

**Rule of thumb**: Default to delegation. Only reach for `--inline` when you can name a specific reason the inter-item context matters. If you find yourself adding `--inline` out of habit, you are paying for rule drift you did not want.

### B-4.1. Chunked Confirmation Gate

After every `CONFIRM_INTERVAL` items (default 5), and only while items remain in the batch, halt execution. Three mutually exclusive behaviors are possible depending on the flags passed at invocation:

| Flags | Gate behavior at every `CONFIRM_INTERVAL` items |
|-------|-------------------------------------------------|
| `--no-confirm` | Gate skipped entirely. Loop runs straight through. |
| `--auto-restart` (and NOT `--no-restart`) | Forced session restart: write `.claude/resume.md`, print a resume hint, and `exit 0`. |
| Default (neither flag) | Interactive `AskUserQuestion` prompt with Continue / Pause / Cancel options. |
| `--auto-restart --no-restart` | `--no-restart` wins: falls back to the interactive gate. |

```
if (( PROCESSED % CONFIRM_INTERVAL == 0 )) && (( PROCESSED < TOTAL )); then
    if [[ "$NO_CONFIRM" == "true" ]]; then
        : # gate disabled; fall through to next item
    elif [[ "$AUTO_RESTART" == "true" && "$NO_RESTART" != "true" ]]; then
        # Forced session restart for full process-level attention reset.
        # The resume file uses the Batch Workflow Resume Format so a fresh
        # session can pick up from item $((PROCESSED + 1)).
        write_resume_md_for_batch
        echo "[${PROCESSED}/${TOTAL}] Session restart triggered for context refresh."
        echo "Resume with: claude  (.claude/resume.md will be detected automatically)"
        exit 0
    else
        decision=$(AskUserQuestion
            question="Processed ${PROCESSED}/${TOTAL} items. Continue, pause, or cancel?"
            header="Batch gate"
            options=(
                "Continue (Recommended)" "Resume the next chunk of ${CONFIRM_INTERVAL} items."
                "Pause and save resume state" "Write .claude/resume.md and exit; the next session can pick up from item $((PROCESSED + 1))."
                "Cancel batch" "Stop now without writing resume state. Already-completed items stay completed."
            )
        )
        case "$decision" in
            Pause*) write_resume_md_for_batch; exit 0 ;;
            Cancel*) exit 0 ;;
            Continue*) : ;;  # fall through to next item
        esac
    fi
fi
```

**Why the interactive gate matters beyond user control**: Each `AskUserQuestion` prompt produces a fresh user message in the conversation. That message acts as an attention anchor — when the model responds, recently-buried `CLAUDE.md` rules and skill instructions regain salience. The gate doubles as both an interactive checkpoint and a context-refresh mechanism for long-running batches.

**Why `--auto-restart` goes further**: An interactive gate still runs inside the same Claude process, so accumulated tool results (gh outputs, build logs, diffs) remain in the context window even after the user clicks "Continue". `--auto-restart` ends the process entirely: a fresh `claude` session starts with an empty tool-result history, the full CLAUDE.md and skill files reloaded at position zero, and resumes work from `resume.md`. This is the strongest context cleanup available short of spawning a separate OS process per item.

**Resume state on pause or auto-restart**: Both `Pause` (interactive) and `--auto-restart` call `write_resume_md_for_batch`, which writes `.claude/resume.md` using the **Batch Workflow Resume Format** described in `workflow/reference/session-resume-templates.md`. The file must include the per-item progress table so a future session can distinguish `DONE`, `IN PROGRESS`, and `PENDING` items and pick up at `$((PROCESSED + 1))`.

Minimal shape of `write_resume_md_for_batch`:

```
write_resume_md_for_batch() {
    mkdir -p .claude
    cat > .claude/resume.md <<EOF
# Session Resume State

**Saved**: $(date '+%Y-%m-%d %H:%M KST')
**Workflow**: issue-work (batch)

## Batch Context

| Field | Value |
|-------|-------|
| Batch Mode | ${BATCH_MODE} |
| Total Items | ${TOTAL} |
| Completed | ${PROCESSED} |
| Current Item | $((PROCESSED + 1)) |

## Batch Progress

${BATCH_PROGRESS_TABLE}

## Next Action

Continue batch from item $((PROCESSED + 1)). Invocation flags: ${ORIGINAL_FLAGS}.
EOF
}
```

**`--no-confirm` use cases**:
- CI-driven batch invocations where no human is at the terminal
- `--dry-run` follow-up runs already pre-approved by the operator
- Scripts that orchestrate `issue-work` programmatically

**`--auto-restart` use cases**:
- Very long unattended batches (near or above `--limit 10`) where interactive confirmation is impractical but rule drift is a concern
- Overnight or CI-dispatched batches paired with a wrapper that re-invokes `claude` on exit (see the external orchestrator pattern)
- Recovery runs after a crash where starting each chunk with a clean slate is safer than resuming a long in-memory session

In interactive sessions without a wrapper to restart the process, leave `--auto-restart` off — the attention-refresh side effect of the interactive gate is the strongest drift mitigation available without actually exiting.

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
