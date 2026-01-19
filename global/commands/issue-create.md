# Issue Create Command

Create well-structured GitHub issues using the 5W1H framework.

## Usage

```
/issue-create <project-name> [--type <type>] [--priority <priority>] [--org <organization>]
/issue-create <organization>/<project-name> [--type <type>] [--priority <priority>]
```

**Example**:
```
/issue-create hospital_erp_system                              # Interactive mode
/issue-create hospital_erp_system --type bug --priority high   # With options
/issue-create mycompany/hospital_erp_system --type feature     # Full repo path
```

## Arguments

`$ARGUMENTS` format: `<project-name> [options]` or `<organization>/<project-name> [options]`

- **Project name**: Repository name (or full path with organization)
- **--type**: Issue type (bug, feature, refactor, docs) - default: feature
- **--priority**: Priority level (critical, high, medium, low) - default: medium
- **--org**: GitHub organization or user (optional, auto-detected if not provided)

## Organization Detection

Parse `$ARGUMENTS` and determine organization:

```bash
# Check if --org flag is provided
if [[ "$ARGUMENTS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$ARGUMENTS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
# Check if first argument contains / (full path format)
elif [[ "$(echo "$ARGUMENTS" | awk '{print $1}')" == *"/"* ]]; then
    REPO_PATH=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
    PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
# Auto-detect from git remote
else
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--type` | bug, feature, refactor, docs | feature | Issue type for labeling |
| `--priority` | critical, high, medium, low | medium | Priority level |
| `--org` | string | auto-detect | GitHub organization or user |

## Instructions

### 1. Gather Issue Details

Collect information through conversation:

| Field | Required | Prompt |
|-------|----------|--------|
| Title | Yes | "What is a brief title for this issue?" |
| Type | Yes | "Is this a bug, feature, refactor, or docs?" |
| Priority | Yes | "What priority: critical, high, medium, or low?" |
| Description | Yes | "Describe the issue in detail (What needs to be done?)" |
| Motivation | Yes | "Why is this needed? What problem does it solve?" |
| Acceptance Criteria | Yes | "What are the acceptance criteria?" |

### 2. Apply 5W1H Framework

Structure the issue using the 5W1H template:

```markdown
## What
<!-- Clear description of the task or problem -->

## Why
<!-- Motivation, impact, and business value -->

## Where
- Files/Components:
- Environment:
- Related Issues:

## How

### Technical Approach
<!-- High-level implementation plan if known -->

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

### 3. Determine Labels

Based on gathered information, select appropriate labels:

#### Type Labels

| Type | Label | Use When |
|------|-------|----------|
| Bug | `type/bug` | Something is broken |
| Feature | `type/feature` | New functionality |
| Refactor | `type/refactor` | Code improvement without behavior change |
| Docs | `type/docs` | Documentation changes |

#### Priority Labels

| Priority | Label | Use When |
|----------|-------|----------|
| Critical | `priority/critical` | Blocking production, security issue |
| High | `priority/high` | Important, needed soon |
| Medium | `priority/medium` | Standard priority |
| Low | `priority/low` | Nice to have |

#### Size Estimation (Optional)

| Size | Label | Expected LOC |
|------|-------|--------------|
| XS | `size/XS` | < 50 lines |
| S | `size/S` | 50-200 lines |
| M | `size/M` | 200-500 lines |
| L | `size/L` | 500-1000 lines |
| XL | `size/XL` | > 1000 lines (should be split) |

### 4. Create Issue

```bash
gh issue create --repo $ORG/$PROJECT \
  --title "[Type]: Title" \
  --label "type/<type>" \
  --label "priority/<priority>" \
  --body "$(cat <<'EOF'
## What
<description>

## Why
<motivation>

## Where
- Files/Components: <if known>
- Related Issues: <if any>

## How

### Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
EOF
)"
```

### 5. Confirm Creation

After creating the issue:
- Report the issue URL
- Summarize the created issue

## Title Conventions

| Type | Format | Example |
|------|--------|---------|
| Bug | `[Bug]: Brief description` | `[Bug]: Login fails with special characters` |
| Feature | `[Feature]: Brief description` | `[Feature]: Add dark mode toggle` |
| Refactor | `[Refactor]: Brief description` | `[Refactor]: Extract auth middleware` |
| Docs | `[Docs]: Brief description` | `[Docs]: Update API documentation` |

## Policies

| Item | Rule |
|------|------|
| Language | English for all issue content |
| Attribution | No Claude, AI, or bot references |
| Title length | 50 characters or less (ideal) |
| Acceptance criteria | At least 2 testable items |

## Output

After completion, provide summary:

```markdown
## Issue Created

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #NUMBER |
| URL | https://github.com/$ORG/$PROJECT/issues/NUMBER |
| Type | type |
| Priority | priority |

### Summary
- Title: <title>
- Description: <brief summary>
- Acceptance Criteria: N items
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Repository access | "Cannot access repository" | Verify repository permissions |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Invalid type | Report valid options: bug, feature, refactor, docs | Choose from valid types |
| Invalid priority | Report valid options: critical, high, medium, low | Choose from valid priorities |
| Empty title | Prompt for title again | Provide a non-empty title |
| Issue creation failed | Report GitHub API error with details | Check repository permissions |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Label not found | Create issue without label, warn user | Labels may need to be created in repository |
