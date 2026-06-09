---
title: "ci(memory): GitHub Actions runs validation on every push"
labels:
  - type/ci
  - priority/medium
  - area/memory
  - size/S
  - phase/C-bootstrap
milestone: memory-sync-v1-bootstrap
blocked_by: [C3]
blocks: [D1, D2, D3]
parent_epic: EPIC
---

## What

Add `.github/workflows/memory-validation.yml` to claude-memory repo. The workflow re-runs `validate.sh` + `secret-check.sh` on full memory tree, runs `regen-index.sh --check`, runs `injection-check.sh` (warn-only), and runs the test suite from #A5. Runs on every push and PR. Fails the check on any blocking violation.

### Scope (in)

- Single workflow file `memory-validation.yml`
- Triggers: push to main, pull_request to any branch
- Jobs: validate, test, drift-check
- Runs on `ubuntu-latest` (Linux bash 5.x) AND `macos-latest` (bash 3.2 — important compat target)
- Status badge in claude-memory README
- Branch protection rule: status check required to merge

### Scope (out)

- Deployment / release automation
- Cross-repo workflows
- Secret scanning beyond what `secret-check.sh` covers (GitHub native secret-scanning runs separately)

## Why

The pre-commit hook (#C3) is bypassable with `--no-verify`. Server-side CI is the **non-bypassable** gate. Without it, an adventurous commit (or a forgotten hook installation on a new machine) could land unvalidated content.

Running on both Ubuntu and macOS catches platform-specific bash regressions immediately — the project commits to bash 3.2 compatibility (#A1 spec) and Linux-only CI would let macOS-only bugs slip through.

### What this unblocks

- #D1 — sync engine pulls from a repo where every commit is server-validated
- General trust in remote: any clone reflects content that passed validation

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: ½ day
- **Target close**: within 3 days of #C3 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-memory/.github/workflows/memory-validation.yml`
- **README badge update**: `kcenon/claude-memory/README.md`
- **Branch protection**: `kcenon/claude-memory` settings

## How

### Approach

Idiomatic GitHub Actions workflow with matrix on OS. Each job sets up bash, runs the validators against the entire `memories/` and `quarantine/` tree, and runs the test runner from #A5. Failure on any blocking violation. Branch protection updated to require the workflow's checks before merge.

### Detailed Design

**`.github/workflows/memory-validation.yml`**:
```yaml
name: Memory validation

on:
  push:
    branches: [main]
  pull_request:

jobs:
  validate:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Show bash version
        run: bash --version
      - name: Run validate.sh
        run: ./scripts/validate.sh --all memories/
      - name: Run secret-check.sh
        run: ./scripts/secret-check.sh --all memories/
      - name: Run injection-check.sh (warn only)
        run: |
          ./scripts/injection-check.sh --all memories/ || \
            echo "::warning::injection-check.sh reported flags (non-blocking)"

  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check MEMORY.md index drift
        run: ./scripts/regen-index.sh --check

  tests:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Run test suite
        run: ./tests/run-validation-tests.sh
```

**Branch protection update** (after workflow lands and runs once):
```
gh api repos/kcenon/claude-memory/branches/main/protection \
  --method PUT \
  -f required_status_checks.strict=true \
  -F required_status_checks.contexts[]="validate (ubuntu-latest)" \
  -F required_status_checks.contexts[]="validate (macos-latest)" \
  -F required_status_checks.contexts[]="drift-check" \
  -F required_status_checks.contexts[]="tests (ubuntu-latest)" \
  -F required_status_checks.contexts[]="tests (macos-latest)"
```

**README badge**:
```markdown
![memory validation](https://github.com/kcenon/claude-memory/actions/workflows/memory-validation.yml/badge.svg)
```

**Performance budget**:
- Each job target: < 2 minutes wall time
- Total workflow: < 5 minutes (parallel jobs)
- Free runner minutes consumed per push: ~10 minutes (5 jobs × 2 min)

**State and side effects**:
- No artifacts produced (read-only validation)
- Status check posts to PR / commit
- No deployment

**External dependencies**: GitHub Actions runner with bash, git, standard POSIX tools.

### Inputs and Outputs

**Input**: a push or PR to claude-memory.

**Output** (success):
- All 5 jobs (validate ubuntu, validate macos, drift-check, tests ubuntu, tests macos) green
- PR mergeable
- Status badge on README shows green

**Output** (failure on secret detection):
```
Run ./scripts/secret-check.sh --all memories/
memories/feedback_leak.md                          SECRET-DETECTED
    [!] non-owner email: leaker@example.com
Summary: 16 clean, 1 with findings
Error: Process completed with exit code 1.
```
- That job fails; status check red; PR cannot merge

**Output** (failure on drift):
```
Run ./scripts/regen-index.sh --check
[DRIFT] MEMORY.md is out of date
--- a/MEMORY.md
+++ b/MEMORY.md
...
Error: Process completed with exit code 1.
```

### Edge Cases

- **macOS runner using updated bash 5.x** (Apple silicon brew bash) → workflow may exercise bash 5 only on both jobs; document and pin if this happens. Workaround: explicit `/bin/bash --version` step + skip if not 3.2 (only as a guard, not a block)
- **Workflow fails on first commit** because validators not yet present — chicken/egg → #C3 lands first; this issue assumes scripts are in repo
- **Repo cloned via `actions/checkout@v4` without `lfs` or submodules** → memory files are plain markdown; no LFS needed
- **Push from a fork** → workflow runs but secrets unavailable; not relevant for single-user private repo, but spelled out
- **Status check name changes after workflow rename** → branch protection requires the exact context name; pin via `name:` in job
- **Concurrent PRs from different branches** → independent workflow runs; no conflict
- **Workflow file syntax error** → workflow doesn't run; status check absent; merge possible if branch protection only requires "required" status checks present (not the workflow file itself); mitigate by having a "lint workflow yaml" step that fails on syntax issue
- **GH Actions outage** → status check pending indefinitely; documented as known temporary risk; user can manually merge with admin override (only if `enforce_admins=false`, which contradicts #C4) — accept short-term mismatch and wait

### Acceptance Criteria

- [ ] `.github/workflows/memory-validation.yml` committed
- [ ] Triggers: push to main, pull_request
- [ ] Matrix on `ubuntu-latest` and `macos-latest`
- [ ] Job `validate` runs `validate.sh`, `secret-check.sh`, `injection-check.sh` (last is warn-only)
- [ ] Job `drift-check` runs `regen-index.sh --check`
- [ ] Job `tests` runs `tests/run-validation-tests.sh`
- [ ] Each job under 2 minutes typical
- [ ] Branch protection on `main` requires all 5 status check contexts to pass
- [ ] Status badge added to claude-memory README
- [ ] Workflow file passes its own lint (e.g., actionlint) — optional but documented
- [ ] On a manually crafted bad push (synthetic secret in fixture), the workflow correctly fails

### Test Plan

- Push a clean commit → all jobs green
- Push a commit introducing a synthetic secret → `validate` job fails, status check red, merge blocked
- Push a commit with index drift → `drift-check` job fails
- Modify a validator and break it → `tests` job fails
- Verify badge on README updates to red on failure
- macOS and Linux jobs both run (matrix expansion verified in Actions UI)

### Implementation Notes

- `actions/checkout@v4` is current standard; pin major to allow patch updates
- For determinism, use named workflow contexts that don't change between runs
- `::warning::` annotation is the GH Actions way to surface a non-blocking note in PR UI; useful for `injection-check.sh` flags
- Avoid `actions/cache` for now — workflow is fast enough without
- Pin actions to major version (`@v4`) not SHA — convenience over supply-chain paranoia for a private personal repo
- After first successful run on main, immediately update branch protection; status checks must exist before they can be required
- Workflow file lives in `.github/workflows/`; do not nest under `scripts/`

### Deliverable

- `.github/workflows/memory-validation.yml`
- Updated `README.md` with badge
- Branch protection updated to require status checks
- PR linked to this issue

### Breaking Changes

After this issue lands, PRs cannot merge until workflow passes. In-flight PRs may need rebase + re-run.

### Rollback Plan

- Remove workflow file or disable workflow in GitHub UI
- Update branch protection to remove status check requirements
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C3
- Blocks: #D1
- Related: #A5 (test runner consumed here), #C4 (companion enforcement)

**Docs**:
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1)

**Commits/PRs**: (filled at PR time)
