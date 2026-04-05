# Agent Team Examples

Seven real-world team configurations demonstrating different architecture patterns and execution modes.

## Table of Contents

1. [Example 1: Research Team (Fan-out/Fan-in)](#example-1-research-team-agent-team-mode)
2. [Example 2: SF Novel Writing Team (Pipeline + Fan-out)](#example-2-sf-novel-writing-team-agent-team-mode)
3. [Example 3: Webtoon Production Team (Producer-Reviewer)](#example-3-webtoon-production-team-sub-agent-mode)
4. [Example 4: Code Review Team (Fan-out/Fan-in + Discussion)](#example-4-code-review-team-agent-team-mode)
5. [Example 5: Code Migration Supervisor](#example-5-supervisor-pattern----code-migration-team-agent-team-mode)
6. [Example 6: Debugging with Competing Hypotheses (Fan-out + Debate)](#example-6-debugging-with-competing-hypotheses-agent-team-mode)
7. [Example 7: Application Builder with Evaluator (Generator-Evaluator)](#example-7-application-builder-with-evaluator-generator-evaluator-pattern)

---

## Example 1: Research Team (Agent Team Mode)

### Team Architecture: Fan-out/Fan-in
### Execution Mode: Agent Team

```
[Leader/Orchestrator]
    +-- TeamCreate(research-team)
    +-- TaskCreate(4 research tasks)
    +-- Members self-coordinate (SendMessage)
    +-- Collect results (Read)
    +-- Generate integrated report
```

### Agent Configuration

| Member | Agent type | Role | Output |
|--------|-----------|------|--------|
| official-researcher | general-purpose | Official docs/blogs | research_official.md |
| media-researcher | general-purpose | Media/investment | research_media.md |
| community-researcher | general-purpose | Community/SNS | research_community.md |
| background-researcher | general-purpose | Background/competition/academic | research_background.md |
| (leader = orchestrator) | -- | Integrated report | final_report.md |

> Research agents use the `general-purpose` built-in type but must be defined as `.claude/agents/{name}.md` files. The files specify role, research scope, and team communication protocol to ensure reusability and collaboration quality.

### Orchestrator Workflow (Agent Team)

```
Phase 1: Preparation
  - Analyze user input (identify topic, research mode)
  - Create _workspace/

Phase 2: Team Assembly
  - TeamCreate(team_name: "research-team", members: [
      { name: "official", prompt: "Research official channels..." },
      { name: "media", prompt: "Research media/investment trends..." },
      { name: "community", prompt: "Research community reactions..." },
      { name: "background", prompt: "Research background/competitive landscape..." }
    ])
  - TaskCreate(tasks: [
      { title: "Official channel research", assignee: "official" },
      { title: "Media trend research", assignee: "media" },
      { title: "Community reaction research", assignee: "community" },
      { title: "Background landscape research", assignee: "background" }
    ])

Phase 3: Research Execution
  - 4 members investigate independently
  - Members share interesting discoveries via SendMessage
    (e.g., media shares an investment news item with background)
  - Members discuss conflicting information directly
  - Each member saves output and notifies the leader on completion

Phase 4: Integration
  - Leader reads all 4 artifacts
  - Generates integrated report
  - Conflicting information is kept with source attribution

Phase 5: Cleanup
  - Send shutdown request to members
  - Clean up team
  - Preserve _workspace/ (for post-verification and audit trails)
```

### Team Communication Patterns

```
official --SendMessage--> background  (share related official announcements)
media    --SendMessage--> background  (share investment/acquisition info)
community --SendMessage--> media      (share media-relevant community reactions)
all members --TaskUpdate--> shared task list  (progress updates)
leader <----- idle notification ---- completed members  (automatic)
```

---

## Example 2: SF Novel Writing Team (Agent Team Mode)

### Team Architecture: Pipeline + Fan-out
### Execution Mode: Agent Team

```
Phase 1 (parallel -- agent team): worldbuilder + character-designer + plot-architect
  -> Coordinate consistency via SendMessage
Phase 2 (sequential): prose-stylist (writing)
Phase 3 (parallel -- agent team): science-consultant + continuity-manager (review)
  -> Share discoveries via SendMessage
Phase 4 (sequential): prose-stylist (revise based on review)
```

### Agent Configuration

| Member | Agent type | Role | Skill |
|--------|-----------|------|-------|
| worldbuilder | custom | World-building | world-setting |
| character-designer | custom | Character design | character-profile |
| plot-architect | custom | Plot structure | outline |
| prose-stylist | custom | Prose editing + writing | write-scene, review-chapter |
| science-consultant | custom | Scientific verification | science-check |
| continuity-manager | custom | Consistency verification | consistency-check |

### Agent File Example: `worldbuilder.md`

```markdown
---
name: worldbuilder
description: "Specialist in building SF novel worlds. Designs physics laws, social structures, technology levels, and history."
---

# Worldbuilder -- SF World Design Specialist

You are a specialist in SF novel world design. You build the physical, social, and technological foundation of the world where the story unfolds, grounded in scientific fact but extended with imagination.

## Core Role
1. Define the world's physical laws and technology level
2. Design social structure, political system, economic system
3. Establish historical context and current conflict structures
4. Describe environments and atmospheres for each location

## Working Principles
- Internal consistency is the top priority -- no contradictions between settings
- Use "What if this technology existed?" chain-reasoning to deduce cascading effects
- World-building serves the story -- avoid excessive settings that hinder the plot

## Input/Output Protocol
- Input: User's world concept, genre requirements
- Output: `_workspace/01_worldbuilder_setting.md`
- Format: Markdown, sectioned by (physics/society/technology/history/locations)

## Team Communication Protocol
- To character-designer: SendMessage about social structure, class systems, occupations
- To plot-architect: SendMessage about major conflict structures, crisis elements
- From science-consultant: Receive scientific error feedback -> revise settings
- Broadcast to all relevant members on world-building changes

## Error Handling
- If the concept is vague, propose 3 directions and request selection
- When scientific errors are found, present alternatives alongside corrections

## Collaboration
- Provide social structure information to character-designer
- Provide conflict structure information to plot-architect
- Revise settings based on science-consultant feedback
```

### Team Workflow Details

```
Phase 1: TeamCreate(team_name: "novel-team", members: [worldbuilder, character-designer, plot-architect])
         TaskCreate([world building, character design, plot structure])
         -> Members self-coordinate and work in parallel
         -> worldbuilder sends social structure to character-designer via SendMessage on completion
         -> character-designer sends protagonist setup to plot-architect via SendMessage

Phase 2: Clean up Phase 1 team -> invoke prose-stylist as sub-agent (solo writing, no team needed)
         prose-stylist Reads 3 artifacts from _workspace/ and writes the draft
         -> Saves result to _workspace/02_prose_draft.md

Phase 3: New team -- TeamCreate(team_name: "review-team", members: [science-consultant, continuity-manager])
         (Only one team can be active per session, but Phase 1 team was cleaned up)
         -> Both reviewers examine the draft and share discoveries
         -> science-consultant notifies continuity-manager of physics errors
         -> Clean up team after review

Phase 4: Invoke prose-stylist as sub-agent, revise based on review results for final draft
```

---

## Example 3: Webtoon Production Team (Sub-agent Mode)

### Team Architecture: Producer-Reviewer
### Execution Mode: Sub-agent

> In this producer-reviewer pattern with only 2 agents, result passing is the core concern rather than communication, making sub-agents appropriate.

```
Phase 1: Agent(webtoon-artist) -> generate panels
Phase 2: Agent(webtoon-reviewer) -> review
Phase 3: Agent(webtoon-artist) -> regenerate problematic panels (max 2 rounds)
```

### Agent Configuration

| Agent | subagent_type | Role | Skill |
|-------|--------------|------|-------|
| webtoon-artist | custom | Panel image generation | generate-webtoon |
| webtoon-reviewer | custom | Quality review | review-webtoon, fix-webtoon-panel |

### Agent File Example: `webtoon-reviewer.md`

```markdown
---
name: webtoon-reviewer
description: "Specialist in reviewing webtoon panel quality. Evaluates composition, character consistency, text legibility, and direction."
---

# Webtoon Reviewer -- Quality Review Specialist

You are a specialist in webtoon panel quality review. You evaluate panels based on visual completeness, storytelling effectiveness, and character consistency.

## Core Role
1. Evaluate composition and visual completeness of each panel
2. Verify character appearance consistency across panels
3. Assess speech bubble text legibility and placement
4. Review overall episode direction flow and pacing

## Working Principles
- Use a clear 3-tier judgment: PASS / FIX / REDO
- FIX for issues resolvable with partial correction; REDO for full regeneration needed
- Judge on objective criteria (consistency, legibility, composition), not subjective taste

## Input/Output Protocol
- Input: Panel images in `_workspace/panels/` directory
- Output: `_workspace/review_report.md`
- Format:
  ## Panel {N}
  - Verdict: PASS | FIX | REDO
  - Reason: [specific reason]
  - Fix instructions: [specific fix direction for FIX/REDO cases]

## Error Handling
- If image loading fails, mark that panel as REDO
- Panels still REDO after 2 regenerations get a warning and are force-PASSED

## Collaboration
- Deliver fix instructions to webtoon-artist (file-based)
- Re-review regenerated panels (max 2 rounds)
```

### Error Handling

```
Retry policy:
- REDO-verdict panels -> request regeneration from artist (with specific fix instructions)
- Max 2 rounds, then force PASS
- If 50%+ of panels are REDO, suggest prompt revision to the user
```

---

## Example 4: Code Review Team (Agent Team Mode)

### Team Architecture: Fan-out/Fan-in + Discussion
### Execution Mode: Agent Team

> Code review is a representative case where agent teams shine. Reviewers with different perspectives share discoveries and challenge each other for deeper reviews.

```
[Leader] -> TeamCreate(review-team)
    +-- security-reviewer: security vulnerability inspection
    +-- performance-reviewer: performance impact analysis
    +-- test-reviewer: test coverage verification
    -> Reviewers share discoveries (SendMessage)
    -> Leader synthesizes results
```

### Team Communication Patterns

```
security    --SendMessage--> performance  ("This SQL query is injectable; check from a performance angle too")
performance --SendMessage--> test         ("N+1 query found; check if there's a related test")
test        --SendMessage--> security     ("No auth module tests; what's the priority from a security perspective?")
```

Key: Reviewers communicate **directly without going through the leader**, enabling rapid detection of cross-domain issues.

---

## Example 5: Supervisor Pattern -- Code Migration Team (Agent Team Mode)

### Team Architecture: Supervisor
### Execution Mode: Agent Team

```
[supervisor/leader] -> analyze file list -> assign batches
    +-> [migrator-1] (batch A)
    +-> [migrator-2] (batch B)
    +-> [migrator-3] (batch C)
    <- receive TaskUpdate -> assign additional batches or reassign
```

### Agent Configuration

| Member | Role |
|--------|------|
| (leader = migration-supervisor) | File analysis, batch distribution, progress management |
| migrator-1 through migrator-3 | Migrate assigned file batches |

### Supervisor's Dynamic Distribution Logic (Agent Team)

```
1. Collect the full target file list
2. Estimate complexity (file size, import count, dependencies)
3. Register file batches as tasks via TaskCreate (including dependencies)
4. Members claim tasks from the shared list
5. When a member completes via TaskUpdate:
   - Success -> member automatically claims next task
   - Failure -> leader checks cause via SendMessage -> reassign or hand to another member
6. All tasks complete -> leader runs integration tests
```

Difference from fan-out: work is not pre-assigned but **dynamically allocated at runtime**. The shared task list's claim mechanism naturally matches the supervisor pattern.

---

## Example 6: Debugging with Competing Hypotheses (Agent Team Mode)

### Team Architecture: Fan-out + Debate
### Execution Mode: Agent Team

When the root cause is unclear, spawn investigators for competing hypotheses. Agent teams enable direct challenge and evidence sharing -- one investigator's finding can redirect another's approach in real time.

```
[Leader] -> TeamCreate(debug-team)
    +-- hypothesis-a-investigator
    +-- hypothesis-b-investigator
    +-- hypothesis-c-investigator
    -> Investigators challenge each other's evidence (SendMessage)
    -> Leader synthesizes into root cause determination
```

### Agent Configuration

| Member | Agent type | Hypothesis | Output |
|--------|-----------|-----------|--------|
| race-condition-investigator | general-purpose | Thread pool race condition | investigation_race.md |
| null-pointer-investigator | general-purpose | Null pointer from API response | investigation_null.md |
| stack-overflow-investigator | general-purpose | Stack overflow in recursive parser | investigation_stack.md |
| (leader = orchestrator) | -- | Root cause synthesis | root_cause_report.md |

### Team Communication Patterns

```
race-condition  --SendMessage--> null-pointer    ("Thread dump shows no contention at crash time -- weakens my hypothesis")
null-pointer    --SendMessage--> stack-overflow  ("API returns valid data in my traces -- your recursion theory looks stronger")
stack-overflow  --SendMessage--> race-condition  ("Stack depth hits 5000 only on Monday batch jobs -- does Monday have larger input?")
all members     --TaskUpdate-->  shared task list (evidence log and confidence scores)
```

**Key behaviors:**
- Members share evidence that supports OR **contradicts** their own hypothesis -- intellectual honesty improves investigation quality
- Direct challenges: "Your race condition theory doesn't explain why it only crashes on Mondays"
- Convergence: when evidence strongly favors one hypothesis, other investigators pivot to supporting investigation (validating the leading theory from different angles)
- Leader tracks confidence scores in the task list and calls convergence when one hypothesis reaches high confidence

### Orchestrator Workflow

```
Phase 1: Leader defines hypotheses based on symptoms
Phase 2: TeamCreate with one investigator per hypothesis
         TaskCreate with investigation tasks + "report evidence and confidence"
Phase 3: Investigators work independently but share findings via SendMessage
         - Each maintains a confidence score (0-100) in their task updates
         - Leader monitors for convergence (one hypothesis >80 confidence)
Phase 4: When converged, leader requests final evidence summary from all
Phase 5: Leader synthesizes root cause report:
         - Winning hypothesis with supporting evidence
         - Eliminated hypotheses with disproving evidence
         - Recommended fix
Phase 6: Cleanup team
```

---

## Example 7: Application Builder with Evaluator (Generator-Evaluator Pattern)

### Team Architecture: Planner (sub-agent) + Generator-Evaluator (agent team)
### Execution Mode: Mixed (sub-agent for planning, agent team for build-evaluate loop)

Uses the Generator-Evaluator pattern with sprint contracts to maintain quality across a multi-feature application build.

```
[Planner sub-agent] -> sprint contract
    ↓
[TeamCreate: build-team]
    +-- generator: implements features per contract
    +-- evaluator: scores output against contract criteria
    -> Iterate until score threshold met (max 3 rounds)
```

### Agent Configuration

| Agent | Type | Role | Output |
|-------|------|------|--------|
| planner | sub-agent (Plan type) | Sprint contract generation | _workspace/sprint_contract.md |
| generator | custom (agent team) | Feature implementation | _workspace/implementation/ |
| evaluator | custom (agent team) | Quality scoring | _workspace/evaluation_report.md |

### Agent File Example: `evaluator.md`

```markdown
---
name: evaluator
description: "Quality evaluator for sprint deliverables. Scores implementation against sprint contract criteria using calibrated rubrics."
tools: [Read, Grep, Glob, Bash]
model: opus
---

# Evaluator -- Quality Scoring Specialist

You are a quality evaluator. Your role is to score implementation artifacts against sprint contract criteria. You NEVER generate code or suggest implementations -- only evaluate.

## Core Role
1. Read the sprint contract criteria
2. Examine the implementation artifacts
3. Score each criterion on a 1-5 scale with specific evidence
4. Identify gaps and provide actionable feedback

## Scoring Calibration

### Example scores for "Test quality" criterion:
- **1 (Fail):** No tests, or tests that don't actually test the feature
- **3 (Acceptable):** Happy path covered, main error cases handled
- **5 (Excellent):** Happy path + edge cases + error cases + integration tests

## Working Principles
- Be skeptical: assume problems exist until proven otherwise
- Cite specific evidence: line numbers, test names, missing scenarios
- Score independently per criterion -- don't let one good area inflate others
- Never generate alternative implementations -- only identify what's missing

## Team Communication Protocol
- Receive from generator: "Implementation complete, ready for evaluation"
- Send to generator: evaluation report with scores and actionable feedback
- To leader: summary score and recommendation (PASS if all criteria >= 3, REVISE otherwise)
```

### Sprint Contract Workflow

```
Phase 1: Invoke planner as sub-agent
         - Input: user requirements
         - Output: _workspace/sprint_contract.md (features, criteria, rubric)

Phase 2: TeamCreate(team_name: "build-team", members: [generator, evaluator])

Phase 3: Build-evaluate loop (max 3 rounds)
         Round 1:
           - generator implements features per contract
           - generator SendMessage to evaluator: "Ready for evaluation"
           - evaluator scores against criteria
           - evaluator SendMessage to generator: scores + feedback

         Round 2 (if needed):
           - generator revises based on feedback
           - evaluator re-scores

         Round 3 (if still needed):
           - Final revision attempt
           - If still below threshold, proceed with current quality + gap report

Phase 4: Leader collects final evaluation report
         - If all criteria >= 3: sprint PASSED
         - Otherwise: report gaps to user

Phase 5: Cleanup team
         - Preserve _workspace/ for audit trail
```

---

## Output Pattern Summary

### Agent Definition Files
Location: `project/.claude/agents/{agent-name}.md`
Required sections: core role, working principles, input/output protocol, error handling, collaboration
Team mode additional section: **Team Communication Protocol** (message send/receive targets, task request scope)

### Skill File Structure
Location: `project/.claude/skills/{skill-name}/SKILL.md` (project level)
Or: `~/.claude/skills/{skill-name}/SKILL.md` (global level)

### Integration Skill (Orchestrator)
A higher-level skill coordinating the entire team. Defines per-scenario agent configuration and workflows.
Template: see `orchestrator-template.md`.
**Always specify the execution mode** -- agent team (default) or sub-agent.
