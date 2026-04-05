# Orchestrator Skill Templates

The orchestrator is a higher-level skill that coordinates the entire team. Three templates are provided based on the execution mode.

## Table of Contents

1. [Template A: Agent Team Mode (Default)](#template-a-agent-team-mode-default)
2. [Template B: Sub-agent Mode (Lightweight)](#template-b-sub-agent-mode-lightweight)
3. [Template C: Long-Running Session Mode](#template-c-long-running-session-mode)
4. [Writing Principles](#writing-principles)

---

## Template A: Agent Team Mode (Default)

Agent teams are created with `TeamCreate` and coordinate via shared task lists and `SendMessage`.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates the {domain} agent team. {trigger keywords}."
---

# {Domain} Orchestrator

An integration skill that coordinates the {domain} agent team to produce {final deliverable}.

## Execution Mode: Agent Team

## Agent Configuration

| Member | Agent type | Role | Skill | Output |
|--------|-----------|------|-------|--------|
| {teammate-1} | {custom or built-in} | {role} | {skill} | {output-file} |
| {teammate-2} | {custom or built-in} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 1: Preparation
1. Analyze user input -- {what to identify}
2. Create `_workspace/` in the working directory
3. Save input data to `_workspace/00_input/`

### Phase 2: Team Assembly

1. Create team:
   TeamCreate(
     team_name: "{domain}-team",
     members: [
       { name: "{teammate-1}", agent_type: "{type}", model: "opus", prompt: "{role description and task instructions}" },
       { name: "{teammate-2}", agent_type: "{type}", model: "opus", prompt: "{role description and task instructions}" },
       ...
     ]
   )

2. Register tasks:
   TaskCreate(tasks: [
     { title: "{task-1}", description: "{detail}", assignee: "{teammate-1}" },
     { title: "{task-2}", description: "{detail}", assignee: "{teammate-2}" },
     { title: "{task-3}", description: "{detail}", depends_on: ["{task-1}"] },
     ...
   ])

   > 5-6 tasks per member is optimal. Use `depends_on` for tasks with dependencies.

### Phase 3: {Main work -- e.g., investigation/generation/analysis}

**Execution method:** Members self-coordinate

Members claim tasks from the shared task list and work independently.
The leader monitors progress and intervenes when necessary.

**Inter-member communication rules:**
- {teammate-1} sends {certain information} to {teammate-2} via SendMessage
- {teammate-2} saves results to file on completion and notifies the leader
- Members request results from other members via SendMessage when needed

**Artifact storage:**

| Member | Output path |
|--------|------------|
| {teammate-1} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

**Leader monitoring:**
- Receives automatic notification when a member becomes idle
- Sends instructions or reassigns work when a member is stuck
- Checks overall progress via TaskGet

### Phase 4: {Follow-up work -- e.g., verification/integration}
1. Wait for all members to complete (check status via TaskGet)
2. Collect each member's artifacts via Read
3. {Integration/verification logic}
4. Generate final deliverable: `{output-path}/{filename}`

### Phase 5: Cleanup
1. Send shutdown request to members (SendMessage)
2. Clean up team (TeamDelete)
3. Preserve `_workspace/` directory (do not delete intermediate artifacts -- for post-verification and audit trails)
4. Report results summary to user

> **When team reconstitution is needed:** If different specialist combinations are required per phase, clean up the current team with TeamDelete, then create the next phase's team with a new TeamCreate. Previous team's artifacts are preserved in `_workspace/` and accessible via Read.

## Data Flow

```
[Leader] -> TeamCreate -> [teammate-1] <-SendMessage-> [teammate-2]
                              |                            |
                              v                            v
                        artifact-1.md               artifact-2.md
                              |                            |
                              +---------- Read ------------+
                                           v
                                   [Leader: Integration]
                                           v
                                    Final deliverable
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| One member fails/stops | Leader detects -> SendMessage to check status -> restart or create replacement member |
| Majority of members fail | Notify user and confirm whether to proceed |
| Timeout | Use partial results collected so far; terminate incomplete members |
| Data conflict between members | Keep both with source attribution; do not delete |
| Task status delay | Leader checks via TaskGet, then manually TaskUpdate |

## Test Scenarios

### Normal flow
1. User provides {input}
2. Phase 1 produces {analysis result}
3. Phase 2 assembles team ({N} members + {M} tasks)
4. Phase 3: members self-coordinate and perform work
5. Phase 4: integrate artifacts into final result
6. Phase 5: clean up team
7. Expected result: `{output-path}/{filename}` generated

### Error flow
1. In Phase 3, {teammate-2} stops due to an error
2. Leader receives idle notification
3. SendMessage to check status -> attempt restart
4. On restart failure, reassign {teammate-2}'s work to {teammate-1}
5. Proceed to Phase 4 with remaining results
6. Final report notes "{teammate-2}'s area partially uncollected"
```

---

## Template B: Sub-agent Mode (Lightweight)

Sub-agents are invoked directly via the `Agent` tool and return results only to the main agent.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates {domain} agents. {trigger keywords}."
---

# {Domain} Orchestrator

An integration skill that coordinates {domain} agents to produce {final deliverable}.

## Execution Mode: Sub-agent

## Agent Configuration

| Agent | subagent_type | Role | Skill | Output |
|-------|--------------|------|-------|--------|
| {agent-1} | {custom or built-in type} | {role} | {skill} | {output-file} |
| {agent-2} | {custom or built-in type} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 1: Preparation
1. Analyze user input -- {what to identify}
2. Create `_workspace/` in the working directory
3. Save input data to `_workspace/00_input/`

### Phase 2: {Main work -- e.g., investigation/generation/analysis}

**Execution method:** {parallel | sequential | conditional}

{For parallel execution}
Invoke N Agent tools simultaneously in a single message:

| Agent | Input | Output | model | run_in_background |
|-------|-------|--------|-------|-------------------|
| {agent-1} | {input source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |
| {agent-2} | {input source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |

{For sequential execution}
Pass the previous agent's output as the next agent's input:

1. Run {agent-1} -> generates `_workspace/01_{artifact}.md`
2. Run {agent-2} (input: output from step 1) -> generates `_workspace/02_{artifact}.md`

### Phase 3: {Follow-up work -- e.g., verification/integration}
1. Collect Phase 2 artifacts via Read
2. {Integration/verification logic}
3. Generate final deliverable: `{output-path}/{filename}`

### Phase 4: Cleanup
1. Preserve `_workspace/` directory (do not delete intermediate artifacts -- for post-verification and audit trails)
2. Report results summary to user

## Data Flow

```
Input -> [agent-1] -> artifact-1 -+
                                  +-> [Integration] -> Final deliverable
Input -> [agent-2] -> artifact-2 -+
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| One agent fails | Retry once. On re-failure, proceed without that result; note the gap in the report |
| Majority of agents fail | Notify user and confirm whether to proceed |
| Timeout | Use partial results collected so far |
| Data conflict between agents | Keep both with source attribution; do not delete |

## Test Scenarios

### Normal flow
1. User provides {input}
2. Phase 1 produces {analysis result}
3. Phase 2: {N} agents run in parallel, each producing artifacts
4. Phase 3: integrate artifacts into final report
5. Expected result: `{output-path}/{filename}` generated

### Error flow
1. In Phase 2, {agent-2} fails
2. Retry once, still fails
3. Proceed to Phase 3 with remaining results (without {agent-2}'s data)
4. Final report notes "{agent-2}'s area data uncollected"
5. Notify user of partial completion
```

---

## Template C: Long-Running Session Mode

For projects spanning multiple context windows where session continuity is critical. Each session focuses on one feature and leaves code in merge-ready state.

```markdown
---
name: {domain}-session-orchestrator
description: "Long-running session orchestrator for {domain}. Manages feature tracking, session handoff, and merge-ready state across multiple sessions."
---

# {Domain} Session Orchestrator

An orchestrator for multi-session projects where work spans multiple context windows.

## Execution Mode: Long-Running Session

## Feature Configuration

Feature list location: `_workspace/features.json` (JSON format, not Markdown)

## Workflow

### Phase 1: Initialization (first session only)
1. Verify working directory and git state (clean working tree)
2. Run `init.sh` for reproducible environment setup
3. Generate feature list as JSON with acceptance criteria
4. Save to `_workspace/features.json`
5. Create `_workspace/progress.txt` (session log)

### Phase 2: Feature Selection (each session)
1. Read `_workspace/features.json`
2. Read `_workspace/progress.txt` (if exists)
3. Read `_workspace/current_state.md` (if exists -- resume context)
4. Select next feature with status "failing" (respect `dependencies`)
5. Set feature status to "in_progress"

### Phase 3: Implementation
1. Implement the selected feature
2. Write tests covering acceptance criteria
3. Run tests and verify passing
4. Commit with descriptive message referencing feature ID

### Phase 4: Session Handoff
1. Update feature status to "passing" in `_workspace/features.json`
2. Update `_workspace/progress.txt` with session summary
3. Write `_workspace/current_state.md` with detailed resume context
4. Verify merge-ready state:
   - No major bugs in completed features
   - All "passing" features have working tests
   - No broken imports or unresolved dependencies
5. Document exact next action for following session

### Context Reset Protocol (when approaching context limits)
1. Write all intermediate state to `_workspace/` files
2. Commit current work (WIP: prefix if incomplete)
3. Start fresh session -- read state files to resume
4. No summarization loss -- file artifacts are source of truth

## Data Flow

```
Session N:
  Read features.json -> select feature -> implement -> test -> commit
    -> update features.json -> update progress.txt -> write current_state.md

Session N+1:
  Read features.json + progress.txt + current_state.md -> continue
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| Feature implementation stuck | Document blocker in current_state.md, move to next feature |
| Tests failing after implementation | Debug in current session; if unresolvable, note in progress.txt and skip |
| Context limit approaching | Execute Context Reset Protocol above |
| Dependencies not met | Skip feature, select next eligible one |

## Test Scenarios

### Normal flow
1. First session: initialize project, generate feature list
2. Sessions 2-N: implement one feature per session
3. Each session ends in merge-ready state
4. Final session: all features "passing", project complete

### Resume flow
1. Session interrupted mid-feature
2. Next session reads current_state.md
3. Continues from documented checkpoint
4. Completes feature and proceeds normally
```

---

## Writing Principles

1. **Specify execution mode first** -- state "Agent Team", "Sub-agent", or "Long-Running Session" at the top of the orchestrator.
2. **For agent team mode, detail TeamCreate/SendMessage/TaskCreate usage** -- team assembly, task registration, communication rules.
3. **For sub-agent mode, specify all Agent tool parameters** -- name, subagent_type, prompt, run_in_background.
4. **For long-running session mode, specify the session handoff protocol** -- what state files to write, how to resume, merge-ready criteria.
5. **Use absolute file paths** -- no relative paths; always clear paths based on `_workspace/`.
6. **Make inter-phase dependencies explicit** -- which phase depends on which phase's results.
7. **Make error handling realistic** -- do not assume everything succeeds.
8. **Test scenarios are required** -- at least 1 normal + 1 error flow.
9. **Specify context management strategy** -- for long-running harnesses, state whether to use compaction (automatic, lossy) or context reset (manual, lossless via file-based state handoff).

## Reference

For a basic fan-out/fan-in orchestrator structure:
Preparation -> TeamCreate + TaskCreate -> N members work in parallel -> Read + integration -> cleanup.
See the research team example in `team-examples.md`.

For long-running session patterns, context reset protocol, and Generator-Evaluator architecture:
See `long-running-harness-guide.md`.
