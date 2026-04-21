---
alwaysApply: false
---

# GitHub Issue Guidelines (5W1H Principle)

Follow the **5W1H framework** for comprehensive, actionable issues.

## 5W1H Framework

| # | Question | Key Fields |
|---|----------|------------|
| 1 | **What** | Title (≤50 chars), description, current/expected behavior, scope |
| 2 | **Why** | Problem statement, impact, business value, priority justification |
| 3 | **Who** | Assignee, reviewer, stakeholders |
| 4 | **When** | Due date, milestone, dependencies, blockers |
| 5 | **Where** | Affected files/components, environment, related issues/PRs |
| 6 | **How** | Technical approach, acceptance criteria, reproduction steps, testing |

> Examples and templates: see `reference/5w1h-examples.md`

## Quick Reference

### Issue Types and Required Fields

| Issue Type | Required 5W1H | Optional |
|------------|---------------|----------|
| **Bug** | What, Why, Where, How (reproduce) | When, Who |
| **Feature** | What, Why, How (criteria) | When, Where, Who |
| **Task** | What, How (criteria) | Why, When, Where, Who |
| **Epic** | What, Why, When | Where, How, Who |
| **Hotfix** | What, Why, Where, How | When (ASAP), Who |

### Issue Splitting Rule

**Issues > 2-3 days MUST be split.** See `reference/issue-examples.md`.

### Auto-Close Keywords (in PRs)

`Closes #N`, `Fixes #N`, `Resolves #N` — closes issue when PR merges.

### Labels

| Category | Common Labels |
|----------|--------------|
| **Priority** | `priority/critical`, `priority/high`, `priority/medium`, `priority/low` |
| **Type** | `type/bug`, `type/feature`, `type/enhancement`, `type/docs` |
| **Size** | `size/XS`, `size/S`, `size/M`, `size/L`, `size/XL` |

> Full definitions: `reference/label-definitions.md` | Automation: `reference/automation-patterns.md`
