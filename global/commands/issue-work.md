# Issue Work Command

Automate GitHub issue workflow with project name as argument.

## Usage

```
/issue-work <project-name> [issue-number] [--org <organization>]
/issue-work <organization>/<project-name> [issue-number]
```

**Examples**:
```
/issue-work vi_slam                              # Auto-select priority issue
/issue-work vi_slam 21                           # Work on issue #21
/issue-work vi_slam 21 --org mycompany          # Explicit organization
/issue-work mycompany/vi_slam 21                # Full repo path format
```

## Arguments

- `<project-name>`: Project name or full repository path (required)
  - Format 1: `<project-name>` - auto-detect organization from git remote
  - Format 2: `<project-name> --org <organization>` - explicit organization
  - Format 3: `<organization>/<project-name>` - full repository path

- `[issue-number]`: GitHub issue number (optional)
  - If provided: Work on the specified issue
  - If omitted: Auto-select highest priority open issue

## Argument Parsing

Parse `$ARGUMENTS` and extract project, organization, and issue number:

```bash
ARGS="$ARGUMENTS"
ISSUE_NUMBER=""
PROJECT=""
ORG=""

# Extract issue number if present (numeric argument)
if [[ "$ARGS" =~ [[:space:]]([0-9]+)([[:space:]]|$) ]]; then
    ISSUE_NUMBER="${BASH_REMATCH[1]}"
    # Remove issue number from args
    ARGS=$(echo "$ARGS" | sed -E "s/[[:space:]]+${ISSUE_NUMBER}([[:space:]]|$)/ /g")
fi

# Check if --org flag is provided
if [[ "$ARGS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGS" | awk '{print $1}')
    ORG=$(echo "$ARGS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
# Check if full path format (contains /)
elif [[ "$ARGS" == *"/"* ]]; then
    ORG=$(echo "$ARGS" | cut -d'/' -f1 | xargs)
    PROJECT=$(echo "$ARGS" | cut -d'/' -f2 | xargs)
# Auto-detect from git remote
else
    PROJECT=$(echo "$ARGS" | xargs)
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
- Issue Number: `$ISSUE_NUMBER` (empty if not provided)

## Instructions

Execute the following workflow for the specified project:

### 1. Issue Selection

**If issue number is provided:**

```bash
# Fetch specific issue
gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json number,title,state,labels

# Verify issue exists and is open
STATE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json state -q '.state')
if [[ "$STATE" != "OPEN" ]]; then
    echo "Error: Issue #$ISSUE_NUMBER is not open (state: $STATE)"
    exit 1
fi
```

**If issue number is NOT provided:**

```bash
# Auto-select by priority
gh issue list --repo $ORG/$PROJECT --label "priority/critical" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/high" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/medium" --state open --limit 1
```

Select the oldest (first created) issue from the results.

Store the selected issue number in `$ISSUE_NUMBER` variable.

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

# Extract issue title for branch name
ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json title -q '.title')
# Convert to kebab-case (lowercase, replace spaces with hyphens)
SHORT_DESC=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g' | cut -c1-50)

# Determine branch type from issue labels
LABELS=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json labels -q '.labels[].name')
if echo "$LABELS" | grep -q "type/feature"; then
    BRANCH_TYPE="feat"
elif echo "$LABELS" | grep -q "type/bug"; then
    BRANCH_TYPE="fix"
elif echo "$LABELS" | grep -q "type/refactor"; then
    BRANCH_TYPE="refactor"
elif echo "$LABELS" | grep -q "type/docs"; then
    BRANCH_TYPE="docs"
else
    BRANCH_TYPE="feat"  # Default
fi

BRANCH_NAME="${BRANCH_TYPE}/issue-${ISSUE_NUMBER}-${SHORT_DESC}"
git checkout -b "$BRANCH_NAME"
```

Branch naming convention examples:
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
   - **Language: MANDATORY English only** - All commit messages MUST be written in English
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
git push -u origin "$BRANCH_NAME"

gh pr create --repo $ORG/$PROJECT \
  --title "${BRANCH_TYPE}(scope): description" \
  --body "Closes #${ISSUE_NUMBER}

## Summary
- Brief description of changes

## Test Plan
- How to verify the changes"
```

**Required**:
- `Closes #<NUMBER>` keyword to link issue
- **Language: MANDATORY English only** - All PR titles and descriptions MUST be written in English
- No Claude/AI references, emojis, or Co-Authored-By (see `commit-settings.md`)

After PR creation, capture the PR URL from `gh pr create` output for the summary.

### 9. Update Original Issue

**IMPORTANT**: All issue comments **MUST** be written in **English only**, regardless of the project's primary language or user's locale.

```bash
gh issue comment <NUMBER> --repo $ORG/$PROJECT \
  --body "Implementation PR: #<PR_NUMBER>"
```

## Policies

See [_policy.md](./_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | **All issue comments, PR titles, PR descriptions, and commit messages MUST be written in English only** |
| Issue linking | `Closes #NUM` required in PR |
| Build verification | Must pass before PR creation |

## Output

After completion, provide summary:

```markdown
## Work Summary

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #$ISSUE_NUMBER - Title |
| Branch | $BRANCH_NAME |
| PR | [#PR_NUMBER](https://github.com/$ORG/$PROJECT/pull/PR_NUMBER) |
| Commits | N commits |

### Changes Made
- List of changes

### Files Modified
- file1.cpp
- file2.h

### Next Steps
- Any follow-up items
```

**IMPORTANT**: Always include the full PR URL in the output (e.g., `https://github.com/org/repo/pull/123`).

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Project directory exists | "Project directory not found: [path]" | Verify project path in configuration |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |
| Issue exists | "Issue #NUM not found" | Verify issue number is correct |
| Issue is open | "Issue #NUM is not open" | Cannot work on closed issues |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No matching issues (auto-select) | Report "No open issues found with specified priority" | Create new issue or adjust priority filter |
| Issue already assigned | Report assignment status, offer to proceed or skip | Confirm continuation or select different issue |
| Branch already exists | Report existing branch, offer to reuse or rename | Delete old branch or use new name |
| Build failure | Create draft PR with failure log, request manual fix | Fix build errors before marking PR ready |
| Test failure | Report failing tests with details, pause workflow | Fix tests and retry |
| Push rejected | Report rejection reason (non-fast-forward, protected branch) | Pull latest changes or request permissions |
| PR creation failed | Report GitHub API error with details | Check repository permissions |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
