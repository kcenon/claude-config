---
name: implement-all-levels
description: Enforce complete implementation of all tiers/difficulty levels for tiered features. Prevents partial implementations.
argument-hint: "<feature-description> [--solo|--team]"
user-invocable: true
---

# Implement All Levels Command

Enforce complete implementation of all tiers/difficulty levels for tiered features.

## Usage

```
/implement-all-levels <feature-description>
```

**Examples**:
```
/implement-all-levels "Add difficulty-based scoring system"
/implement-all-levels "Implement authentication with basic/advanced modes"
/implement-all-levels "Create tiered caching strategy"
/implement-all-levels "Add scoring system" --solo    # Force solo mode
/implement-all-levels "Add scoring system" --team    # Force team mode
```

## Purpose

This command enforces an "enumerate-first" workflow to ensure complete coverage of all implementation tiers. It prevents the common pattern of implementing only the Easy tier while neglecting Medium/Hard levels.

## Workflow

### Phase 0: Execution Mode Selection

#### 0-1. If `--solo` or `--team` flag was provided

Extract the flag from `$ARGUMENTS` (strip it before passing to Step 1).
Use `$EXEC_MODE` directly.

#### 0-2. If no flag was provided (interactive selection)

Auto-recommend based on tier count and complexity:

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Tiers | 2 | 3+ |
| Per-tier complexity | Low (< 100 LOC each) | High (100+ LOC each) |
| Cross-tier dependencies | Minimal | Significant |

Use `AskUserQuestion` to present the choice:

- **Question**: "Implement <feature> with N tiers. Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential implementation. Single agent handles all tiers in order. Lower token cost."
- **Description for Team**: "3-team parallel: dev implements + reviewer validates + doc-writer documents each tier. Higher quality."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-3. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode** (Steps 1-5 below, unchanged)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions** (after Solo Mode)

---

## Solo Mode

### Step 1: Enumerate All Tiers

Before writing any code, list ALL implementation tiers:

```markdown
## Implementation Tiers for: [Feature Description]

| Tier | Description | Status |
|------|-------------|--------|
| Easy | [Basic functionality] | Pending |
| Medium | [Enhanced features] | Pending |
| Hard | [Advanced capabilities] | Pending |
```

**Rules**:
- Minimum 2 tiers required
- Maximum 5 tiers recommended
- Each tier must have clear, distinct requirements
- Tiers should be progressively more complex

### Step 2: User Confirmation

Present the tier list and ask for confirmation:

```
I've identified the following implementation tiers:

1. **Easy**: [description]
2. **Medium**: [description]
3. **Hard**: [description]

Do you want to proceed with implementing all tiers? (yes/no)
```

**Do NOT proceed** until user confirms.

### Step 3: Implement Each Tier

Implement tiers in order (Easy -> Medium -> Hard):

```markdown
## Progress Tracking

| Tier | Status | Notes |
|------|--------|-------|
| Easy | Completed | Implemented basic scoring |
| Medium | In Progress | Adding multipliers |
| Hard | Pending | Combo system pending |
```

**Status Indicators**:
- Pending - Not started
- In Progress - Currently implementing
- Completed - Done and tested

### Step 4: Test Each Tier

After implementing each tier, run relevant tests:

```bash
# Example test commands
pytest tests/test_scoring.py -k "easy"
pytest tests/test_scoring.py -k "medium"
pytest tests/test_scoring.py -k "hard"
```

**Requirements**:
- Each tier MUST have corresponding tests
- Tests MUST pass before marking tier as complete
- No tier can be marked Completed without passing tests

### Step 5: Final Report

Generate completion report:

```markdown
## Implementation Complete

### Summary
- **Feature**: [Feature Description]
- **Total Tiers**: 3
- **Completed**: 3/3 (100%)

### Tier Details

#### Easy Tier
- Files modified: `src/scoring/basic.py`
- Tests: `tests/test_scoring.py::test_easy_*` (5 passed)

#### Medium Tier
- Files modified: `src/scoring/multipliers.py`
- Tests: `tests/test_scoring.py::test_medium_*` (8 passed)

#### Hard Tier
- Files modified: `src/scoring/combos.py`
- Tests: `tests/test_scoring.py::test_hard_*` (12 passed)

### Total Test Coverage
- 25 tests passed
- 0 tests failed
- 0 tests skipped
```

## Enforcement Rules

### Prohibited Patterns

The following are **NOT ALLOWED**:

1. **Partial Implementation**
```python
# BAD: Only Easy implemented
def get_score(difficulty: str) -> int:
    if difficulty == "easy":
        return calculate_easy()
    else:
        raise NotImplementedError()  # Forbidden
```

2. **TODO Comments**
```python
# BAD: TODO instead of implementation
def calculate_medium():
    # TODO: Implement medium difficulty  # Forbidden
    pass
```

3. **Placeholder Returns**
```python
# BAD: Empty or placeholder return
def calculate_hard():
    return 0  # Placeholder value
    return None  # Placeholder value
    return {}  # Empty placeholder
```

4. **Untested Tiers**
```python
# BAD: No tests for tier
def calculate_hard():
    return complex_calculation()  # No corresponding test
```

### Required Patterns

All implementations MUST follow:

1. **Complete Coverage**
```python
# GOOD: All tiers implemented
def get_score(difficulty: str) -> int:
    match difficulty:
        case "easy": return calculate_easy()
        case "medium": return calculate_medium()
        case "hard": return calculate_hard()
```

2. **Exhaustive Tests**
```python
# GOOD: Tests for all tiers
class TestScoring:
    def test_easy_scoring(self): ...
    def test_medium_scoring(self): ...
    def test_hard_scoring(self): ...
```

## Interruption Handling

If implementation is interrupted:

1. **Save Progress**: Update status table with current state
2. **Document Blockers**: Note any issues preventing completion
3. **Resume Point**: Clearly indicate where to resume

```markdown
## Implementation Paused

| Tier | Status | Notes |
|------|--------|-------|
| Easy | Completed | Done |
| Medium | In Progress | Blocked: need API design decision |
| Hard | Pending | Waiting for Medium |

### Resume Instructions
- Resolve: API endpoint naming convention
- Continue: Medium tier implementation in `src/api/handlers.py`
```

## Related Rules

- [implementation-standards.md](../project/.claude/rules/coding/implementation-standards.md) - Static rule for implementation completeness
- [quality.md](../project/.claude/rules/coding/quality.md) - Code quality standards

---

## Team Mode Instructions

Three-team workflow for tiered feature implementation. Dev team implements each tier, Review team validates quality, Doc team documents. Per-tier feedback loop ensures every tier meets quality gates.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Tier tracking │
         │ Final report  │
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│ Dev  │◄──│Review│   │ Doc  │
│ Team │──►│ Team │   │ Team │
└──────┘   └──────┘   └──────┘
  dev     reviewer    doc-writer

  Per tier: Dev implements → Reviewer validates → Doc-writer documents
  Feedback: Reviewer → Dev for fixes before moving to next tier
```

### T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (Enumerate Tiers, User Confirmation).
After user confirms, create team.

### T-2. Create Team and Tasks

```
TeamCreate(team_name="impl-all-levels", description="Implement all tiers for: $FEATURE")
```

For each tier (e.g., Easy, Medium, Hard), create a task group:

| Task | Subject | Owner | blockedBy |
|------|---------|-------|-----------|
| 1 | Implement Easy tier | dev | — |
| 2 | Write tests for Easy tier | dev | 1 |
| 3 | Review Easy tier: quality + completeness | reviewer | 2 |
| 4 | Document Easy tier | doc-writer | 2 |
| 5 | Apply review changes for Easy tier (if any) | dev | 3 |
| 6 | Implement Medium tier | dev | 3 or 5 |
| 7 | Write tests for Medium tier | dev | 6 |
| 8 | Review Medium tier | reviewer | 7 |
| 9 | Document Medium tier | doc-writer | 7 |
| 10 | Apply review changes for Medium tier (if any) | dev | 8 |
| 11 | Implement Hard tier | dev | 8 or 10 |
| 12 | Write tests for Hard tier | dev | 11 |
| 13 | Review Hard tier | reviewer | 12 |
| 14 | Document Hard tier | doc-writer | 12 |
| 15 | Apply review changes for Hard tier (if any) | dev | 13 |
| 16 | Final report: all tiers complete | lead | 13 or 15, 4, 9, 14 |

**Key flow:** Each tier follows: Dev implements → Dev tests → Reviewer reviews ∥ Doc-writer documents → Dev fixes (if needed) → Next tier.

Doc-writer tasks can run in parallel with review (both depend on implementation + tests).

### T-3. Spawn Teammates

**Dev Team** (implementation + tests):

```
Agent(
  name="dev",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the dev team for implementing all tiers of: $FEATURE

    Your responsibilities:
    1. Implement each tier in order (Easy → Medium → Hard)
    2. Write comprehensive tests for each tier
    3. Run tests and verify passing before marking implementation complete
    4. If reviewer sends change requests, apply fixes before moving to next tier

    Enforcement rules (CRITICAL):
    - NO partial implementations: every tier must be fully functional
    - NO TODO comments: every function must be implemented
    - NO placeholder returns: no 'return 0', 'return None', 'return {}'
    - NO untested tiers: each tier MUST have passing tests

    Commit format: feat(scope): implement <tier> tier (English only, no emojis)
    Test commit: test(scope): add tests for <tier> tier

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (quality validation per tier):

```
Agent(
  name="reviewer",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the review team for validating all tiers of: $FEATURE

    Your responsibilities per tier:
    1. Verify the implementation is complete (no TODOs, no placeholders)
    2. Check code quality: DRY, proper error handling, edge cases
    3. Verify tests cover the tier's requirements adequately
    4. Check that the tier integrates correctly with previous tiers
    5. If issues found, send change requests to dev

    Classification:
    - Critical: Incomplete implementation, placeholder code, missing tests
    - Major: Poor error handling, missing edge cases, integration issues
    - Minor: Style, naming, minor optimizations

    Feedback loop:
    - Send change requests to dev via SendMessage if Critical/Major found
    - Max 2 review rounds per tier. After round 2, approve with notes.
    - Do NOT allow moving to next tier with unresolved Critical items.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (per-tier documentation):

```
Agent(
  name="doc-writer",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the documentation team for: $FEATURE

    Your responsibilities per tier:
    1. Document the tier's functionality and usage
    2. Add code examples showing how to use the tier
    3. Update any relevant README sections
    4. If the tier adds CLI flags or configuration, document them

    Rules:
    - Document each tier as it's completed (don't wait for all tiers)
    - Match existing documentation style
    - Commit format: docs(scope): document <tier> tier (English only)

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

### T-4. Workflow (Lead coordinates)

For each tier (Easy → Medium → Hard):

**Per-Tier Cycle:**
1. Dev implements tier + writes tests (sequential)
2. Reviewer validates ∥ Doc-writer documents (parallel)
3. If reviewer has Critical/Major findings → Dev fixes → Reviewer re-reviews
4. When tier approved → proceed to next tier

```
┌─── Tier N ────────────────────────────────┐
│ Dev: implement → test                      │
│        │                                   │
│        ├──► Reviewer: validate             │
│        │         │                         │
│        │    Has Critical?                  │
│        │    ├─ Yes → Dev fixes → Re-review │
│        │    └─ No → Approved               │
│        │                                   │
│        └──► Doc-writer: document           │
│                                            │
│ Tier approved → Next Tier ─────────────────┘
```

**Important:** Do NOT start next tier until reviewer approves current tier.
This prevents cascade failures where later tiers build on broken earlier tiers.

### T-5. Final Report (Lead)

After all tiers complete, generate the same report format as Solo Mode Step 5,
with additional team metrics:

| Metric | Value |
|--------|-------|
| Tiers completed | N/N (100%) |
| Review rounds | X total across all tiers |
| Change requests resolved | Y |

### T-6. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

### T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Check which tiers are complete (all must have passing tests)
3. Offer to continue in Solo Mode from the next incomplete tier
4. Preserve all commits — completed tiers are still valid

## Error Handling

| Scenario | Action |
|----------|--------|
| User declines confirmation | Stop and ask for clarification |
| Tests fail for a tier | Fix before proceeding to next tier |
| Blocked by external dependency | Pause, document, and notify user |
| Unclear tier requirements | Ask user for clarification before implementing |
| Team mode: teammate failure | Fallback to Solo Mode from next incomplete tier |
| Team mode: review loop exceeded | Approve tier with remaining items noted (max 2 rounds) |
| Agent Teams not enabled | Fall back to Solo Mode with warning |
