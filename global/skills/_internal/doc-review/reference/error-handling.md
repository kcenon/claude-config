# Error Handling

Prerequisite checks and runtime error handling for the document review command.

---

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| Docs directory exists | "Directory not found: [path]" | Verify path or use auto-detection |
| Markdown files found | "No .md files found in [path]" | Check directory contains markdown files |
| Git repository (for --fix) | "Not a git repository" | Run from within a git repository |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Agent timeout | Report partial results from completed agents | Re-run with smaller file set |
| No findings | Report clean status with score 10/10 | No action needed |
| Fix introduces new errors | Revert fix, report regression | Manual intervention required |
| File encoding issues | Skip file with warning | Ensure files are UTF-8 |
| Team mode: teammate failure | Fallback to Solo Mode for failed partition | Automatic recovery |
| Team mode: coordination timeout | Aggregate partial results, report incomplete | Re-run failed partitions |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
