---
name: harness
description: "Design and build domain-specific agent team harnesses. Analyzes project domains, selects architecture patterns (Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical, Generator-Evaluator, Long-Running Session), defines specialized agents (.claude/agents/), and generates skills (.claude/skills/) with orchestration. Use when building new agent teams, designing multi-agent workflows, creating domain harnesses, restructuring agent architectures, setting up long-running multi-session projects, or configuring agent frontmatter (tools, memory, permissions)."
argument-hint: "[domain-or-project-description]"
user-invocable: true
disable-model-invocation: true
loop_safe: false
---

# Harness -- Agent Team & Skill Architect

A meta-skill for designing domain/project-specific harnesses: defining each agent's role and generating the skills each agent will use.

**Core principles:**
1. Generate agent definitions (`.claude/agents/`) and skills (`.claude/skills/`).
2. **Use agent teams as the default execution mode.**

## Workflow

### Phase 1: Domain Analysis

1. Identify the domain/project from the user's request.
2. Identify core task types (creation, validation, editing, analysis, etc.).
3. Check existing agents/skills to prevent conflicts or duplication.
4. Explore the project codebase -- tech stack, data models, key modules.
5. **Detect user proficiency** -- gauge technical level from conversational cues (terminology, question depth) and adjust communication tone accordingly. Avoid using terms like "assertion" or "JSON schema" without explanation for users with limited coding experience.

### Phase 2: Team Architecture Design

#### 2-1. Execution Mode: Agent Teams vs Sub-agents

**The default is agent teams.** When two or more agents collaborate, prefer agent teams. Team members coordinate via direct communication (`SendMessage`) and shared task lists (`TaskCreate`), enabling discovery sharing, conflict discussion, and gap coverage that improve result quality.

Use sub-agents only when there is a single agent, or when inter-agent communication is unnecessary (only result passing is needed).

> See `reference/agent-design-patterns.md` for the comparison table and decision tree.

#### 2-2. Architecture Pattern Selection

1. Decompose the work into specialized domains.
2. Choose a team structure (see `reference/agent-design-patterns.md` for details):
   - **Pipeline**: Sequential dependent tasks
   - **Fan-out/Fan-in**: Parallel independent tasks
   - **Expert Pool**: Situational selective invocation
   - **Producer-Reviewer**: Generation followed by quality review
   - **Supervisor**: Central agent manages state and distributes work dynamically
   - **Hierarchical Delegation**: Upper agents recursively delegate to lower agents
   - **Generator-Evaluator**: Strict role separation between generation and evaluation to prevent self-assessment bias. Uses calibrated scoring rubrics and few-shot examples for evaluation.
   - **Long-Running Session**: Initializer + incremental worker pattern for multi-session projects that span multiple context windows. Uses JSON feature tracking and merge-ready state quality gates.

#### 2-3. Agent Separation Criteria

Evaluate along 4 axes: specialization, parallelism, context, and reusability. See `reference/agent-design-patterns.md` for the detailed criteria table.

### Phase 3: Agent Definition Generation

**All agents must be defined as `project/.claude/agents/{name}.md` files.** Never put the role directly into the Agent tool's prompt parameter without an agent definition file. Reasons:
- Agent definitions in files are reusable across sessions.
- Explicit team communication protocols ensure collaboration quality.
- The core value of a harness is separating agents (who) from skills (how).

Even when using built-in types (`general-purpose`, `Explore`, `Plan`), create an agent definition file. Specify the built-in type via the Agent tool's `subagent_type` parameter, and include role, principles, and protocols in the definition file.

**Model configuration:** All agents use `model: "opus"` by default. Always include `model: "opus"` when invoking the Agent tool. Harness quality depends directly on agent reasoning capability, and opus provides the highest quality. This is configurable -- substitute a different model if cost or speed constraints require it.

**Team reconstitution:** Only one agent team can be active per session, but you can disband a team between phases and create a new one. For pipeline patterns requiring different specialist combinations per phase, save previous team outputs to files, clean up the team, then create a new team.

Define each agent in `project/.claude/agents/{name}.md`. Required sections: core role, working principles, input/output protocol, error handling, collaboration. In agent team mode, add a `## Team Communication Protocol` section specifying message send/receive targets and task request scope.

**Agent frontmatter fields:** Beyond `name` and `description`, agent definitions support 13+ optional fields including `tools`, `model`, `permissionMode`, `memory`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `background`, `effort`, `isolation`, `color`, and `initialPrompt`. Use these fields to precisely control each agent's capabilities, security posture, and execution behavior. See `reference/agent-frontmatter-spec.md` for the complete specification and field-by-field guidance.

**Agent memory:** For agents that build knowledge across sessions, specify the `memory` field in frontmatter. Three scopes are available:
- `project`: Version-controlled and team-shareable (`.claude/agent-memory/<name>/`). Best for patterns the whole team benefits from.
- `user`: Cross-project and private (`~/.claude/agent-memory/<name>/`). Best for personal workflow preferences.
- `local`: Project-specific, not version-controlled (`.claude/agent-memory-local/<name>/`). Best for machine-specific environment details.

Memory is curated automatically (200 lines / 25KB limit in context). Include `initialPrompt: "Check your memory for established patterns before starting."` to ensure agents consult prior knowledge.

> See `reference/agent-design-patterns.md` for agent definition structure, `reference/agent-frontmatter-spec.md` for the complete frontmatter specification, and `reference/team-examples.md` for full file examples.

**When including a QA agent:**
- Use the `general-purpose` type (`Explore` is read-only and cannot run verification scripts).
- The essence of QA is **cross-boundary comparison**, not mere existence checking -- read the API response and front-end hook simultaneously and compare shapes.
- Run QA incrementally after each module completes, not just once after everything is done.
- See `reference/qa-agent-guide.md` for the detailed guide.

### Phase 4: Skill Generation

Generate skills for each agent at `project/.claude/skills/{name}/SKILL.md`. See `reference/skill-writing-guide.md` for detailed writing guidance.

#### 4-1. Skill Structure

```
skill-name/
  SKILL.md          (required: YAML frontmatter with name + description, then markdown body)
  scripts/          (optional: executable code for repetitive/deterministic tasks)
  references/       (optional: conditionally loaded reference documents)
  assets/           (optional: output files such as templates, images)
```

#### 4-2. Description Writing -- Aggressive Trigger Induction

The description is the skill's only trigger mechanism. Claude tends to be conservative about triggering, so write descriptions **aggressively ("pushy")**.

**Bad:** `"A skill that processes PDF documents"`
**Good:** `"Read PDF files, extract text/tables, merge, split, rotate, watermark, encrypt, OCR, and all other PDF operations. Use this skill whenever a .pdf file is mentioned or a PDF output is requested."`

Key: describe what the skill does + specific trigger situations, and distinguish from similar but non-triggering cases.

#### 4-3. Body Writing Principles

| Principle | Description |
|-----------|-------------|
| **Explain the why** | Instead of "ALWAYS/NEVER" directives, convey reasons. LLMs judge edge cases correctly when they understand the rationale. |
| **Keep it lean** | The context window is a shared resource. Target under 500 lines for SKILL.md; move non-essential content to references/. |
| **Generalize** | Explain principles rather than narrow rules that only fit specific examples. Avoid overfitting. |
| **Bundle repetitive code** | When agents commonly write the same helper scripts during testing, pre-bundle them in `scripts/`. |
| **Use imperative voice** | Write in directive style: "Do X", "Use Y". |

#### 4-4. Progressive Disclosure (Staged Information Loading)

Skills manage context through a 3-tier loading system:

| Tier | Loaded when | Size target |
|------|------------|-------------|
| **Metadata** (name + description) | Always in context | ~100 words |
| **SKILL.md body** | On skill trigger | <500 lines |
| **references/** | On demand only | Unlimited (scripts can be executed without loading) |

**Size management rules:**
- When SKILL.md approaches 500 lines, split detailed content into references/ and leave a pointer in the body stating when to read that file.
- Reference files over 300 lines should include a table of contents at the top.
- For domain/framework variations, separate into per-domain files under references/ so only the relevant file is loaded.

#### 4-5. Skill-Agent Connection Principles

- One agent can use 1-to-N skills.
- Multiple agents can share a single skill.
- Skills define "how to do it"; agents define "who does it".

### Phase 5: Integration and Orchestration

The orchestrator is a specialized skill that weaves individual agents and skills into a single workflow, coordinating the entire team. While Phase 4 skills define "what each agent does and how", the orchestrator defines "who collaborates in what order and when". See `reference/orchestrator-template.md` for concrete templates.

#### 5-0. Orchestrator Patterns by Mode

**Agent team mode (default):**
The orchestrator creates a team with `TeamCreate`, assigns tasks via `TaskCreate`. Members coordinate via `SendMessage`. The leader monitors progress and synthesizes results.

**Sub-agent mode:**
The orchestrator calls sub-agents directly via the `Agent` tool. Sub-agents return results only to the main agent.

#### 5-1. Data Passing Protocol

| Strategy | Method | Execution mode | Best for |
|----------|--------|---------------|----------|
| **Message-based** | `SendMessage` between team members | Agent team | Real-time coordination, feedback exchange, lightweight state |
| **Task-based** | `TaskCreate`/`TaskUpdate` for shared state | Agent team | Progress tracking, dependency management, task requests |
| **File-based** | Write/read at agreed paths | Both | Large data, structured artifacts, audit trails |

**Recommended combination for agent teams:** task-based (coordination) + file-based (artifacts) + message-based (real-time communication).

File-based passing rules:
- Create a `_workspace/` folder under the working directory for intermediate artifacts.
- File naming convention: `{phase}_{agent}_{artifact}.{ext}` (e.g., `01_analyst_requirements.md`).
- Output only final artifacts to user-specified paths; preserve intermediate files in `_workspace/` for auditing.

#### 5-2. Error Handling

Include error handling policies in the orchestrator. Core principle: retry once, then proceed without that result on re-failure (note the gap in the report); for conflicting data, keep both with source attribution.

> See `reference/orchestrator-template.md` for error type strategy tables and implementation details.

#### 5-4. Context Management

For long-running harnesses that span multiple context windows, prefer **context reset** (clear window + hand off structured state via files) over automatic compaction. Compaction is lossy -- each summarization round loses detail. Context reset preserves full fidelity by writing all intermediate state to `_workspace/` files before clearing the window.

**Reset protocol:** When approaching context limits, write intermediate state to `_workspace/` (progress.txt, features.json, current_state.md), commit current work, then start a fresh session that reads state files to resume.

**Session continuity:** Each session must end in a "merge-ready state" -- no major bugs in completed features, all tests passing, clear documentation of the next action. This ensures any session can be the last without leaving broken code.

> See `reference/long-running-harness-guide.md` for the full context reset protocol, session continuity patterns, sprint contracts, and the Generator-Evaluator architecture.

#### 5-5. Team Mode: Team Size Guidelines

| Work scope | Recommended team size | Tasks per member |
|-----------|----------------------|-----------------|
| Small (5-10 tasks) | 2-3 members | 3-5 |
| Medium (10-20 tasks) | 3-5 members | 4-6 |
| Large (20+ tasks) | 5-7 members | 4-5 |

> More members means more coordination overhead. Three focused members outperform five unfocused ones.

### Phase 6: Verification and Testing

Validate the generated harness. See `reference/skill-testing-guide.md` for the detailed testing methodology.

#### 6-1. Structural Verification

- Confirm all agent files are in the correct locations.
- Validate skill frontmatter (name, description).
- Verify cross-reference consistency between agents.
- Confirm no commands were generated (commands are not created).

#### 6-2. Execution Mode Verification

- **Agent team mode**: verify inter-member communication paths, task dependencies, and team size appropriateness.
- **Sub-agent mode**: verify each agent's I/O connections and `run_in_background` settings.

#### 6-3. Skill Execution Testing

1. **Write test prompts** -- 2-3 realistic prompts per skill, as a real user would phrase them.
2. **With-skill vs without-skill comparison** -- spawn paired sub-agents (one using the skill, one as baseline) to confirm the skill's added value.
3. **Evaluate results** -- qualitative (user review) + quantitative (assertion-based) grading. Use assertions for objectively verifiable outputs; rely on user feedback for subjective outputs.
4. **Iterative improvement loop** -- if issues are found, generalize the feedback into skill fixes (avoid narrow overfitting), re-test, and repeat until satisfactory.
5. **Bundle repetitive patterns** -- if agents consistently generate the same helper code across tests, pre-bundle it in `scripts/`.

#### 6-4. Trigger Verification

Validate that each skill's description triggers correctly:

1. **Should-trigger queries** (8-10) -- diverse phrasings (formal/casual, explicit/implicit).
2. **Should-NOT-trigger queries** (8-10) -- near-miss queries with similar keywords but requiring a different tool/skill.

**Near-miss key insight:** obviously unrelated queries ("write a Fibonacci function") have no test value. Good test cases are **ambiguous boundary queries** like "extract charts from this Excel file as PNG" (spreadsheet skill vs image conversion).

Also check for trigger collisions with existing skills.

#### 6-5. Dry-run Testing

- Review whether the orchestrator skill's phase order is logical.
- Confirm no dead links in data passing paths.
- Verify all agent inputs match the preceding phase's outputs.
- Verify fallback paths for error scenarios are executable.

#### 6-6. Test Scenario Authoring

- Add a `## Test Scenarios` section to the orchestrator skill.
- Include at least 1 normal flow + 1 error flow.

## Output Checklist

After generation, confirm:

- [ ] `project/.claude/agents/` -- agent definition files created (even for built-in types)
- [ ] `project/.claude/skills/` -- skill files (SKILL.md + references/)
- [ ] One orchestrator skill (with data flow + error handling + test scenarios)
- [ ] Execution mode specified (agent team or sub-agent)
- [ ] All Agent calls include `model: "opus"` parameter
- [ ] `.claude/commands/` -- nothing created
- [ ] No conflicts with existing agents/skills
- [ ] Skill descriptions are written aggressively ("pushy")
- [ ] SKILL.md bodies are under 500 lines; excess moved to references/
- [ ] Execution verified with 2-3 test prompts
- [ ] Trigger verification complete (should-trigger + should-NOT-trigger)

## References

- Architecture patterns (8 types): `reference/agent-design-patterns.md`
- **Agent frontmatter specification**: `reference/agent-frontmatter-spec.md` -- complete 13+ field reference for `.claude/agents/` definitions, including tools, model, permissionMode, memory, and more
- **Long-running harness patterns**: `reference/long-running-harness-guide.md` -- Generator-Evaluator architecture, session continuity, context reset strategy, sprint contracts, harness evolution
- Real-world team examples (full file contents): `reference/team-examples.md`
- Orchestrator templates: `reference/orchestrator-template.md`
- **Skill writing guide**: `reference/skill-writing-guide.md` -- writing patterns, examples, data schema standards
- **Skill testing guide**: `reference/skill-testing-guide.md` -- testing/evaluation/iterative improvement methodology
- **QA agent guide**: `reference/qa-agent-guide.md` -- for including a QA agent in build harnesses; covers integration coherence verification, boundary bug patterns, and QA agent definition templates based on 7 real-world bug cases
