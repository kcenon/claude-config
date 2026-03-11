---
name: doc-review
description: Comprehensive markdown document review - anchors, accuracy, SSOT, cross-references, and redundancy analysis.
argument-hint: "[docs-directory] [--scope anchors|accuracy|ssot|all] [--fix]"
user-invocable: true
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

## Argument Parsing

Parse `$ARGUMENTS` and extract directory, scope, and fix flag:

```bash
ARGS="$ARGUMENTS"
DOCS_DIR=""
SCOPE="all"
FIX_MODE=false

# Extract flags
if [[ "$ARGS" == *"--fix"* ]]; then
    FIX_MODE=true
    ARGS=$(echo "$ARGS" | sed 's/--fix//g')
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

Execute the document review workflow. Use parallel agents for scalability — split files equally among agents based on file count.

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

After completion, provide a structured review report:

```markdown
## Document Review Report

| Metric | Value |
|--------|-------|
| Directory | $DOCS_DIR |
| Files analyzed | N |
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

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| Docs directory exists | "Directory not found: [path]" | Verify path or use auto-detection |
| Markdown files found | "No .md files found in [path]" | Check directory contains markdown files |
| Git repository (for --fix) | "Not a git repository" | Run from within a git repository |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Agent timeout | Report partial results from completed agents | Re-run with smaller file set |
| No findings | Report clean status with score 10/10 | No action needed |
| Fix introduces new errors | Revert fix, report regression | Manual intervention required |
| File encoding issues | Skip file with warning | Ensure files are UTF-8 |
