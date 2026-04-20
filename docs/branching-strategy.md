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

3. **Merge via squash merge** after review. Note: CI does not run on develop-targeting PRs (see [CI/CD Policy](#cicd-policy)).

4. **Request review** if required by your team's policy.

5. **Squash merge** the PR once approved and CI is green.

### After Merge

- The feature branch is deleted (manually or via GitHub auto-delete).
- Use `/branch-cleanup` to remove stale local branches.

## Release Workflow

### Creating a Release

1. **Open a pull request** from `develop` into `main`.

2. **Review the changelog** — use `/release` to generate it automatically from commit history.

3. **Merge into `main`** via squash merge after CI passes.

4. **Tag the release** on `main`:

   ```bash
   git checkout main
   git pull origin main
   git tag -a v1.8.0 -m "v1.8.0"
   git push origin v1.8.0
   ```

5. **Create a GitHub Release** from the tag.

6. **Recreate `develop` from `main`** to synchronize histories.

   **Automated path (preferred).** The `post-release-develop-reset` workflow
   (`.github/workflows/post-release-develop-reset.yml`) runs on every push to
   `main` and performs the reset server-side. No manual action required when
   the release PR is squash-merged through the normal flow.

   **Manual path (fallback).** When the workflow is disabled, failed, or you
   need to reset develop outside the release flow, run:

   ```bash
   MAIN_SHA=$(gh api repos/$ORG/$PROJECT/git/ref/heads/main --jq .object.sha)

   # 1. Delete develop on the server.
   gh api -X DELETE repos/$ORG/$PROJECT/git/refs/heads/develop

   # 2. Recreate develop at main's HEAD via the REST API. Using gh api
   #    instead of `git push origin develop` avoids the local pre-push hook
   #    that blocks pushes to protected branches — branch protection is
   #    still applied to the new ref by GitHub.
   gh api -X POST repos/$ORG/$PROJECT/git/refs \
     -f ref=refs/heads/develop \
     -f sha="$MAIN_SHA"
   ```

> **Prerequisites.** The following repository settings are required for either
> path to succeed:
>
> - `default_branch = main`. GitHub refuses to delete whichever branch is set
>   as the repository default, so `main` must own that role. `develop` remains
>   the working/integration branch but is not the repository default.
> - `develop.allow_deletions = true` on branch protection. `allow_force_pushes`
>   can remain `false` — recreation creates a fresh ref, it does not rewrite
>   develop's history.
>
> **Interaction with `delete_branch_on_merge`.** The repository setting
> `delete_branch_on_merge = true` causes GitHub to auto-delete the head branch
> of every merged PR, including `develop` when a release PR merges into main.
> The automated workflow is idempotent: when it fires on the release push,
> develop is typically already gone and the workflow simply creates it fresh
> at main's SHA. The manual fallback behaves the same — if step 1's delete
> returns 422 ("Reference does not exist"), proceed to step 2 directly.
>
> **Why recreate develop?** Squash merging develop → main produces a single commit on
> `main` with a different SHA than the original commits on `develop`. This causes the
> two branches to diverge in git history, making subsequent develop → main PRs show
> conflicts on already-merged content. Deleting and recreating `develop` from `main`
> after each release keeps the histories aligned.

## CI/CD Policy

| Event | CI Triggered? |
|-------|---------------|
| Pull request to `main` | Yes — full validation (skills, hooks, shellcheck) |
| Pull request to `develop` | No — code review only |
| Push to any branch | No |
| Tag push (`v*`) | No (releases are created manually) |

Both workflows use **path filters** — they only trigger when relevant files change:
- `validate-skills.yml`: triggers on changes to `global/skills/**`, `project/.claude/skills/**`, `plugin/skills/**`
- `validate-hooks.yml`: triggers on changes to `global/hooks/**`, `tests/hooks/**`

### CI Checks

| Workflow | What It Validates | Path Filter |
|----------|-------------------|-------------|
| `validate-skills.yml` | SKILL.md frontmatter format, name, description length | `**/skills/**` |
| `validate-hooks.yml` | Hook script correctness (test suite + shellcheck) | `global/hooks/**`, `tests/hooks/**` |

### Merge Rules

**Release PRs (develop → main):**
- All triggered CI checks must pass before merging.
- **Squash merge** is the only allowed merge strategy.
- **Never merge** while any check is `queued` or `in_progress`.
- CI failures must be investigated — do not dismiss failures as flaky or unrelated.

**Feature PRs (feature → develop):**
- CI does not run. Code review is the quality gate.
- **Squash merge** is the only allowed merge strategy.

### Branch Protection Configuration

| Setting | `main` | `develop` |
|---------|--------|-----------|
| PR required | Yes | Yes |
| Required status checks | None (path-filtered CI runs when triggered) | None |
| Enforce admins | Yes | Yes |
| Force pushes | Blocked | Blocked |
| Branch deletion | Blocked | Blocked |
| Merge method | Squash only | Squash only |

> **Note**: Required status checks are not enforced at the branch protection level because
> path-filtered CI workflows do not trigger on every PR. When a workflow doesn't trigger,
> its required check would remain pending indefinitely, blocking all merges. Instead, CI
> runs as advisory checks — they execute when path filters match and block merge only when
> they fail.

## Enforcement Layers

| Layer | Type | Scope |
|-------|------|-------|
| GitHub branch protection | Server-side | Blocks direct push to `main` and `develop` |
| `pre-push` git hook | Client-side | Blocks direct push to `main` and `develop` locally |
| Squash merge only | Server-side | Only squash merge allowed in GitHub settings |
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
