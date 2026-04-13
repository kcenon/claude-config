# Branching Strategy

This document describes the branching model, daily workflow, release process, and CI/CD policies for this repository.

## Overview

This repository uses a **simplified git-flow** model with two long-lived branches and short-lived feature branches. All changes reach `main` through pull requests — direct pushes to protected branches are blocked by git hooks.

## Branch Model

```
main ← develop ← feature/*
  │        │
  │        ├── docs/issue-42-add-readme
  │        ├── feat/issue-50-new-skill
  │        └── fix/issue-55-hook-crash
  │
  └── (releases tagged from main)
```

| Branch | Purpose | Protection |
|--------|---------|------------|
| `main` | Stable, release-ready code | Protected — no direct push, PR required |
| `develop` | Integration branch for ongoing work | Protected — no direct push, PR required |
| `feature/*` | Short-lived branches for individual changes | None — deleted after merge |

## Daily Workflow

### Starting Work

1. **Create a feature branch from `develop`:**

   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feat/issue-123-description
   ```

2. **Branch naming convention:**

   ```
   <type>/issue-<number>-<short-description>
   ```

   Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### Submitting Work

1. **Push to your feature branch:**

   ```bash
   git push origin feat/issue-123-description
   ```

2. **Open a pull request** targeting `develop`.

3. **Wait for CI checks** to pass. All checks must reach `completed` status before merge.

4. **Request review** if required by your team's policy.

5. **Squash merge** the PR once approved and CI is green.

### After Merge

- The feature branch is deleted (manually or via GitHub auto-delete).
- Use `/branch-cleanup` to remove stale local branches.

## Release Workflow

### Creating a Release

1. **Open a pull request** from `develop` into `main`.

2. **Review the changelog** — use `/release` to generate it automatically from commit history.

3. **Merge into `main`** after CI passes.

4. **Tag the release** on `main`:

   ```bash
   git checkout main
   git pull origin main
   git tag -a v1.8.0 -m "v1.8.0"
   git push origin v1.8.0
   ```

5. **Create a GitHub Release** from the tag.

## CI/CD Policy

| Event | CI Triggered? |
|-------|---------------|
| Pull request to `main` | Yes — full validation (skills, hooks, shellcheck) |
| Pull request to `develop` | Yes — same checks as `main` |
| Push to feature branch | No |
| Tag push (`v*`) | No (releases are created manually) |

### CI Checks

| Workflow | What It Validates |
|----------|-------------------|
| `validate-skills.yml` | SKILL.md frontmatter format, name, description length |
| `validate-hooks.yml` | Hook script correctness (test suite + shellcheck) |

### Merge Rules

- **All CI checks must pass** before merging. No exceptions.
- **Squash merge** is the preferred merge strategy to keep history clean.
- **Never merge** while any check is `queued` or `in_progress`.
- **CI failures must be investigated** — do not dismiss failures as flaky or unrelated.

## Enforcement Layers

| Layer | Type | Scope |
|-------|------|-------|
| GitHub branch protection | Server-side | Blocks direct push to `main` and `develop` |
| `pre-push` git hook | Client-side | Blocks direct push to `main` and `develop` locally |
| Squash merge policy | Convention | Enforced by team practice and PR review |
| Auto-delete branches | Server-side | Cleans up feature branches after PR merge |

## FAQ

### What about hotfixes?

Create a hotfix branch from `main`, fix the issue, and open a PR directly to `main`. After merging, merge `main` back into `develop` to keep branches in sync.

```bash
git checkout main
git pull origin main
git checkout -b fix/issue-99-critical-bug
# ... fix and push ...
# Open PR to main, merge, then sync:
git checkout develop
git merge main
git push origin develop
```

### What if CI fails on a release PR?

Fix the issue on `develop` first, then update the release PR. Never bypass failing CI checks to merge a release. If the failure is in a test, fix the test or the code — do not increase timeouts or skip tests without understanding the root cause.
