---
paths:
  - ".claude/rules/**"
alwaysApply: false
---

# Agent Teams and Parallel Workflow Patterns

> **Version**: 1.0.0
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

### Display Mode

```json
{
  "teammateMode": "auto"
}
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

### Keyboard Shortcuts (In-Process Mode)

| Shortcut | Action |
|----------|--------|
| `Shift+Down` | Cycle through teammates |
| `Ctrl+T` | Access shared task list |

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
- One team per session maximum
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

---

*Reference document for parallel workflow configuration. Version 1.0.0*
