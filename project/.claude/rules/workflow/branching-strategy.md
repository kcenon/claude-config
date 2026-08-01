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

CI scope is decided by each workflow's `pull_request` trigger, not by the branch
model. A `pull_request:` trigger with **no `branches:` filter fires on PRs to every
base branch, `develop` included** — so unless a workflow explicitly filters to
`main`, feature PRs to `develop` run it too.

Verify before assuming either way: grep the `branches:` filters under
`.github/workflows/` rather than relying on this document. Budget accordingly —
a feature PR to `develop` usually costs a full CI run, not zero.

The "CI gate" invariant (a task is not complete while any `gh pr checks` entry is
failing, pending, or incomplete) therefore applies to `develop` PRs as well.

## Enforcement Layers

| Layer | Mechanism | Scope |
|-------|-----------|-------|
| Pre-push hook | `hooks/pre-push` | Blocks direct push to `main`/`develop` |
| PreToolUse hook | `pr-target-guard` | Blocks `gh pr create --base main` (unless `--head develop`) |
| GitHub Actions | `validate-pr-target.yml` | Auto-closes non-develop PRs targeting `main` |
| Release skill | integrity check | Warns if `main` diverged from `develop` before release |
