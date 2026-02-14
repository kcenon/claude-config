# Code Quality Analysis Command

Analyze code quality and provide improvement suggestions.

## Usage

```
/code-quality [FILE_PATH or DIRECTORY]
```

## Arguments

- `FILE_PATH or DIRECTORY`: Target to analyze (required)
  - If directory, analyze all supported files recursively

## Options

| Option | Default | Description |
|--------|---------|-------------|
| --depth | unlimited | Max directory depth for recursive analysis |
| --format | markdown | Output format (markdown, json) |
| --verbose | false | Include detailed metrics |

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

## Thresholds

| Metric | OK | Warning | Critical |
|--------|-----|---------|----------|
| Cyclomatic Complexity | ≤10 | 11-20 | >20 |
| Cognitive Complexity | ≤15 | 16-30 | >30 |
| Function Length | ≤50 lines | 51-100 | >100 |
| Nesting Depth | ≤4 | 5-6 | >6 |
| File Length | ≤500 lines | 501-1000 | >1000 |
| Test Coverage | ≥80% | 60-79% | <60% |

## Language-Specific Tools

| Language | Complexity | Linting | Type Check |
|----------|------------|---------|------------|
| TypeScript | ts-complexity | ESLint | tsc --noEmit |
| Python | radon cc | ruff, pylint | mypy |
| C/C++ | lizard | clang-tidy | - |
| Go | gocyclo | golangci-lint | go vet |
| Rust | - | clippy | cargo check |

## Scoring Formula

```
Score = 10 - (Critical × 2) - (Warning × 0.5)
Minimum score: 0
```

| Score Range | Rating | Interpretation |
|-------------|--------|----------------|
| 9-10 | Excellent | Production-ready, minimal issues |
| 7-8 | Good | Minor improvements recommended |
| 5-6 | Fair | Several issues need attention |
| 3-4 | Poor | Significant refactoring required |
| 0-2 | Critical | Major quality concerns |

## Policies

See [_policy.md](./_policy.md) for common rules.

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
1. [Issue description] - [Severity: Critical/Major/Minor/Info]
   - Location: line X
   - Suggestion: [How to fix]

> Use the severity scale defined in [`pr-review.md`](pr-review.md#severity-definitions).

#### Recommendations
- [Prioritized list of improvements]

#### Score: X/10
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| File exists | "File not found: [path]" | Verify path and file existence |
| Readable file | "Permission denied: [path]" | Check file permissions |
| Supported file type | "Unsupported file type: [ext]" | Use supported extensions (.ts, .py, .kt, .cpp, etc.) |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Empty file | Report "No code to analyze" and skip | Add code to file or remove from analysis |
| Binary file | Report "Cannot analyze binary file" and skip | Exclude binary files from target |
| Encoding error | Report "Unable to read file encoding" | Convert file to UTF-8 |
| Directory not found | Report error with suggested similar paths | Verify directory path |
| Unsupported language | Report "Language not supported: [lang]" and list similar files | Target supported file types |
| Analysis timeout | Report partial results with warning | Reduce scope or split analysis |
