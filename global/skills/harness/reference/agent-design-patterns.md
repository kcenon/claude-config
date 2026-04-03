# Agent Team Design Patterns

## Table of Contents

1. [Execution Modes: Agent Teams vs Sub-agents](#execution-modes-agent-teams-vs-sub-agents)
2. [Agent Team Architecture Types](#agent-team-architecture-types)
3. [Composite Patterns](#composite-patterns)
4. [Agent Type Selection](#agent-type-selection)
5. [Agent Definition Structure](#agent-definition-structure)
6. [Agent Separation Criteria](#agent-separation-criteria)
7. [Skills vs Agents](#skills-vs-agents)
8. [Skill-Agent Connection Methods](#skill-agent-connection-methods)

---

## Execution Modes: Agent Teams vs Sub-agents

Understand the core differences between the two execution modes and choose the appropriate one.

### Agent Teams -- Default Mode

The team leader creates a team with `TeamCreate`, and members run as independent Claude Code instances. Members communicate directly via `SendMessage` and coordinate through shared task lists (`TaskCreate`/`TaskUpdate`).

```
[Leader] <-> [Member A] <-> [Member B]
  |              |              |
  +------ Shared Task List ----+
```

**Core tools:**
- `TeamCreate`: Create team + spawn members
- `SendMessage({to: name})`: Message a specific member
- `SendMessage({to: "all"})`: Broadcast (expensive, use sparingly)
- `TaskCreate`/`TaskUpdate`: Shared task list management

**Characteristics:**
- Members can directly discuss, challenge, and verify each other's work
- Information flows between members without passing through the leader
- Shared task list enables self-coordination (members can claim tasks)
- Members automatically notify the leader when they become idle
- Plan approval mode allows review before risky operations

**Constraints:**
- Only one team can be **active** per session (but teams can be disbanded between phases and new ones created)
- No nested teams (members cannot create their own teams)
- Leader is fixed (cannot be transferred)
- Higher token cost

**Team reconstitution pattern:**
When different specialist combinations are needed per phase: save previous team outputs to files -> clean up team -> create new team. Previous outputs are preserved in `_workspace/` so the new team can access them via Read.

### Sub-agents -- Lightweight Mode

The main agent creates sub-agents via the `Agent` tool. Sub-agents return results only to the main agent and do not communicate with each other.

```
[Main] -> [Sub-A] -> return result
       -> [Sub-B] -> return result
       -> [Sub-C] -> return result
```

**Core tools:**
- `Agent(prompt, subagent_type, run_in_background)`: Create sub-agent

**Characteristics:**
- Lightweight and fast
- Results are summarized and returned to the main context
- Token-efficient

**Constraints:**
- No inter-sub-agent communication
- Main agent handles all coordination
- No real-time collaboration or challenge

### Mode Selection Decision Tree

```
Are there 2+ agents?
+-- Yes -> Is inter-agent communication needed?
|          +-- Yes -> Agent team (default)
|          |         Cross-verification, discovery sharing, real-time feedback improve quality.
|          |
|          +-- No  -> Sub-agents are also viable
|                     For structures needing only result passing (producer-reviewer, expert pool, etc.)
|
+-- No (1 agent) -> Sub-agent
                    A single agent doesn't need team infrastructure.
```

> **Core principle:** Agent teams are the default. When choosing sub-agents, ask yourself: "Is inter-member communication truly unnecessary?"

---

## Agent Team Architecture Types

### 1. Pipeline

Sequential task flow. Each agent's output is the next agent's input.

```
[Analysis] -> [Design] -> [Implementation] -> [Verification]
```

**Best for:** Each stage strongly depends on the previous stage's output.
**Example:** Novel writing -- world-building -> characters -> plot -> prose -> editing.
**Caution:** A bottleneck delays the entire pipeline. Design each stage as independently as possible.
**Team mode fit:** Strong sequential dependency limits team mode benefits. However, team mode is useful if parallel segments exist within the pipeline.

### 2. Fan-out/Fan-in

Parallel processing followed by result integration. Independent tasks execute simultaneously.

```
          +-> [Specialist A] -+
[Dispatch] -> [Specialist B] -+-> [Integration]
          +-> [Specialist C] -+
```

**Best for:** Different perspectives/domains of analysis are needed for the same input.
**Example:** Comprehensive research -- official/media/community/background investigated concurrently -> integrated report.
**Caution:** The integration stage's quality determines overall quality.
**Team mode fit:** The most natural pattern for agent teams. **Always use agent teams for this pattern.** Members share discoveries and challenge each other -- one agent's finding can adjust another's investigation direction in real time, significantly improving quality over solo investigation.

### 3. Expert Pool

Selectively invoke the appropriate specialist based on the situation.

```
[Router] -> { Expert A | Expert B | Expert C }
```

**Best for:** Different processing is needed depending on input type.
**Example:** Code review -- invoke only the relevant expert from security/performance/architecture.
**Caution:** The router's classification accuracy is critical.
**Team mode fit:** Sub-agents are more suitable. Only the needed expert is invoked, so a standing team is unnecessary.

### 4. Producer-Reviewer

Generation and review agents work in pairs.

```
[Producer] -> [Reviewer] -> (if issues) -> [Producer] re-run
```

**Best for:** Output quality assurance is important and objective review criteria exist.
**Example:** Webtoon -- artist generates -> reviewer inspects -> problematic panels are regenerated.
**Caution:** Set a maximum retry count (2-3) to prevent infinite loops.
**Team mode fit:** Agent teams are useful. `SendMessage` enables real-time feedback exchange between producer and reviewer.

### 5. Supervisor

A central agent manages task state and dynamically distributes work to subordinate agents.

```
            +-> [Worker A]
[Supervisor] -> [Worker B]    <- Supervisor distributes dynamically based on state
            +-> [Worker C]
```

**Best for:** Variable workloads or when task distribution must be decided at runtime.
**Example:** Large-scale code migration -- supervisor analyzes the file list and assigns batches to workers.
**Difference from fan-out:** Fan-out pre-assigns work; supervisor adjusts dynamically based on progress.
**Caution:** Set delegation units large enough so the supervisor doesn't become a bottleneck.
**Team mode fit:** Agent teams' shared task list naturally matches the supervisor pattern. Tasks are registered via `TaskCreate`; members claim them.

### 6. Hierarchical Delegation

Upper agents recursively delegate to lower agents. Complex problems are decomposed in stages.

```
[Director] -> [Team Lead A] -> [Worker A1]
                             -> [Worker A2]
            -> [Team Lead B] -> [Worker B1]
```

**Best for:** Problems that naturally decompose hierarchically.
**Example:** Full-stack app development -- director -> frontend lead -> (UI/logic/tests) + backend lead -> (API/DB/tests).
**Caution:** Depth beyond 3 levels causes latency and context loss. Recommended: 2 levels or fewer.
**Team mode fit:** Agent teams cannot be nested (members cannot create teams). Implement level 1 as a team and level 2 as sub-agents, or flatten into a single team.

## Composite Patterns

In practice, composite patterns are more common than single patterns:

| Composite Pattern | Composition | Example |
|-------------------|-------------|---------|
| **Fan-out + Producer-Reviewer** | Parallel generation, each followed by review | Multilingual translation -- 4 languages translated in parallel -> each reviewed by a native speaker |
| **Pipeline + Fan-out** | Some stages in a sequence are parallelized | Analysis (sequential) -> implementation (parallel) -> integration testing (sequential) |
| **Supervisor + Expert Pool** | Supervisor dynamically invokes experts | Customer inquiry handling -- supervisor classifies, then assigns the appropriate expert |

### Execution Mode for Composite Patterns

**Use agent teams for all composite patterns by default.** Active communication between members is the key driver of result quality.

| Scenario | Recommended mode | Reason |
|----------|-----------------|--------|
| **Research + Analysis** | Agent team | Investigators share discoveries, discuss conflicting information in real time |
| **Design + Implementation + Verification** | Agent team | Feedback loops between designer, implementer, and verifier |
| **Supervisor + Workers** | Agent team | Shared task list for dynamic assignment; workers share progress |
| **Producer + Reviewer** | Agent team | Real-time feedback between producer and reviewer minimizes rework |

> Only consider mixing in sub-agents when a single agent performs a completely isolated, one-shot task.

---

## Agent Type Selection

Specify the type via the Agent tool's `subagent_type` parameter. Agent team members can also use custom agent definitions.

### Built-in Types

| Type | Tool access | Best for |
|------|------------|---------|
| `general-purpose` | Full (including WebSearch, WebFetch) | Web research, general-purpose tasks |
| `Explore` | Read-only (no Edit/Write) | Codebase exploration, analysis |
| `Plan` | Read-only (no Edit/Write) | Architecture design, planning |

### Custom Types

Define an agent in `.claude/agents/{name}.md` and invoke it with `subagent_type: "{name}"`. Custom agents have full tool access.

### Selection Criteria

| Situation | Recommended | Reason |
|-----------|-------------|--------|
| Complex role, reused across sessions | **Custom type** (`.claude/agents/`) | Persona and principles managed in files |
| Simple research/collection, prompt suffices | **`general-purpose`** + detailed prompt | No agent file needed |
| Read-only code analysis/review | **`Explore`** | Prevents accidental file modifications |
| Design/planning only | **`Plan`** | Focused on analysis, prevents code changes |
| Implementation requiring file edits | **Custom type** | Full tool access + specialized instructions |

**Principle:** All agents must be defined as `.claude/agents/{name}.md` files. Even built-in types get an agent definition file specifying role, principles, and protocols. Files enable reuse across sessions and explicit team communication protocols ensure collaboration quality.

**Model:** All agents use `model: "opus"` by default. Always include `model: "opus"` when invoking the Agent tool. This is configurable if cost or speed constraints require a different model.

---

## Agent Definition Structure

```markdown
---
name: agent-name
description: "1-2 sentence role description. List trigger keywords."
---

# Agent Name -- One-line Role Summary

You are a [role] specialist in [domain].

## Core Role
1. Role item 1
2. Role item 2

## Working Principles
- Principle 1
- Principle 2

## Input/Output Protocol
- Input: [where and what is received]
- Output: [where and what is written]
- Format: [file format, structure]

## Team Communication Protocol (agent team mode)
- Receive messages from: [who sends what]
- Send messages to: [who receives what]
- Task requests: [what types of tasks to claim from the shared list]

## Error Handling
- [Behavior on failure]
- [Behavior on timeout]

## Collaboration
- Relationships with other agents
```

---

## Agent Separation Criteria

| Criterion | Separate | Merge |
|-----------|----------|-------|
| Specialization | Different domains -> separate | Overlapping domains -> merge |
| Parallelism | Can run independently -> separate | Sequentially dependent -> consider merging |
| Context | Heavy context burden -> separate | Lightweight and fast -> consider merging |
| Reusability | Used by other teams -> separate | Only used by this team -> consider merging |

---

## Skills vs Agents

| Aspect | Skill | Agent |
|--------|-------|-------|
| Definition | Procedural knowledge + tool bundles | Specialist persona + behavioral principles |
| Location | `.claude/skills/` | `.claude/agents/` |
| Trigger | User request keyword matching | Explicit invocation via Agent tool |
| Size | Small to large (workflow) | Small (role definition) |
| Purpose | "How to do it" | "Who does it" |

Skills are **procedural guides** that agents reference when performing tasks.
Agents are **specialist role definitions** that utilize skills.

---

## Skill-Agent Connection Methods

Three ways agents use skills:

| Method | Implementation | Best for |
|--------|---------------|---------|
| **Skill tool invocation** | Specify `invoke /skill-name via Skill tool` in the agent's prompt | When the skill is a standalone workflow and user-invocable |
| **Inline in prompt** | Include skill content directly in the agent definition | When the skill is short (<50 lines) and agent-specific |
| **Reference loading** | Use `Read` to load skill reference/ files on demand | When skill content is large and only conditionally needed |

Recommendation: Skill tool for high reusability, inline for dedicated use, reference loading for large content.
