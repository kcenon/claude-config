# Auto-Fixable SonarQube Rules (whitelist)

| Rule  | Type                | Phase  | Codified Fix |
|-------|---------------------|--------|--------------|
| S1481 | Unused local        | **P2** | **See § S1481** |
| S1128 | Unused import       | **P2** | **See § S1128** |
| S1854 | Dead assignment     | P4     | TODO: P4 |
| S1192 | Literal duplication | P4     | TODO: P4 |
| S125  | Commented-out code  | P4     | TODO: P4 |
| S1116 | Empty statement     | P4     | TODO: P4 |

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
