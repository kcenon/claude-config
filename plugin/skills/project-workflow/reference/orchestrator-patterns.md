# Orchestrator Pattern Templates

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/orchestrator-patterns`.
> **Architecture patterns**: See `rules/workflow/reference/agent-teams.md` for the 6 architecture patterns these templates implement.

## Table of Contents

- [Template A: Agent Team Mode](#template-a-agent-team-mode)
- [Template B: Sub-Agent Mode](#template-b-sub-agent-mode)
- [Data Passing Protocols](#data-passing-protocols)
- [Workspace Convention](#workspace-convention)
- [Error Handling Strategies](#error-handling-strategies)
- [Test Scenarios](#test-scenarios)

## Template A: Agent Team Mode

### Overview

Use when 2+ agents need real-time collaboration (Fan-out/Fan-in, Producer-Reviewer, Supervisor patterns).

### Orchestrator Skill Structure

```yaml
---
name: {domain}-orchestrator
description: "{domain} agent team coordinator. Creates and manages a team of specialized agents for {task}."
user-invocable: true
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep]
---
```

### Workflow Phases

#### Phase 1: Preparation
- Parse user input and validate requirements
- Create `_workspace/` directory
- Save input artifacts to `_workspace/00_input/`

#### Phase 2: Team Assembly
- `TeamCreate(team_name, members)` with defined roles
- `TaskCreate` with task dependencies (blockedBy relationships)
- Assign initial tasks to team members

#### Phase 3: Execution
- Team members self-coordinate via `SendMessage`
- Leader monitors progress via `TaskGet` and automatic idle alerts
- Output files follow naming convention: `_workspace/{phase}_{agent}_{artifact}.{ext}`
- Use `SendMessage(to: "all")` for broadcast updates

#### Phase 4: Integration
- Read all output artifacts from `_workspace/`
- Synthesize consolidated output
- Resolve conflicts between agent outputs

#### Phase 5: Cleanup
- `SendMessage` shutdown notice to team members
- `TeamDelete` to release resources
- Preserve `_workspace/` for audit trail (do NOT delete)

### Example: Code Review Orchestrator
```
Lead creates team: security-reviewer, performance-reviewer, test-reviewer
-> TaskCreate: 3 parallel review tasks (no dependencies)
-> Each reviewer reads code, writes findings to _workspace/
-> Reviewers share discoveries via SendMessage
-> Lead reads all findings, produces consolidated review report
-> TeamDelete, _workspace/ preserved
```

## Template B: Sub-Agent Mode

### Overview

Use when agents work independently without inter-communication (Expert Pool pattern, simple parallel tasks).

### Workflow

```
Main Agent:
  -> Agent("task-1-agent", prompt="...", run_in_background=true)
  -> Agent("task-2-agent", prompt="...", run_in_background=true)
  -> Wait for all results
  -> Integrate outputs
```

### Key Differences from Team Mode

| Aspect | Agent Team | Sub-Agent |
|--------|-----------|-----------|
| Communication | Direct via SendMessage | Results return to main only |
| Coordination | Shared task list | Main manages all |
| Error handling | Retry via message + task reassign | Retry once, proceed with partial |
| Token cost | Higher (persistent contexts) | Lower (disposable contexts) |
| Best for | Collaborative tasks | Independent parallel tasks |

### Error Handling
- On failure: retry once with adjusted prompt
- On second failure: proceed with partial results, note gap in output
- Never block the entire workflow for one sub-agent failure

## Data Passing Protocols

| Strategy | Tool | When to Use | Example |
|----------|------|-------------|---------|
| **Message-based** | `SendMessage` | Real-time coordination, feedback exchange, lightweight state | "Found SQL injection in auth.py:45" |
| **Task-based** | `TaskCreate`/`TaskUpdate` | Progress tracking, dependency management, work requests | Create task "Review auth module" blocked by "Implement auth" |
| **File-based** | `Read`/file paths | Large data, structured outputs, audit trail | `_workspace/02_security_review_findings.md` |

### When to Use Which

- **Feedback between agents**: Message-based (immediate, no file I/O)
- **Work assignment**: Task-based (tracks completion, manages dependencies)
- **Deliverables and artifacts**: File-based (persistent, structured, auditable)
- **Status updates**: Message-based for urgent, task-based for tracking

## Workspace Convention

### Directory Structure

```
_workspace/
  00_input/                           # Original input artifacts
  {phase}_{agent}_{artifact}.{ext}    # Intermediate outputs
  final/                              # Consolidated deliverables
```

### File Naming Convention

`{phase}_{agent}_{artifact}.{ext}`

| Component | Format | Example |
|-----------|--------|---------|
| `phase` | 2-digit number | `01`, `02`, `03` |
| `agent` | agent name (kebab-case) | `security-reviewer` |
| `artifact` | descriptive name | `findings`, `report`, `data` |
| `ext` | file extension | `.md`, `.json`, `.csv` |

**Examples:**
- `01_security-reviewer_findings.md`
- `02_performance-reviewer_metrics.json`
- `03_lead_consolidated-report.md`

### Workspace Lifecycle
1. Created at workflow start
2. Populated during execution
3. **Preserved after completion** (audit trail)
4. Add `_workspace/` to `.gitignore`

## Error Handling Strategies

| Situation | Agent Team Strategy | Sub-Agent Strategy |
|-----------|-------------------|-------------------|
| Agent fails task | SendMessage feedback + reassign task | Retry once with adjusted prompt |
| Agent timeout | TaskUpdate to reassign, notify lead | Proceed without, note in output |
| Conflicting outputs | SendMessage discussion between agents | Main agent resolves with context |
| Partial results | Continue with available data, flag gaps | Merge available results, note gaps |
| All agents fail | Lead performs task directly as fallback | Main performs task directly |

### Retry Limits
- Agent Team: Up to 2 retries via task reassignment
- Sub-Agent: 1 retry maximum
- Producer-Reviewer: 2-3 review cycles maximum

## Test Scenarios

### Normal Flow Test
1. Provide representative input
2. Verify team creation / agent spawning
3. Verify task assignment and completion
4. Verify artifact creation in `_workspace/`
5. Verify final output quality and completeness

### Error Flow Test
1. Simulate agent failure (invalid input, timeout)
2. Verify error handling triggers correctly
3. Verify graceful degradation (partial results, not crash)
4. Verify cleanup occurs (TeamDelete, workspace preserved)

---

*Reference document for multi-agent orchestration patterns. Version 1.0.0*
