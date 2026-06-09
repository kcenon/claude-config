# Error Handling and Common CI Failure Patterns

Prerequisite checks, runtime errors, batch mode errors, and common CI failure patterns for the pr-work skill.

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
