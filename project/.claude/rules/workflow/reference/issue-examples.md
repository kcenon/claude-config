# Issue Examples Reference

> **Version**: 1.0.0
> **Parent**: [GitHub Issue Guidelines](../github-issue-5w1h.md)
> **Purpose**: Detailed examples for issue splitting, hierarchy, linking, and templates

## Issue Splitting Rules

**MANDATORY**: Issues estimated to exceed **2-3 days** of work MUST be split into smaller, manageable issues.

### Why Split Large Issues?

1. **Better tracking**: Smaller issues provide clearer progress visibility
2. **Easier review**: Smaller PRs are easier to review and less error-prone
3. **Reduced risk**: Large issues have higher risk of scope creep and delays
4. **Parallel work**: Split issues can be worked on by multiple team members
5. **Incremental value**: Deliver value sooner with smaller, deployable units

### When to Split

| Estimated Duration | Action Required |
|--------------------|-----------------|
| ≤ 2 days (`size/XS`, `size/S`, `size/M`) | No split needed |
| 3-5 days (`size/L`) | **Consider splitting** - evaluate if natural boundaries exist |
| 1+ week (`size/XL`) | **Must split** - break down into smaller tasks immediately |

### How to Split Issues

#### Step 1: Identify Natural Boundaries

Look for these splitting points:

- **By layer**: Frontend / Backend / Database
- **By functionality**: CRUD operations (Create, Read, Update, Delete)
- **By component**: Individual UI components or services
- **By phase**: Setup → Implementation → Testing → Documentation
- **By dependency**: Independent features vs. dependent features

#### Step 2: Apply the INVEST Criteria

Each split issue should be:

| Criteria | Description |
|----------|-------------|
| **I**ndependent | Minimal dependencies on other issues |
| **N**egotiable | Flexible in implementation details |
| **V**aluable | Delivers some value when completed |
| **E**stimable | Can be reasonably estimated |
| **S**mall | Fits within 2 days of work |
| **T**estable | Has clear acceptance criteria |

#### Step 3: Create Parent-Child Structure

```markdown
## Parent Issue (Epic/Story)
- Title: [Feature]: User Authentication System
- Labels: `hierarchy/epic`, `size/XL`
- Description: Overview of the complete feature

### Child Issues (Tasks)
1. [Task]: Set up authentication database schema (#201)
   - size/S, 1-2 days
2. [Task]: Implement JWT token generation (#202)
   - size/M, 1-2 days
3. [Task]: Create login/logout API endpoints (#203)
   - size/M, 1-2 days
4. [Task]: Add authentication middleware (#204)
   - size/S, 1 day
5. [Task]: Write integration tests for auth flow (#205)
   - size/M, 1-2 days
```

### Splitting Patterns by Issue Type

#### Feature Development

```markdown
Original: "Implement user dashboard" (size/XL, ~2 weeks)

Split into:
1. Create dashboard layout component (size/S)
2. Implement user stats widget (size/M)
3. Implement recent activity widget (size/M)
4. Implement notifications widget (size/M)
5. Add dashboard API endpoints (size/M)
6. Write E2E tests for dashboard (size/S)
```

#### Bug Fix (Complex)

```markdown
Original: "Fix data synchronization issues" (size/L, ~4 days)

Split into:
1. Investigate and document sync failure scenarios (size/S)
2. Fix race condition in data fetching (size/M)
3. Add retry logic for failed syncs (size/S)
4. Add monitoring for sync failures (size/S)
```

#### Refactoring

```markdown
Original: "Refactor authentication module" (size/XL, ~1 week)

Split into:
1. Extract auth service from monolith (size/M)
2. Add unit tests for extracted service (size/M)
3. Migrate existing code to use new service (size/M)
4. Remove deprecated auth code (size/S)
5. Update documentation (size/S)
```

### Issue Splitting Checklist

Before creating a large issue, verify:

- [ ] **Estimated duration**: Is it > 2-3 days?
- [ ] **Splittable**: Can it be broken into independent units?
- [ ] **Dependencies mapped**: Are inter-issue dependencies clear?
- [ ] **Parent created**: Is there an Epic/Story to track the whole feature?
- [ ] **Each child valid**: Does each child meet INVEST criteria?
- [ ] **Total coverage**: Do all children together complete the parent?

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| Arbitrary splitting | "Part 1", "Part 2" without logic | Split by functionality or layer |
| Over-splitting | 20 tiny issues for a simple feature | Keep reasonable granularity (3-7 issues) |
| Missing parent | Child issues without tracking Epic | Always create parent for visibility |
| Circular dependencies | Issues that block each other | Reorder or restructure splits |
| Incomplete splits | Some work not captured in any child | Audit split completeness |

## Issue Hierarchy

Structure issues in a hierarchy for complex projects:

```
Epic (Large initiative, multiple sprints)
├── Story (User-facing feature, fits in one sprint)
│   ├── Task (Technical work item, 1-3 days)
│   │   └── Subtask (Checkbox items within a task)
│   └── Task
└── Story
    └── Task
```

### Hierarchy Definitions

| Level | Scope | Duration | Example |
|-------|-------|----------|---------|
| **Epic** | Major initiative or theme | Multiple sprints | "User Authentication System" |
| **Story** | User-facing functionality | 1 sprint or less | "As a user, I can reset my password" |
| **Task** | Technical implementation | 1-3 days | "Implement password reset API endpoint" |
| **Subtask** | Granular checklist item | < 1 day | "Add email validation" |

## Issue Linking

Use consistent syntax to connect related issues:

### Linking Keywords

| Keyword | Purpose | Example |
|---------|---------|---------|
| `Parent:` | Link to parent Epic/Story | `Parent: #100` |
| `Child:` | Link to child issues | `Child: #101, #102` |
| `Blocks:` | This issue blocks others | `Blocks: #103` |
| `Blocked by:` | This issue is blocked | `Blocked by: #99` |
| `Related:` | Related but not dependent | `Related: #105, #106` |
| `Duplicate of:` | Mark as duplicate | `Duplicate of: #50` |

### Auto-Close Keywords (in PRs)

These keywords in PR descriptions automatically close issues when merged:

| Keyword | Usage |
|---------|-------|
| `Closes #123` | Closes issue #123 |
| `Fixes #123` | Fixes issue #123 |
| `Resolves #123` | Resolves issue #123 |

```markdown
## Example Issue with Links

Parent: #100 (Epic: User Authentication)
Blocked by: #110 (Database migration)
Related: #115 (Login UI design)

## What
Implement JWT token refresh endpoint...
```

## GitHub Issue Templates

Create templates in `.github/ISSUE_TEMPLATE/` for consistent issue creation.

### Directory Structure

```
.github/
└── ISSUE_TEMPLATE/
    ├── bug_report.yml
    ├── feature_request.yml
    ├── task.yml
    └── config.yml
```

### Bug Report Template (bug_report.yml)

```yaml
name: Bug Report
description: Report a bug or unexpected behavior
title: "[Bug]: "
labels: ["type/bug", "status/needs-triage"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for reporting a bug! Please fill out the sections below.

  - type: textarea
    id: what
    attributes:
      label: What happened?
      description: Clear description of the bug
      placeholder: Describe the bug...
    validations:
      required: true

  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
      description: What should have happened?
    validations:
      required: true

  - type: textarea
    id: reproduce
    attributes:
      label: Steps to reproduce
      description: How can we reproduce this issue?
      placeholder: |
        1. Go to '...'
        2. Click on '...'
        3. See error
    validations:
      required: true

  - type: dropdown
    id: priority
    attributes:
      label: Priority
      options:
        - Low
        - Medium
        - High
        - Critical
    validations:
      required: true

  - type: textarea
    id: environment
    attributes:
      label: Environment
      description: OS, browser, version, etc.
      placeholder: |
        - OS: macOS 14.0
        - Browser: Chrome 120
        - Version: v2.1.0

  - type: textarea
    id: context
    attributes:
      label: Additional context
      description: Screenshots, logs, related issues
```

### Feature Request Template (feature_request.yml)

```yaml
name: Feature Request
description: Suggest a new feature or enhancement
title: "[Feature]: "
labels: ["type/feature", "status/needs-triage"]
body:
  - type: textarea
    id: what
    attributes:
      label: What feature do you want?
      description: Clear description of the feature
    validations:
      required: true

  - type: textarea
    id: why
    attributes:
      label: Why do you need this?
      description: Problem this solves or value it provides
    validations:
      required: true

  - type: textarea
    id: how
    attributes:
      label: Proposed solution
      description: How should this work? (optional)

  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives considered
      description: Other solutions you've considered

  - type: dropdown
    id: priority
    attributes:
      label: Priority
      options:
        - Low
        - Medium
        - High
    validations:
      required: true

  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria
      description: How will we know this is complete?
      placeholder: |
        - [ ] Criterion 1
        - [ ] Criterion 2
```

### Task Template (task.yml)

```yaml
name: Task
description: Create a technical task
title: "[Task]: "
labels: ["type/task"]
body:
  - type: textarea
    id: what
    attributes:
      label: What needs to be done?
      description: Clear description of the task
    validations:
      required: true

  - type: textarea
    id: approach
    attributes:
      label: Technical approach
      description: How will this be implemented?

  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria
      placeholder: |
        - [ ] Criterion 1
        - [ ] Criterion 2
    validations:
      required: true

  - type: dropdown
    id: size
    attributes:
      label: Size estimate
      options:
        - XS (< 1 hour)
        - S (1-4 hours)
        - M (1-2 days)
        - L (3-5 days)
        - XL (1+ week)

  - type: input
    id: parent
    attributes:
      label: Parent issue
      description: Link to parent Epic or Story
      placeholder: "#123"
```

### Config Template (config.yml)

```yaml
blank_issues_enabled: false
contact_links:
  - name: Documentation
    url: https://docs.example.com
    about: Check the documentation before opening an issue
  - name: Discussions
    url: https://github.com/org/repo/discussions
    about: For questions and general discussion
```

## Issue-PR Bidirectional Linking

### Updating Issues with PR Information

**MANDATORY**: When a PR is created for an issue, update the issue with PR information.

#### Why Update Issues?

1. **Traceability**: Easy to find the solution from the problem description
2. **Status visibility**: Stakeholders can track progress without navigating to PRs
3. **Review coordination**: Reviewers can access related context quickly
4. **Historical record**: Complete documentation of how issues were resolved

#### Issue Update Template

Add this comment when a PR is created:

```markdown
## Implementation Update

| Field | Value |
|-------|-------|
| **PR** | #[PR_NUMBER] |
| **Branch** | `[BRANCH_NAME]` |
| **Status** | In Progress / In Review / Merged |
| **Assignee** | @[USERNAME] |

### Implementation Notes
<!-- Brief notes about the implementation approach -->

### Remaining Work
- [ ] Item 1
- [ ] Item 2
```

#### Multiple PRs for Single Issue

For large issues requiring multiple PRs:

```markdown
## Implementation Progress

### Related PRs
| PR | Description | Status |
|----|-------------|--------|
| #201 | Database schema changes | Merged |
| #205 | Backend API implementation | In Review |
| #210 | Frontend integration | In Progress |

### Overall Progress: 66% (2/3 PRs merged)
```

---

*Part of the [GitHub Issue Guidelines](../github-issue-5w1h.md) reference documentation*
