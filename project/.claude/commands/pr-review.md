# PR Review Command

Review pull requests with comprehensive analysis.

## Usage

```
/pr-review [PR_NUMBER]
```

## Arguments

- `PR_NUMBER`: Pull request number to review
  - If omitted, detect open PR for current branch

## Options

| Option | Default | Description |
|--------|---------|-------------|
| --depth | standard | Review depth (quick, standard, thorough) |
| --focus | all | Focus area (security, performance, all) |

## Instructions

When reviewing a PR, analyze the following:

### 1. Code Quality
- Check for code style consistency
- Identify potential bugs or issues
- Review error handling
- Check for code duplication

### 2. Security
- Look for security vulnerabilities
- Check input validation
- Review authentication/authorization
- Identify sensitive data exposure

### 3. Performance
- Identify potential performance issues
- Check for unnecessary computations
- Review database queries
- Check memory usage patterns

### 4. Testing
- Verify test coverage
- Check test quality
- Identify missing edge cases

### 5. Documentation
- Check for updated documentation
- Review code comments
- Verify API documentation updates

## Output Format

Provide feedback in this format:

```markdown
## PR Review: #[NUMBER]

### Summary
[Brief summary of the PR]

### Findings

#### Critical
- [List critical issues]

#### Suggestions
- [List suggestions for improvement]

#### Positive
- [List positive aspects]

### Recommendation
[APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION]
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Repository access | "No access to repository" | Verify permissions or request access |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| PR not found | Report "PR #X not found" and suggest `gh pr list` | Verify PR number exists |
| PR already merged | Report "PR #X is already merged - showing historical review" | No action needed |
| PR closed | Report "PR #X is closed without merge" | Reopen PR if review still needed |
| No PR for branch | Report "No open PR found for current branch" and show how to create | Create PR with `gh pr create` |
| Large PR (>1000 lines) | Warn about review complexity, offer to split by file type | Consider splitting PR |
| API rate limit | Report "GitHub API rate limit exceeded, resets at [time]" | Wait or authenticate with different token |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
