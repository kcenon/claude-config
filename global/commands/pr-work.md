# PR Work Command

Analyze and fix failed CI/CD workflows for a pull request.

## Usage

```
/pr-work <project-name> <pr-number>
```

**Example**:
```
/pr-work hospital_erp_system 42
/pr-work messaging_system 156
/pr-work thread_system 89
```

## Arguments

`$ARGUMENTS` format: `<project-name> <pr-number>`

- **Project name**: Repository name under `kcenon/`
- **PR number**: Pull request number to fix

Parsing:
```bash
PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
PR_NUMBER=$(echo "$ARGUMENTS" | awk '{print $2}')
```

## Instructions

### 1. PR Information Retrieval

```bash
gh pr view $PR_NUMBER --repo kcenon/$PROJECT --json title,state,headRefName,checks
```

Identify:
- PR title and branch name
- Current PR state
- Failed checks/workflows

### 2. Failed Workflow Analysis

```bash
# List failed workflow runs for the PR
gh run list --repo kcenon/$PROJECT --branch <head-branch> --status failure --limit 5

# Get detailed log for failed run
gh run view <RUN_ID> --repo kcenon/$PROJECT --log-failed
```

For each failed workflow:
1. Identify the failing job and step
2. Extract error messages
3. Determine root cause

### 3. Checkout PR Branch

```bash
cd $PROJECT
git fetch origin
git checkout <head-branch>
git pull origin <head-branch>
```

### 4. Fix Issues

Based on workflow analysis, fix the identified issues:

| Failure Type | Common Fixes |
|--------------|--------------|
| **Build error** | Fix compilation errors, missing dependencies |
| **Test failure** | Fix failing tests or update test expectations |
| **Lint error** | Apply code formatting, fix style violations |
| **Type error** | Fix type mismatches, add missing types |
| **Missing header** | Add required #include statements |
| **Link error** | Fix undefined references, library linking |

### 5. Verify Fix Locally

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

### 6. Commit Fix

```bash
git add <fixed-files>
git commit -m "fix(<scope>): <description>

Fixes CI failure: <brief explanation>"
```

**Commit rules**:
- Type: Usually `fix`, `build`, `test`, or `ci`
- Language: English only
- No Claude/AI references
- No Co-Authored-By
- No emojis

### 7. Push and Verify

```bash
git push origin <head-branch>
```

After push:
```bash
# Monitor workflow status
gh run list --repo kcenon/$PROJECT --branch <head-branch> --limit 3

# Wait for completion and check result
gh run watch <RUN_ID> --repo kcenon/$PROJECT
```

### 8. Iterate if Needed

If workflows still fail:
1. Repeat steps 2-7
2. Each fix should be a separate commit
3. Continue until all workflows pass

## Policies

| Item | Rule |
|------|------|
| Language | English for all commits |
| Attribution | No Claude, AI, Co-Authored-By references |
| Emojis | Forbidden in commits |
| Commit style | Conventional Commits format |

## Output

After completion, provide summary:

```markdown
## PR Fix Summary

| Item | Value |
|------|-------|
| Project | $PROJECT |
| PR | #$PR_NUMBER |
| Branch | branch-name |

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
