# Error Handling

Prerequisite checks, runtime errors, and batch mode errors for the issue-work skill.

---

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
| Team mode: file conflict | Lead collects conflict file list, determines primary owner via git blame, applies primary owner's changes, preserves non-owner's changes in a separate commit | Assign distinct file ownership at task creation; if conflict occurs, Lead arbitrates based on git blame history |
| Team mode: review loop exceeded | Approve with remaining items noted in PR | Max 2 review rounds enforced |
| Team mode: coordination timeout | Shutdown team, preserve branch commits | Continue manually or re-run Solo |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |

### Batch Mode Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No repos found (cross-repo) | Report "No accessible repositories found" | Check `gh auth status` or use `--org` |
| No open issues found | Report "No open issues matching criteria" | Adjust `--priority` filter or create issues |
| GitHub API rate limit during discovery | Pause until reset, then resume | Wait or reduce `--limit` |
| Single item failure in batch | Mark FAILED, continue to next item | Review failed items in batch summary |
| Session interrupted during batch | Write progress to `.claude/resume.md` | Resume with next session start |
| All items in batch fail | Report batch summary with all failures | Review individual failure reasons |
