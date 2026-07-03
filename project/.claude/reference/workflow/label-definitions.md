---
paths:
  - ".github/**"
alwaysApply: false
---

# Label Definitions Reference

> **Version**: 1.0.0
> **Parent**: [GitHub Issue Guidelines](../github-issue-5w1h.md)
> **Purpose**: Comprehensive reference for GitHub issue labeling standards

## Priority Labels

Use priority labels to indicate urgency and importance:

| Label | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| `priority/critical` | System down, security breach, data loss | Immediate (< 4h) | Production outage, security vulnerability |
| `priority/high` | Major feature broken, blocking release | Same day (< 24h) | Core functionality failure, critical bug |
| `priority/medium` | Important but not urgent, planned work | This sprint | Feature requests, non-critical bugs |
| `priority/low` | Nice to have, minor improvements | Backlog | Minor UI issues, documentation updates |

### Priority Selection Guidelines

1. **Critical**: Assign only when business operations are severely impacted
2. **High**: Use for issues blocking other work or affecting many users
3. **Medium**: Default for most planned features and improvements
4. **Low**: For issues that can wait without significant impact

## Type Labels

Classify issues by their nature:

| Label | Description | When to Use |
|-------|-------------|-------------|
| `type/bug` | Something isn't working | Unexpected behavior, errors, crashes |
| `type/feature` | New functionality | Adding new capabilities |
| `type/enhancement` | Improvement to existing feature | Better UX, performance, etc. |
| `type/docs` | Documentation only | README, API docs, comments |
| `type/refactor` | Code restructuring | No behavior change, cleaner code |
| `type/test` | Test-related changes | Adding/fixing tests |
| `type/chore` | Maintenance tasks | Dependencies, configs, cleanup |
| `type/security` | Security-related | Vulnerabilities, hardening |

## Area Labels

Identify affected codebase areas (customize per project):

| Label | Description | Examples |
|-------|-------------|----------|
| `area/api` | API layer | REST endpoints, GraphQL resolvers |
| `area/auth` | Authentication/Authorization | Login, permissions, tokens |
| `area/ui` | User interface | Components, styling, UX |
| `area/db` | Database layer | Schema, queries, migrations |
| `area/infra` | Infrastructure | CI/CD, deployment, Docker |
| `area/core` | Core business logic | Domain models, services |
| `area/config` | Configuration | Settings, environment variables |
| `area/deps` | Dependencies | Package updates, vulnerabilities |

### Defining Project-Specific Areas

```markdown
<!-- Recommended: 5-10 areas based on your architecture -->
area/api          # API endpoints
area/auth         # Authentication
area/billing      # Payment & subscriptions
area/notifications # Email, push, SMS
area/analytics    # Metrics, tracking
area/admin        # Admin dashboard
```

## Status Labels

Track issue lifecycle:

| Label | Description | When to Apply |
|-------|-------------|---------------|
| `status/needs-triage` | Awaiting review | Auto-applied to new issues |
| `status/confirmed` | Verified and accepted | After triage review |
| `status/in-progress` | Actively being worked | When work starts |
| `status/needs-info` | Waiting for reporter | Missing details |
| `status/blocked` | Cannot proceed | Dependency or external blocker |
| `status/wontfix` | Will not be addressed | Out of scope, by design |
| `status/duplicate` | Already reported | Link to original issue |

## Size Labels

Estimate effort for sprint planning:

| Label | Effort | Time Estimate | Examples |
|-------|--------|---------------|----------|
| `size/XS` | Trivial | < 1 hour | Typo fix, config change |
| `size/S` | Small | 1-4 hours | Simple bug fix, minor feature |
| `size/M` | Medium | 1-2 days | Standard feature, moderate bug |
| `size/L` | Large | 3-5 days | Complex feature, significant refactor |
| `size/XL` | Extra Large | 1+ week | Major feature, architecture change |

### Size Estimation Guidelines

1. **Include**: Development, testing, code review, documentation
2. **Exclude**: Waiting time, meetings, deployment
3. **When uncertain**: Choose the larger size
4. **Re-estimate**: Update if scope changes during work

```markdown
<!-- Size estimation examples -->
size/XS  → Fix typo in error message
size/S   → Add input validation to form
size/M   → Implement password reset flow
size/L   → Add OAuth2 integration
size/XL  → Migrate from REST to GraphQL
```

## Hierarchy Labels

Structure issues in a hierarchy for complex projects:

| Label | Description |
|-------|-------------|
| `hierarchy/epic` | Top-level initiative |
| `hierarchy/story` | User story |
| `hierarchy/task` | Technical task |

## Label Combinations

Common label combinations for different issue types:

```markdown
<!-- Bug report -->
Labels: `type/bug`, `priority/high`, `area/auth`, `status/confirmed`

<!-- New feature -->
Labels: `type/feature`, `priority/medium`, `area/api`, `area/db`

<!-- Security issue -->
Labels: `type/security`, `priority/critical`, `area/auth`

<!-- Documentation -->
Labels: `type/docs`, `priority/low`, `area/api`

<!-- Technical debt -->
Labels: `type/refactor`, `priority/medium`, `area/core`
```

## Mandatory Label Checklist

**IMPORTANT**: Every issue MUST have at least the required labels before submission.

### Required Labels by Issue Type

| Issue Type | Required Labels | Recommended Labels |
|------------|-----------------|-------------------|
| **Bug** | `type/bug`, `priority/*`, `area/*` | `status/*`, `size/*` |
| **Feature** | `type/feature`, `priority/*` | `area/*`, `size/*` |
| **Enhancement** | `type/enhancement`, `priority/*`, `area/*` | `size/*` |
| **Security** | `type/security`, `priority/critical` or `priority/high` | `area/*` |
| **Documentation** | `type/docs` | `area/*` |
| **Refactor** | `type/refactor`, `area/*` | `priority/*`, `size/*` |
| **Task** | `type/task` or `type/chore` | `area/*`, `size/*` |

### Label Validation Checklist

Before creating an issue, verify:

- [ ] **Type label**: One `type/*` label is applied
- [ ] **Priority label**: One `priority/*` label is applied (required for bugs, features, security)
- [ ] **Area label**: At least one `area/*` label is applied (when applicable)
- [ ] **Size label**: One `size/*` label is applied (for sprint planning)
- [ ] **No conflicting labels**: Only one priority, one size, one type

## Label Decision Tree

Use this decision tree to select appropriate labels:

```
┌─ Is it broken/not working?
│   └─ YES → type/bug
│       └─ Production issue? → priority/critical
│       └─ Blocking work? → priority/high
│       └─ Annoying but workaround exists? → priority/medium
│       └─ Minor inconvenience? → priority/low
│
├─ Is it a new capability?
│   └─ YES → type/feature
│       └─ Business critical? → priority/high
│       └─ Nice to have? → priority/medium or priority/low
│
├─ Is it improving existing functionality?
│   └─ YES → type/enhancement
│
├─ Is it security-related?
│   └─ YES → type/security + priority/critical or priority/high
│
├─ Is it code restructuring without behavior change?
│   └─ YES → type/refactor
│
├─ Is it documentation only?
│   └─ YES → type/docs
│
└─ Is it maintenance/configuration?
    └─ YES → type/chore
```

## Label Naming Convention

| Rule | Example | Rationale |
|------|---------|-----------|
| Use `/` as separator | `type/bug`, `area/api` | Clear categorization |
| Lowercase only | `priority/high` not `Priority/High` | Consistency |
| Singular nouns | `type/bug` not `type/bugs` | Simplicity |
| No spaces | `area/user-management` | URL-safe |

---

*Part of the [GitHub Issue Guidelines](../github-issue-5w1h.md) reference documentation*
