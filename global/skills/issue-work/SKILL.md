---
name: issue-work
description: Automate GitHub issue workflow - select issue, create branch, implement, build, test, and create PR.
argument-hint: "[project-name] [issue-number] [--solo|--team] [--limit N] [--dry-run]"
user-invocable: true
---

# Issue Work Command

Automate GitHub issue workflow with project name as argument.

## Usage

```
/issue-work                                       # Batch: all repos, all open issues
/issue-work vi_slam                               # Batch: all open issues in vi_slam
/issue-work vi_slam 21                            # Single: work on issue #21
/issue-work vi_slam 21 --org mycompany           # Explicit organization
/issue-work mycompany/vi_slam 21                 # Full repo path format
/issue-work vi_slam 21 --solo                    # Force solo mode (sequential)
/issue-work vi_slam 21 --team                    # Force team mode (implementer + tester)
/issue-work --org mycompany                      # Batch: all repos in org
/issue-work vi_slam --limit 5                    # Batch: top 5 priority issues
/issue-work vi_slam --dry-run                    # Preview batch plan only
```

## Arguments

- `[project-name]`: Project name or full repository path (optional)
  - Format 1: `<project-name>` - auto-detect organization from git remote
  - Format 2: `<project-name> --org <organization>` - explicit organization
  - Format 3: `<organization>/<project-name>` - full repository path
  - If omitted: **Batch mode** — discover all user repos and process all open issues

- `[issue-number]`: GitHub issue number (optional)
  - If provided: Work on the specified issue (single-item mode)
  - If omitted with project: **Batch mode** — process all open issues in the project
  - If omitted without project: **Batch mode** — process all open issues across all repos

- `[--solo|--team]`: Execution mode override (optional)
  - `--solo` — Force solo mode for all items (single agent, sequential workflow)
  - `--team` — Force team mode for all items (implementer + tester agents in parallel)
  - If omitted in single-item mode: auto-recommend based on issue size, then ask user
  - If omitted in batch mode: auto-decide per item using weighted scoring (no per-item prompt)

- `[--limit N]`: Maximum number of items to process in batch mode (default: 20, max: 50)

- `[--dry-run]`: Show batch plan only, do not execute

- `[--priority <level>]`: Filter batch to this priority level and above
  - Levels: `critical`, `high`, `medium`, `low`, `all` (default: `all`)

## Argument Parsing

Parse `$ARGUMENTS` and extract project, organization, issue number, and batch flags:

```bash
ARGS="$ARGUMENTS"
ISSUE_NUMBER="" PROJECT="" ORG="" EXEC_MODE=""
BATCH_MODE="single"  BATCH_LIMIT=20  DRY_RUN=false  PRIORITY_FILTER="all"

# Extract flags
if [[ "$ARGS" == *"--solo"* ]]; then EXEC_MODE="solo"; ARGS=$(echo "$ARGS" | sed 's/--solo//g'); fi
if [[ "$ARGS" == *"--team"* ]]; then EXEC_MODE="team"; ARGS=$(echo "$ARGS" | sed 's/--team//g'); fi
if [[ "$ARGS" == *"--dry-run"* ]]; then DRY_RUN=true; ARGS=$(echo "$ARGS" | sed 's/--dry-run//g'); fi
if [[ "$ARGS" =~ --limit[[:space:]]+([0-9]+) ]]; then BATCH_LIMIT="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--limit[[:space:]]+[0-9]+//g'); fi
if [[ "$ARGS" =~ --priority[[:space:]]+(critical|high|medium|low|all) ]]; then PRIORITY_FILTER="${BASH_REMATCH[1]}"; ARGS=$(echo "$ARGS" | sed -E 's/--priority[[:space:]]+\w+//g'); fi

# Extract issue number if present (numeric argument)
if [[ "$ARGS" =~ [[:space:]]([0-9]+)([[:space:]]|$) ]]; then
    ISSUE_NUMBER="${BASH_REMATCH[1]}"
    ARGS=$(echo "$ARGS" | sed -E "s/[[:space:]]+${ISSUE_NUMBER}([[:space:]]|$)/ /g")
fi
ARGS=$(echo "$ARGS" | xargs)

# Helper: resolve ORG/PROJECT from remaining ARGS
resolve_org_project() {
    if [[ "$ARGS" == *"--org"* ]]; then
        PROJECT=$(echo "$ARGS" | awk '{print $1}')
        ORG=$(echo "$ARGS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
    elif [[ "$ARGS" == *"/"* ]]; then
        ORG=$(echo "$ARGS" | cut -d'/' -f1 | xargs)
        PROJECT=$(echo "$ARGS" | cut -d'/' -f2 | xargs)
    else
        PROJECT="$ARGS"
        cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
        ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    fi
}

# Determine batch mode and resolve org/project
if [[ -z "$ARGS" && -z "$ISSUE_NUMBER" ]]; then
    BATCH_MODE="cross-repo"
    if [[ "$ARGS" == *"--org"* ]]; then
        ORG=$(echo "$ARGS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
    fi
elif [[ -n "$ARGS" && -z "$ISSUE_NUMBER" ]]; then
    BATCH_MODE="single-repo"
    resolve_org_project
else
    BATCH_MODE="single"
    resolve_org_project
fi
```

- Repository: `https://github.com/$ORG/$PROJECT` (single/single-repo modes)
- Source path: `./$PROJECT`
- Issue Number: `$ISSUE_NUMBER` (empty for batch modes)
- Batch Mode: `$BATCH_MODE` (`single`, `single-repo`, or `cross-repo`)

## Instructions

### Mode Routing

- If `$BATCH_MODE == "single-repo"` or `$BATCH_MODE == "cross-repo"` → Execute **Batch Mode Instructions** below
- If `$BATCH_MODE == "single"` → Execute **Phase 0: Execution Mode Selection** (skip Batch Mode)

---

## Batch Mode Instructions

See `reference/batch-mode.md` for the complete batch mode workflow including discovery, priority sorting, plan approval, and sequential execution.

---

### Phase 0: Execution Mode Selection (Single-Item Mode)

Determine whether to run in Solo mode (single agent, sequential) or Team mode (implementer + tester agents in parallel).

#### 0-1. If `--solo` or `--team` flag was provided

Skip mode selection — use `$EXEC_MODE` directly.

#### 0-2. If no flag was provided (interactive selection)

First, fetch issue information for size estimation (after Issue Selection in Step 1):

```bash
ISSUE_INFO=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT \
  --json title,body,labels -q '{title: .title, body: .body, labels: [.labels[].name]}')
```

Auto-recommend based on issue size:

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Size label | `size/XS`, `size/S` | `size/M`, `size/L`, `size/XL` |
| Description length | < 500 chars | > 500 chars |
| Acceptance criteria | < 3 items | 4+ items |
| Subtask references | None | "Part of", checklist items |

Use `AskUserQuestion` to present the choice:

- **Question**: "Issue #$ISSUE_NUMBER — <title> (<estimated-size>). Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential execution by a single agent. Lower token cost. Best for XS-S issues."
- **Description for Team**: "3-team parallel: dev + reviewer + doc-writer with review feedback loop. Higher quality for M+ issues. ~2x token cost."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-3. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode Instructions** (Steps 1-12 below)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions** (after Solo Mode section)

---

## Solo Mode Instructions

Execute the following workflow for the specified project:

### 1. Issue Selection

**If issue number is provided:**

```bash
# Fetch specific issue
gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json number,title,state,labels

# Verify issue exists and is open
STATE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json state -q '.state')
if [[ "$STATE" != "OPEN" ]]; then
    echo "Error: Issue #$ISSUE_NUMBER is not open (state: $STATE)"
    exit 1
fi
```

**If issue number is NOT provided:**

```bash
# Auto-select by priority
gh issue list --repo $ORG/$PROJECT --label "priority/critical" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/high" --state open --limit 1
# If none found:
gh issue list --repo $ORG/$PROJECT --label "priority/medium" --state open --limit 1
```

Select the oldest (first created) issue from the results.

Store the selected issue number in `$ISSUE_NUMBER` variable.

### 2. Issue Size Evaluation

Analyze the issue and determine size:

| Size | Expected LOC | Action |
|------|--------------|--------|
| XS/S | < 200 | Proceed directly |
| M | 200-500 | Consider splitting into 2-3 sub-issues |
| L/XL | > 500 | **Must split** into sub-issues, work on first |

If splitting required:
- Create sub-issues with `Part of #ORIGINAL` reference
- Apply 5W1H template for each sub-issue
- Proceed with the first sub-issue

### 3. Git Environment Setup

```bash
cd $PROJECT
git fetch origin
git checkout main && git pull origin main

# Extract issue title for branch name
ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json title -q '.title')
# Convert to kebab-case (lowercase, replace spaces with hyphens)
SHORT_DESC=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g' | cut -c1-50)

# Determine branch type from issue labels
LABELS=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json labels -q '.labels[].name')
if echo "$LABELS" | grep -q "type/feature"; then
    BRANCH_TYPE="feat"
elif echo "$LABELS" | grep -q "type/bug"; then
    BRANCH_TYPE="fix"
elif echo "$LABELS" | grep -q "type/refactor"; then
    BRANCH_TYPE="refactor"
elif echo "$LABELS" | grep -q "type/docs"; then
    BRANCH_TYPE="docs"
else
    BRANCH_TYPE="feat"  # Default
fi

BRANCH_NAME="${BRANCH_TYPE}/issue-${ISSUE_NUMBER}-${SHORT_DESC}"
git checkout -b "$BRANCH_NAME"
```

### 4. Issue Assignment

```bash
gh issue edit <NUMBER> --repo $ORG/$PROJECT --add-assignee @me
```

### 5. Code Implementation

**Priority**: Start implementation immediately. Minimize upfront planning — analyze code
as you implement, not in a separate planning phase.

1. **Analyze existing code style**:
   - Check `.clang-format`, `.editorconfig` if present
   - Review existing file patterns and conventions

2. **Implement changes**:
   - Follow existing code style strictly
   - Keep changes minimal and focused
   - **Validate incrementally**: Build/test after each logical change, not after all changes

3. **Header file review** (C/C++ projects):
   - Verify all used symbols have corresponding #include
   - Add missing headers

4. **Commit per logical unit**:
   - Format: `type(scope): description`
   - **Language: MANDATORY English only** - All commit messages MUST be written in English
   - **Forbidden**: Claude/AI references, emojis, Co-Authored-By

### 6. Build and Test Verification

Follow the build verification workflow rule (`build-verification.md`) to select the
appropriate strategy based on expected build duration.

#### Toolchain Availability Check

Before running local builds, verify required toolchains are installed:

```bash
# Check availability — do NOT install without asking the user
command -v go &>/dev/null    # Go
command -v cargo &>/dev/null # Rust
command -v cmake &>/dev/null # C++
command -v npm &>/dev/null   # Node.js
```

**If toolchain is unavailable**: Skip local build verification and rely on CI.
Do NOT attempt to install toolchains without asking the user first.
Report what was verified locally vs what needs CI.

#### Strategy Selection

| Build System | Typical Duration | Strategy |
|-------------|-----------------|----------|
| `go build` / `cargo check` | < 30s | Inline (synchronous) |
| `cmake --build` / `gradle build` | 30s - 5min | Background + log polling |
| `ctest` / `pytest` (large suites) | 1 - 10min | Background + log polling |
| CI pipeline (`gh workflow run`) | 5min+ | CI log check |

#### Inline Strategy (short builds)

For builds expected under 30 seconds:

```
Bash(command="go build ./...", timeout=60000)
Bash(command="cargo check", timeout=60000)
```

#### Background + Log Polling Strategy (long builds)

For builds expected over 30 seconds:

1. Launch in background: `Bash(command="cmake --build build/ ...", run_in_background=true)`
2. Poll output every 10-15s: `TaskOutput(task_id="<id>", block=false, timeout=10000)`
3. Detect outcome: `Built target`/`Finished` = success, `error:`/`FAILED` = fix needed
4. Run tests with same pattern: `Bash(command="ctest --test-dir build/ ...", run_in_background=true)`

#### On Build/Test Failure

1. Read the error output from build logs
2. Categorize failure (compile error, linker error, test assertion, missing dependency)
3. Apply fix based on error pattern
4. Re-run build/test to verify fix
5. If persistent failure: create draft PR with failure log (see Error Handling)

Do NOT retry the same build without changes -- diagnose first.

### 7. Documentation Update

Update relevant documentation if applicable:
- README.md
- CHANGELOG.md
- API documentation
- Code comments for complex logic

Commit separately:
```
docs(scope): update documentation for <feature>
```

### 8. Push and Create PR

```bash
git push -u origin "$BRANCH_NAME"

gh pr create --repo $ORG/$PROJECT \
  --title "${BRANCH_TYPE}(scope): description" \
  --body "Closes #${ISSUE_NUMBER}

## Summary
- Brief description of changes

## Test Plan
- How to verify the changes"
```

**Required**:
- `Closes #<NUMBER>` keyword to link issue
- **Language: MANDATORY English only** - All PR titles and descriptions MUST be written in English
- No Claude/AI references, emojis, or Co-Authored-By (see `commit-settings.md`)

After PR creation, capture the PR URL from `gh pr create` output for the summary.

### 9. Monitor CI

After PR creation, monitor CI with non-blocking polling:

```bash
# Wait briefly for workflows to register
sleep 8
```

Poll **all** PR checks every 30 seconds, max 10 minutes:

```bash
gh run list --repo $ORG/$PROJECT --branch "$BRANCH_NAME" \
  --json databaseId,name,status,conclusion
```

**Decision table — apply per run, evaluate ALL runs each poll cycle:**

| All runs status | Any conclusion=failure | Action |
|-----------------|----------------------|--------|
| All `completed` | No | All pass → proceed to merge |
| All `completed` | Yes | Diagnose, fix, push, re-poll |
| Any `in_progress` or `queued` | — | Poll again after 30s |

**Merge gate**: Do NOT merge until every run shows `status: completed`.
A run that is `in_progress` or `queued` is NOT a passing run — wait for it.

**Timeout**: If 10-minute polling limit is reached and any run is still
`in_progress` or `queued`, stop polling, report the current status table
to the user, and **do NOT merge**. Ask the user whether to wait longer
or leave the PR open for manual merge.

**Do NOT** use `gh run watch` — it blocks the entire session.

On CI failure, fix the issue and push. Repeat up to 3 attempts. After 3 failures,
convert the PR to draft, report the status, and **do NOT proceed to merge or produce a completion summary**. The task is NOT complete until all CI checks pass and the PR is merged.

### 10. Squash Merge

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

If merge fails (e.g., review required), report the status and skip merge.

### 11. Close Related Issues and Epics

After merge:

```bash
# Verify the linked issue was closed by the merge
STATE=$(gh issue view $ISSUE_NUMBER --repo $ORG/$PROJECT --json state -q '.state')
if [[ "$STATE" != "CLOSED" ]]; then
    gh issue close $ISSUE_NUMBER --repo $ORG/$PROJECT
fi
```

**Epic closure**: If the issue references a parent epic (e.g., `Part of #N`),
check if all sub-issues of that epic are now closed. If so, close the epic
with a summary comment.

### 12. Update Original Issue

**IMPORTANT**: All issue comments **MUST** be written in **English only**, regardless of the project's primary language or user's locale.

```bash
gh issue comment <NUMBER> --repo $ORG/$PROJECT \
  --body "Implementation PR: #<PR_NUMBER>"
```

---

## Team Mode Instructions

See `reference/team-mode.md` for the complete team mode workflow with 3-team architecture (dev, reviewer, doc-writer), feedback loops, and cleanup.

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | **All issue comments, PR titles, PR descriptions, and commit messages MUST be written in English only** |
| Issue linking | `Closes #NUM` required in PR |
| Build verification | Must pass before PR creation |

## Output

**CRITICAL**: Do NOT produce a completion summary if CI has any failing, pending, or incomplete checks. A task is only complete when the PR is merged with all CI checks passing.

After successful merge, provide summary:

```markdown
## Work Summary

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #$ISSUE_NUMBER - Title |
| Branch | $BRANCH_NAME |
| Execution mode | Solo / Team |
| PR | [#PR_NUMBER](https://github.com/$ORG/$PROJECT/pull/PR_NUMBER) |
| CI Status | All checks passed |
| Merged | Yes |
| Commits | N commits |

### Changes Made
- List of changes

### Files Modified
- file1.cpp
- file2.h

### Next Steps
- Any follow-up items
```

If CI failed or the PR was not merged, use this format instead:

```markdown
## Work Summary (INCOMPLETE)

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #$ISSUE_NUMBER - Title |
| Branch | $BRANCH_NAME |
| PR | [#PR_NUMBER](https://github.com/$ORG/$PROJECT/pull/PR_NUMBER) |
| CI Status | FAILING — [list failed checks] |
| Merged | No |
| Reason | [CI failure / Max retries exceeded / Timeout] |

### Action Required
- User must resolve CI failures before merge
```

**IMPORTANT**: Always include the full PR URL in the output (e.g., `https://github.com/org/repo/pull/123`).

### Batch Mode Output

In batch mode, use the summary format from **Phase B-5** instead. Include per-item results and the overall success/failure count.

## Error Handling

See `reference/error-handling.md` for prerequisite checks, runtime errors, and batch mode errors.
