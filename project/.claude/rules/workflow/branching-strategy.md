---
description: "Git branching strategy and CI policy"
alwaysApply: true
---

# Branching Strategy

## Branch Model

| Branch | Purpose | Protection |
|--------|---------|------------|
| `main` | Production releases only | PR required, CI must pass |
| `develop` | Integration branch (default) | PR required |
| `feature/*`, `fix/*`, `chore/*` | Work branches | None |

## Workflow

1. Create work branch from `develop`
2. Squash merge to `develop` via PR
3. Delete work branch after merge
4. Release: squash merge `develop` → `main` via PR (CI gate)
5. After release merge: delete `develop`, recreate from `main`

## CI Policy

CI runs only on PRs targeting `main`. Feature PRs to `develop` do not trigger CI.
