---
name: doc-review
description: Comprehensive markdown document review - anchors, accuracy, SSOT, cross-references, and redundancy analysis.
argument-hint: "[docs-directory] [--scope anchors|accuracy|ssot|all] [--fix] [--solo|--team]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Bash(git *)"
context: fork
agent: general-purpose
loop_safe: true
halt_conditions:
  - { type: success, expr: "review report emitted with all in-scope findings" }
  - { type: failure, expr: "fatal error reading the docs directory or scope cannot be resolved" }
on_halt: "Emit partial report listing what was reviewed and what was skipped"
---

# Document Review Command

Comprehensive markdown document review with parallel agent analysis.

## Usage

```
/doc-review                                    # Review all docs (auto-detect directory)
/doc-review docs/reference                     # Specify docs directory
/doc-review --scope anchors                    # Anchor validation only
/doc-review --scope accuracy                   # Accuracy/consistency only
/doc-review --scope ssot                       # SSOT/redundancy only
/doc-review --scope all --fix                  # Full review with auto-fix
/doc-review --solo                              # Force solo mode (subagents)
/doc-review --team                              # Force team mode (Agent Teams)
/doc-review docs/ --scope all --fix --team      # Full review, team mode, auto-fix
```

## Arguments

- `[docs-directory]`: Path to documentation directory (optional)
  - Auto-detection order: `docs/reference/` → `docs/` → `./`
  - Only `.md` files are analyzed

- `[--scope <phase>]`: Limit review to a specific phase (optional)
  - `anchors` — Phase 1 only (anchor/link validation)
  - `accuracy` — Phase 2 only (accuracy/consistency)
  - `ssot` — Phase 3 only (SSOT/redundancy)
  - `all` — All phases (default)

- `[--fix]`: Automatically apply fixes and commit (optional)
  - Without `--fix`: Report-only mode (no file modifications)
  - With `--fix`: Apply fixes → re-validate → commit

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode (independent subagents, no coordination)
  - `--team` — Force team mode (Agent Teams with shared task list)
  - If omitted: auto-recommend based on file count, then ask user

## Argument Parsing

Parse `$ARGUMENTS` and extract directory, scope, and fix flag:

```bash
ARGS="$ARGUMENTS"
DOCS_DIR=""
SCOPE="all"
FIX_MODE=false
EXEC_MODE=""

# Extract flags
if [[ "$ARGS" == *"--fix"* ]]; then
    FIX_MODE=true
    ARGS=$(echo "$ARGS" | sed 's/--fix//g')
fi

if [[ "$ARGS" == *"--solo"* ]]; then
    EXEC_MODE="solo"
    ARGS=$(echo "$ARGS" | sed 's/--solo//g')
elif [[ "$ARGS" == *"--team"* ]]; then
    EXEC_MODE="team"
    ARGS=$(echo "$ARGS" | sed 's/--team//g')
fi

if [[ "$ARGS" =~ --scope[[:space:]]+([a-z]+) ]]; then
    SCOPE="${BASH_REMATCH[1]}"
    ARGS=$(echo "$ARGS" | sed -E 's/--scope[[:space:]]+[a-z]+//g')
fi

# Remaining argument is docs directory
DOCS_DIR=$(echo "$ARGS" | xargs)

# Auto-detect if not specified
if [ -z "$DOCS_DIR" ]; then
    if [ -d "docs/reference" ]; then
        DOCS_DIR="docs/reference"
    elif [ -d "docs" ]; then
        DOCS_DIR="docs"
    else
        DOCS_DIR="."
    fi
fi
```

## Instructions

### Phase 0: Execution Mode Selection

Determine whether to run in Solo mode (independent subagents) or Team mode (coordinated Agent Teams).

#### 0-1. Count Target Files

```bash
FILE_COUNT=$(find "$DOCS_DIR" -name "*.md" -type f | wc -l | xargs)
```

#### 0-2. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-3. If no flag was provided (interactive selection)

Auto-recommend based on file count, then ask the user:

| File Count | Recommended Mode | Reason |
|-----------|-----------------|--------|
| 1-10 | Solo | Low coordination overhead |
| 11+ | Team | Benefit from shared findings and coordinated review |

Use `AskUserQuestion` to present the choice:

- **Question**: "Review $FILE_COUNT files in `$DOCS_DIR`. Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Independent subagents — simpler, lower token cost. Best for small doc sets."
- **Description for Team**: "Agent Teams with shared task list — reviewers can share findings. Better for large doc sets."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-4. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode** (subagent-based parallelism)
- If `$EXEC_MODE == "team"` → Execute **Team Mode** (Agent Teams with coordination)

---

## Solo Mode Instructions

Execute the document review workflow using independent subagents. Split files equally among agents based on file count.

### Agent Strategy

Determine the number of parallel agents based on file count:

| File Count | Agents | Strategy |
|-----------|--------|----------|
| 1-5 | 1 | Single agent, all phases sequentially |
| 6-15 | 2 | Split files evenly between 2 agents |
| 16-30 | 4 | Split files evenly among 4 agents |
| 31+ | 6 | Split files evenly among 6 agents |

Each agent receives its assigned file list and runs all applicable phases on those files. Use the `Agent` tool with `subagent_type=general-purpose` for each partition.

### Phase 1: Anchor and Link Validation

**Scope**: `anchors` or `all`

For each markdown file in the assigned partition:

1. **Build anchor registry**: Parse all headings to generate GitHub-style anchors
   - Algorithm: strip formatting → lowercase → remove non-alnum/space/hyphen (keep Unicode letters) → spaces→hyphens → collapse hyphens
   - Track duplicate headings (append `-1`, `-2` suffixes)
   - Skip content inside fenced code blocks (``` or ~~~)

2. **Validate intra-file references**: Check all `](#anchor)` links against the file's own anchors

3. **Validate inter-file references**: Check all `](./file.md#anchor)` and `](file.md#anchor)` links
   - Resolve relative paths from the referencing file's directory
   - Exclude external URLs (containing `:`)

4. **Report findings**: For each broken reference, record:
   - File name and line number
   - Expected anchor vs. actual heading
   - Severity: **Must-Fix** (all broken anchors are Must-Fix)

### Phase 2: Accuracy and Consistency

**Scope**: `accuracy` or `all`

For each markdown file in the assigned partition:

1. **Terminology consistency**: Identify inconsistent use of key terms across documents
   - Check for version number mismatches (e.g., "PostgreSQL 15" vs "PostgreSQL 16")
   - Check for product name variations (e.g., "DynamoDB" vs "Dynamo DB")
   - Check for standard/specification version inconsistencies

2. **Fact checking**: Flag statements that may be outdated or incorrect
   - Year references (check against current date)
   - URL/link validity (existence check only, not content)
   - Version numbers of external tools/libraries

3. **Report findings**: Classify each finding:
   - **Must-Fix**: Factual errors, version mismatches
   - **Should-Fix**: Inconsistent terminology, outdated references
   - **Nice-to-Have**: Style inconsistencies, minor wording issues

### Phase 3: SSOT and Redundancy Analysis

**Scope**: `ssot` or `all`

For each markdown file in the assigned partition:

1. **SSOT declaration detection**: Find explicit SSOT declarations
   - Pattern: sections marked as authoritative source for a topic
   - Track which topics have declared SSOTs

2. **Redundancy detection**: Find content that appears to duplicate another document's SSOT
   - Look for repeated tables, lists, or technical specifications
   - Check if non-SSOT documents properly defer via cross-references

3. **Cross-reference completeness**: Verify bidirectional cross-references
   - If document A references document B, check if B has a relevant back-reference
   - Identify orphan documents (no incoming cross-references)

4. **Report findings**: Classify each finding:
   - **Must-Fix**: Content contradicting SSOT, missing SSOT declarations for key topics
   - **Should-Fix**: Missing cross-references, one-directional references
   - **Nice-to-Have**: Redundant content that could be replaced with cross-references

### Phase 4: Fix and Verify (--fix mode only)

**Prerequisite**: `--fix` flag must be set. If not set, skip this phase and output report only.

1. **Priority order**: Fix Must-Fix items first, then Should-Fix, then Nice-to-Have
2. **Apply fixes**: Edit files using the `Edit` tool
   - Broken anchors: update reference to match actual heading anchor
   - Missing cross-references: add appropriate cross-reference blocks
   - Redundant content: replace with cross-reference to SSOT
3. **Regression validation**: After all fixes, re-run Phase 1 (anchor validation) to ensure no new breakages
4. **Commit**: If all validations pass, commit with message:
   ```
   docs: fix N broken anchors, M cross-references, K redundancies
   ```

### Result Aggregation

After all agents complete, aggregate results into a unified report.

---

## Team Mode Instructions

See `reference/team-mode.md` for the complete team mode workflow with parallel agent analysis, including team architecture, task creation, teammate spawning (Analyzer/Fixer/Validator), workflow phases, cleanup, and fallback handling.

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Scope** | Only analyze `.md` files in the specified directory (recursive) |
| **Code blocks** | Always skip content inside fenced code blocks |
| **Anchors** | Use GitHub-compatible slug algorithm for anchor generation |
| **Severity** | Every finding must be classified as Must-Fix, Should-Fix, or Nice-to-Have |
| **Commits** | Commit messages in English, conventional commit format |

## Output

This skill runs in a forked context (`context: fork`) using the `general-purpose` agent — write access is required for `--fix` mode. The forked subagent does not see the calling conversation's history; operate entirely from the supplied arguments.

After completion, provide a structured review report:

```markdown
## Document Review Report

| Metric | Value |
|--------|-------|
| Directory | $DOCS_DIR |
| Files analyzed | N |
| Execution mode | Solo / Team |
| Agents used | M |
| Scope | $SCOPE |

### Findings Summary

| Severity | Phase 1 (Anchors) | Phase 2 (Accuracy) | Phase 3 (SSOT) | Total |
|----------|-------------------|-------------------|----------------|-------|
| Must-Fix | A | B | C | A+B+C |
| Should-Fix | D | E | F | D+E+F |
| Nice-to-Have | G | H | I | G+H+I |

### Must-Fix Items
1. `file.md:42` — broken anchor `#nonexistent` → should be `#existing-heading`
2. ...

### Should-Fix Items
1. ...

### Nice-to-Have Items
1. ...

### Score
Overall: X.X/10 (Anchors: A/10, Accuracy: B/10, SSOT: C/10)

### Files Modified (--fix mode)
- file1.md (+3/-2)
- file2.md (+1/-1)
```

## Error Handling

See `reference/error-handling.md` for prerequisite checks and runtime error handling.
