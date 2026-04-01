---
name: pr-work
description: Analyze and fix failed CI/CD workflows for a pull request with automated retry and escalation.
argument-hint: "[project-name] [pr-number] [--solo|--team] [--limit N] [--dry-run]"
user-invocable: true
---

# PR Work Command

Analyze and fix failed CI/CD workflows for a pull request.

## Usage

```
/pr-work                                            # Batch: all repos, all failing PRs
/pr-work <project-name>                             # Batch: all failing PRs in project
/pr-work <pr-number>                                # Single: fix PR in current project
/pr-work <project-name> <pr-number>                 # Single: fix specific PR
/pr-work <organization>/<project-name> <pr-number>
```

**Examples**:
```
/pr-work                                            # Batch: all repos, all PRs with failed CI
/pr-work hospital_erp_system                        # Batch: all failing PRs in project
/pr-work 42                                         # Single: fix PR #42 (auto-detect repo)
/pr-work hospital_erp_system 42                     # Single: fix PR #42 in project
/pr-work hospital_erp_system 42 --org mycompany     # Explicit org
/pr-work mycompany/hospital_erp_system 42           # Full path format
/pr-work 42 --solo                                  # Force solo mode (sequential)
/pr-work 42 --team                                  # Force team mode (diagnoser + fixer)
/pr-work --org mycompany                            # Batch: all repos in org
/pr-work hospital_erp_system --limit 5              # Batch: top 5 failing PRs
/pr-work hospital_erp_system --dry-run              # Preview batch plan only
```

## Arguments

- `[project-name]`: Project name or full repository path (optional)
  - If omitted with PR number: auto-detect from current directory git remote
  - If omitted without PR number: **Batch mode** — discover all repos, process all failing PRs

- `[pr-number]`: Pull request number (optional)
  - If provided: Work on the specified PR (single-item mode)
  - If omitted with project: **Batch mode** — process all failing PRs in the project
  - If omitted without project: **Batch mode** — process all failing PRs across all repos

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode for all items
  - `--team` — Force team mode for all items
  - If omitted in single-item mode: auto-recommend based on failure complexity, then ask user
  - If omitted in batch mode: auto-decide per item using weighted scoring (no per-item prompt)

- `[--limit N]`: Maximum number of items to process in batch mode (default: 20, max: 50)

- `[--dry-run]`: Show batch plan only, do not execute

- `[--org <organization>]`: Scope to a specific GitHub organization

**Auto-checkout**: In single-item mode, the command automatically detects and checks out the PR's branch.

## Argument Parsing

Parse `$ARGUMENTS` and determine organization, PR number, and batch mode:

```bash
ARGS="$ARGUMENTS"
PR_NUMBER=""
PROJECT=""
ORG=""
EXEC_MODE=""
BATCH_MODE="single"   # single | single-repo | cross-repo
BATCH_LIMIT=20
DRY_RUN=false

# Extract flags
ORIGINAL_ARGS="$ARGS"
if [[ "$ARGS" == *"--solo"* ]]; then EXEC_MODE="solo"; ARGS=$(echo "$ARGS" | sed 's/--solo//g'); fi
if [[ "$ARGS" == *"--team"* ]]; then EXEC_MODE="team"; ARGS=$(echo "$ARGS" | sed 's/--team//g'); fi
if [[ "$ARGS" == *"--dry-run"* ]]; then DRY_RUN=true; ARGS=$(echo "$ARGS" | sed 's/--dry-run//g'); fi
if [[ "$ARGS" =~ --limit[[:space:]]+([0-9]+) ]]; then BATCH_LIMIT="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--limit[[:space:]]+[0-9]+//g'); fi
if [[ "$ARGS" =~ --org[[:space:]]+([^[:space:]]+) ]]; then ORG="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--org[[:space:]]+[^[:space:]]+//g'); fi

# Trim remaining args
ARGS=$(echo "$ARGS" | xargs)

# Determine mode based on remaining args
if [[ -z "$ARGS" && -z "$ORG" ]]; then
    # No args at all → cross-repo batch
    BATCH_MODE="cross-repo"

elif [[ -z "$ARGS" && -n "$ORG" ]]; then
    # Only --org provided → cross-repo batch scoped to org
    BATCH_MODE="cross-repo"

elif [[ "$ARGS" =~ ^[0-9]+$ ]]; then
    # Single numeric arg → PR number in current project (unchanged behavior)
    BATCH_MODE="single"
    PR_NUMBER="$ARGS"
    REMOTE_URL=$(git remote get-url origin 2>/dev/null)
    ORG=$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    PROJECT=$(echo "$REMOTE_URL" | sed -E 's|.*[:/][^/]+/([^/]+)\.git$|\1|' | sed -E 's|.*[:/][^/]+/([^/]+)$|\1|')

elif [[ "$ARGS" =~ ^[a-zA-Z] ]] && ! [[ "$ARGS" =~ [[:space:]][0-9]+([[:space:]]|$) ]]; then
    # Project name only, no PR number → single-repo batch
    BATCH_MODE="single-repo"
    if [[ "$ARGS" == *"/"* ]]; then
        ORG=$(echo "$ARGS" | cut -d'/' -f1 | xargs)
        PROJECT=$(echo "$ARGS" | cut -d'/' -f2 | xargs)
    else
        PROJECT="$ARGS"
        if [[ -z "$ORG" ]]; then
            cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
            ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
        fi
    fi

else
    # Project + PR number → single-item mode (unchanged)
    BATCH_MODE="single"
    if [[ "$ARGS" == *"/"* ]]; then
        REPO_PATH=$(echo "$ARGS" | awk '{print $1}')
        ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
        PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
        PR_NUMBER=$(echo "$ARGS" | awk '{print $2}')
    else
        PROJECT=$(echo "$ARGS" | awk '{print $1}')
        PR_NUMBER=$(echo "$ARGS" | awk '{print $2}')
        if [[ -z "$ORG" ]]; then
            cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
            ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
        fi
    fi
fi
```

## Instructions

### Mode Routing

- If `$BATCH_MODE == "single-repo"` or `$BATCH_MODE == "cross-repo"` → Execute **Batch Mode Instructions** below
- If `$BATCH_MODE == "single"` → Execute **Phase 0: Execution Mode Selection** (skip Batch Mode)

---

## Batch Mode Instructions

Process multiple failing PRs sequentially. Each PR is handled using the existing Solo or Team workflow.

### B-0. Batch Discovery

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

### B-1. Failure Severity Sorting

Assign each failing PR a severity score:

| Signal | Score |
|--------|-------|
| Multiple failed workflows | 0 (most urgent) |
| Single failed workflow, build error | 1 |
| Single failed workflow, test error | 2 |
| Single failed workflow, lint/style error | 3 |

Sort FAILING_PRS by: score ascending → `createdAt` ascending → repo name ascending.

Apply `--limit N` (default: 20, max: 50). If no failing PRs found, report "No open PRs with failed CI found" and exit.

### B-2. Auto Size/Mode Estimation per Item

For each PR, decide solo vs team **without prompting the user**.

**Weighted scoring matrix:**

| Factor | Weight | Solo Signal (0) | Team Signal (1) |
|--------|--------|-----------------|-----------------|
| Failed workflow count | 3 | 1 | 2+ |
| Error category count | 2 | Single category | Multiple categories |
| Previous fix attempts | 2 | 0 pushes after first failure | 1+ pushes (recurring) |
| Error log complexity | 1 | < 20 lines of error output | 20+ lines |

**Decision**: Sum the weights where Team Signal matches. If total >= 4 → `team`, otherwise → `solo`.

**Override**: If `--solo` or `--team` flag was passed globally, apply that mode to ALL items.

### B-3. Batch Plan Summary and Approval

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
  1. "Approve and start (Recommended)" — proceed with batch execution
  2. "Modify plan" — user can exclude items or change modes
  3. "Cancel" — abort batch

If `--dry-run` is set, display the plan and exit without prompting.

### B-4. Sequential Execution Loop

Process each item one at a time:

```
for each item in approved batch plan:
    1. Log progress: "[N/TOTAL] Starting: $REPO PR #$PR_NUMBER — $TITLE ($MODE)"

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

    6. Log completion: "[N/TOTAL] Completed: $REPO PR #$PR_NUMBER — $RESULT"

    7. Pause 2 seconds between items (rate limiting)
```

**Failure handling per item:**
- CI failure after 3 retries → mark FAILED, add escalation comment to PR, continue to next
- Team mode failure → fallback to solo for THIS item, then continue
- MAX_TEAMS exceeded → force solo for this item
- PR merged/closed by someone else → mark SKIPPED, continue

### B-5. Batch Summary Report

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
- org/repo-b #15: Lint failure persists — `clang-format` version mismatch. Manual fix needed.
```

Delete `.claude/resume.md` after successful batch completion.

---

### Phase 0: Execution Mode Selection (Single-Item Mode)

Determine whether to run in Solo mode (single agent, sequential) or Team mode (diagnoser + fixer agents in parallel).

#### 0-1. Gather Failure Information

```bash
FAILED_RUNS=$(gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --status failure --limit 10 --json databaseId,name -q 'length')
```

#### 0-2. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-3. If no flag was provided (interactive selection)

Auto-recommend based on failure complexity:

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Failed workflows | 1 | 2+ |
| Error categories | Single (build OR test OR lint) | Multiple (build AND test) |
| Previous fix attempts | 0 | 1+ (already tried, recurring) |

Use `AskUserQuestion` to present the choice:

- **Question**: "PR #$PR_NUMBER has $FAILED_RUNS failed workflow(s). Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential diagnosis and fix. Lower token cost. Best for single-category failures."
- **Description for Team**: "Parallel diagnoser + fixer. Diagnoser analyzes next failure while fixer resolves current one. Best for multi-category failures."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-4. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode Instructions** (Steps 1-11 below)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions** (after Solo Mode section)

---

## Solo Mode Instructions

### 1. PR Information Retrieval

```bash
# Get PR information including branch name
PR_INFO=$(gh pr view $PR_NUMBER --repo $ORG/$PROJECT --json title,state,headRefName,checks)

# Extract branch name from PR
HEAD_BRANCH=$(echo "$PR_INFO" | jq -r '.headRefName')

if [[ -z "$HEAD_BRANCH" ]]; then
    echo "Error: Cannot determine branch name for PR #$PR_NUMBER"
    exit 1
fi

echo "PR #$PR_NUMBER branch: $HEAD_BRANCH"
```

Identify:
- PR title and branch name
- Current PR state
- Failed checks/workflows

**Branch auto-detection**: The PR's branch name is automatically extracted from `headRefName`.

### 2. Failed Workflow Analysis

```bash
# List failed workflow runs for the PR
gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --status failure --limit 5

# Get detailed log for failed run
gh run view <RUN_ID> --repo $ORG/$PROJECT --log-failed
```

For each failed workflow:
1. Identify the failing job and step
2. Extract error messages
3. Determine root cause

### 3. Post Failure Analysis Comment

**MANDATORY**: After analyzing failures, post a comment to the PR documenting the analysis.

**IMPORTANT**: All PR comments **MUST** be written in **English only**, regardless of the project's primary language or user's locale.

```bash
gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "$(cat <<'EOF'
## CI/CD Failure Analysis

**Analysis Time**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Attempt**: #[ATTEMPT_NUMBER]

### Failed Workflows

| Workflow | Job | Step | Status |
|----------|-----|------|--------|
| [workflow-name] | [job-name] | [step-name] | Failed |

### Root Cause Analysis

**Primary Error**:
```
[Extract key error message here]
```

**Analysis**:
[Brief explanation of why this error occurred]

**Identified Issues**:
1. [Issue 1 description]
2. [Issue 2 description]

### Proposed Fix

| Issue | Proposed Solution | Files Affected |
|-------|-------------------|----------------|
| [Issue 1] | [Solution description] | `path/to/file.ext` |

### Next Steps
- [ ] Apply proposed fixes
- [ ] Verify locally
- [ ] Push and monitor CI

---
*Automated failure analysis - Attempt #[ATTEMPT_NUMBER]*
EOF
)"
```

#### Comment Guidelines

| Item | Requirement |
|------|-------------|
| **Language** | **MANDATORY: English only** - All PR comments MUST be written in English, regardless of project language or user locale |
| Timing | Immediately after failure analysis, before attempting fix |
| Content | Include actual error messages (sanitized if needed) |
| Format | Use tables and code blocks for readability |
| Updates | Edit existing comment or add new comment per attempt |

#### Sensitive Data Handling

Before posting, sanitize the following from error logs:
- API keys and secrets
- Internal hostnames/IPs
- Personal identifiable information (PII)
- Database connection strings

### 4. Checkout PR Branch

**Auto-checkout**: The command automatically checks out the PR's branch.

```bash
# Navigate to project directory (if not already there)
if [[ ! -z "$PROJECT" && -d "$PROJECT" ]]; then
    cd "$PROJECT"
fi

# Fetch latest changes
git fetch origin

# Check if branch exists locally
if git show-ref --verify --quiet refs/heads/"$HEAD_BRANCH"; then
    # Branch exists locally, switch to it
    git checkout "$HEAD_BRANCH"
    git pull origin "$HEAD_BRANCH"
else
    # Branch doesn't exist locally, create and track
    git checkout -b "$HEAD_BRANCH" "origin/$HEAD_BRANCH"
fi

echo "Switched to PR branch: $HEAD_BRANCH"
```

**Branch handling**:
- If branch exists locally: checkout and pull latest changes
- If branch doesn't exist: create local branch tracking remote

### 5. Fix Issues

Based on workflow analysis, fix the identified issues:

| Failure Type | Common Fixes |
|--------------|--------------|
| **Build error** | Fix compilation errors, missing dependencies |
| **Test failure** | Fix failing tests or update test expectations |
| **Lint error** | Apply code formatting, fix style violations |
| **Type error** | Fix type mismatches, add missing types |
| **Missing header** | Add required #include statements |
| **Link error** | Fix undefined references, library linking |

### 6. Verify Fix Locally

Follow the build verification workflow rule (`build-verification.md`) to select the
appropriate strategy based on expected build duration.

#### Strategy Selection

| Build System | Typical Duration | Strategy |
|-------------|-----------------|----------|
| `go build` / `cargo check` | < 30s | Inline (synchronous) |
| `cmake --build` / `gradle build` | 30s - 5min | Background + log polling |
| Full test suites (`ctest` / `pytest`) | 1 - 10min | Background + log polling |

#### Inline Strategy (short builds)

For builds expected under 30 seconds:

```
Bash(command="go build ./... && go test ./...", timeout=60000)
Bash(command="cargo check && cargo test", timeout=60000)
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

Do NOT retry the same build without changes -- diagnose first.

### 7. Commit Fix

```bash
git add <fixed-files>
git commit -m "fix(<scope>): <description>

Fixes CI failure: <brief explanation>"
```

**Commit rules**:
- Type: Usually `fix`, `build`, `test`, or `ci`
- **Language: MANDATORY English only** - All commit messages MUST be written in English
- No Claude/AI references, emojis, or Co-Authored-By (see `commit-settings.md`)

### 8. Push and Verify

```bash
git push origin "$HEAD_BRANCH"
```

#### TLS/Sandbox Error Handling

If `gh` commands fail with TLS certificate errors in sandbox mode:

```
x509: certificate signed by unknown authority
tls: failed to verify certificate
```

Use `dangerouslyDisableSandbox` for the `gh` command, or suggest the user
run outside sandbox. Never assume authentication has failed without verifying —
ask the user to confirm if unclear.

#### CI Monitoring

After push, monitor CI with non-blocking polling:

**Step A**: Get the triggered run ID
```bash
# Wait briefly for workflow to register
sleep 5
RUN_ID=$(gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --limit 1 --json databaseId -q '.[0].databaseId')
```

**Step B**: Poll CI status (non-blocking, every 30 seconds)
```bash
gh run view $RUN_ID --repo $ORG/$PROJECT --json status,conclusion -q '{status: .status, conclusion: .conclusion}'
```

**Step C**: Interpret result

| status | conclusion | Action |
|--------|-----------|--------|
| completed | success | Proceed to summary |
| completed | failure | Fetch failed logs, go to Step 9 |
| completed | cancelled | Report cancellation, investigate or re-trigger |
| completed | timed_out | Report timeout, check workflow config |
| in_progress | — | Poll again after 30s interval |
| queued | — | Poll again after 30s interval |
| waiting | — | Poll again after 30s interval (approval gate) |

**Step D**: On failure, fetch specific error logs
```bash
gh run view $RUN_ID --repo $ORG/$PROJECT --log-failed 2>&1 | head -100
```

#### CI Polling Limits

**Do NOT** use `gh run watch` — it blocks the entire session.
**Do NOT** poll more frequently than every 30 seconds — respect API rate limits.
**Do NOT** block indefinitely — max 10 minutes of polling per run.
**Do NOT** merge while any check is `queued` or `in_progress`.

If the 10-minute polling limit is reached with CI still running:
1. Stop polling immediately
2. Report current status of all checks to the user
3. **Do NOT merge** — the user decides next steps

### 9. Iterate if Needed

If workflows still fail, repeat steps 2-8 with the following limits:

#### Iteration Limits

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max retry attempts | 3 | Balance between automation and human review |
| CI poll interval | 30 seconds | Respect GitHub API rate limits |
| CI max poll duration | 10 minutes | Typical CI completion time |
| Pause between retries | Wait for CI result via polling | No blocking watch |

#### CI Status Polling Loop

Instead of blocking with `gh run watch`, use non-blocking status polling:

```
For each poll (max 20 iterations x 30s = 10 minutes):
  1. Check: gh run view $RUN_ID --repo $ORG/$PROJECT --json status,conclusion
  2. If completed + failure -> fetch logs, diagnose, fix, go to next attempt
  3. If completed + success -> done
  4. If in_progress -> wait 30s, poll again
  5. If max polls reached -> report timeout, escalate
```

This approach:
- Detects failures as soon as CI completes (not after 10min timeout)
- Provides status updates to the user between polls
- Allows early intervention when failure is detected

**Do NOT** use `gh run watch` -- it blocks the entire session.

#### Iteration Rules

1. Each fix should be a separate commit
2. Track attempt count (max 3 attempts)
3. **Post failure analysis comment** (Step 3) at the start of each iteration
4. After each fix, monitor CI via polling (Step 8)
5. Continue until all workflows pass OR max attempts reached

#### Per-Attempt Comment Updates

For subsequent attempts, update the PR with a follow-up comment:

**IMPORTANT**: All PR comments **MUST** be written in **English only**.

```bash
gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "$(cat <<'EOF'
## CI/CD Failure Analysis - Attempt #[N]

**Previous Attempt Result**: [Passed/Failed]
**Previous Fix Applied**: [Brief description of what was fixed]

### New Failure Analysis

| Workflow | Job | Step | Previous Status | Current Status |
|----------|-----|------|-----------------|----------------|
| [workflow-name] | [job-name] | [step-name] | Fixed | New Failure |

### What Changed

**Previous Fix**:
- [What was fixed in the previous attempt]

**Why It Still Fails**:
- [Analysis of why the previous fix didn't fully resolve the issue]

### New Root Cause

**Error**:
```
[New error message]
```

**Analysis**:
[Updated analysis based on new information]

### Updated Proposed Fix

| Issue | Proposed Solution | Files Affected |
|-------|-------------------|----------------|
| [Issue] | [Solution] | `path/to/file.ext` |

---
*Automated failure analysis - Attempt #[N] of 3*
EOF
)"
```

### 10. Auto-Merge on Success

When all CI checks pass after fixing:

```bash
gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash --delete-branch
```

If merge fails (e.g., review required, branch protection), report the status
and skip merge. Do not force-merge.

### 11. Failure Escalation

When max retry attempts (3) are exceeded without success:

#### Escalation Steps

**IMPORTANT**: All escalation comments **MUST** be written in **English only**.

1. **Add summary comment to PR**:
   ```bash
   gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "## Auto-fix Summary

   **Attempted fixes**: 3
   **Status**: Manual intervention required

   ### Attempted Fixes
   1. [commit-hash] fix description - Still failing
   2. [commit-hash] fix description - Still failing
   3. [commit-hash] fix description - Still failing

   ### Current Failures
   - Workflow: [workflow-name]
   - Error: [error-summary]

   Please review manually."
   ```

2. **Add label** (if available):
   ```bash
   gh pr edit $PR_NUMBER --repo $ORG/$PROJECT --add-label "needs-manual-review"
   ```

3. **Report final status** to user with detailed failure information

#### Escalation Decision Matrix

| Attempt | Action |
|---------|--------|
| 1-2 | Auto-fix and retry |
| 3 | Final attempt with detailed logging |
| After max | Escalate to human review |

---

## Team Mode Instructions

Three-team workflow with feedback loop for CI/CD failure resolution. Dev team fixes code, Review team validates fixes and manages PR, Doc team updates documentation if behavior changes.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
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

  Review ──► Dev: "Fix validated, but also fix [issue]" (feedback loop)
  Dev ──► Review: "Fix applied, ready for re-review"
  Review ──► Lead: "All fixes validated, ready for merge"
```

### T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (PR Information Retrieval, Failed Workflow Analysis).
Collect the list of failed workflows and their error categories.

Prepare shared context for all teammates:
- `$ORG`, `$PROJECT`, `$PR_NUMBER`, `$HEAD_BRANCH`
- Failed workflow names and error summaries

### T-2. Create Team and Tasks

```
TeamCreate(team_name="pr-fix-$PR_NUMBER", description="Fix CI failures for PR #$PR_NUMBER")
```

Create tasks with dependencies:

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Analyze all failed workflows and categorize errors | reviewer | — | A |
| 2 | Post failure analysis comment to PR | reviewer | 1 | A |
| 3 | Fix identified issues (attempt 1) | dev | 1 | B |
| 4 | Verify fix locally (build + test) | dev | 3 | B |
| 5 | Review: validate fix correctness and completeness | reviewer | 4 | C |
| 6 | Update docs/comments if fix changes behavior | doc-writer | 4 | C |
| 7 | Apply review change requests (if any) | dev | 5 | D |
| 8 | Re-review after changes (if Task 7 was needed) | reviewer | 7 | D |
| 9 | Push and monitor CI | lead | 5 or 8, 6 | E |

### T-3. Spawn Teammates

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
    2. Task 4: Verify locally — run build and tests to confirm the fix works.
    3. Task 7: If reviewer sends change requests after reviewing your fix,
       apply the requested changes and re-verify locally.

    Rules:
    - Commit format: fix(scope): description (English only, no emojis)
    - No Claude/AI references in commits
    - Validate incrementally: build after each fix
    - Do NOT retry the same build without changes — diagnose first

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

### T-4. Workflow Phases (Lead coordinates)

**Phase A — Failure Analysis (Reviewer):**
1. Reviewer analyzes all failed CI workflows (Task 1)
2. Reviewer posts failure analysis comment to PR (Task 2)

**Phase B — Fix Implementation (Dev):**
1. Dev reads reviewer's analysis and applies fixes (Task 3)
2. Dev verifies locally with build + tests (Task 4)

**Phase C — Review + Documentation (parallel):**
1. Reviewer validates fix correctness and completeness (Task 5)
2. Doc-writer checks if docs need updating (Task 6)
3. These run in parallel — both depend on Task 4 completing

**Phase D — Feedback Loop (if needed):**

```
Reviewer has Critical/Major findings?
  │
  ├─ No → Approve (skip Tasks 7, 8)
  │
  └─ Yes → Send change requests to dev
            │
            ▼
     Dev applies changes (Task 7)
            │
            ▼
     Reviewer re-reviews (Task 8)
            │
     ┌──────┴──────┐
     │             │
  Approved    Still issues?
     │        (max 2 rounds,
     ▼         then approve
   Task 9      with notes)
```

**Phase E — Push and CI (Lead):**
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

### T-5. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

### T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Report what was completed (which fixes applied, which CI runs passed)
3. Offer to continue in Solo Mode from the current attempt number

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | **All PR comments and commit messages MUST be written in English only** |
| Max retry attempts | 3 before escalation |
| CI poll interval | >= 30 seconds (respect API rate limits) |
| CI max poll duration | 10 minutes per run (20 polls x 30s) |

## Output

After completion, provide summary:

```markdown
## PR Fix Summary

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| PR | #$PR_NUMBER |
| Branch | $HEAD_BRANCH |
| Execution mode | Solo / Team |
| Attempts | X/3 |
| Final Status | Success / Escalated |

### Workflows Fixed
| Workflow | Status | Fix Applied |
|----------|--------|-------------|
| Build | Fixed | description |
| Test | Fixed | description |

### Commits Made
1. `fix(scope): description` - hash
2. `fix(scope): description` - hash

### Current Status
- [ ] All workflows passing
- [ ] Ready for review

### Escalation (if applicable)
- Escalation reason: [reason]
- PR comment added: Yes/No
- Label applied: needs-manual-review
```

## Common CI Failure Patterns

### Build Failures
```bash
# Missing header
error: 'SomeClass' was not declared in this scope
# Fix: Add #include "some_class.h"

# Undefined reference
undefined reference to `SomeFunction()`
# Fix: Link library or implement function
```

### Test Failures
```bash
# Assertion failed
Expected: X, Actual: Y
# Fix: Update code logic or test expectation

# Timeout
Test timed out after 60s
# Fix: Optimize test or increase timeout
```

### Lint Failures
```bash
# Formatting
error: code should be formatted with clang-format
# Fix: Run formatter

# Style violation
warning: variable name should be camelCase
# Fix: Rename variable
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Project directory exists | "Project directory not found: [path]" | Verify project path in configuration |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| PR not found | Report "PR #X not found" and list valid PR numbers | Verify PR number with `gh pr list` |
| All workflows passing | Report "No failed workflows found - PR is ready for review" | Proceed to review or merge |
| Branch not found | Report "Branch not found" with PR details | Check if branch was deleted |
| Cannot checkout branch | Report checkout failure reason | Resolve local changes or conflicts |
| Local build failure (short) | Report error output, attempt auto-fix | Fix and re-run inline |
| Local build failure (long) | Detect via log polling, diagnose error pattern | Fix and re-run in background |
| Push rejected | Report rejection reason | Pull latest or resolve conflicts |
| CI failure detected via poll | Fetch failed logs immediately, start next attempt | No wait for full timeout |
| CI poll timeout (10min) | Report last known status, escalate | Check CI health or increase poll duration |
| CI run cancelled | Report cancellation, investigate cause | Re-trigger workflow or check repo settings |
| CI run timed out | Report workflow timeout, check config | Increase workflow timeout or optimize CI |
| CI status unknown | Report API response, suggest manual check | Run `gh run view` manually |
| Max retries exceeded | Escalate with PR comment and label, report final status | Review failures manually |
| API rate limit | Report "GitHub API rate limit exceeded, resets at [time]" | Wait or authenticate with different token |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Team mode: teammate failure | Fallback to Solo Mode from current attempt | Automatic recovery |
| Team mode: coordination timeout | Shutdown team, report partial progress | Continue manually or re-run |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |

### Batch Mode Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No repos found (cross-repo) | Report "No accessible repositories found" | Check `gh auth status` or use `--org` |
| No failing PRs found | Report "No open PRs with failed CI found" | All PRs are passing or no open PRs |
| GitHub API rate limit during discovery | Pause until reset, then resume | Wait or reduce `--limit` |
| Single item failure in batch | Mark FAILED, add escalation comment, continue | Review failed items in batch summary |
| Session interrupted during batch | Write progress to `.claude/resume.md` | Resume with next session start |
| All items in batch fail | Report batch summary with all failures | Review individual failure reasons |
