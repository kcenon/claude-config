# Issue Work Command

Automate GitHub issue workflow with project name as argument.

## Usage

```
/issue-work <project-name>
```

**Example**:
```
/issue-work hospital_erp_system
/issue-work messaging_system
/issue-work thread_system
```

## Arguments

- `$ARGUMENTS`: Project name (required)
  - Repository: `https://github.com/kcenon/$ARGUMENTS`
  - Source path: `./$ARGUMENTS`

## Instructions

Execute the following workflow for the specified project:

### 1. Issue Selection

```bash
gh issue list --repo kcenon/$ARGUMENTS --label "priority/critical" --state open --limit 1
# If none found:
gh issue list --repo kcenon/$ARGUMENTS --label "priority/high" --state open --limit 1
```

Select the oldest (first created) issue from the results.

### 2. Issue Size Evaluation

Analyze the issue and determine size:

| Size | Expected LOC | Action |
|------|--------------|--------|
| XS/S | < 200 | Proceed directly |
| M | 200-500 | Consider splitting into 2-3 sub-issues |
| L/XL | > 500 | **Must split** into sub-issues, work on first |

If splitting required:
- Create sub-issues with `Part of #ORIGINAL` reference
- Apply 5W1H template for each sub-issue
- Proceed with the first sub-issue

### 3. Git Environment Setup

```bash
cd $ARGUMENTS
git fetch origin
git checkout main && git pull origin main
git checkout -b <type>/issue-<NUMBER>-<short-description>
```

Branch naming convention:
- `feat/issue-123-add-auth` (new feature)
- `fix/issue-456-null-pointer` (bug fix)
- `refactor/issue-789-optimize-query` (refactoring)
- `docs/issue-101-update-readme` (documentation)

### 4. Issue Assignment

```bash
gh issue edit <NUMBER> --repo kcenon/$ARGUMENTS --add-assignee @me
```

### 5. Code Implementation

1. **Analyze existing code style**:
   - Check `.clang-format`, `.editorconfig` if present
   - Review existing file patterns and conventions

2. **Implement changes**:
   - Follow existing code style strictly
   - Keep changes minimal and focused

3. **Header file review** (C/C++ projects):
   - Verify all used symbols have corresponding #include
   - Add missing headers

4. **Commit per logical unit**:
   - Format: `type(scope): description`
   - Language: English only
   - **Forbidden**: Claude/AI references, emojis, Co-Authored-By

### 6. Build and Test Verification

```bash
# Verify build succeeds (adapt to project's build system)
cmake --build build/ --config Release
# or: make, meson compile, cargo build, etc.

# Run tests
ctest --test-dir build/ --output-on-failure
# or: make test, cargo test, pytest, etc.
```

**If build/test fails**: Fix issues and retry before proceeding.

### 7. Documentation Update

Update relevant documentation if applicable:
- README.md
- CHANGELOG.md
- API documentation
- Code comments for complex logic

Commit separately:
```
docs(scope): update documentation for <feature>
```

### 8. Push and Create PR

```bash
git push -u origin <branch-name>

gh pr create --repo kcenon/$ARGUMENTS \
  --title "type(scope): description" \
  --body "Closes #<ISSUE_NUMBER>

## Summary
- Brief description of changes

## Test Plan
- How to verify the changes"
```

**Required**:
- `Closes #<NUMBER>` keyword to link issue
- English only
- No Claude/AI references or emojis

### 9. Update Original Issue

```bash
gh issue comment <NUMBER> --repo kcenon/$ARGUMENTS \
  --body "Implementation PR: #<PR_NUMBER>"
```

## Policies

| Item | Rule |
|------|------|
| Language | English for all commits, PRs, issues |
| Attribution | No Claude, AI, Co-Authored-By references |
| Emojis | Forbidden in commits and PRs |
| Issue linking | `Closes #NUM` required in PR |
| Build verification | Must pass before PR creation |

## Output

After completion, provide summary:

```markdown
## Work Summary

| Item | Value |
|------|-------|
| Project | $ARGUMENTS |
| Issue | #NUMBER - Title |
| Branch | branch-name |
| PR | #PR_NUMBER |
| Commits | N commits |

### Changes Made
- List of changes

### Files Modified
- file1.cpp
- file2.h

### Next Steps
- Any follow-up items
```
