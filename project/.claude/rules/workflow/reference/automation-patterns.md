---
paths:
  - ".github/**"
alwaysApply: false
---

# Automation Patterns Reference

> **Version**: 1.0.0
> **Parent**: [GitHub Issue Guidelines](../github-issue-5w1h.md)
> **Purpose**: GitHub CLI commands and automation workflows for issue management

## gh CLI Label Commands

Use the GitHub CLI (`gh`) for efficient issue creation with labels.

### Creating Issues with Labels

```bash
# Basic issue with labels
gh issue create \
  --title "[Bug]: Authentication fails on timeout" \
  --body "$(cat <<'EOF'
## What
Authentication endpoint returns 500 error after 30s timeout.

## Why
Users cannot log in, blocking all authenticated features.

## How
### Steps to Reproduce
1. Navigate to login page
2. Enter credentials
3. Wait 30+ seconds

### Acceptance Criteria
- [ ] Login succeeds within reasonable timeout
- [ ] Proper error message on timeout
EOF
)" \
  --label "type/bug" \
  --label "priority/high" \
  --label "area/auth" \
  --label "size/M"

# Feature request with multiple areas
gh issue create \
  --title "[Feature]: Add OAuth2 support" \
  --body "..." \
  --label "type/feature" \
  --label "priority/medium" \
  --label "area/auth" \
  --label "area/api" \
  --label "size/L"

# Security issue (always high priority)
gh issue create \
  --title "[Security]: SQL injection vulnerability in search" \
  --body "..." \
  --label "type/security" \
  --label "priority/critical" \
  --label "area/db" \
  --label "area/api"
```

### Adding Labels to Existing Issues

```bash
# Add single label
gh issue edit 123 --add-label "priority/high"

# Add multiple labels
gh issue edit 123 --add-label "type/bug" --add-label "area/auth"

# Remove label
gh issue edit 123 --remove-label "status/needs-triage"

# Replace labels (remove old, add new)
gh issue edit 123 \
  --remove-label "priority/medium" \
  --add-label "priority/high"
```

### Listing Issues by Label

```bash
# Find all high priority bugs
gh issue list --label "type/bug" --label "priority/high"

# Find all issues in auth area
gh issue list --label "area/auth"

# Find all critical issues
gh issue list --label "priority/critical" --state open

# Find issues needing triage
gh issue list --label "status/needs-triage" --limit 50
```

### Batch Label Operations

```bash
# Add label to multiple issues
for issue in 101 102 103; do
  gh issue edit $issue --add-label "milestone/v2.0"
done

# Label all untriaged issues as needs-info
gh issue list --label "status/needs-triage" --json number -q '.[].number' | \
  xargs -I {} gh issue edit {} --add-label "status/needs-info"
```

## GitHub Actions Labeler

Create `.github/labeler.yml` to automatically apply area labels based on changed files:

```yaml
# .github/labeler.yml
area/api:
  - changed-files:
    - any-glob-to-any-file: 'src/api/**/*'
    - any-glob-to-any-file: 'src/routes/**/*'

area/auth:
  - changed-files:
    - any-glob-to-any-file: 'src/auth/**/*'
    - any-glob-to-any-file: 'src/middleware/auth*'

area/db:
  - changed-files:
    - any-glob-to-any-file: 'src/models/**/*'
    - any-glob-to-any-file: 'src/migrations/**/*'
    - any-glob-to-any-file: 'prisma/**/*'

area/ui:
  - changed-files:
    - any-glob-to-any-file: 'src/components/**/*'
    - any-glob-to-any-file: 'src/pages/**/*'
    - any-glob-to-any-file: '**/*.css'
    - any-glob-to-any-file: '**/*.scss'

area/infra:
  - changed-files:
    - any-glob-to-any-file: '.github/**/*'
    - any-glob-to-any-file: 'docker/**/*'
    - any-glob-to-any-file: 'Dockerfile'
    - any-glob-to-any-file: 'docker-compose*.yml'

area/config:
  - changed-files:
    - any-glob-to-any-file: 'config/**/*'
    - any-glob-to-any-file: '*.config.js'
    - any-glob-to-any-file: '*.config.ts'

type/docs:
  - changed-files:
    - any-glob-to-any-file: '**/*.md'
    - any-glob-to-any-file: 'docs/**/*'

type/test:
  - changed-files:
    - any-glob-to-any-file: '**/*.test.*'
    - any-glob-to-any-file: '**/*.spec.*'
    - any-glob-to-any-file: 'tests/**/*'
    - any-glob-to-any-file: '__tests__/**/*'
```

### Labeler Workflow

```yaml
# .github/workflows/labeler.yml
name: Pull Request Labeler

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

jobs:
  labeler:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/labeler@v5
        with:
          repo-token: "${{ secrets.GITHUB_TOKEN }}"
          configuration-path: .github/labeler.yml
```

## Issue Auto-Labeling Workflow

Automatically label new issues based on content:

```yaml
# .github/workflows/issue-labeler.yml
name: Issue Labeler

on:
  issues:
    types: [opened, edited]

permissions:
  issues: write

jobs:
  label-issues:
    runs-on: ubuntu-latest
    steps:
      - name: Auto-label based on title/content
        uses: actions/github-script@v7
        with:
          script: |
            const issue = context.payload.issue;
            const title = issue.title.toLowerCase();
            const body = (issue.body || '').toLowerCase();
            const content = title + ' ' + body;

            const labelsToAdd = [];

            // Type detection from title prefix
            if (title.startsWith('[bug]')) {
              labelsToAdd.push('type/bug');
            } else if (title.startsWith('[feature]')) {
              labelsToAdd.push('type/feature');
            } else if (title.startsWith('[security]')) {
              labelsToAdd.push('type/security');
              labelsToAdd.push('priority/critical');
            } else if (title.startsWith('[docs]')) {
              labelsToAdd.push('type/docs');
            } else if (title.startsWith('[task]')) {
              labelsToAdd.push('type/task');
            }

            // Area detection from content keywords
            const areaKeywords = {
              'area/auth': ['authentication', 'login', 'logout', 'jwt', 'oauth', 'password', 'session'],
              'area/api': ['endpoint', 'rest', 'graphql', 'api', 'request', 'response'],
              'area/db': ['database', 'query', 'migration', 'schema', 'sql', 'postgres', 'mysql'],
              'area/ui': ['component', 'button', 'form', 'modal', 'css', 'style', 'frontend'],
              'area/infra': ['docker', 'kubernetes', 'ci/cd', 'deployment', 'pipeline']
            };

            for (const [label, keywords] of Object.entries(areaKeywords)) {
              if (keywords.some(kw => content.includes(kw))) {
                labelsToAdd.push(label);
              }
            }

            // Always add needs-triage for new issues
            if (context.payload.action === 'opened') {
              labelsToAdd.push('status/needs-triage');
            }

            // Add labels if any detected
            if (labelsToAdd.length > 0) {
              await github.rest.issues.addLabels({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issue.number,
                labels: [...new Set(labelsToAdd)]
              });
            }
```

## Label Validation Workflow

Ensure required labels are present:

```yaml
# .github/workflows/label-validation.yml
name: Label Validation

on:
  issues:
    types: [opened, labeled, unlabeled]
  pull_request:
    types: [opened, labeled, unlabeled]

jobs:
  validate-labels:
    runs-on: ubuntu-latest
    steps:
      - name: Check required labels
        uses: actions/github-script@v7
        with:
          script: |
            const labels = context.payload.issue?.labels || context.payload.pull_request?.labels || [];
            const labelNames = labels.map(l => l.name);

            const hasType = labelNames.some(l => l.startsWith('type/'));
            const hasPriority = labelNames.some(l => l.startsWith('priority/'));
            const isBugOrFeature = labelNames.includes('type/bug') || labelNames.includes('type/feature');

            const warnings = [];

            if (!hasType) {
              warnings.push('Missing type label (e.g., type/bug, type/feature)');
            }

            if (isBugOrFeature && !hasPriority) {
              warnings.push('Bugs and features require a priority label');
            }

            if (warnings.length > 0) {
              console.log('Label validation warnings:');
              warnings.forEach(w => console.log(w));

              const number = context.issue?.number || context.payload.pull_request?.number;
              if (number) {
                await github.rest.issues.createComment({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: number,
                  body: `## Label Validation\n\n${warnings.map(w => '- ' + w).join('\n')}\n\nPlease add the required labels.`
                });
              }
            }
```

---

*Part of the [GitHub Issue Guidelines](../github-issue-5w1h.md) reference documentation*
