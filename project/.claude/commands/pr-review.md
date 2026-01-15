# PR Review Command

Review pull requests with comprehensive analysis.

## Usage

```
/pr-review [PR_NUMBER]
```

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
