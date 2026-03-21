---
paths:
  - ".claude/rules/**"
alwaysApply: false
---

# Agent Teams and Parallel Workflow Patterns

> **Version**: 1.1.0
> **Parent**: [GitHub PR Guidelines](../github-pr-5w1h.md)
> **Purpose**: Decision framework for Claude Code parallel execution strategies
> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/agent-teams`.

## Decision Matrix

Choose the right parallel strategy based on your task characteristics:

| Scenario | Strategy | Why |
|----------|----------|-----|
| Multi-file feature with tests | **Agent Teams** | Coordination via shared tasks, teammate messaging |
| Quick code search or analysis | **Subagent** | Fast, disposable context, results return to main |
| Mass code migration (find-and-replace) | **`/batch`** + worktrees | Parallel isolated changes across files |
| Isolated feature branch development | **Worktree** | Full git isolation, independent sessions |
| Code review from multiple angles | **Agent Teams** | Teammates review security, performance, tests in parallel |
| Debugging competing hypotheses | **Agent Teams** | Teammates test different theories, share findings |

## Strategy Comparison

| Feature | Agent Teams | Subagents | Worktrees | `/batch` |
|---------|-------------|-----------|-----------|----------|
| **Context** | Own context window per teammate | Own context, results return | Separate git branches | Parallel isolated agents |
| **Communication** | Direct teammate-to-teammate messaging | Report back to main only | Manual via git | Results collected by main |
| **Coordination** | Shared task list, mailbox system | Main agent manages all | Git-based isolation | Main orchestrates workers |
| **Best for** | Complex parallel work with discussion | Focused, sequential tasks | Independent feature work | Large-scale file changes |
| **Token usage** | High (scales linearly with teammates) | Moderate | Same as single session | High (parallel sessions) |

## Agent Teams Configuration

### Enable Agent Teams

Add to `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### Team Limit

Control the maximum number of concurrent teams via `MAX_TEAMS` environment variable.
A `PreToolUse` hook on `TeamCreate` enforces this limit by counting directories in `~/.claude/teams/`.

```json
{
  "env": {
    "MAX_TEAMS": "3"
  }
}
```

| Value | Meaning |
|-------|---------|
| `1` | Single team only (strictest) |
| `3` | Default — allows 3 concurrent teams across sessions |
| `0` or unset | No limit (hook still runs but defaults to 3) |

When the limit is reached, `TeamCreate` is blocked with a message to delete unused teams first.

### Display Mode

Set in `settings.json` or via CLI flag:

```json
{
  "teammateMode": "auto"
}
```

```bash
# CLI override (takes precedence over settings.json)
claude --teammate-mode tmux
claude --teammate-mode in-process
```

| Mode | Behavior | Requirements |
|------|----------|-------------|
| `auto` | Split panes if tmux/iTerm2 available, otherwise in-process | None |
| `in-process` | All teammates in same terminal | None |
| `tmux` | Split-pane display via tmux | `brew install tmux` |

### When to Use Agent Teams

- Tasks that naturally decompose into 2-3 parallel streams
- When agents need to coordinate (one writes code, another writes tests)
- Research from multiple angles (security audit + performance review)
- Long-running tasks where idle agents can pick up new work

### When NOT to Use Agent Teams

- Simple single-file changes (overhead exceeds benefit)
- Tasks requiring strict sequential ordering
- Quick lookups or explorations (use subagents instead)
- Fewer than 3 tasks to parallelize

### Recommended Team Sizing

| Team Size | Use Case |
|-----------|----------|
| 2-3 | Focused pair work (implement + test, review + fix) |
| 3-5 | Multi-angle investigation or feature development |
| 5+ | Avoid — coordination overhead exceeds benefits |

Aim for 5-6 tasks per teammate for optimal productivity.

## Launching Agent Teams

Request teams in natural language — no special command required:

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
```

### Coordination Commands

```
# Assign work to specific teammates
Ask the researcher to investigate the cache layer

# Require plan approval before implementation
Spawn an architect teammate to refactor the auth module.
Require plan approval before they make any changes.

# Direct messaging
Talk to the performance reviewer about database indexes

# Graceful shutdown
Ask the researcher teammate to shut down

# Clean up entire team
Clean up the team
```

### Plan Approval Workflow

Teammates can be required to get approval before implementing:

```
Spawn a teammate to refactor the auth module.
Require plan approval before making any changes.
```

When plan approval is required:
1. Teammate analyzes the codebase and drafts a plan
2. Teammate sends the plan to the lead for review
3. Lead approves, rejects, or requests modifications
4. Teammate proceeds only after approval

This prevents teammates from making large, uncoordinated changes.

### Team Config Storage

| Path | Purpose |
|------|---------|
| `~/.claude/teams/` | Saved team configurations for reuse |
| `~/.claude/tasks/` | Shared task list state between teammates |

### Keyboard Shortcuts (In-Process Mode)

| Shortcut | Action |
|----------|--------|
| `Shift+Down` | Cycle through teammates |
| `Ctrl+T` | Access shared task list |
| `Enter` | Send message to currently focused teammate |
| `Escape` | Return focus to lead agent |

## TeammateIdle Hook

Fires when a teammate finishes its turn and is about to go idle.

### Hook Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "TeammateIdle",
  "teammate_name": "researcher",
  "team_name": "my-project",
  "cwd": "/path/to/project",
  "permission_mode": "default"
}
```

### Decision Control

Uses **exit code only** (not JSON decision control):

| Exit Code | Effect |
|-----------|--------|
| `0` | Allow teammate to go idle |
| `2` | Block idle — stderr message sent as feedback to teammate |

### Example: Quality Gate Hook

```bash
#!/bin/bash
# Prevent teammate from going idle if build artifacts are missing

if [ ! -f "./dist/output.js" ]; then
  echo "Build artifact missing. Run the build before stopping." >&2
  exit 2  # Block idle, provide feedback
fi

exit 0  # Allow idle
```

### Example: settings.json Configuration

```json
"TeammateIdle": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/session-logger.sh teammate-idle",
        "timeout": 5,
        "async": true
      }
    ]
  }
]
```

## TaskCompleted Hook

Fires when a teammate completes a task from the shared task list.

### Hook Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "TaskCompleted",
  "task_id": "task-456",
  "task_subject": "Implement user validation",
  "teammate_name": "backend",
  "team_name": "my-project",
  "cwd": "/path/to/project"
}
```

### Decision Control

Uses **exit code only** (not JSON decision control):

| Exit Code | Effect |
|-----------|--------|
| `0` | Accept task completion |
| `2` | Block completion — stderr message sent as feedback to teammate |

Exit code 2 is useful for enforcing quality gates (e.g., requiring tests to pass before a task is considered complete).

## Context Inheritance

| Inherited | Not Inherited |
|-----------|---------------|
| CLAUDE.md files | Lead's conversation history |
| MCP server configuration | In-progress task context |
| Skills and commands | Lead's tool approvals |
| Permission settings | — |

Include task-specific context in the spawn prompt since teammates start with a fresh conversation.

## Limitations (Experimental Feature)

- No session resumption with in-process teammates
- Task status may lag (manual updates sometimes needed)
- One team per session maximum; cross-session limit controlled by `MAX_TEAMS` (default: 3)
- No nested teams — only the lead can create teams
- Teammates cannot spawn their own teammates
- Lead is fixed for lifetime of team
- Not supported in: VS Code integrated terminal, Windows Terminal, Ghostty (for split-pane mode)

## Practical Examples

### Example 1: Feature Development

```
Create a team for implementing the user notification system:
- Teammate "backend": Implement notification service and API endpoints
- Teammate "frontend": Build notification UI components
- Teammate "tests": Write integration tests for the notification flow
```

### Example 2: Code Review

```
Create a team to review the authentication refactor in PR #89:
- Teammate "security": Focus on authentication vulnerabilities
- Teammate "performance": Profile database query patterns
- Teammate "coverage": Verify test coverage for edge cases
```

### Example 3: Debugging

```
Create a team to investigate the intermittent timeout issue:
- Teammate "network": Analyze network layer and connection pooling
- Teammate "database": Profile slow queries and lock contention
- Teammate "logs": Correlate error patterns across log files
```

## Best Practices

1. **Wait for teammates to finish before reviewing their work** — checking intermediate state leads to confusion
2. **Avoid file conflicts** — assign distinct file sets to each teammate (e.g., backend vs. frontend)
3. **Include context in spawn prompts** — teammates start with fresh conversations, so provide relevant file paths, issue numbers, and requirements
4. **Use plan approval for risky changes** — require approval when teammates modify shared code or architecture
5. **Keep teams small** — 2-3 teammates is optimal; beyond 5, coordination overhead dominates
6. **Assign clear ownership** — each task should have exactly one teammate responsible
7. **Use the shared task list** — `Ctrl+T` to track progress across all teammates

## Troubleshooting

### Teammates not spawning

1. Verify the feature flag: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `settings.json` `env`
2. Check `teammateMode` setting — `tmux` mode requires tmux to be installed
3. Restart Claude Code after changing settings

### Tmux panes not splitting

- Verify tmux is installed: `tmux -V`
- Ensure terminal supports split panes (not supported in VS Code integrated terminal, Windows Terminal, Ghostty)
- Fall back to `in-process` mode: `claude --teammate-mode in-process`

### Task list out of sync

- Task status may lag; teammates can manually update task status
- Use `Ctrl+T` to view the latest shared task list state

### Teammate stuck or unresponsive

- Send a direct message to the teammate to check its status
- If unresponsive, ask the teammate to shut down and respawn a new one
- As a last resort, clean up the entire team and start fresh

---

*Reference document for parallel workflow configuration. Version 1.1.0*
