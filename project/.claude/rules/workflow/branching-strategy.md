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

## Enforcement Layers

| Layer | Mechanism | Scope |
|-------|-----------|-------|
| Pre-push hook | `hooks/pre-push` | Blocks direct push to `main`/`develop` |
| PreToolUse hook | `pr-target-guard` | Blocks `gh pr create --base main` (unless `--head develop`) |
| GitHub Actions | `validate-pr-target.yml` | Auto-closes non-develop PRs targeting `main` |
| Release skill | integrity check | Warns if `main` diverged from `develop` before release |
