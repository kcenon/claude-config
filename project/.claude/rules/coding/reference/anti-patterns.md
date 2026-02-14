# Anti-Patterns Reference

Concrete before/after examples of common LLM coding mistakes. Each example maps to a principle in `core/principles.md`.

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/anti-patterns`.
>
> Inspired by [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876)
> and [forrestchang/andrej-karpathy-skills EXAMPLES.md](https://github.com/forrestchang/andrej-karpathy-skills/blob/main/EXAMPLES.md).

---

## 1. Challenge the Request

> Maps to: `core/principles.md` > **Think Before Acting**
> - Push back if a simpler approach exists
> - Present alternatives — don't pick silently

### Example 1.1: Hidden Assumptions

**User Request:** "Add a feature to export user data"

**What LLMs Commonly Do (Wrong)**

```python
def export_users(format='json'):
    """Export all users to a file."""
    users = User.query.all()

    if format == 'json':
        with open('users.json', 'w') as f:
            json.dump([u.to_dict() for u in users], f)
    elif format == 'csv':
        with open('users.csv', 'w') as f:
            writer = csv.DictWriter(f, fieldnames=['id', 'email', 'name'])
            writer.writeheader()
            writer.writerows([u.to_dict() for u in users])

    return f"Exported {len(users)} users"
```

**Problems:**
- Assumed export means ALL users (privacy? pagination?)
- Assumed file location without asking
- Assumed which fields to include
- Assumed CSV fieldnames without checking actual data structure
- Invented a second format (CSV) that was never requested

**What Should Happen (Correct)**

```
Before implementing, I need to clarify:

1. **Scope**: Export all users or filtered subset? (privacy implications)
2. **Format**: You mentioned "export" — did you mean:
   - Download file in browser?
   - Background job with email notification?
   - API endpoint returning data?
3. **Fields**: Which user fields? (some might be sensitive)
4. **Volume**: How many users typically? (affects approach)

Simplest approach: Add an API endpoint that returns paginated JSON.
Would need more info for file-based exports.
```

### Example 1.2: Multiple Interpretations

**User Request:** "Make the search faster"

**What LLMs Commonly Do (Wrong)**

```python
# Adds caching, database indexes, and async processing
# without asking which "faster" matters
@lru_cache(maxsize=1000)
async def search(query: str) -> List[Result]:
    # ... 200 lines of optimization code
```

**What Should Happen (Correct)**

```
"Make the search faster" could mean:

1. **Faster response time** (< 100ms instead of 500ms)
   → Add database indexes, cache frequent queries

2. **Handle more concurrent searches** (throughput)
   → Add async/await, connection pooling

3. **Faster perceived speed** (UX)
   → Show partial results immediately, progressive loading

Current search takes ~500ms for typical queries.
Which aspect matters most for your use case?
```

---

## 2. Minimize Code

> Maps to: `core/principles.md` > **Minimize & Focus**
> - No premature abstraction: three similar lines beat an unnecessary helper
> - Rewrite if bloated: if 200 lines could be 50, rewrite it
> - Self-check: "Would a senior engineer say this is overcomplicated?"

### Example 2.1: Over-Abstraction

**User Request:** "Add a function to calculate discount"

**What LLMs Commonly Do (Wrong)**

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float:
        pass

class PercentageDiscount(DiscountStrategy):
    def __init__(self, percentage: float):
        self.percentage = percentage

    def calculate(self, amount: float) -> float:
        return amount * (self.percentage / 100)

class FixedDiscount(DiscountStrategy):
    def __init__(self, fixed_amount: float):
        self.fixed_amount = fixed_amount

    def calculate(self, amount: float) -> float:
        return min(self.fixed_amount, amount)

@dataclass
class DiscountConfig:
    strategy: DiscountStrategy
    min_purchase: float = 0.0
    max_discount: float = float('inf')

class DiscountCalculator:
    def __init__(self, config: DiscountConfig):
        self.config = config

    def apply_discount(self, amount: float) -> float:
        if amount < self.config.min_purchase:
            return 0
        discount = self.config.strategy.calculate(amount)
        return min(discount, self.config.max_discount)
```

**Problems:**
- Strategy pattern with 5 classes for a single function
- Abstract base class for one concrete implementation
- Config dataclass for parameters that could be function arguments
- 40+ lines for what should be 3 lines

**What Should Happen (Correct)**

```python
def calculate_discount(amount: float, percent: float) -> float:
    """Calculate discount amount. percent should be 0-100."""
    return amount * (percent / 100)
```

Add complexity only when you actually need multiple discount types. If that requirement comes later, refactor then.

### Example 2.2: Speculative Features

**User Request:** "Save user preferences to database"

**What LLMs Commonly Do (Wrong)**

```python
class PreferenceManager:
    def __init__(self, db, cache=None, validator=None):
        self.db = db
        self.cache = cache or InMemoryCache()
        self.validator = validator or DefaultValidator()

    def save(self, user_id: int, prefs: dict,
             merge: bool = True,
             validate: bool = True,
             notify: bool = False) -> bool:
        if validate:
            errors = self.validator.validate(prefs)
            if errors:
                raise ValidationError(errors)

        existing = self.get(user_id) if merge else {}
        if merge:
            existing.update(prefs)
            prefs = existing

        self.db.execute(
            "UPDATE users SET preferences = ? WHERE id = ?",
            (json.dumps(prefs), user_id)
        )

        if self.cache:
            self.cache.set(f"prefs:{user_id}", prefs)

        if notify:
            self.notify_preference_change(user_id, prefs)

        return True
```

**Problems:**
- Cache, validation, merging, and notifications — none of which were requested
- 5 parameters with defaults that mask unneeded complexity
- Class wrapping a single database call

**What Should Happen (Correct)**

```python
def save_preferences(db, user_id: int, preferences: dict):
    """Save user preferences to database."""
    db.execute(
        "UPDATE users SET preferences = ? WHERE id = ?",
        (json.dumps(preferences), user_id)
    )
```

Add caching when performance demands it, validation when bad data appears, merging when the requirement emerges.

---

## 3. Surgical Edits

> Maps to: `core/principles.md` > **Surgical Precision**
> - Don't touch adjacent code
> - Clean up only your own mess — not pre-existing dead code
> - Self-check: "Does every changed line trace directly to the user's request?"

### Example 3.1: Drive-by Refactoring

**User Request:** "Fix the bug where empty emails crash the validator"

**What LLMs Commonly Do (Wrong)**

```diff
  def validate_user(user_data):
-     # Check email format
-     if not user_data.get('email'):
+     """Validate user data."""
+     email = user_data.get('email', '').strip()
+
+     # Validate email
+     if not email:
          raise ValueError("Email required")
-
-     # Basic email validation
-     if '@' not in user_data['email']:
+     if '@' not in email or '.' not in email.split('@')[1]:
          raise ValueError("Invalid email")

-     # Check username
-     if not user_data.get('username'):
+     # Validate username
+     username = user_data.get('username', '').strip()
+     if not username:
          raise ValueError("Username required")
+     if len(username) < 3:
+         raise ValueError("Username too short")
+     if not username.isalnum():
+         raise ValueError("Username must be alphanumeric")

      return True
```

**Problems:**
- "Improved" email validation beyond the bug fix
- Added username validation nobody asked for
- Changed comments ("Check" → "Validate")
- Added docstring to an existing function

**What Should Happen (Correct)**

```diff
  def validate_user(user_data):
      # Check email format
-     if not user_data.get('email'):
+     email = user_data.get('email', '')
+     if not email or not email.strip():
          raise ValueError("Email required")

      # Basic email validation
-     if '@' not in user_data['email']:
+     if '@' not in email:
          raise ValueError("Invalid email")

      # Check username
      if not user_data.get('username'):
          raise ValueError("Username required")

      return True
```

Only the lines that fix empty email handling are changed. Everything else is untouched.

### Example 3.2: Style Drift

**User Request:** "Add logging to the upload function"

**What LLMs Commonly Do (Wrong)**

```diff
- def upload_file(file_path, destination):
+ def upload_file(file_path: str, destination: str) -> bool:
+     """Upload file to destination with logging."""
+     logger.info(f"Uploading {file_path} to {destination}")
      try:
-         with open(file_path, 'rb') as f:
+         with open(file_path, "rb") as f:
              data = f.read()
-         response = requests.post(destination, files={'file': data})
-         if response.status_code == 200:
-             return True
-         else:
-             return False
+         response = requests.post(destination, files={"file": data})
+         success = response.status_code == 200
+         if success:
+             logger.info(f"Upload successful: {file_path}")
+         else:
+             logger.error(f"Upload failed: status={response.status_code}")
+         return success
      except Exception as e:
-         print(f"Error: {e}")
+         logger.exception(f"Upload error for {file_path}: {e}")
          return False
```

**Problems:**
- Changed quote style (`''` to `""`)
- Added type hints nobody asked for
- Added docstring
- Refactored boolean return logic
- Changed whitespace patterns

**What Should Happen (Correct)**

```diff
+ import logging
+
+ logger = logging.getLogger(__name__)
+
  def upload_file(file_path, destination):
+     logger.info(f'Starting upload: {file_path}')
      try:
          with open(file_path, 'rb') as f:
              data = f.read()
          response = requests.post(destination, files={'file': data})
          if response.status_code == 200:
+             logger.info(f'Upload successful: {file_path}')
              return True
          else:
+             logger.error(f'Upload failed: status={response.status_code}')
              return False
      except Exception as e:
-         print(f"Error: {e}")
+         logger.exception(f'Upload error: {file_path}')
          return False
```

Matched the existing code style: single quotes, no type hints, same boolean pattern, same spacing.

---

## 4. Test-First Verification

> Maps to: `core/principles.md` > **Verify & Iterate**
> - Reproduce before fixing: "fix the bug" → "write a test that reproduces it, then make it pass"
> - Define done: state what "done" looks like at each step before coding

### Example 4.1: Vague vs. Verifiable Execution

**User Request:** "Fix the authentication system"

**What LLMs Commonly Do (Wrong)**

```
I'll fix the authentication system by:
1. Reviewing the code
2. Identifying issues
3. Making improvements
4. Testing the changes

[Proceeds to make changes without clear success criteria]
```

**What Should Happen (Correct)**

```
To "fix authentication," I need to define success criteria.
What specific issue are we solving?

If the issue is "users stay logged in after password change":

Plan:
1. Write test: Change password → verify old session invalidated
   Verify: Test fails (reproduces bug)

2. Implement: Invalidate sessions on password change
   Verify: Test passes

3. Check edge cases: Multiple active sessions, concurrent changes
   Verify: Additional tests pass

4. Verify no regression: Existing auth tests still pass
   Verify: Full test suite green

What's the specific auth issue you're seeing?
```

### Example 4.2: Fix Without Reproducing

**User Request:** "The sorting breaks when there are duplicate scores"

**What LLMs Commonly Do (Wrong)**

```python
# Immediately changes sort logic without confirming the bug
def sort_scores(scores):
    return sorted(scores, key=lambda x: (-x['score'], x['name']))
```

**What Should Happen (Correct)**

```python
# Step 1: Write a test that reproduces the issue
def test_sort_with_duplicate_scores():
    scores = [
        {'name': 'Alice', 'score': 100},
        {'name': 'Bob', 'score': 100},
        {'name': 'Charlie', 'score': 90},
    ]

    result = sort_scores(scores)

    # The bug: order is non-deterministic for duplicates
    assert result[0]['score'] == 100
    assert result[1]['score'] == 100
    assert result[2]['score'] == 90
    # Stable ordering for ties
    assert result[0]['name'] == 'Alice'
    assert result[1]['name'] == 'Bob'

# Verify: Test fails with inconsistent ordering

# Step 2: Fix with stable sort
def sort_scores(scores):
    """Sort by score descending, then name ascending for ties."""
    return sorted(scores, key=lambda x: (-x['score'], x['name']))

# Verify: Test passes consistently
```

---

## Summary

| Principle | Anti-Pattern | Fix |
|-----------|-------------|-----|
| Challenge the Request | Silently assumes format, fields, scope | List assumptions, ask for clarification |
| Minimize Code | Strategy pattern for single calculation | One function until complexity is needed |
| Surgical Edits | Reformats quotes, adds type hints during bug fix | Only change lines that fix the issue |
| Test-First Verification | "I'll review and improve the code" | "Write test for X → make it pass → verify" |

## Key Insight

The "overcomplicated" examples aren't obviously wrong — they follow design patterns and best practices. The problem is **timing**: they add complexity before it's needed.

- Makes code harder to understand
- Introduces more surface area for bugs
- Takes longer to implement and review
- Harder to test

Good code solves today's problem simply. Refactor when complexity is actually needed.

---
*Reference document for core/principles.md. Version 1.0.0*
