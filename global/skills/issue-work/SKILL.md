---
name: issue-work
description: Automate GitHub issue workflow - select issue, create branch, implement, build, test, and create PR.
argument-hint: "<project-name> [issue-number] [--solo|--team]"
user-invocable: true
---

# Issue Work Command

Automate GitHub issue workflow with project name as argument.

## Usage

```
/issue-work <project-name> [issue-number] [--org <organization>]
/issue-work <organization>/<project-name> [issue-number]
```

**Examples**:
```
/issue-work vi_slam                              # Auto-select priority issue
/issue-work vi_slam 21                           # Work on issue #21
/issue-work vi_slam 21 --org mycompany          # Explicit organization
/issue-work mycompany/vi_slam 21                # Full repo path format
/issue-work vi_slam 21 --solo                   # Force solo mode (sequential)
/issue-work vi_slam 21 --team                   # Force team mode (implementer + tester)
```

## Arguments

- `<project-name>`: Project name or full repository path (required)
  - Format 1: `<project-name>` - auto-detect organization from git remote
  - Format 2: `<project-name> --org <organization>` - explicit organization
  - Format 3: `<organization>/<project-name>` - full repository path

- `[issue-number]`: GitHub issue number (optional)
  - If provided: Work on the specified issue
  - If omitted: Auto-select highest priority open issue

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode (single agent, sequential workflow)
  - `--team` — Force team mode (implementer + tester agents in parallel)
  - If omitted: auto-recommend based on issue size, then ask user

## Argument Parsing

Parse `$ARGUMENTS` and extract project, organization, and issue number:

```bash
ARGS="$ARGUMENTS"
ISSUE_NUMBER=""
PROJECT=""
ORG=""
EXEC_MODE=""

# Extract execution mode flag
if [[ "$ARGS" == *"--solo"* ]]; then
    EXEC_MODE="solo"
    ARGS=$(echo "$ARGS" | sed 's/--solo//g')
elif [[ "$ARGS" == *"--team"* ]]; then
    EXEC_MODE="team"
    ARGS=$(echo "$ARGS" | sed 's/--team//g')
fi

# Extract issue number if present (numeric argument)
if [[ "$ARGS" =~ [[:space:]]([0-9]+)([[:space:]]|$) ]]; then
    ISSUE_NUMBER="${BASH_REMATCH[1]}"
    # Remove issue number from args
    ARGS=$(echo "$ARGS" | sed -E "s/[[:space:]]+${ISSUE_NUMBER}([[:space:]]|$)/ /g")
fi

# Check if --org flag is provided
if [[ "$ARGS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGS" | awk '{print $1}')
    ORG=$(echo "$ARGS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
# Check if full path format (contains /)
elif [[ "$ARGS" == *"/"* ]]; then
    ORG=$(echo "$ARGS" | cut -d'/' -f1 | xargs)
    PROJECT=$(echo "$ARGS" | cut -d'/' -f2 | xargs)
# Auto-detect from git remote
else
    PROJECT=$(echo "$ARGS" | xargs)
    cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

- Repository: `https://github.com/$ORG/$PROJECT`
- Source path: `./$PROJECT`
- Issue Number: `$ISSUE_NUMBER` (empty if not provided)

## Instructions

### Phase 0: Execution Mode Selection

Determine whether to run in Solo mode (single agent, sequential) or Team mode (implementer + tester agents in parallel).

#### 0-1. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-2. If no flag was provided (interactive selection)

First, fetch issue information for size estimation (after Issue Selection in Step 1):

```bash
ISSUE_INFO=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT \
  --json title,body,labels -q '{title: .title, body: .body, labels: [.labels[].name]}')
```

Auto-recommend based on issue size:

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Size label | `size/XS`, `size/S` | `size/M`, `size/L`, `size/XL` |
| Description length | < 500 chars | > 500 chars |
| Acceptance criteria | < 3 items | 4+ items |
| Subtask references | None | "Part of", checklist items |

Use `AskUserQuestion` to present the choice:

- **Question**: "Issue #$ISSUE_NUMBER — <title> (<estimated-size>). Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential execution by a single agent. Lower token cost. Best for XS-S issues."
- **Description for Team**: "3-team parallel: dev + reviewer + doc-writer with review feedback loop. Higher quality for M+ issues. ~2x token cost."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-3. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode Instructions** (Steps 1-12 below)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions** (after Solo Mode section)

---

## Solo Mode Instructions

Execute the following workflow for the specified project:

### 1. Issue Selection

**If issue number is provided:**

```bash
# Fetch specific issue
gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json number,title,state,labels

# Verify issue exists and is open
STATE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json state -q '.state')
if [[ "$STATE" != "OPEN" ]]; then
    echo "Error: Issue #$ISSUE_NUMBER is not open (state: $STATE)"
    exit 1
fi
```

**If issue number is NOT provided:**

```bash
# Auto-select by priority
gh issue list --repo $ORG/$PROJECT --label "priority/critical" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/high" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/medium" --state open --limit 1
```

Select the oldest (first created) issue from the results.

Store the selected issue number in `$ISSUE_NUMBER` variable.

### 2. Issue Size Evaluation

Analyze the issue and determine size:

| Size | Expected LOC | Action |
|------|--------------|--------|
| XS/S | < 200 | Proceed directly |
| M | 200-500 | Consider splitting into 2-3 sub-issues |
| L/XL | > 500 | **Must split** into sub-issues, work on first |

If splitting required:
- Create sub-issues with `Part of #ORIGINAL` reference
- Apply 5W1H template for each sub-issue
- Proceed with the first sub-issue

### 3. Git Environment Setup

```bash
cd $PROJECT
git fetch origin
git checkout main && git pull origin main

# Extract issue title for branch name
ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json title -q '.title')
# Convert to kebab-case (lowercase, replace spaces with hyphens)
SHORT_DESC=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g' | cut -c1-50)

# Determine branch type from issue labels
LABELS=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json labels -q '.labels[].name')
if echo "$LABELS" | grep -q "type/feature"; then
    BRANCH_TYPE="feat"
elif echo "$LABELS" | grep -q "type/bug"; then
    BRANCH_TYPE="fix"
elif echo "$LABELS" | grep -q "type/refactor"; then
    BRANCH_TYPE="refactor"
elif echo "$LABELS" | grep -q "type/docs"; then
    BRANCH_TYPE="docs"
else
    BRANCH_TYPE="feat"  # Default
fi

BRANCH_NAME="${BRANCH_TYPE}/issue-${ISSUE_NUMBER}-${SHORT_DESC}"
git checkout -b "$BRANCH_NAME"
```

Branch naming convention examples:
- `feat/issue-123-add-auth` (new feature)
- `fix/issue-456-null-pointer` (bug fix)
- `refactor/issue-789-optimize-query` (refactoring)
- `docs/issue-101-update-readme` (documentation)

### 4. Issue Assignment

```bash
gh issue edit <NUMBER> --repo $ORG/$PROJECT --add-assignee @me
```

### 5. Code Implementation

**Priority**: Start implementation immediately. Minimize upfront planning — analyze code
as you implement, not in a separate planning phase.

1. **Analyze existing code style**:
   - Check `.clang-format`, `.editorconfig` if present
   - Review existing file patterns and conventions

2. **Implement changes**:
   - Follow existing code style strictly
   - Keep changes minimal and focused
   - **Validate incrementally**: Build/test after each logical change, not after all changes

3. **Header file review** (C/C++ projects):
   - Verify all used symbols have corresponding #include
   - Add missing headers

4. **Commit per logical unit**:
   - Format: `type(scope): description`
   - **Language: MANDATORY English only** - All commit messages MUST be written in English
   - **Forbidden**: Claude/AI references, emojis, Co-Authored-By

### 6. Build and Test Verification

Follow the build verification workflow rule (`build-verification.md`) to select the
appropriate strategy based on expected build duration.

#### Toolchain Availability Check

Before running local builds, verify required toolchains are installed:

```bash
# Check availability — do NOT install without asking the user
command -v go &>/dev/null    # Go
command -v cargo &>/dev/null # Rust
command -v cmake &>/dev/null # C++
command -v npm &>/dev/null   # Node.js
```

**If toolchain is unavailable**: Skip local build verification and rely on CI.
Do NOT attempt to install toolchains without asking the user first.
Report what was verified locally vs what needs CI.

#### Strategy Selection

| Build System | Typical Duration | Strategy |
|-------------|-----------------|----------|
| `go build` / `cargo check` | < 30s | Inline (synchronous) |
| `cmake --build` / `gradle build` | 30s - 5min | Background + log polling |
| `ctest` / `pytest` (large suites) | 1 - 10min | Background + log polling |
| CI pipeline (`gh workflow run`) | 5min+ | CI log check |

#### Inline Strategy (short builds)

For builds expected under 30 seconds:

```
Bash(command="go build ./...", timeout=60000)
Bash(command="cargo check", timeout=60000)
```

#### Background + Log Polling Strategy (long builds)

For builds expected over 30 seconds:

**Step A**: Launch build in background
```
Bash(command="cmake --build build/ --config Release 2>&1", run_in_background=true)
# -> Returns task_id
```

**Step B**: Poll build output (non-blocking, every 10-15 seconds)
```
TaskOutput(task_id="<id>", block=false, timeout=10000)
# -> Check for error patterns or completion indicators
```

**Step C**: Detect outcome from output

| Outcome | Indicators | Action |
|---------|-----------|--------|
| Success | `Built target`, `Finished`, clean exit | Proceed to tests |
| Failure | `error:`, `FAILED`, `Error` | Diagnose and fix |
| Timeout | No output after 30s of polling | Check system resources |

**Step D**: Run tests with same pattern
```
Bash(command="ctest --test-dir build/ --output-on-failure 2>&1", run_in_background=true)
```

#### On Build/Test Failure

1. Read the error output from build logs
2. Categorize failure (compile error, linker error, test assertion, missing dependency)
3. Apply fix based on error pattern
4. Re-run build/test to verify fix
5. If persistent failure: create draft PR with failure log (see Error Handling)

Do NOT retry the same build without changes -- diagnose first.

### 7. Documentation Update

Update relevant documentation if applicable:
- README.md
- CHANGELOG.md
- API documentation
- Code comments for complex logic

Commit separately:
```
docs(scope): update documentation for <feature>
```

### 8. Push and Create PR

```bash
git push -u origin "$BRANCH_NAME"

gh pr create --repo $ORG/$PROJECT \
  --title "${BRANCH_TYPE}(scope): description" \
  --body "Closes #${ISSUE_NUMBER}

## Summary
- Brief description of changes

## Test Plan
- How to verify the changes"
```

**Required**:
- `Closes #<NUMBER>` keyword to link issue
- **Language: MANDATORY English only** - All PR titles and descriptions MUST be written in English
- No Claude/AI references, emojis, or Co-Authored-By (see `commit-settings.md`)

After PR creation, capture the PR URL from `gh pr create` output for the summary.

### 9. Monitor CI

After PR creation, monitor CI with non-blocking polling:

```bash
# Wait briefly for workflows to register
sleep 8
```

Poll **all** PR checks every 30 seconds, max 10 minutes:

```bash
gh run list --repo $ORG/$PROJECT --branch "$BRANCH_NAME" \
  --json databaseId,name,status,conclusion
```

**Decision table — apply per run, evaluate ALL runs each poll cycle:**

| All runs status | Any conclusion=failure | Action |
|-----------------|----------------------|--------|
| All `completed` | No | All pass → proceed to merge |
| All `completed` | Yes | Diagnose, fix, push, re-poll |
| Any `in_progress` or `queued` | — | Poll again after 30s |

**Merge gate**: Do NOT merge until every run shows `status: completed`.
A run that is `in_progress` or `queued` is NOT a passing run — wait for it.

**Timeout**: If 10-minute polling limit is reached and any run is still
`in_progress` or `queued`, stop polling, report the current status table
to the user, and **do NOT merge**. Ask the user whether to wait longer
or leave the PR open for manual merge.

**Do NOT** use `gh run watch` — it blocks the entire session.

On CI failure, fix the issue and push. Repeat up to 3 attempts. After 3 failures,
convert the PR to draft and report the status.

### 10. Squash Merge

When all CI checks pass:

```bash
gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash --delete-branch
```

If merge fails (e.g., review required), report the status and skip merge.

### 11. Close Related Issues and Epics

After merge:

```bash
# Verify the linked issue was closed by the merge
STATE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json state -q '.state')
if [[ "$STATE" != "CLOSED" ]]; then
    gh issue close $ISSUE_NUMBER --repo $ORG/$PROJECT
fi
```

**Epic closure**: If the issue references a parent epic (e.g., `Part of #N`),
check if all sub-issues of that epic are now closed. If so, close the epic
with a summary comment.

### 12. Update Original Issue

**IMPORTANT**: All issue comments **MUST** be written in **English only**, regardless of the project's primary language or user's locale.

```bash
gh issue comment <NUMBER> --repo $ORG/$PROJECT \
  --body "Implementation PR: #<PR_NUMBER>"
```

---

## Team Mode Instructions

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

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | **All issue comments, PR titles, PR descriptions, and commit messages MUST be written in English only** |
| Issue linking | `Closes #NUM` required in PR |
| Build verification | Must pass before PR creation |

## Output

After completion, provide summary:

```markdown
## Work Summary

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #$ISSUE_NUMBER - Title |
| Branch | $BRANCH_NAME |
| Execution mode | Solo / Team |
| PR | [#PR_NUMBER](https://github.com/$ORG/$PROJECT/pull/PR_NUMBER) |
| Commits | N commits |

### Changes Made
- List of changes

### Files Modified
- file1.cpp
- file2.h

### Next Steps
- Any follow-up items
```

**IMPORTANT**: Always include the full PR URL in the output (e.g., `https://github.com/org/repo/pull/123`).

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Project directory exists | "Project directory not found: [path]" | Verify project path in configuration |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |
| Issue exists | "Issue #NUM not found" | Verify issue number is correct |
| Issue is open | "Issue #NUM is not open" | Cannot work on closed issues |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No matching issues (auto-select) | Report "No open issues found with specified priority" | Create new issue or adjust priority filter |
| Issue already assigned | Report assignment status, offer to proceed or skip | Confirm continuation or select different issue |
| Branch already exists | Report existing branch, offer to reuse or rename | Delete old branch or use new name |
| Build failure (inline) | Report error output, attempt auto-fix | Fix build errors and re-run inline |
| Build failure (background) | Detect via log polling, diagnose error pattern | Fix errors and re-run in background |
| Test failure (inline) | Report failing tests with details | Fix tests and retry inline |
| Test failure (background) | Detect via log polling, report specific failures | Fix tests and retry in background |
| Build/test timeout | Report last known output, check system resources | Increase timeout or split build |
| Push rejected | Report rejection reason (non-fast-forward, protected branch) | Pull latest changes or request permissions |
| PR creation failed | Report GitHub API error with details | Check repository permissions |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Team mode: teammate failure | Fallback to Solo Mode from last completed phase | Automatic recovery |
| Team mode: file conflict | Lead resolves conflict between dev and doc-writer | Ensure non-overlapping file ownership |
| Team mode: review loop exceeded | Approve with remaining items noted in PR | Max 2 review rounds enforced |
| Team mode: coordination timeout | Shutdown team, preserve branch commits | Continue manually or re-run Solo |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
