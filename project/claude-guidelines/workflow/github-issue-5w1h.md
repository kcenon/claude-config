# GitHub Issue Guidelines (5W1H Principle)

> **Version**: 2.0.0
> **Extracted from**: workflow.md
> **Purpose**: Framework for creating actionable GitHub issues

When creating GitHub issues, follow the **5W1H framework** to ensure comprehensive and actionable documentation.

## Reference Documentation

For detailed examples and automation patterns, see:

| Reference | Content |
|-----------|---------|
| [Label Definitions](reference/label-definitions.md) | Priority, type, area, status, size labels |
| [Automation Patterns](reference/automation-patterns.md) | gh CLI commands, GitHub Actions workflows |
| [Issue Examples](reference/issue-examples.md) | Splitting, hierarchy, linking, templates |

## Language and Attribution Policy

### Language Requirement

**All issues MUST be written in English** for:
- Global accessibility and collaboration
- Consistency with codebase and documentation standards
- Integration with automated tools and CI/CD systems

### No AI Attribution

**Exclude all AI-related references** from issues (professional appearance, focus on technical content).

## 5W1H Framework

### 1. What

**Describe the task or problem clearly**

- **Title**: Concise, descriptive summary (50 characters or less ideal)
- **Description**: Detailed explanation of what needs to be done
- **Current behavior**: What is happening now (for bugs)
- **Expected behavior**: What should happen instead
- **Scope**: Define boundaries - what IS and IS NOT included

```markdown
## What
- Implement user authentication using JWT tokens
- Current: No authentication exists
- Expected: Users can register, login, and access protected routes
- Scope: Backend API only (frontend will be separate issue)
```

### 2. Why

**Explain the motivation and business value**

- **Problem statement**: Why does this issue exist?
- **Impact**: What happens if this is not addressed?
- **Business value**: How does solving this benefit users?
- **Priority justification**: Why this priority level?

```markdown
## Why
- Users cannot securely access personal data without authentication
- Impact: Security vulnerability, cannot launch to production
- Value: Enables personalized features and data protection
- Priority: Critical - blocks all user-facing features
```

### 3. Who

**Identify stakeholders and responsibilities**

- **Assignee**: Who will work on this?
- **Reviewer**: Who should review the solution?
- **Stakeholders**: Who is affected by this issue?
- **Reporter**: Who identified this issue?

### 4. When

**Define timeline and milestones**

- **Due date**: When should this be completed?
- **Milestone**: Which release or sprint does this belong to?
- **Dependencies**: What must be completed before this can start?
- **Blockers**: What is preventing progress?

### 5. Where

**Specify location and context**

- **Affected files/components**: Which parts of the codebase?
- **Environment**: Development, staging, production?
- **Platform**: Web, mobile, API, specific OS?
- **Related issues/PRs**: Links to connected work

### 6. How

**Outline the implementation approach**

- **Technical approach**: High-level solution design
- **Acceptance criteria**: Specific, testable conditions for completion
- **Steps to reproduce**: (for bugs) Exact steps to recreate
- **Testing requirements**: How will this be verified?

```markdown
## How

### Technical Approach
1. Implement JWT token generation on login
2. Create authentication middleware
3. Add token refresh endpoint

### Acceptance Criteria
- [ ] User can register with email/password
- [ ] User can login and receive JWT token
- [ ] Protected routes reject requests without valid token
- [ ] Token expires after 24 hours
```

## Issue Template

```markdown
## What
<!-- Clear description of the task or problem -->

## Why
<!-- Motivation, impact, and business value -->

## Who
- Assignee:
- Reviewer:
- Stakeholders:

## When
- Due:
- Milestone:
- Dependencies:

## Where
- Files/Components:
- Environment:
- Related Issues:

## How

### Technical Approach
<!-- High-level implementation plan -->

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

### Additional Context
<!-- Screenshots, logs, references -->
```

## Quick Reference

### Pre-Submit Checklist

- [ ] **What**: Is the task/problem clearly described?
- [ ] **Why**: Is the motivation and impact explained?
- [ ] **Who**: Are assignees and stakeholders identified?
- [ ] **When**: Are deadlines and dependencies specified?
- [ ] **Where**: Are affected areas and related issues linked?
- [ ] **How**: Are acceptance criteria and approach defined?

### Issue Types and Required Fields

| Issue Type | Required 5W1H | Optional |
|------------|---------------|----------|
| **Bug** | What, Why, Where, How (reproduce) | When, Who |
| **Feature** | What, Why, How (criteria) | When, Where, Who |
| **Task** | What, How (criteria) | Why, When, Where, Who |
| **Epic** | What, Why, When | Where, How, Who |
| **Hotfix** | What, Why, Where, How | When (ASAP), Who |

### Quick Label Reference

| Category | Common Labels |
|----------|--------------|
| **Priority** | `priority/critical`, `priority/high`, `priority/medium`, `priority/low` |
| **Type** | `type/bug`, `type/feature`, `type/enhancement`, `type/docs` |
| **Size** | `size/XS`, `size/S`, `size/M`, `size/L`, `size/XL` |

For complete label definitions, see [Label Definitions Reference](reference/label-definitions.md).

### Issue Splitting Rule

**Issues > 2-3 days MUST be split** into smaller tasks.

| Size | Action |
|------|--------|
| ≤ 2 days | No split needed |
| 3-5 days | Consider splitting |
| 1+ week | **Must split** |

For splitting patterns and examples, see [Issue Examples Reference](reference/issue-examples.md).

### Auto-Close Keywords (in PRs)

| Keyword | Effect |
|---------|--------|
| `Closes #123` | Closes issue when PR merged |
| `Fixes #123` | Closes issue when PR merged |
| `Resolves #123` | Closes issue when PR merged |

## gh CLI Quick Commands

```bash
# Create issue with labels
gh issue create --title "[Bug]: Title" --label "type/bug" --label "priority/high"

# Add labels to existing issue
gh issue edit 123 --add-label "priority/high"

# List issues by label
gh issue list --label "type/bug" --label "priority/high"
```

For complete CLI reference and automation workflows, see [Automation Patterns Reference](reference/automation-patterns.md).

---

*Part of the workflow guidelines module*
