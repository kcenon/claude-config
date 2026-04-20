---
name: pr-work
description: "Analyze and fix failed CI/CD workflows for a pull request. Use when CI checks fail, GitHub Actions show red, build/test/lint errors block a PR, or the user says 'fix CI', 'fix the build', 'PR is failing', or 'check failed'. Supports solo, team, and batch modes with automated retry and escalation."
argument-hint: "[project-name] [pr-number] [--solo|--team] [--limit N] [--dry-run] [--inline] [--reanchor-interval N]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Bash(gh *)"
max_iterations: 5
halt_condition: "All PR checks pass, OR user aborts, OR 3 identical CI failures in a row"
on_halt: "Report failing checks with gh pr checks output, do not merge"
loop_safe: false
---

# PR Work Command

Analyze and fix failed CI/CD workflows for a pull request.

## Usage

```
/pr-work                                            # Batch: all repos, all failing PRs
/pr-work <project-name>                             # Batch: all failing PRs in project
/pr-work <pr-number>                                # Single: fix PR in current project
/pr-work <project-name> <pr-number>                 # Single: fix specific PR
/pr-work <organization>/<project-name> <pr-number>
```

**Examples**:
```
/pr-work                                            # Batch: all repos, all PRs with failed CI
/pr-work hospital_erp_system                        # Batch: all failing PRs in project
/pr-work 42                                         # Single: fix PR #42 (auto-detect repo)
/pr-work hospital_erp_system 42                     # Single: fix PR #42 in project
/pr-work hospital_erp_system 42 --org mycompany     # Explicit org
/pr-work mycompany/hospital_erp_system 42           # Full path format
/pr-work 42 --solo                                  # Force solo mode (sequential)
/pr-work 42 --team                                  # Force team mode (diagnoser + fixer)
/pr-work --org mycompany                            # Batch: all repos in org
/pr-work hospital_erp_system --limit 5              # Batch: top 5 failing PRs
/pr-work hospital_erp_system --dry-run              # Preview batch plan only
/pr-work hospital_erp_system --inline               # Batch: process items in the parent context (legacy)
```

## Arguments

- `[project-name]`: Project name or full repository path (optional)
  - If omitted with PR number: auto-detect from current directory git remote
  - If omitted without PR number: **Batch mode** — discover all repos, process all failing PRs

- `[pr-number]`: Pull request number (optional)
  - If provided: Work on the specified PR (single-item mode)
  - If omitted with project: **Batch mode** — process all failing PRs in the project
  - If omitted without project: **Batch mode** — process all failing PRs across all repos

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode for all items
  - `--team` — Force team mode for all items
  - If omitted in single-item mode: auto-recommend based on failure complexity, then ask user
  - If omitted in batch mode: auto-decide per item using weighted scoring (no per-item prompt)

- `[--limit N]`: Maximum number of items to process in batch mode (default: 5, max: 10)
  - Values above 10 require `--force-large` to acknowledge rule drift risk. Empirically, drift becomes visible around items 15-25 in long batches; the conservative default keeps batches inside the safe zone.

- `[--force-large]`: Allow `--limit > 10`. Required to bypass the safe-batch cap.

- `[--no-confirm]`: Skip the chunked confirmation gate fired every 5 items in batch mode. Intended for CI-driven or fully unattended batches; interactive sessions should leave it off so the gate can serve as both a user-control checkpoint and an attention refresh for accumulated context.

- `[--auto-restart]`: Force a session restart every `CONFIRM_INTERVAL` items instead of showing the interactive chunked gate. The batch writes `.claude/resume.md` using the Batch Workflow Resume Format and exits cleanly; a fresh `claude` session picks up the next PR from the resume file. Use for long unattended PR-fixing batches where a full process-level attention reset per chunk matters more than human confirmation. Ignored in single-item mode.

- `[--no-restart]`: Suppress the forced restart. When combined with `--auto-restart`, the batch falls back to the interactive chunked gate. Meaningful primarily as a defensive flag in scripts that want to guarantee no session exit even if `--auto-restart` is set elsewhere (aliases, wrappers, or a future default change).

- `[--dry-run]`: Show batch plan only, do not execute

- `[--inline]`: Process each batch item in the parent conversation context instead of delegating to a fresh subagent.
  - **Default (omitted)**: Each failing PR is handled by a fresh `general-purpose` Agent. The parent keeps only the queue state and a short per-item summary; CI log fetches, diff reads, and build outputs live inside the subagent and are discarded on completion. This is the preferred mode for batches >3 items because rule compliance at item 30 looks like item 1.
  - **With `--inline`**: The parent executes Solo/Team workflow directly for every item. Lower token overhead (~10-15% savings) but accumulated CI log noise drives rule drift around items 15-25. Use for tiny batches (≤3 items) or when several PRs share a root cause and you want cross-item context.
  - Ignored in single-item mode.

- `[--org <organization>]`: Scope to a specific GitHub organization

**Auto-checkout**: In single-item mode, the command automatically detects and checks out the PR's branch.

## Argument Parsing

Parse `$ARGUMENTS` and determine organization, PR number, and batch mode:

```bash
ARGS="$ARGUMENTS"
PR_NUMBER=""
PROJECT=""
ORG=""
EXEC_MODE=""
BATCH_MODE="single"   # single | single-repo | cross-repo
BATCH_LIMIT=5
MAX_LIMIT=10
CONFIRM_INTERVAL=5
DRY_RUN=false
FORCE_LARGE=false
NO_CONFIRM=false
INLINE_MODE=false
AUTO_RESTART=false
NO_RESTART=false

# Extract flags
ORIGINAL_ARGS="$ARGS"
if [[ "$ARGS" == *"--solo"* ]]; then EXEC_MODE="solo"; ARGS=$(echo "$ARGS" | sed 's/--solo//g'); fi
if [[ "$ARGS" == *"--team"* ]]; then EXEC_MODE="team"; ARGS=$(echo "$ARGS" | sed 's/--team//g'); fi
if [[ "$ARGS" == *"--dry-run"* ]]; then DRY_RUN=true; ARGS=$(echo "$ARGS" | sed 's/--dry-run//g'); fi
if [[ "$ARGS" == *"--force-large"* ]]; then FORCE_LARGE=true; ARGS=$(echo "$ARGS" | sed 's/--force-large//g'); fi
if [[ "$ARGS" == *"--no-confirm"* ]]; then NO_CONFIRM=true; ARGS=$(echo "$ARGS" | sed 's/--no-confirm//g'); fi
if [[ "$ARGS" == *"--no-restart"* ]]; then NO_RESTART=true; ARGS=$(echo "$ARGS" | sed 's/--no-restart//g'); fi
if [[ "$ARGS" == *"--auto-restart"* ]]; then AUTO_RESTART=true; ARGS=$(echo "$ARGS" | sed 's/--auto-restart//g'); fi
if [[ "$ARGS" == *"--inline"* ]]; then INLINE_MODE=true; ARGS=$(echo "$ARGS" | sed 's/--inline//g'); fi
if [[ "$ARGS" =~ --limit[[:space:]]+([0-9]+) ]]; then BATCH_LIMIT="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--limit[[:space:]]+[0-9]+//g'); fi
if [[ "$ARGS" =~ --org[[:space:]]+([^[:space:]]+) ]]; then ORG="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--org[[:space:]]+[^[:space:]]+//g'); fi

# Hard cap on batch size to mitigate rule drift in long batches.
# Drift becomes empirically visible around items 15-25; default 5 keeps the
# operator inside the safe zone, and bypassing requires explicit acknowledgment.
if (( BATCH_LIMIT > MAX_LIMIT )) && [[ "$FORCE_LARGE" != "true" ]]; then
    echo "Error: --limit ${BATCH_LIMIT} exceeds safe cap of ${MAX_LIMIT}." >&2
    echo "Long batches risk rule drift around items 15-25." >&2
    echo "Either split the batch into smaller runs or pass --force-large to override." >&2
    exit 1
fi

# Trim remaining args
ARGS=$(echo "$ARGS" | xargs)

# Determine mode based on remaining args
if [[ -z "$ARGS" && -z "$ORG" ]]; then
    # No args at all → cross-repo batch
    BATCH_MODE="cross-repo"

elif [[ -z "$ARGS" && -n "$ORG" ]]; then
    # Only --org provided → cross-repo batch scoped to org
    BATCH_MODE="cross-repo"

elif [[ "$ARGS" =~ ^[0-9]+$ ]]; then
    # Single numeric arg → PR number in current project (unchanged behavior)
    BATCH_MODE="single"
    PR_NUMBER="$ARGS"
    REMOTE_URL=$(git remote get-url origin 2>/dev/null)
    ORG=$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    PROJECT=$(echo "$REMOTE_URL" | sed -E 's|.*[:/][^/]+/([^/]+)\.git$|\1|' | sed -E 's|.*[:/][^/]+/([^/]+)$|\1|')

elif [[ "$ARGS" =~ ^[a-zA-Z] ]] && ! [[ "$ARGS" =~ [[:space:]][0-9]+([[:space:]]|$) ]]; then
    # Project name only, no PR number → single-repo batch
    BATCH_MODE="single-repo"
    if [[ "$ARGS" == *"/"* ]]; then
        ORG=$(echo "$ARGS" | cut -d'/' -f1 | xargs)
        PROJECT=$(echo "$ARGS" | cut -d'/' -f2 | xargs)
    else
        PROJECT="$ARGS"
        if [[ -z "$ORG" ]]; then
            cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
            ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
        fi
    fi

else
    # Project + PR number → single-item mode (unchanged)
    BATCH_MODE="single"
    if [[ "$ARGS" == *"/"* ]]; then
        REPO_PATH=$(echo "$ARGS" | awk '{print $1}')
        ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
        PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
        PR_NUMBER=$(echo "$ARGS" | awk '{print $2}')
    else
        PROJECT=$(echo "$ARGS" | awk '{print $1}')
        PR_NUMBER=$(echo "$ARGS" | awk '{print $2}')
        if [[ -z "$ORG" ]]; then
            cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
            ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
        fi
    fi
fi
```

## Instructions

### Mode Routing

- If `$BATCH_MODE == "single-repo"` or `$BATCH_MODE == "cross-repo"` → Execute **Batch Mode Instructions** below
- If `$BATCH_MODE == "single"` → Execute **Phase 0: Execution Mode Selection** (skip Batch Mode)

---

## Batch Mode Instructions

See `reference/batch-mode.md` for the complete batch mode workflow including discovery, priority sorting, plan approval, and sequential execution.

**Batch-only behaviors** (do not apply in single-item mode):
- **Subagent delegation by default** (B-4): each failing PR is dispatched to a fresh `general-purpose` Agent so CI log fetches and file reads live inside the subagent and never reach the parent. The parent retains only `{pr_number, repo, status, ci_conclusion}` per item. Pass `--inline` to fall back to the legacy single-context loop.
- **Per-item rule reminder** (B-4.0): a 5-line invariant block is emitted as a fresh tool result before each PR so language/CI/attribution rules stay in the recent attention window. In delegated mode this reminder is embedded in the subagent prompt; in `--inline` mode it is emitted directly in the parent context.
- **No `@load: reference/...` inside the per-item loop**: keep the inline reminder as the most recent context anchor.
- **Chunked confirmation gate** (B-4.1): user confirmation prompt every 5 items, bypassable with `--no-confirm`. When `--auto-restart` is set (and `--no-restart` is not), the gate is replaced by a forced session restart that writes `.claude/resume.md` and exits; a fresh `claude` session resumes from the next PR.

---

### Phase 0: Execution Mode Selection (Single-Item Mode)

Determine whether to run in Solo mode (single agent, sequential) or Team mode (diagnoser + fixer agents in parallel).

#### 0-1. Gather Failure Information

```bash
FAILED_RUNS=$(gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --status failure --limit 10 --json databaseId,name -q 'length')
```

#### 0-2. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-3. If no flag was provided (interactive selection)

Auto-recommend based on failure complexity:

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Failed workflows | 1 | 2+ |
| Error categories | Single (build OR test OR lint) | Multiple (build AND test) |
| Previous fix attempts | 0 | 1+ (already tried, recurring) |

Use `AskUserQuestion` to present the choice:

- **Question**: "PR #$PR_NUMBER has $FAILED_RUNS failed workflow(s). Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential diagnosis and fix. Lower token cost. Best for single-category failures."
- **Description for Team**: "Parallel diagnoser + fixer. Diagnoser analyzes next failure while fixer resolves current one. Best for multi-category failures."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-4. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode Instructions** (Steps 1-11 below)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions** (after Solo Mode section)

---

## Solo Mode Instructions

### 1. PR Information Retrieval

```bash
# Get PR information including branch name
PR_INFO=$(gh pr view $PR_NUMBER --repo $ORG/$PROJECT --json title,state,headRefName,checks)

# Extract branch name from PR
HEAD_BRANCH=$(echo "$PR_INFO" | jq -r '.headRefName')

if [[ -z "$HEAD_BRANCH" ]]; then
    echo "Error: Cannot determine branch name for PR #$PR_NUMBER"
    exit 1
fi

echo "PR #$PR_NUMBER branch: $HEAD_BRANCH"
```

Identify:
- PR title and branch name
- Current PR state
- Failed checks/workflows

**Branch auto-detection**: The PR's branch name is automatically extracted from `headRefName`.

### 2. Failed Workflow Analysis

```bash
# List failed workflow runs for the PR
gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --status failure --limit 5

# Get detailed log for failed run
gh run view <RUN_ID> --repo $ORG/$PROJECT --log-failed
```

For each failed workflow:
1. Identify the failing job and step
2. Extract error messages
3. Determine root cause

### 3. Post Failure Analysis Comment

**MANDATORY**: Post a failure analysis comment to the PR after analysis, before attempting a fix. All comments must be in **English only**. Sanitize secrets, IPs, PII, and connection strings before posting.

> See `reference/comment-templates.md` for the full comment template, guidelines, and sensitive data handling rules.

### 4. Checkout PR Branch

**Auto-checkout**: The command automatically checks out the PR's branch.

```bash
# Navigate to project directory (if not already there)
if [[ ! -z "$PROJECT" && -d "$PROJECT" ]]; then
    cd "$PROJECT"
fi

# Fetch latest changes
git fetch origin

# Check if branch exists locally
if git show-ref --verify --quiet refs/heads/"$HEAD_BRANCH"; then
    # Branch exists locally, switch to it
    git checkout "$HEAD_BRANCH"
    git pull origin "$HEAD_BRANCH"
else
    # Branch doesn't exist locally, create and track
    git checkout -b "$HEAD_BRANCH" "origin/$HEAD_BRANCH"
fi

echo "Switched to PR branch: $HEAD_BRANCH"
```

**Branch handling**:
- If branch exists locally: checkout and pull latest changes
- If branch doesn't exist: create local branch tracking remote

### 5. Fix Issues

Based on workflow analysis, fix the identified issues:

| Failure Type | Common Fixes |
|--------------|--------------|
| **Build error** | Fix compilation errors, missing dependencies |
| **Test failure** | Fix failing tests or update test expectations |
| **Lint error** | Apply code formatting, fix style violations |
| **Type error** | Fix type mismatches, add missing types |
| **Missing header** | Add required #include statements |
| **Link error** | Fix undefined references, library linking |

**Known-pattern shortcut**: before hand-authoring a fix, check the `ci-fix` skill
(`global/skills/ci-fix/SKILL.md`). It classifies the failure log against three recurring
patterns (MSVC C4996, CMake FetchContent shallow clone, `__cpp_lib_format` probe) and applies
a codified remediation. Invoke with `/ci-fix <pr-number>` — falls through to this manual
workflow when no pattern matches.

### 6. Verify Fix Locally

Select inline (< 30s) or background + log polling (30s+) strategy based on build duration. Diagnose before retrying — do NOT re-run the same build without changes.

> See `reference/build-verification.md` for strategy selection table, inline/background execution patterns, and outcome detection.

### 7. Commit Fix

```bash
git add <fixed-files>
git commit -m "fix(<scope>): <description>

Fixes CI failure: <brief explanation>"
```

**Commit rules**:
- Type: Usually `fix`, `build`, `test`, or `ci`
- **Language: MANDATORY English only** - All commit messages MUST be written in English
- No Claude/AI references, emojis, or Co-Authored-By (see `commit-settings.md`)

### 8. Push and Verify

```bash
git push origin "$HEAD_BRANCH"
```

#### TLS/Sandbox Error Handling

See **Environment Workarounds** in `global/CLAUDE.md` for the canonical rule. `SSL_CERT_FILE` / `SSL_CERT_DIR` are wired in `global/settings.json` so `git` / `curl` succeed inside the sandbox; `gh` on macOS remains the exception and is handled via Bash allowlist. Never flag a TLS error as an authentication failure without verifying.

#### CI Monitoring

After push, monitor CI with non-blocking polling (30s intervals, 10min max). Do NOT use `gh run watch`. Do NOT merge while any check is `queued` or `in_progress`.

> See `reference/build-verification.md` for the full CI monitoring protocol, status interpretation table, and polling limits.

### 9. Iterate if Needed

If workflows still fail, repeat steps 2-8. Max 3 retry attempts with 30s CI polling intervals. Each fix is a separate commit. Post a follow-up failure analysis comment at the start of each iteration.

> See `reference/build-verification.md` for iteration limits, CI polling loop, and iteration rules.
> See `reference/comment-templates.md` for the per-attempt follow-up comment template.

### 10. Auto-Merge on Success

**ABSOLUTE CI GATE — MANDATORY PRE-MERGE VERIFICATION:**

Before executing `gh pr merge`, you MUST run `gh pr checks` and verify every single check:

```bash
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT
```

**Do NOT merge if ANY check shows:**
- `fail` or `failure` conclusion (regardless of perceived cause)
- `pending`, `queued`, or `in_progress` status
- `cancelled`, `timed_out`, or `startup_failure` conclusion

**ALL checks must show `pass` or `neutral` to proceed.** No exceptions. No rationalization.
Never judge a failure as "unrelated", "pre-existing", or "infrastructure-only" — all failures block merge.

If any check is not passing, STOP. Do NOT proceed to merge. Instead:
1. Report the full `gh pr checks` output to the user
2. Either fix the failure and re-poll, or let the user decide

Only when ALL checks pass:

```bash
gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash --delete-branch
```

If merge fails (e.g., review required, branch protection), report the status
and skip merge. Do not force-merge.

### 11. Failure Escalation

When max retry attempts (3) are exceeded: post summary comment to PR (English only), add `needs-manual-review` label, and report final status to user.

> See `reference/comment-templates.md` for the escalation comment template and decision matrix.

---

## Team Mode Instructions

See `reference/team-mode.md` for the complete team mode workflow including architecture, teammate spawning, feedback loops, and cleanup.

## Policies

See [_policy.md](../_policy.md) for common rules, including the **Atomic Multi-Phase Execution** rule — when the user specifies multiple phases (e.g., "Phase 1/2/3"), complete all phases without pausing between them for confirmation.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | **All PR comments and commit messages MUST be written in English only** |
| Max retry attempts | 3 before escalation |
| CI poll interval | >= 30 seconds (respect API rate limits) |
| CI max poll duration | 10 minutes per run (20 polls x 30s) |

## Output

**CRITICAL**: Do NOT produce a "Success" summary if CI has any failing, pending, or incomplete checks. A task is only successful when `gh pr checks` confirms ALL checks pass.

After successful merge, provide summary:

```markdown
## PR Fix Summary

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| PR | #$PR_NUMBER |
| Branch | $HEAD_BRANCH |
| Execution mode | Solo / Team |
| Attempts | X/3 |
| CI Status | All checks passed (`gh pr checks` verified) |
| Final Status | Success — Merged |

### Workflows Fixed
| Workflow | Status | Fix Applied |
|----------|--------|-------------|
| Build | Fixed | description |
| Test | Fixed | description |

### Commits Made
1. `fix(scope): description` - hash
2. `fix(scope): description` - hash
```

If CI failed or max retries exceeded, use this format instead:

```markdown
## PR Fix Summary (INCOMPLETE)

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| PR | #$PR_NUMBER |
| Branch | $HEAD_BRANCH |
| Attempts | X/3 |
| CI Status | FAILING — [list failed checks] |
| Final Status | Escalated — NOT merged |

### Escalation
- Escalation reason: [reason]
- PR comment added: Yes/No
- Label applied: needs-manual-review

### Action Required
- User must resolve CI failures before merge
```

## Reanchoring Loop Invariants

`--reanchor-interval N` (default 5, `0` disables) controls how often the Core invariants block from `global/skills/_shared/invariants.md` is emitted inside long loops.

Loop bind points for pr-work:
- **Batch mode**: between items, same semantics as `issue-work` batch-mode (every N items).
- **Single-PR CI polling**: every N poll cycles of the 30-second monitor loop, keeping the CI gate rules adjacent to the latest `gh pr checks` output.

## Error Handling

See `reference/error-handling.md` for prerequisite checks, runtime errors, batch mode errors, and common CI failure patterns.
