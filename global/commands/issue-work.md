# Issue Work Command

Automate GitHub issue workflow with project name as argument.

## Usage

```
/issue-work <project-name> [--org <organization>]
/issue-work <organization>/<project-name>
```

**Example**:
```
/issue-work hospital_erp_system                    # Auto-detect org from git remote
/issue-work hospital_erp_system --org mycompany    # Explicit organization
/issue-work mycompany/hospital_erp_system          # Full repo path format
```

## Arguments

- `$ARGUMENTS`: Project name or full repository path (required)
  - Format 1: `<project-name>` - auto-detect organization from git remote
  - Format 2: `<project-name> --org <organization>` - explicit organization
  - Format 3: `<organization>/<project-name>` - full repository path

## Organization Detection

Parse `$ARGUMENTS` and determine organization:

```bash
# Check if --org flag is provided
if [[ "$ARGUMENTS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$ARGUMENTS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
# Check if full path format (contains /)
elif [[ "$ARGUMENTS" == *"/"* ]]; then
    ORG=$(echo "$ARGUMENTS" | cut -d'/' -f1)
    PROJECT=$(echo "$ARGUMENTS" | cut -d'/' -f2)
# Auto-detect from git remote
else
    PROJECT="$ARGUMENTS"
    cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

- Repository: `https://github.com/$ORG/$PROJECT`
- Source path: `./$PROJECT`

## Instructions

Execute the following workflow for the specified project:

### 1. Issue Selection

```bash
gh issue list --repo $ORG/$PROJECT --label "priority/critical" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/high" --state open --limit 1
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
cd $PROJECT
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
gh issue edit <NUMBER> --repo $ORG/$PROJECT --add-assignee @me
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

gh pr create --repo $ORG/$PROJECT \
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
gh issue comment <NUMBER> --repo $ORG/$PROJECT \
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
| Repository | $ORG/$PROJECT |
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

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Project directory exists | "Project directory not found: [path]" | Verify project path in configuration |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No matching issues | Report "No critical/high priority issues found" | Check issue labels or lower priority filter |
| Issue already assigned | Report assignment status, offer to proceed or skip | Confirm continuation or select different issue |
| Branch already exists | Report existing branch, offer to reuse or rename | Delete old branch or use new name |
| Build failure | Create draft PR with failure log, request manual fix | Fix build errors before marking PR ready |
| Test failure | Report failing tests with details, pause workflow | Fix tests and retry |
| Push rejected | Report rejection reason (non-fast-forward, protected branch) | Pull latest changes or request permissions |
| PR creation failed | Report GitHub API error with details | Check repository permissions |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
