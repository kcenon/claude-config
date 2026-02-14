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

```bash
# Run the same checks locally before pushing
# Adapt to project's build system

# Build
cmake --build build/ --config Release
# or: make, cargo build, npm run build, etc.

# Test
ctest --test-dir build/ --output-on-failure
# or: make test, cargo test, npm test, pytest, etc.

# Lint (if applicable)
# clang-format, black, prettier, etc.
```

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

After push:
```bash
# Monitor workflow status
gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --limit 3

# Wait for completion and check result
gh run watch <RUN_ID> --repo $ORG/$PROJECT
```

### 9. Iterate if Needed

If workflows still fail, repeat steps 2-8 with the following limits:

#### Iteration Limits

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max retry attempts | 3 | Balance between automation and human review |
| Workflow wait timeout | 10 minutes | Typical CI completion time |
| Pause between retries | Wait for CI completion | Avoid redundant fixes |

#### Workflow Monitoring with Timeout

```bash
# Wait for workflow with timeout (600 seconds = 10 minutes)
timeout 600 gh run watch <RUN_ID> --repo $ORG/$PROJECT

# Check exit code
if [ $? -eq 124 ]; then
    echo "Workflow timed out after 10 minutes"
    # Continue with current status check
fi
```

#### Iteration Rules

1. Each fix should be a separate commit
2. Track attempt count (max 3 attempts)
3. **Post failure analysis comment** (Step 3) at the start of each iteration
4. After each fix, wait for workflow completion or timeout
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
| Workflow timeout | 10 minutes per run |

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
| Fix verification failed | Report local test/build failure, pause workflow | Debug and fix before pushing |
| Push rejected | Report rejection reason | Pull latest or resolve conflicts |
| Workflow still failing after fix | Continue with retry until max attempts reached | Monitor retry count |
| Max retries exceeded | Escalate with PR comment and label, report final status | Review failures manually |
| Workflow wait timeout | Report timeout, check workflow status | May need to increase timeout or check CI health |
| API rate limit | Report "GitHub API rate limit exceeded, resets at [time]" | Wait or authenticate with different token |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
