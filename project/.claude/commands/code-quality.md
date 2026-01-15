# Code Quality Analysis Command

Analyze code quality and provide improvement suggestions.

## Usage

```
/code-quality [FILE_PATH or DIRECTORY]
```

## Instructions

Perform comprehensive code quality analysis:

### 1. Complexity Analysis
- Cyclomatic complexity
- Cognitive complexity
- Nesting depth
- Function length

### 2. Code Smells
- Long methods
- Large classes
- Feature envy
- Data clumps
- Primitive obsession

### 3. SOLID Principles
- Single Responsibility
- Open/Closed
- Liskov Substitution
- Interface Segregation
- Dependency Inversion

### 4. Best Practices
- Naming conventions
- Error handling
- Logging practices
- Documentation coverage

### 5. Maintainability
- Code duplication
- Dead code
- Unused dependencies
- Technical debt

## Output Format

```markdown
## Code Quality Report

### File: [FILE_PATH]

#### Metrics
| Metric | Value | Status |
|--------|-------|--------|
| Complexity | X | OK/HIGH |
| Lines of Code | X | OK/HIGH |
| Test Coverage | X% | OK/LOW |

#### Issues Found
1. [Issue description] - [Severity]
   - Location: line X
   - Suggestion: [How to fix]

#### Recommendations
- [Prioritized list of improvements]

#### Score: X/10
```
