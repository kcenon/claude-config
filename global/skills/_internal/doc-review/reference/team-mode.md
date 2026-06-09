# Team Mode Instructions

Complete team mode workflow for parallel agent document analysis. Three-team architecture with feedback loops for finding, fixing, and validating document issues.

---

Three-team workflow for document review: Analyzer team finds issues, Fixer team applies corrections, Validator team re-checks quality. Feedback loop ensures fixes don't introduce new problems.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Phase control │
         │ Final report  │
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│Analyz│   │Fixer │   │Valid-│
│ Team │──►│ Team │──►│ator │
└──────┘   └──────┘   └──────┘
 analyzer    fixer    validator

  Analyzer ──► Fixer: "Issues found: [list with severity]"
  Fixer ──► Validator: "Fixes applied, ready for validation"
  Validator ──► Fixer: "Regression found in [file]" (feedback loop)
  Validator ──► Lead: "All validations pass, report ready"
```

### T-1. Create Team and Tasks

```
TeamCreate(team_name="doc-review", description="Review $FILE_COUNT markdown files in $DOCS_DIR")
```

Split files into partitions based on file count (same strategy as Solo Mode Agent Strategy table). Create tasks:

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Analyze partition A: anchors, accuracy, SSOT | analyzer | — | A |
| 2 | Analyze partition B: anchors, accuracy, SSOT | analyzer | — | A |
| N | Analyze partition N | analyzer | — | A |
| N+1 | Aggregate analysis findings and prioritize | lead | 1..N | B |
| N+2 | Apply Must-Fix corrections | fixer | N+1 | C |
| N+3 | Apply Should-Fix corrections | fixer | N+2 | C |
| N+4 | Validate all fixes: regression check | validator | N+3 | D |
| N+5 | Re-fix any regressions (if found) | fixer | N+4 | E |
| N+6 | Final validation and report | validator | N+5 | E |
| N+7 | Commit fixes and generate report | lead | N+6 | F |

### T-2. Spawn Teammates

**Analyzer Team** (issue detection — read-only):

```
Agent(
  name="analyzer",
  team_name="doc-review",
  subagent_type="general-purpose",
  prompt="You are the analyzer team for the document review.
    Your assigned files: [file list — split across tasks]
    Scope: $SCOPE

    For each file, run the applicable review phases:
    - Phase 1 (anchors): Build anchor registry (GitHub-style slugs), validate
      intra-file and inter-file references. Skip fenced code blocks.
    - Phase 2 (accuracy): Check terminology consistency, version mismatches,
      outdated year references, URL validity.
    - Phase 3 (ssot): Detect SSOT declarations, find redundancy, verify
      bidirectional cross-references, identify orphan documents.

    Classify every finding:
    - Must-Fix: Broken anchors, factual errors, SSOT contradictions
    - Should-Fix: Inconsistent terminology, missing cross-references
    - Nice-to-Have: Style issues, redundant content

    Report findings as a structured list with file:line, severity, and description.
    If you discover a cross-document issue affecting files outside your partition,
    note it clearly for the lead to forward.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Fixer Team** (applies corrections):

```
Agent(
  name="fixer",
  team_name="doc-review",
  subagent_type="general-purpose",
  prompt="You are the fixer team for the document review.
    Docs directory: $DOCS_DIR

    Your responsibilities:
    1. Read the aggregated findings from the lead (sorted by severity)
    2. Apply Must-Fix corrections first, then Should-Fix, then Nice-to-Have
    3. For each fix:
       - Broken anchors: update reference to match actual heading anchor
       - Missing cross-references: add appropriate cross-reference blocks
       - Redundant content: replace with cross-reference to SSOT
       - Terminology: standardize to the authoritative form
    4. If validator reports regressions, fix those too (Task N+5)

    Rules:
    - Each fix should be verifiable (anchor must resolve, link must work)
    - Do not change content meaning — only fix structural/reference issues
    - Commit format: docs: fix N broken anchors, M cross-references
    - Preserve existing formatting style

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Validator Team** (quality gate — read-only verification):

```
Agent(
  name="validator",
  team_name="doc-review",
  subagent_type="general-purpose",
  prompt="You are the validator team for the document review.
    Docs directory: $DOCS_DIR

    Your responsibilities:
    1. Task N+4: After fixer applies corrections, re-run Phase 1 (anchor
       validation) on ALL files to check for regressions.
       - Did any fix break an existing anchor?
       - Did any cross-reference update introduce a new broken link?
       - Are all Must-Fix items actually resolved?
    2. If regressions found: send details to fixer via SendMessage:
       'Regressions found: 1. [file:line — description] 2. ...'
    3. Task N+6: After fixer resolves regressions, do final validation:
       - Confirm zero Must-Fix items remain
       - Calculate per-phase and overall scores
       - Generate findings summary for the report

    Feedback loop rules:
    - Max 2 validation rounds. After round 2, accept with remaining items noted.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

### T-3. Workflow Phases (Lead coordinates)

**Phase A — Parallel Analysis:**
1. Analyzer processes all file partitions in parallel (Tasks 1..N)
2. If multiple analyzer tasks, they run simultaneously

**Phase B — Aggregation (Lead):**
1. Collect findings from all analyzer tasks
2. Deduplicate (multiple analyzers may flag same inter-file issue)
3. Sort by severity: Must-Fix → Should-Fix → Nice-to-Have
4. Prepare prioritized fix list for fixer

**Phase C — Fix Application (Fixer, --fix mode only):**
1. Fixer applies Must-Fix corrections (Task N+2)
2. Fixer applies Should-Fix corrections (Task N+3)
3. If `$FIX_MODE == false`: skip Phase C-F, go directly to report

**Phase D — Validation:**
1. Validator re-runs anchor checks on all files (Task N+4)
2. Validator reports any regressions to fixer

**Phase E — Feedback Loop (if needed):**

```
Validator found regressions?
  │
  ├─ No → Proceed to final report
  │
  └─ Yes → Send regression details to fixer
            │
            ▼
     Fixer resolves regressions (Task N+5)
            │
            ▼
     Validator final check (Task N+6)
            │
     ┌──────┴──────┐
     │             │
   Clean       Still issues?
     │         (max 2 rounds,
     ▼          then accept
   Report       with notes)
```

**Phase F — Commit and Report (Lead):**
1. If fixes were applied: commit with `docs: fix N issues across M files`
2. Generate unified report (same format as Solo Mode output)

### T-4. Cleanup

```
SendMessage(to="analyzer", message={type: "shutdown_request"})
SendMessage(to="fixer", message={type: "shutdown_request"})
SendMessage(to="validator", message={type: "shutdown_request"})
TeamDelete()
```

### T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Report partial results (analysis findings are still valuable even without fixes)
3. Offer to re-run in Solo Mode for fix application
