# Error Handling

Prerequisite checks and runtime error handling for the release command.

---

## Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Inside git repo | "Not a git repository" | Navigate to a git repository |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

## Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Invalid version format | Report "Invalid version format" with example | Use semver format (1.2.0) |
| Tag already exists | Report "Tag vX.X.X already exists" | Choose different version |
| No commits since last release | Report "No new commits since PREVIOUS_TAG" | Verify commit history |
| Tag push failed | Report "Failed to push tag" | Check repository permissions |
| Release creation failed | Report GitHub API error with details | Check repository permissions |
| Network error | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Team mode: teammate failure | Fallback to Solo Mode from last completed step | Automatic recovery |
| Team mode: reviewer disagrees on version | Report version concern to user for decision | User decides final version |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
