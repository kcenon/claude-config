# Long-Running Harness Patterns

Patterns for harnesses that span multiple context windows or require sustained quality over long execution periods. Based on Anthropic's official engineering blog posts on harness design.

---

## Table of Contents

1. [Generator-Evaluator Architecture](#1-generator-evaluator-architecture)
2. [Long-Running Session Pattern](#2-long-running-session-pattern)
3. [Context Management Strategies](#3-context-management-strategies)
4. [Sprint Contracts](#4-sprint-contracts)
5. [Session Continuity](#5-session-continuity)
6. [Harness Evolution](#6-harness-evolution)

---

## 1. Generator-Evaluator Architecture

### The Self-Evaluation Problem

Agents evaluate their own output poorly. When the same agent generates and assesses, confirmation bias leads to systematically inflated quality scores. The root issue: the generator has already "decided" the output is good during creation, making objective evaluation psychologically impossible.

**Solution:** Strict role separation. The generator never evaluates. The evaluator never generates. Each agent specializes in one cognitive mode.

### Three-Agent Pattern: Planner-Generator-Evaluator

```
[Planner] ─── sprint contract ──> [Generator] ─── artifacts ──> [Evaluator]
                                       ^                             |
                                       +──── revision feedback ──────+
                                             (max 2-3 rounds)
```

**Planner**: Transforms high-level user requirements into structured sprint contracts with explicit success criteria. Runs once per sprint (or when scope changes).

**Generator**: Implements features according to the sprint contract. Focuses purely on creation -- code, content, design, whatever the domain requires.

**Evaluator**: Scores output against the sprint contract's criteria. Provides specific, actionable feedback for revision. Never generates alternative implementations -- only identifies gaps and suggests directions.

### Evaluator Design Principles

**1. Skeptical prompts beat generic assessment.**

Bad: "Review the quality of this output and provide feedback."
Good: "Find every problem, gap, and inconsistency in this output. Score each criterion from 1-5 with specific evidence."

Skeptical framing produces more thorough evaluation because it sets the expectation that problems exist.

**2. Few-shot examples calibrate judgment.**

Include 2-3 scored examples in the evaluator's prompt showing what constitutes a 1/5 vs 3/5 vs 5/5 for each criterion. Without calibration, evaluators tend toward the middle of any scale.

**3. Measurable criteria over subjective impressions.**

Convert subjective qualities into observable properties:

| Subjective | Measurable |
|-----------|-----------|
| "Well designed" | "All components follow the established naming convention; no function exceeds 30 lines" |
| "Good test coverage" | "Every public API method has at least 2 test cases (happy path + error)" |
| "Readable" | "No nested callbacks deeper than 3 levels; all magic numbers are named constants" |

**4. Model-capability-aware weighting.**

Weight evaluation criteria based on model strengths. Claude excels at craft (code quality, consistency) and functionality (correctness, completeness) but may need more scrutiny on originality (novel approaches) and design (system architecture).

### When to Use Generator-Evaluator vs Producer-Reviewer

| Aspect | Producer-Reviewer | Generator-Evaluator |
|--------|-------------------|---------------------|
| Judgment model | Categorical (PASS / FIX / REDO) | Quantitative (scored rubric) |
| Feedback depth | Fix instructions for specific issues | Scored assessment across all criteria |
| Calibration | Not required | Few-shot examples essential |
| Best for | Iterating on individual artifacts | Maintaining quality across large outputs |
| Retry semantics | Regenerate specific items | Revise based on scored gaps |

Use **Producer-Reviewer** when output is discrete (panels, pages, modules) and a binary pass/fail makes sense. Use **Generator-Evaluator** when output is holistic (application, document, system) and multi-dimensional scoring matters.

---

## 2. Long-Running Session Pattern

### Initializer + Incremental Worker

For projects too large for a single context window, split into an initialization phase and repeatable work sessions.

```
[Initializer Agent] ─── environment setup ──> feature list (JSON)
                                                    |
                                                    v
[Coding Agent] ─── pick feature ──> implement ──> test ──> commit ──> repeat
                       ^                                                  |
                       +──────────────── next session ────────────────────+
```

### Session Initialization Sequence

The Initializer runs once and establishes the project foundation:

1. **Verify working directory and git state** -- ensure clean working tree
2. **Review git logs** -- understand recent context and commit patterns
3. **Generate feature list** as JSON (see format below)
4. **Run `init.sh`** for reproducible environment setup (dependencies, config)
5. **Validate prerequisites** -- tools installed, services running
6. **Select first feature** to implement

### Feature Specification Format

Use JSON, not Markdown. Markdown feature lists are vulnerable to model-induced corruption during updates (accidental reformatting, lost items, merged entries). JSON's strict syntax makes corruption immediately visible as parse errors.

```json
{
  "features": [
    {
      "id": "auth-001",
      "title": "JWT token generation on login",
      "description": "Generate and return JWT on successful /auth/login",
      "status": "failing",
      "acceptance_criteria": [
        "POST /auth/login returns 200 with { token: string }",
        "Token contains user_id and exp claims",
        "Invalid credentials return 401"
      ],
      "dependencies": []
    },
    {
      "id": "auth-002",
      "title": "Auth middleware for protected routes",
      "status": "failing",
      "description": "Middleware validates JWT and rejects invalid tokens",
      "acceptance_criteria": [
        "Protected routes return 401 without token",
        "Valid token passes through with user context",
        "Expired token returns 401"
      ],
      "dependencies": ["auth-001"]
    }
  ]
}
```

**Status values:** `failing` (not started) → `in_progress` (current session) → `passing` (complete with tests)

### Single Feature Per Session

Each coding session focuses on one feature:

1. Read `features.json`, pick next `failing` feature
2. Set status to `in_progress`
3. Implement the feature
4. Write and run tests
5. Set status to `passing`
6. Commit with descriptive message referencing feature ID
7. Verify merge-ready state (see below)

### Quality Gate: Merge-Ready State

Every session must leave code in a state where another developer (or agent) could merge it:

- No major bugs in implemented features
- All `passing` features have working tests
- No broken imports or unresolved dependencies
- Documentation updated for completed features
- Clear indication of what to work on next

---

## 3. Context Management Strategies

### Context Reset vs Compaction

| Strategy | Mechanism | Fidelity | Best for |
|----------|-----------|----------|----------|
| **Compaction** | Automatic summarization by the model | Lossy -- details are condensed | Short sessions within a single context window |
| **Context reset** | Clear window + structured state handoff via files | Lossless -- artifacts are the source of truth | Long-running harnesses spanning multiple sessions |

### Why Context Reset Wins for Long-Running Work

Compaction summarizes context to free space, but each summarization round loses detail. After multiple compactions, the model may forget key decisions, constraints, or intermediate results.

Context reset avoids this by:
1. Writing **all** intermediate state to `_workspace/` files before the reset
2. Clearing the context window entirely
3. Starting a fresh session that reads state files to resume
4. No summarization loss -- file artifacts preserve full fidelity

### Reset Protocol

When approaching context limits (~80% capacity):

```
1. Write intermediate state:
   - _workspace/progress.txt (human-readable summary)
   - _workspace/features.json (updated statuses)
   - _workspace/current_state.md (what's in progress, decisions made, blockers)

2. Commit current work:
   - Stage and commit all code changes
   - Include "WIP:" prefix if feature is incomplete

3. End session gracefully:
   - Note the exact next step in progress.txt
   - Confirm all state is persisted

4. New session resumes:
   - Read _workspace/progress.txt
   - Read _workspace/features.json
   - Read _workspace/current_state.md
   - Continue from documented next step
```

---

## 4. Sprint Contracts

### What They Are

Sprint contracts are negotiated documents between the Planner and Generator that bridge high-level specs and implementation. They make evaluation criteria explicit before work begins, preventing post-hoc rationalization.

### Structure

```markdown
# Sprint Contract: [Sprint Name]

## Scope
Features to implement this sprint: [feature IDs]

## Success Criteria per Feature

### [Feature ID]: [Title]
- [ ] Criterion 1 (with measurable definition)
- [ ] Criterion 2
- [ ] Criterion 3

## Constraints
- Technology restrictions
- Performance requirements
- Compatibility requirements

## Dependencies
- External: [APIs, services that must be available]
- Internal: [features that must be complete first]

## Evaluation Rubric
| Criterion | 1 (Fail) | 3 (Acceptable) | 5 (Excellent) |
|-----------|----------|-----------------|----------------|
| Correctness | Missing features | All criteria met | Handles edge cases |
| Test quality | No tests | Happy path covered | Full coverage + edge cases |
| Code quality | Major issues | Clean, consistent | Exemplary patterns |
```

### Workflow

```
1. Planner generates contract from user requirements
2. Generator reviews and negotiates (can request scope changes)
3. Both agree on final contract
4. Generator implements
5. Evaluator scores against contract criteria
6. Below threshold → Generator revises (max 2-3 rounds)
7. Above threshold → Sprint complete, Planner generates next contract
```

The negotiation step is important: it surfaces misunderstandings early, before implementation effort is wasted.

---

## 5. Session Continuity

### Progress Tracking Files

| File | Format | Purpose | Reader |
|------|--------|---------|--------|
| `_workspace/progress.txt` | Plain text | Human-readable session log | Humans and agents |
| `_workspace/features.json` | JSON | Machine-readable feature state | Coding agent |
| `_workspace/current_state.md` | Markdown | Detailed context for resume | Next session's agent |

### progress.txt Format

```
=== Session 3 (2026-04-05) ===
Completed: auth-001 (JWT token generation)
Started: auth-002 (Auth middleware) -- 60% complete
  - Middleware created and registered
  - Token validation working
  - TODO: expired token handling, error response format
Next: finish auth-002 expired token handling, then auth-003
Blockers: none
```

### Handoff Pattern

Every session ends with this sequence:

1. **Commit current work** -- even if incomplete (`WIP:` prefix)
2. **Update progress files** -- `progress.txt`, `features.json`, `current_state.md`
3. **Verify merge-ready state** -- no breaking changes for completed features
4. **Document next action** -- specific enough that a new agent can continue without ambiguity

The goal: the next session starts productive work in under 2 minutes of context reading.

---

## 6. Harness Evolution

### Simplification with Model Improvements

Harnesses compensate for model limitations. As models improve, some harness components become unnecessary overhead. Periodically reassess:

| Question | If yes | If no |
|----------|--------|-------|
| Does the Evaluator catch issues the Generator doesn't self-correct? | Keep Evaluator | Consider removing |
| Does the Planner produce better contracts than ad-hoc feature selection? | Keep Planner | Simplify to feature list only |
| Does context reset produce better results than compaction? | Keep reset protocol | Simplify to auto-compaction |
| Does strict role separation improve output quality? | Keep separation | Consider merging roles |

### Tracking Harness Value

For each harness component, track:
- **Quality delta**: output quality with vs without the component
- **Cost delta**: additional tokens / time with the component
- **ROI**: quality improvement per unit cost

A component earning its keep should show measurable quality improvement that justifies its token and latency cost.

### Weaving AI Features

When designing harnesses for application development, instruct the Planner to identify where autonomous agent capabilities can be integrated into the application itself. The Planner should ask: "Which features in this application could benefit from an AI agent?" This surfaces opportunities that domain experts might miss.

### Model Transition Guidance

When a new model version is released:
1. Run existing test scenarios on the new model
2. Compare quality scores against the previous model baseline
3. If the new model matches harness-assisted quality without the harness, simplify
4. If the new model improves but gaps remain, keep the harness with adjusted evaluator calibration
