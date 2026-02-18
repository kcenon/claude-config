# PR Work Command

Analyze and fix failed CI/CD workflows for a pull request.

## Usage

```
/pr-work <pr-number>                                # Work on PR in current project (auto-checkout branch)
/pr-work <project-name> <pr-number> [--org <organization>]
/pr-work <organization>/<project-name> <pr-number>
```

**Example**:
```
/pr-work 42                                        # Auto: detect org/project, checkout PR branch
/pr-work hospital_erp_system 42                    # Auto-detect org, checkout PR branch
/pr-work hospital_erp_system 42 --org mycompany    # Explicit org, checkout PR branch
/pr-work mycompany/hospital_erp_system 42          # Full path, checkout PR branch
```

## Arguments

`$ARGUMENTS` format:
- `<pr-number>` (work on specific PR in current project, auto-checkout branch)
- `<project-name> <pr-number> [--org <organization>]`
- `<organization>/<project-name> <pr-number>`

- **PR number only**: Use current project with specified PR number, auto-checkout PR branch
- **Project name**: Repository name (or full path with organization)
- **PR number**: Pull request number to fix
- **--org**: GitHub organization or user (optional, auto-detected if not provided)

**Auto-checkout**: The command automatically detects and checks out the PR's branch.

## Organization Detection

Parse `$ARGUMENTS` and determine organization:

```bash
# Single number argument - PR number in current project
if [[ "$ARGUMENTS" =~ ^[0-9]+$ ]]; then
    PR_NUMBER="$ARGUMENTS"

    # Get org and project from git remote in current directory
    REMOTE_URL=$(git remote get-url origin 2>/dev/null)
    if [[ -z "$REMOTE_URL" ]]; then
        echo "Error: No git remote 'origin' found in current directory"
        exit 1
    fi

    ORG=$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    PROJECT=$(echo "$REMOTE_URL" | sed -E 's|.*[:/][^/]+/([^/]+)\.git$|\1|' | sed -E 's|.*[:/][^/]+/([^/]+)$|\1|')

    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization from git remote"
        exit 1
    fi

    echo "Detected: $ORG/$PROJECT PR #$PR_NUMBER"

# Check if --org flag is provided
elif [[ "$ARGUMENTS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    PR_NUMBER=$(echo "$ARGUMENTS" | awk '{print $2}')
    ORG=$(echo "$ARGUMENTS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')

# Check if first argument contains / (full path format)
elif [[ "$(echo "$ARGUMENTS" | awk '{print $1}')" == *"/"* ]]; then
    REPO_PATH=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
    PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
    PR_NUMBER=$(echo "$ARGUMENTS" | awk '{print $2}')

# Auto-detect from git remote
else
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    PR_NUMBER=$(echo "$ARGUMENTS" | awk '{print $2}')
    cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

## Instructions

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
# → Returns task_id
```

**Step B**: Poll build output (non-blocking, every 10-15 seconds)
```
TaskOutput(task_id="<id>", block=false, timeout=10000)
# → Check for error patterns or completion indicators
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

Do NOT retry the same build without changes — diagnose first.

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
| in_progress | — | Poll again after 30s interval |
| queued | — | Poll again after 30s interval |

**Step D**: On failure, fetch specific error logs
```bash
gh run view $RUN_ID --repo $ORG/$PROJECT --log-failed 2>&1 | head -100
```

**Do NOT** use `gh run watch` — it blocks the entire session.
**Do NOT** poll more frequently than every 30 seconds — respect API rate limits.

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
  2. If completed + failure → fetch logs, diagnose, fix, go to next attempt
  3. If completed + success → done
  4. If in_progress → wait 30s, poll again
  5. If max polls reached → report timeout, escalate
```

This approach:
- Detects failures as soon as CI completes (not after 10min timeout)
- Provides status updates to the user between polls
- Allows early intervention when failure is detected

**Do NOT** use `gh run watch` — it blocks the entire session.

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

### 10. Failure Escalation

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

## Policies

See [_policy.md](./_policy.md) for common rules.

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
| CI status unknown | Report API response, suggest manual check | Run `gh run view` manually |
| Max retries exceeded | Escalate with PR comment and label, report final status | Review failures manually |
| API rate limit | Report "GitHub API rate limit exceeded, resets at [time]" | Wait or authenticate with different token |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
