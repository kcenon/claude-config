---
name: implement-all-levels
description: Enforce complete implementation of all tiers/difficulty levels for tiered features. Prevents partial implementations.
argument-hint: "<feature-description> [--solo|--team]"
user-invocable: true
disable-model-invocation: true
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

See `reference/team-mode.md` for the complete team mode workflow with per-tier dev/reviewer/doc-writer cycles, task dependency tables, teammate spawn prompts, and fallback procedures.

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
