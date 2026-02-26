# 5W1H Examples and Templates

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/5w1h-examples`.

## Issue Examples

### What

```markdown
## What
- Implement user authentication using JWT tokens
- Current: No authentication exists
- Expected: Users can register, login, and access protected routes
- Scope: Backend API only (frontend will be separate issue)
```

### Why

```markdown
## Why
- Users cannot securely access personal data without authentication
- Impact: Security vulnerability, cannot launch to production
- Value: Enables personalized features and data protection
- Priority: Critical - blocks all user-facing features
```

### How

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

## PR Examples

### What

```markdown
## What

### Summary
Implements JWT-based authentication for the REST API, including user registration,
login, and token refresh endpoints.

### Change Type
- [x] Feature (new functionality)
- [ ] Bugfix (fixes an issue)
- [ ] Refactor (no functional changes)
- [ ] Documentation
- [ ] Test

### Affected Components
- `src/auth/` - New authentication service
- `src/middleware/` - Auth middleware added
- `src/routes/` - New auth routes
```

### Why

```markdown
## Why

### Problem Solved
Users currently cannot securely access their personal data. This PR implements
authentication to protect user resources and enable personalized features.

### Related Issues
- Closes #142 (Implement user authentication)
- Relates to #125 (Frontend login page)

### Alternative Approaches Considered
1. Session-based auth - Rejected due to stateless API requirement
2. OAuth only - Deferred to future PR for social login
```

### Issue Update Comment (MANDATORY after PR creation)

```markdown
## Implementation Update

| Field | Value |
|-------|-------|
| **PR** | #[PR_NUMBER] |
| **Branch** | `[BRANCH_NAME]` |
| **Status** | In Review |

### Summary
Brief description of the implementation approach.
```

### Multiple Issues Linking

```markdown
## Related Issues

### Primary
- Closes #142 (Implement user authentication)

### Secondary
- Relates to #125 (Frontend login page) - This PR provides backend endpoints
- Part of #100 (Epic: User Management) - First step of the epic

### Blocking
- Blocks #150 (Password reset feature) - Needs auth endpoints from this PR
```

### Who

```markdown
## Who

### Reviewers
- @security-lead - Security review required
- @backend-team - Code review

### Stakeholders
- Backend team (new patterns introduced)
- Frontend team (new API endpoints to consume)
- QA team (new test scenarios)

### Required Approvals
- [ ] Security team sign-off
- [ ] Backend lead approval
```

### When

```markdown
## When

### Urgency
- [x] Normal - Follow standard review process
- [ ] High Priority - Needed for upcoming release
- [ ] Hotfix - Production issue, expedite review

### Target Release
v2.0.0 (Sprint 15)

### Deployment Notes
- Requires database migration before deployment
- Should be deployed during low-traffic window

### Dependencies
- Depends on: #140 (Database schema changes) - Already merged
- Blocks: #145 (Password reset feature)
```

### Where

```markdown
## Where

### Files Changed
| Directory | Files | Type of Change |
|-----------|-------|----------------|
| `src/auth/` | 5 | New service |
| `src/middleware/` | 2 | New middleware |
| `src/routes/` | 3 | New endpoints |
| `tests/auth/` | 8 | New tests |

### API Changes
| Endpoint | Method | Status |
|----------|--------|--------|
| `/auth/register` | POST | New |
| `/auth/login` | POST | New |
| `/auth/refresh` | POST | New |
| `/auth/logout` | POST | New |

### Database Changes
- New table: `refresh_tokens`
- Migration: `20241201_add_refresh_tokens.sql`
```

### How

```markdown
## How

### Implementation Details
1. JWT tokens using RS256 algorithm with rotating keys
2. Access tokens expire in 15 minutes, refresh tokens in 7 days
3. Refresh tokens stored in database with device fingerprinting
4. Rate limiting: 5 login attempts per minute per IP

### Testing Done
- [x] Unit tests (47 new, all passing)
- [x] Integration tests (12 new, all passing)
- [x] Manual testing with Postman
- [x] Load testing (1000 concurrent logins)
- [ ] Security penetration testing (scheduled)

### Test Plan for Reviewers
1. Run `npm test` - All tests should pass
2. Start server: `npm run dev`
3. Test registration: `POST /auth/register` with valid payload
4. Test login: `POST /auth/login` and verify JWT returned
5. Test protected route with/without token

### Breaking Changes
- None - New endpoints only

### Rollback Plan
1. Revert this PR
2. Run down migration: `npm run migrate:down`
3. No data loss - new tables only
```

## PR Template

```markdown
## What

### Summary
<!-- Brief description of changes (2-3 sentences) -->

### Change Type
- [ ] Feature
- [ ] Bugfix
- [ ] Refactor
- [ ] Documentation
- [ ] Test
- [ ] Chore

## Why

### Related Issues
<!-- Closes #issue_number -->

### Motivation
<!-- Why are these changes needed? -->

## Who

### Reviewers
<!-- @mention required reviewers -->

### Required Approvals
- [ ] Code owner
- [ ] Security review (if applicable)

## When

### Urgency
- [ ] Normal
- [ ] High Priority
- [ ] Hotfix

### Target Release
<!-- Version or sprint -->

## Where

### Files Changed Summary
<!-- Overview of modified areas -->

### API/Database Changes
<!-- List any interface or schema changes -->

## How

### Implementation Highlights
<!-- Key technical decisions -->

### Testing Done
- [ ] Unit tests
- [ ] Integration tests
- [ ] Manual testing

### Test Plan
<!-- Steps for reviewers to verify -->

### Breaking Changes
<!-- List any breaking changes or "None" -->

## Checklist

- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No sensitive data exposed
- [ ] Commits are atomic and well-described
- [ ] Related issue(s) linked with closing keywords
- [ ] Comment added to related issue(s) with PR information
```
