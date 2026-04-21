---
alwaysApply: false
---

# GitHub Pull Request Guidelines (5W1H Principle)

Follow the **5W1H framework** so reviewers can quickly understand and evaluate changes.

## 5W1H Framework

| # | Question | Key Fields |
|---|----------|------------|
| 1 | **What** | Title (`type(scope): desc`), summary, change type, affected components |
| 2 | **Why** | Problem solved, related issues, business value, alternatives considered |
| 3 | **Who** | Reviewers, stakeholders, required sign-offs |
| 4 | **When** | Urgency, target release, deployment notes, dependencies |
| 5 | **Where** | Files changed, architecture/API/database impact |
| 6 | **How** | Implementation details, testing done, test plan, breaking changes, rollback |

> Examples and templates: see `reference/5w1h-examples.md`

## Issue Linking (MANDATORY)

Every PR MUST link to at least one issue (unless trivial fix).

- **Close**: `Closes #N`, `Fixes #N`, `Resolves #N`
- **Reference**: `Relates to #N`, `Part of #N`, `See also #N`
- **After PR creation**: Add implementation update comment to linked issue(s)

## Quick Reference

### PR Title Conventions

`feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `security`

### PR Size Guidelines

| Size | Lines | Recommendation |
|------|-------|----------------|
| **XS** | < 50 | Ideal |
| **S** | 50-200 | Preferred |
| **M** | 200-500 | Consider splitting |
| **L** | 500-1000 | Split if possible |
| **XL** | > 1000 | Must split |

### Reviewer Checklist

- [ ] Changes match description (What)
- [ ] Solves stated problem (Why)
- [ ] Correct reviewers (Who)
- [ ] No timing issues (When)
- [ ] Scoped correctly (Where)
- [ ] Sound implementation, adequate tests (How)
- [ ] Issue(s) properly linked
