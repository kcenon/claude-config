# Agent Definition Frontmatter Specification

Complete reference for all YAML frontmatter fields available in `.claude/agents/{name}.md` files. This supplements the minimal structure shown in `agent-design-patterns.md` with the full specification.

---

## Table of Contents

1. [Required Fields](#1-required-fields)
2. [Tool Control](#2-tool-control)
3. [Model & Execution](#3-model--execution)
4. [Permission & Security](#4-permission--security)
5. [Context & Memory](#5-context--memory)
6. [Lifecycle & Display](#6-lifecycle--display)
7. [Field Resolution Order](#7-field-resolution-order)
8. [Examples by Use Case](#8-examples-by-use-case)

---

## 1. Required Fields

Only two fields are required. All others are optional with sensible defaults.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique identifier. Lowercase letters, digits, and hyphens only. Used for `subagent_type` and `SendMessage({to: name})`. |
| `description` | string | When Claude should delegate to this agent. Write aggressively -- Claude is conservative about auto-delegation, so explicit trigger situations compensate. |

```yaml
---
name: security-reviewer
description: "Security-focused code review. Use when reviewing PRs, auditing authentication/authorization code, checking for OWASP Top 10 vulnerabilities, or when 'security' is mentioned in a review context."
---
```

---

## 2. Tool Control

Restrict which tools the agent can access. Useful for enforcing read-only behavior or preventing unintended modifications.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tools` | list | All tools | Allowlist -- agent can ONLY use these tools |
| `disallowedTools` | list | None | Denylist -- agent can use all tools EXCEPT these |

Use one or the other, not both. Allowlists are safer for restrictive agents; denylists are easier for permissive agents.

### Tool Names

Common tool names: `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `Agent`, `WebSearch`, `WebFetch`, `NotebookEdit`.

### Restricting Spawnable Subagent Types

To limit which subagents an agent can create, use the `Agent()` syntax in the tools list:

```yaml
tools: [Read, Grep, Glob, Bash, "Agent(worker, researcher)"]
```

This allows the agent to spawn only `worker` and `researcher` subagents -- not arbitrary types.

### Selection Criteria

| Situation | Approach | Example |
|-----------|----------|---------|
| Agent should only read code | Allowlist | `tools: [Read, Grep, Glob]` |
| Agent needs most tools but not web | Denylist | `disallowedTools: [WebSearch, WebFetch]` |
| Agent should not spawn subagents | Denylist | `disallowedTools: [Agent]` |
| Agent needs full access | Omit both | Inherits all tools |

---

## 3. Model & Execution

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `model` | string | `inherit` | `sonnet`, `opus`, `haiku`, full model ID, or `inherit` (use parent session's model) |
| `maxTurns` | integer | None | Maximum agentic turns before forced termination. Prevents runaway agents. |
| `effort` | string | Inherit | `low`, `medium`, `high`, or `max`. Overrides session-level effort. |
| `background` | boolean | `false` | `true` = always run in background. Concurrent execution, pre-approved permissions. |

### Model Resolution Order

When multiple sources specify a model, this precedence applies:

```
Environment variable (CLAUDE_MODEL)
  ↓ overrides
Per-invocation parameter (Agent tool's model field)
  ↓ overrides
Frontmatter (model field in .md file)
  ↓ overrides
Parent session's model
```

### maxTurns Guidance

| Agent type | Recommended maxTurns |
|-----------|---------------------|
| Quick lookup / analysis | 5-10 |
| Moderate implementation | 15-30 |
| Complex multi-step task | 50-100 |
| Omit for unconstrained | -- |

---

## 4. Permission & Security

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `permissionMode` | string | `default` | Controls how the agent handles permission prompts |

### Permission Modes

| Mode | Behavior | Use case |
|------|----------|----------|
| `default` | Prompts user for each permission | Safety-critical agents |
| `acceptEdits` | Auto-accepts file edits, prompts for other actions | Implementation agents |
| `auto` | Auto-accepts most actions | Trusted automation |
| `dontAsk` | Skips actions requiring permission (no prompt, no execution) | Background agents that should never block |
| `bypassPermissions` | No permission checks at all | Fully trusted pipelines |
| `plan` | Requires plan approval before execution | Risky operations needing oversight |

### Precedence Rule

Parent session's `bypassPermissions` takes precedence over subagent's `permissionMode`. A subagent cannot escalate beyond the parent's trust level.

### Background Agent Permissions

Background agents use a pre-approval model: permissions granted at spawn time remain active. Actions not pre-approved are auto-denied (not queued). Design background agents with narrow tool allowlists to avoid silent denials.

---

## 5. Context & Memory

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `memory` | string | None | Persistent memory scope: `user`, `project`, or `local` |
| `skills` | list | None | Skills to preload (full content injected into context) |
| `mcpServers` | list | None | MCP servers accessible to this agent |

### Memory Scopes

| Scope | Location | VCS | Shared | Best for |
|-------|----------|-----|--------|----------|
| `user` | `~/.claude/agent-memory/<name>/` | No | No | Personal cross-project knowledge |
| `project` | `.claude/agent-memory/<name>/` | Yes | Team | Shared project patterns, API conventions |
| `local` | `.claude/agent-memory-local/<name>/` | No | No | Local environment specifics |

Memory works via a `MEMORY.md` index file in the scope directory. The system auto-includes the first 200 lines / 25KB into context. Agents are instructed to curate when exceeding limits.

### Memory Selection Criteria

| Situation | Scope | Reason |
|-----------|-------|--------|
| Reviewer learning project patterns | `project` | Knowledge benefits the whole team |
| Personal workflow preferences | `user` | Private, spans multiple projects |
| Local env quirks (paths, tools) | `local` | Machine-specific, not shareable |
| One-off agent, no learning needed | Omit | No persistence overhead |

### Skills Preloading

Subagents do NOT inherit parent session's skills. To give an agent skill knowledge, list skills explicitly:

```yaml
skills: [code-quality, security-audit]
```

The full content of each listed skill's SKILL.md is injected into the agent's context at startup.

### MCP Server Scoping

Assign MCP servers to specific agents to avoid bloating the parent session's context:

```yaml
mcpServers: [database-tools, api-explorer]
```

MCP servers defined here are available only to this agent, not the parent session.

---

## 6. Lifecycle & Display

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks` | object | None | Lifecycle hooks (e.g., `PreToolUse`) |
| `isolation` | string | None | `worktree` creates a temporary git worktree |
| `color` | string | None | Visual identifier in terminal |
| `initialPrompt` | string | None | Auto-submitted prompt on startup |

### Isolation

`isolation: worktree` creates a temporary git worktree so the agent works on an isolated copy of the repository. Changes in the worktree do not affect the main working directory until explicitly merged.

Best for: test runners, experimental implementations, any agent whose file changes should be reviewed before integration.

### Color

Available: `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`.

Useful for visual identification when multiple agents run in split-pane (tmux) display mode.

### Hooks

Agent-specific lifecycle hooks for fine-grained control:

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      command: "validate-command.sh"
```

Hook input is passed as JSON via stdin. Exit code 2 blocks the operation and sends feedback to the agent.

### Initial Prompt

Auto-submitted on agent startup -- useful for bootstrap behavior:

```yaml
initialPrompt: "Read the project README and check your memory for established patterns before starting work."
```

---

## 7. Field Resolution Order

```
┌─────────────────────────────────────┐
│ Environment variables               │  Highest priority
│ (CLAUDE_MODEL, etc.)                │
├─────────────────────────────────────┤
│ Per-invocation parameters           │
│ (Agent tool's model/mode fields)    │
├─────────────────────────────────────┤
│ Frontmatter fields                  │
│ (in .claude/agents/{name}.md)       │
├─────────────────────────────────────┤
│ Parent session defaults             │  Lowest priority
│ (inherited from the calling agent)  │
└─────────────────────────────────────┘
```

**Exception:** `permissionMode` -- parent's `bypassPermissions` overrides any subagent setting. Subagents cannot escalate trust.

---

## 8. Examples by Use Case

### Read-only Code Analyzer

```yaml
---
name: code-analyzer
description: "Analyze codebase architecture, patterns, and conventions. Use when the user asks to understand, explore, or document existing code."
tools: [Read, Grep, Glob]
model: sonnet
effort: medium
---
```

### Full-capability Implementer

```yaml
---
name: feature-builder
description: "Implement features end-to-end: code, tests, documentation. Use when the user asks to build, add, or create new functionality."
model: opus
permissionMode: acceptEdits
maxTurns: 50
skills: [coding-guidelines, project-workflow]
---
```

### Background Test Runner

```yaml
---
name: test-runner
description: "Run test suites and report results. Use proactively after code changes to verify nothing is broken."
tools: [Read, Grep, Glob, Bash]
model: haiku
background: true
isolation: worktree
permissionMode: auto
maxTurns: 20
color: green
---
```

### Memory-enabled Reviewer

```yaml
---
name: pr-reviewer
description: "Review pull requests for code quality, security, and performance. Learns project patterns over time."
tools: [Read, Grep, Glob, Bash]
model: opus
memory: project
initialPrompt: "Check your memory for established review patterns before starting."
color: purple
---
```

### Scoped Research Agent

```yaml
---
name: api-researcher
description: "Research external APIs and documentation. Use when the user needs to understand a third-party API."
tools: [Read, Grep, Glob, WebSearch, WebFetch]
disallowedTools: [Edit, Write, Bash]
model: sonnet
mcpServers: [api-explorer]
---
```
