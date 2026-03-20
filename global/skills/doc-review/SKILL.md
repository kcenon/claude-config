---
name: doc-review
description: Comprehensive markdown document review - anchors, accuracy, SSOT, cross-references, and redundancy analysis.
argument-hint: "[docs-directory] [--scope anchors|accuracy|ssot|all] [--fix] [--solo|--team]"
user-invocable: true
---

# Document Review Command

Comprehensive markdown document review with parallel agent analysis.

## Usage

```
/doc-review                                    # Review all docs (auto-detect directory)
/doc-review docs/reference                     # Specify docs directory
/doc-review --scope anchors                    # Anchor validation only
/doc-review --scope accuracy                   # Accuracy/consistency only
/doc-review --scope ssot                       # SSOT/redundancy only
/doc-review --scope all --fix                  # Full review with auto-fix
/doc-review --solo                              # Force solo mode (subagents)
/doc-review --team                              # Force team mode (Agent Teams)
/doc-review docs/ --scope all --fix --team      # Full review, team mode, auto-fix
```

## Arguments

- `[docs-directory]`: Path to documentation directory (optional)
  - Auto-detection order: `docs/reference/` → `docs/` → `./`
  - Only `.md` files are analyzed

- `[--scope <phase>]`: Limit review to a specific phase (optional)
  - `anchors` — Phase 1 only (anchor/link validation)
  - `accuracy` — Phase 2 only (accuracy/consistency)
  - `ssot` — Phase 3 only (SSOT/redundancy)
  - `all` — All phases (default)

- `[--fix]`: Automatically apply fixes and commit (optional)
  - Without `--fix`: Report-only mode (no file modifications)
  - With `--fix`: Apply fixes → re-validate → commit

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode (independent subagents, no coordination)
  - `--team` — Force team mode (Agent Teams with shared task list)
  - If omitted: auto-recommend based on file count, then ask user

## Argument Parsing

Parse `$ARGUMENTS` and extract directory, scope, and fix flag:

```bash
ARGS="$ARGUMENTS"
DOCS_DIR=""
SCOPE="all"
FIX_MODE=false
EXEC_MODE=""

# Extract flags
if [[ "$ARGS" == *"--fix"* ]]; then
    FIX_MODE=true
    ARGS=$(echo "$ARGS" | sed 's/--fix//g')
fi

if [[ "$ARGS" == *"--solo"* ]]; then
    EXEC_MODE="solo"
    ARGS=$(echo "$ARGS" | sed 's/--solo//g')
elif [[ "$ARGS" == *"--team"* ]]; then
    EXEC_MODE="team"
    ARGS=$(echo "$ARGS" | sed 's/--team//g')
fi

if [[ "$ARGS" =~ --scope[[:space:]]+([a-z]+) ]]; then
    SCOPE="${BASH_REMATCH[1]}"
    ARGS=$(echo "$ARGS" | sed -E 's/--scope[[:space:]]+[a-z]+//g')
fi

# Remaining argument is docs directory
DOCS_DIR=$(echo "$ARGS" | xargs)

# Auto-detect if not specified
if [ -z "$DOCS_DIR" ]; then
    if [ -d "docs/reference" ]; then
        DOCS_DIR="docs/reference"
    elif [ -d "docs" ]; then
        DOCS_DIR="docs"
    else
        DOCS_DIR="."
    fi
fi
```

## Instructions

### Phase 0: Execution Mode Selection

Determine whether to run in Solo mode (independent subagents) or Team mode (coordinated Agent Teams).

#### 0-1. Count Target Files

```bash
FILE_COUNT=$(find "$DOCS_DIR" -name "*.md" -type f | wc -l | xargs)
```

#### 0-2. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-3. If no flag was provided (interactive selection)

Auto-recommend based on file count, then ask the user:

| File Count | Recommended Mode | Reason |
|-----------|-----------------|--------|
| 1-10 | Solo | Low coordination overhead |
| 11+ | Team | Benefit from shared findings and coordinated review |

Use `AskUserQuestion` to present the choice:

- **Question**: "Review $FILE_COUNT files in `$DOCS_DIR`. Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Independent subagents — simpler, lower token cost. Best for small doc sets."
- **Description for Team**: "Agent Teams with shared task list — reviewers can share findings. Better for large doc sets."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-4. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode** (subagent-based parallelism)
- If `$EXEC_MODE == "team"` → Execute **Team Mode** (Agent Teams with coordination)

---

## Solo Mode Instructions

Execute the document review workflow using independent subagents. Split files equally among agents based on file count.

### Agent Strategy

Determine the number of parallel agents based on file count:

| File Count | Agents | Strategy |
|-----------|--------|----------|
| 1-5 | 1 | Single agent, all phases sequentially |
| 6-15 | 2 | Split files evenly between 2 agents |
| 16-30 | 4 | Split files evenly among 4 agents |
| 31+ | 6 | Split files evenly among 6 agents |

Each agent receives its assigned file list and runs all applicable phases on those files. Use the `Agent` tool with `subagent_type=general-purpose` for each partition.

### Phase 1: Anchor and Link Validation

**Scope**: `anchors` or `all`

For each markdown file in the assigned partition:

1. **Build anchor registry**: Parse all headings to generate GitHub-style anchors
   - Algorithm: strip formatting → lowercase → remove non-alnum/space/hyphen (keep Unicode letters) → spaces→hyphens → collapse hyphens
   - Track duplicate headings (append `-1`, `-2` suffixes)
   - Skip content inside fenced code blocks (``` or ~~~)

2. **Validate intra-file references**: Check all `](#anchor)` links against the file's own anchors

3. **Validate inter-file references**: Check all `](./file.md#anchor)` and `](file.md#anchor)` links
   - Resolve relative paths from the referencing file's directory
   - Exclude external URLs (containing `:`)

4. **Report findings**: For each broken reference, record:
   - File name and line number
   - Expected anchor vs. actual heading
   - Severity: **Must-Fix** (all broken anchors are Must-Fix)

### Phase 2: Accuracy and Consistency

**Scope**: `accuracy` or `all`

For each markdown file in the assigned partition:

1. **Terminology consistency**: Identify inconsistent use of key terms across documents
   - Check for version number mismatches (e.g., "PostgreSQL 15" vs "PostgreSQL 16")
   - Check for product name variations (e.g., "DynamoDB" vs "Dynamo DB")
   - Check for standard/specification version inconsistencies

2. **Fact checking**: Flag statements that may be outdated or incorrect
   - Year references (check against current date)
   - URL/link validity (existence check only, not content)
   - Version numbers of external tools/libraries

3. **Report findings**: Classify each finding:
   - **Must-Fix**: Factual errors, version mismatches
   - **Should-Fix**: Inconsistent terminology, outdated references
   - **Nice-to-Have**: Style inconsistencies, minor wording issues

### Phase 3: SSOT and Redundancy Analysis

**Scope**: `ssot` or `all`

For each markdown file in the assigned partition:

1. **SSOT declaration detection**: Find explicit SSOT declarations
   - Pattern: sections marked as authoritative source for a topic
   - Track which topics have declared SSOTs

2. **Redundancy detection**: Find content that appears to duplicate another document's SSOT
   - Look for repeated tables, lists, or technical specifications
   - Check if non-SSOT documents properly defer via cross-references

3. **Cross-reference completeness**: Verify bidirectional cross-references
   - If document A references document B, check if B has a relevant back-reference
   - Identify orphan documents (no incoming cross-references)

4. **Report findings**: Classify each finding:
   - **Must-Fix**: Content contradicting SSOT, missing SSOT declarations for key topics
   - **Should-Fix**: Missing cross-references, one-directional references
   - **Nice-to-Have**: Redundant content that could be replaced with cross-references

### Phase 4: Fix and Verify (--fix mode only)

**Prerequisite**: `--fix` flag must be set. If not set, skip this phase and output report only.

1. **Priority order**: Fix Must-Fix items first, then Should-Fix, then Nice-to-Have
2. **Apply fixes**: Edit files using the `Edit` tool
   - Broken anchors: update reference to match actual heading anchor
   - Missing cross-references: add appropriate cross-reference blocks
   - Redundant content: replace with cross-reference to SSOT
3. **Regression validation**: After all fixes, re-run Phase 1 (anchor validation) to ensure no new breakages
4. **Commit**: If all validations pass, commit with message:
   ```
   docs: fix N broken anchors, M cross-references, K redundancies
   ```

### Result Aggregation

After all agents complete, aggregate results into a unified report.

---

## Team Mode Instructions

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

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Scope** | Only analyze `.md` files in the specified directory (recursive) |
| **Code blocks** | Always skip content inside fenced code blocks |
| **Anchors** | Use GitHub-compatible slug algorithm for anchor generation |
| **Severity** | Every finding must be classified as Must-Fix, Should-Fix, or Nice-to-Have |
| **Commits** | Commit messages in English, conventional commit format |

## Output

After completion, provide a structured review report:

```markdown
## Document Review Report

| Metric | Value |
|--------|-------|
| Directory | $DOCS_DIR |
| Files analyzed | N |
| Execution mode | Solo / Team |
| Agents used | M |
| Scope | $SCOPE |

### Findings Summary

| Severity | Phase 1 (Anchors) | Phase 2 (Accuracy) | Phase 3 (SSOT) | Total |
|----------|-------------------|-------------------|----------------|-------|
| Must-Fix | A | B | C | A+B+C |
| Should-Fix | D | E | F | D+E+F |
| Nice-to-Have | G | H | I | G+H+I |

### Must-Fix Items
1. `file.md:42` — broken anchor `#nonexistent` → should be `#existing-heading`
2. ...

### Should-Fix Items
1. ...

### Nice-to-Have Items
1. ...

### Score
Overall: X.X/10 (Anchors: A/10, Accuracy: B/10, SSOT: C/10)

### Files Modified (--fix mode)
- file1.md (+3/-2)
- file2.md (+1/-1)
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| Docs directory exists | "Directory not found: [path]" | Verify path or use auto-detection |
| Markdown files found | "No .md files found in [path]" | Check directory contains markdown files |
| Git repository (for --fix) | "Not a git repository" | Run from within a git repository |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Agent timeout | Report partial results from completed agents | Re-run with smaller file set |
| No findings | Report clean status with score 10/10 | No action needed |
| Fix introduces new errors | Revert fix, report regression | Manual intervention required |
| File encoding issues | Skip file with warning | Ensure files are UTF-8 |
| Team mode: teammate failure | Fallback to Solo Mode for failed partition | Automatic recovery |
| Team mode: coordination timeout | Aggregate partial results, report incomplete | Re-run failed partitions |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
