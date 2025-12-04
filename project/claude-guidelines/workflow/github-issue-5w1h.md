# GitHub Issue Guidelines (5W1H Principle)

> **Version**: 1.1.0
> **Extracted from**: workflow.md
> **Purpose**: Comprehensive framework for creating actionable GitHub issues

When creating GitHub issues, follow the **5W1H framework** to ensure comprehensive and actionable documentation.

## 1. What

**Describe the task or problem clearly**

- **Title**: Concise, descriptive summary (50 characters or less ideal)
- **Description**: Detailed explanation of what needs to be done or what the problem is
- **Current behavior**: What is happening now (for bugs)
- **Expected behavior**: What should happen instead
- **Scope**: Define boundaries - what IS and IS NOT included in this issue

```markdown
## What
- Implement user authentication using JWT tokens
- Current: No authentication exists
- Expected: Users can register, login, and access protected routes
- Scope: Backend API only (frontend will be separate issue)
```

## 2. Why

**Explain the motivation and business value**

- **Problem statement**: Why does this issue exist?
- **Impact**: What happens if this is not addressed?
- **Business value**: How does solving this benefit users or the project?
- **Priority justification**: Why this priority level?

```markdown
## Why
- Users cannot securely access personal data without authentication
- Impact: Security vulnerability, cannot launch to production
- Value: Enables personalized features and data protection
- Priority: Critical - blocks all user-facing features
```

## 3. Who

**Identify stakeholders and responsibilities**

- **Assignee**: Who will work on this?
- **Reviewer**: Who should review the solution?
- **Stakeholders**: Who is affected by this issue?
- **Reporter**: Who identified this issue? (for context/questions)

```markdown
## Who
- Assignee: @backend-team
- Reviewer: @security-lead
- Stakeholders: All users requiring login
- Reporter: @product-manager (for requirement clarification)
```

## 4. When

**Define timeline and milestones**

- **Due date**: When should this be completed?
- **Milestone**: Which release or sprint does this belong to?
- **Dependencies**: What must be completed before this can start?
- **Blockers**: What is preventing progress? (if applicable)

```markdown
## When
- Due: 2024-12-15
- Milestone: v2.0.0 Release
- Dependencies: Database schema migration (#123)
- Blockers: Waiting for security audit results
```

## 5. Where

**Specify location and context**

- **Affected files/components**: Which parts of the codebase are involved?
- **Environment**: Development, staging, production?
- **Platform**: Web, mobile, API, specific OS?
- **Related issues/PRs**: Links to connected work

```markdown
## Where
- Files: `src/auth/`, `src/middleware/auth.ts`
- Environment: All environments
- Platform: REST API (Node.js backend)
- Related: #120 (user model), #125 (frontend login page)
```

## 6. How

**Outline the implementation approach**

- **Technical approach**: High-level solution design
- **Acceptance criteria**: Specific, testable conditions for completion
- **Steps to reproduce**: (for bugs) Exact steps to recreate the issue
- **Testing requirements**: How will this be verified?

```markdown
## How

### Technical Approach
1. Implement JWT token generation on login
2. Create authentication middleware
3. Add token refresh endpoint
4. Integrate with existing user model

### Acceptance Criteria
- [ ] User can register with email/password
- [ ] User can login and receive JWT token
- [ ] Protected routes reject requests without valid token
- [ ] Token expires after 24 hours
- [ ] Refresh token extends session

### Testing Requirements
- Unit tests for auth service (>80% coverage)
- Integration tests for auth endpoints
- Security penetration test for token handling
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

---
*Part of the workflow guidelines module*
