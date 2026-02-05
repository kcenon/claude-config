---
paths: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.jsx", "**/*.py", "**/*.java", "**/*.go", "**/*.rs"]
---

# Implementation Standards

> **Purpose**: Ensure complete implementation of all feature tiers and variants
> **Impact**: Prevents incomplete implementations that cause test failures

## Core Principle

When implementing features with multiple tiers, difficulty levels, or variants, **all levels must be fully implemented**. Partial implementations (e.g., only Easy tier) are not acceptable.

## Enumeration-First Approach

Before writing any implementation code:

1. **List all tiers/variants** that need implementation
2. **Document each tier's requirements** explicitly
3. **Plan implementation order** (typically Easy → Medium → Hard)
4. **Verify completeness** against the full specification

### Example: Tiered Feature Implementation

When implementing a feature with difficulty tiers:

```typescript
// Step 1: Enumerate ALL tiers before coding
enum DifficultyTier {
    EASY = 'easy',
    MEDIUM = 'medium',
    HARD = 'hard',
    EXPERT = 'expert'  // Don't forget any tier!
}

// Step 2: Implement ALL cases
function processByDifficulty(tier: DifficultyTier): Result {
    switch (tier) {
        case DifficultyTier.EASY:
            return processEasyTier();
        case DifficultyTier.MEDIUM:
            return processMediumTier();
        case DifficultyTier.HARD:
            return processHardTier();
        case DifficultyTier.EXPERT:
            return processExpertTier();
        // No default - compiler catches missing cases
    }
}
```

## Anti-Patterns to Avoid

### Incomplete Switch Statements

```typescript
function handleTier(tier: Tier): void {
    switch (tier) {
        case Tier.EASY:
            handleEasy();
            break;
        // MEDIUM and HARD are missing!
        default:
            throw new Error('Not implemented');  // Unacceptable
    }
}
```

### TODO Comments Instead of Implementation

```python
def process_difficulty(level: str) -> Result:
    if level == "easy":
        return easy_implementation()
    elif level == "medium":
        # TODO: Implement medium difficulty  # Unacceptable
        pass
    elif level == "hard":
        raise NotImplementedError()  # Unacceptable
```

### Placeholder Returns

```go
func ProcessTier(tier TierType) (Result, error) {
    switch tier {
    case TierEasy:
        return processEasy()
    case TierMedium:
        return Result{}, nil  // Empty placeholder - Unacceptable
    case TierHard:
        return Result{Status: "pending"}, nil  // Stub - Unacceptable
    }
}
```

## Correct Implementation Patterns

### Complete Enum Coverage

```typescript
// TypeScript: Use exhaustive switch with type checking
type Difficulty = 'easy' | 'medium' | 'hard';

function getMultiplier(difficulty: Difficulty): number {
    switch (difficulty) {
        case 'easy': return 1.0;
        case 'medium': return 1.5;
        case 'hard': return 2.0;
    }
    // TypeScript error if any case is missing (with strictNullChecks)
}
```

### Pattern Matching with Exhaustiveness

```rust
// Rust: Compiler enforces exhaustive matching
enum Difficulty {
    Easy,
    Medium,
    Hard,
}

fn get_score_multiplier(difficulty: Difficulty) -> f64 {
    match difficulty {
        Difficulty::Easy => 1.0,
        Difficulty::Medium => 1.5,
        Difficulty::Hard => 2.0,
        // Compiler error if any variant is missing
    }
}
```

### Complete Dictionary Mapping

```python
from typing import Callable, Dict

TIER_HANDLERS: Dict[str, Callable[[], Result]] = {
    "easy": handle_easy,
    "medium": handle_medium,
    "hard": handle_hard,
}

def process_tier(tier: str) -> Result:
    handler = TIER_HANDLERS.get(tier)
    if handler is None:
        raise ValueError(f"Unknown tier: {tier}")
    return handler()
```

## Verification Checklist

Before marking implementation as complete:

- [ ] All enum values/tiers have corresponding implementations
- [ ] No `TODO`, `FIXME`, or `NotImplementedError` in production code
- [ ] No empty/placeholder return values
- [ ] Tests exist and pass for ALL tiers/variants
- [ ] Edge cases for each tier are handled

## Test Coverage Requirements

Each tier must have dedicated tests:

```python
class TestDifficultyTiers:
    def test_easy_tier_processing(self):
        result = process_tier("easy")
        assert result.status == "success"
        assert result.multiplier == 1.0

    def test_medium_tier_processing(self):
        result = process_tier("medium")
        assert result.status == "success"
        assert result.multiplier == 1.5

    def test_hard_tier_processing(self):
        result = process_tier("hard")
        assert result.status == "success"
        assert result.multiplier == 2.0
```

## Language-Specific Guidelines

| Language | Exhaustiveness Check | Recommended Pattern |
|----------|---------------------|---------------------|
| TypeScript | `strictNullChecks` + no default | Discriminated unions |
| Rust | Built-in match exhaustiveness | `match` expressions |
| Python | Manual verification | Dictionary mapping |
| Java | IDE warnings for switch | Sealed classes (17+) |
| Go | Manual verification | Explicit error returns |

## Related Guidelines

- [Quality Standards](quality.md) - General code quality
- [Error Handling](error-handling.md) - Exception handling patterns
