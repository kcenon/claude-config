# Auto-Fixable SonarQube Rules (whitelist)

| Rule  | Type                | Phase  | Codified Fix |
|-------|---------------------|--------|--------------|
| S1481 | Unused local        | **P2** | **See § S1481** |
| S1128 | Unused import       | **P2** | **See § S1128** |
| S1854 | Dead assignment     | **P4** | **See § S1854** |
| S1192 | Literal duplication | **P4** | **See § S1192** |
| S125  | Commented-out code  | **P4** | **See § S125**  |
| S1116 | Empty statement     | **P4** | **See § S1116** |

## Excluded (never auto-fixed)
- `security_hotspot` (type): manual security review required
- `vulnerability` (type): manual security review required
- Complexity rules (cognitive/cyclomatic): architectural decisions
- Naming rules: cascade-heavy renames, risk of breaking external callers

---

## S1481 — Unused local variable

### Classifier
- sonarcloud[bot] inline comment matches `rule=S1481` (or message text contains "Remove this unused")
- severity ∈ {MINOR, MAJOR}
- target file extension ∈ {.py, .js, .ts, .go, .java, .cs, .cpp, .c} (skill is language-aware)

### Root cause
A local variable is declared and assigned but never read.

### Before
```python
def calculate(x, y):
    result = x + y   # noqa  ← S1481 warns here
    return x * y
```

### After
```python
def calculate(x, y):
    return x * y
```

### Verify
- After applying the fix, the surrounding function still parses (run language's syntax check)
- Re-run sonarcloud[bot] scan: the S1481 finding on the original `file:line` is gone
- No other diagnostic appears on the affected line

### Safety
- Idempotent: applying twice yields the same tree
- Side-effect risk: if the RHS of the assignment has side-effects (function call), do **not** auto-fix — escalate via `escalation-template.md`. Detect by parsing the AST; if not available, conservatively escalate when RHS contains `(` or `await` or `yield`.

---

## S1128 — Unused import

### Classifier
- sonarcloud[bot] inline comment matches `rule=S1128`
- severity ∈ {MINOR, MAJOR}
- target file extension ∈ {.py, .js, .ts, .java}

### Root cause
An import statement is present but the imported symbol is never used in the file.

### Before
```python
import os
import json

def load(path):
    return json.load(open(path))
```

### After
```python
import json

def load(path):
    return json.load(open(path))
```

### Verify
- After applying the fix, the file still parses
- Re-run sonarcloud[bot] scan: the S1128 finding on the original `file:line` is gone
- Run the test suite for the affected module — if a side-effect import was misclassified, tests catch it

### Safety
- Side-effect imports (e.g., `import django.setup`, `import warnings; warnings.filterwarnings(...)`) must be preserved. Detect by checking for top-level statements other than `import` in the imported module — if unsure, escalate.
- Preserve import grouping (stdlib / third-party / local), preserve blank-line separators between groups.

---

## S1854 — Dead assignment

### Classifier
- sonarcloud[bot] inline comment matches `rule=S1854` (or message text contains "Remove this useless assignment")
- severity ∈ {MINOR, MAJOR}
- target file extension ∈ {.py, .js, .ts, .go, .java, .cs, .cpp, .c}

### Root cause
A value is assigned to a variable, but before that variable is read the assignment is overwritten by a later one (or the variable's scope ends). The first assignment is therefore dead.

### Before
```python
def pick(items):
    chosen = items[0]   # ← S1854 warns here: chosen is overwritten before any read
    chosen = items[-1]
    return chosen
```

### After
```python
def pick(items):
    chosen = items[-1]
    return chosen
```

### Verify
- The line carrying the original `file:line` from the finding no longer exists, and the function still parses
- The variable on the surviving line is still read at least once in the same scope (otherwise it has degenerated into an S1481 finding and must be handled there)
- Re-run sonarcloud[bot] scan: the S1854 finding on the original `file:line` is gone

### Safety
- Side-effect risk: if the RHS of the dead assignment is a function call, a `print`/`logger.*` invocation, an `assert`, an `await`, or a `yield`, do **not** auto-fix — escalate. Only literal/identifier RHS values are eligible.
- Debug-trace risk: if the dead assignment matches a temporary-variable convention (`tmp_*`, `_dbg_*`, `_unused_*`) the developer may be intentionally probing — escalate.
- Idempotent: applying twice yields the same tree.

---

## S1192 — String literal duplication

### Classifier
- sonarcloud[bot] inline comment matches `rule=S1192` (or message text contains "Define a constant instead of duplicating this literal")
- severity ∈ {MAJOR, CRITICAL}
- target file extension ∈ {.py, .js, .ts, .java, .cs}

### Root cause
The same string literal appears three or more times in the same file, suggesting it should be extracted into a named constant so a future rename is a one-line change.

### Before
```python
def has_admin(user):
    return user.role == "administrator"

def grant_admin(user):
    user.role = "administrator"
    save(user)

def is_admin_email(email):
    return email.endswith("@administrator.example.com") and "administrator" in email
```

### After
```python
ADMINISTRATOR_ROLE = "administrator"


def has_admin(user):
    return user.role == ADMINISTRATOR_ROLE

def grant_admin(user):
    user.role = ADMINISTRATOR_ROLE
    save(user)

def is_admin_email(email):
    return email.endswith("@administrator.example.com") and ADMINISTRATOR_ROLE in email
```

### Verify
- The original literal no longer appears as a bare string at the three (or more) sites flagged by the finding — every occurrence in those sites is now a constant reference
- The new constant is defined exactly once at module scope (or class scope when all occurrences share a class)
- The existing test suite for the affected module passes — a misclassified literal (different semantics per site) will fail a test that compared the constant's identity to a string of a different role
- Re-run sonarcloud[bot] scan: the S1192 finding on the original `file:line` is gone

### Safety
- Semantic divergence: if any of the duplicated occurrences serves a different role (e.g., one is a format-string token like `"%s"`, another is a user-facing label), **escalate** — they only look the same.
- Security-sensitive literals: SQL fragments, HTML tags, URL paths, regex patterns, secrets/keys — **escalate**. Extracting a constant changes how reviewers reason about injection surface.
- Naming ambiguity: if no obvious constant name covers all sites' semantics (e.g., `"admin"` used both as a role name and as a URL segment), **escalate** rather than pick a name.
- Length floor: literals shorter than 5 characters are **not** auto-fixed even when duplicated — a constant indirection costs more readability than it saves.

---

## S125 — Commented-out code

### Classifier
- sonarcloud[bot] inline comment matches `rule=S125` (or message text contains "Remove this commented out code")
- severity ∈ {MAJOR, MINOR}
- target file extension ∈ any source file the skill is configured for

### Root cause
A comment block contains code that could be uncommented and run, rather than prose explaining intent. Version control already preserves the prior code, so the comment is noise.

### Before
```python
def parse(payload):
    data = json.loads(payload)
    # result = legacy_parser(payload)
    # if result is None:
    #     result = data
    return data
```

### After
```python
def parse(payload):
    data = json.loads(payload)
    return data
```

### Verify
- The exact comment line(s) flagged by the finding are removed; the surrounding prose comments (rationale, TODOs, license headers) remain untouched
- The file still parses
- Re-run sonarcloud[bot] scan: the S125 finding on the original `file:line` is gone

### Safety
- Intentional-marker comments: if the comment line contains `TODO`, `FIXME`, `NOTE`, `XXX`, or `HACK` (case-insensitive), **escalate** — the line is documentation, not dead code, regardless of what the SonarQube parser thinks.
- Fresh authorship: if `git blame` for the comment line is ≤30 days old, **escalate** — the author may still be iterating and uncomment the block soon.
- Block size: a contiguous commented-code block of three or more lines is intentional often enough that the skill **escalates** rather than deletes. Only single-line or two-line commented-out fragments are auto-fixed.
- Idempotent: applying twice yields the same tree.

---

## S1116 — Empty statement

### Classifier
- sonarcloud[bot] inline comment matches `rule=S1116` (or message text contains "Remove this empty statement")
- severity ∈ {MINOR}
- target file extension ∈ any source file the skill is configured for

### Root cause
A bare `;` (in C-family languages) or a redundant statement separator produces a statement with no effect. The most common cause is a typo at the end of an `if`, `for`, or `while` header.

### Before
```c
if (cond);
{
    do_thing();
}
```

### After
```c
if (cond)
{
    do_thing();
}
```

### Verify
- The bare `;` flagged by the finding is removed; the control-flow structure that follows is now correctly attached to its header
- The file still parses and the surrounding control-flow semantics are intact (the block now executes conditionally, not unconditionally)
- Re-run sonarcloud[bot] scan: the S1116 finding on the original `file:line` is gone

### Safety
- Intentional empty body: if the `;` follows an `if`/`while`/`for`/`switch` header and is paired with a comment that asserts intent (`/* intentional */`, `// empty on purpose`, `# nop`), **escalate** — the empty body is deliberate.
- Timing-loop idiom: in C/C++, constructs such as `while (*p++) ;` or `for (volatile int i = 0; i < N; i++) ;` are intentional spin loops. If the `;` body is the sole body of a loop and the loop header has side-effects, **escalate**.
- Function-body fallthrough: an empty `;` inside a function body (not following a control header) is the only configuration auto-fixed.
- Language-specific replacement: Python flags an empty block as a `SyntaxError` rather than S1116; if a Python `pass` is being targeted as "empty," it must be preserved (it is the only legal empty body in Python).
