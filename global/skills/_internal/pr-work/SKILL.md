---
name: pr-work
description: "Analyze and fix failed CI/CD workflows for a pull request. Use when CI checks fail, GitHub Actions show red, build/test/lint errors block a PR, or the user says 'fix CI', 'fix the build', 'PR is failing', or 'check failed'. Supports solo, team, and batch modes with automated retry and escalation."
argument-hint: "[project-name] [pr-number] [--solo|--team] [--limit N] [--dry-run] [--inline] [--reanchor-interval N]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Bash(gh *)"
max_iterations: 5
halt_conditions:
  - { type: success, expr: "All PR checks pass" }
  - { type: user,    expr: "user aborts" }
  - { type: limit,   expr: "3 identical CI failures in a row" }
  - { type: limit,   expr: "sonar-fix exhausted max_iterations and Quality Gate still FAIL" }
on_halt: "Report failing checks with gh pr checks output, do not merge"
loop_safe: false
tiers:
  light:
    ref_docs: []
    deep_checks: false
  standard:
    ref_docs: [core]
    deep_checks: true
  deep:
    ref_docs: [core, advanced]
    deep_checks: true
default_tier: standard
iso_class: A
applies_at_or_above: A
# ref_docs keys:
#   core     -> reference/error-handling.md
#   advanced -> reference/batch-mode.md, reference/team-mode.md,
#               reference/build-verification.md, reference/comment-templates.md
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

## Phase 0a -- Regulated-track detection

After argument parsing, before any mode routing or PR work, detect whether the
consumer project is on the regulated-industry track. Set `$REGULATED_TRACK=true`
when the project root contains a `compliance/` directory (typically
`compliance/iec-62304.md`, `iso-13485.md`, `iso-14971.md`); set
`$REGULATED_TRACK=false` otherwise.

```bash
# Resolve the consumer-project root from the parsed PROJECT name (or current
# cwd when invoked via the skill alias from inside a project).
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
if [ -n "$PROJECT" ] && [ -d "$PROJECT_ROOT/$PROJECT" ]; then
    PROJECT_ROOT="$PROJECT_ROOT/$PROJECT"
fi

if [ -d "$PROJECT_ROOT/compliance" ]; then
    REGULATED_TRACK=true
else
    REGULATED_TRACK=false
fi
```

**Behavior matrix:**

| `$REGULATED_TRACK` | Effect on the rest of the skill |
|--------------------|---------------------------------|
| `false` (default)  | Skill proceeds exactly as documented in the existing phases below. Phase 5b and Phase 9b are skipped entirely. No behavior change relative to pre-#603 invocations. |
| `true`             | After the existing Phase 5 (push and `gh pr create`) the skill runs Phase 5b (traceability impact injection). Before the existing Phase 10 (`gh pr merge`) the skill runs Phase 9b (evidence-attachment gate). All other phases are unchanged. |

The detection is a single test on directory presence -- no parsing, no glob.
When `compliance/` is absent the skill is functionally identical to its
pre-#603 form; this is the most important functional invariant of this
extension. The two regulated phases (5b and 9b) gate on `$REGULATED_TRACK=true`
at every entry point and are no-ops otherwise.

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

**MANDATORY**: Post a failure analysis comment to the PR after analysis, before attempting a fix. Comment language must comply with the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`; default `english`). Sanitize secrets, IPs, PII, and connection strings before posting regardless of policy.

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
(`global/skills/_internal/ci-fix/SKILL.md`). It classifies the failure log against three recurring
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
- **Language**: Follow the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`; default `english`).
- No Claude/AI references, emojis, or Co-Authored-By regardless of policy (see `commit-settings.md`)

### 8. Push and Verify

```bash
git push origin "$HEAD_BRANCH"
```

#### TLS/Sandbox Error Handling

See **Environment Workarounds** in `global/CLAUDE.md` for the canonical rule. `SSL_CERT_FILE` / `SSL_CERT_DIR` are wired in `global/settings.json` so `git` / `curl` succeed inside the sandbox; `gh` on macOS remains the exception and is handled via Bash allowlist. Never flag a TLS error as an authentication failure without verifying.

#### CI Monitoring

After push, monitor CI with non-blocking polling (30s intervals, 10min max). Do NOT use `gh run watch`. Do NOT merge while any check is `queued` or `in_progress`.

> See `reference/build-verification.md` for the full CI monitoring protocol, status interpretation table, and polling limits.

### 5b. Traceability impact injection (regulated track only)

**Gate:** runs only when `$REGULATED_TRACK=true` (see Phase 0a). Skipped
entirely when the consumer project has no `compliance/` directory; non-regulated
projects see no behavior change from this extension.

After the push in Step 8 (and on every subsequent iteration that pushes new
commits), compute the traceability cascade impacted by the diff and inject a
`## Traceability Impact` section into the PR body. This surfaces, in narrative
form, the same information the `traceability-guard` PreToolUse hook (#590,
PR #593) checks silently. Reviewers see which downstream tests, risks, and
clauses are touched without leaving the PR conversation.

**Reuse rule (mandatory):** the cascade walk MUST source the shared library at
`hooks/lib/validate-traceability.sh`. Do NOT re-derive cascade-walk logic in
this skill body. The library is the single source of truth for cascade rules
and is already used by `traceability-guard` (PreToolUse) and `pre-push` (git
hook).

```bash
# Skip when the regulated track is off.
if [ "$REGULATED_TRACK" != "true" ]; then
    echo "pr-work: regulated track off -- Phase 5b skipped"
    return 0
fi

# Source the shared cascade library. The library exposes
# validate_traceability_range <base_ref> <head_ref> <repo_root>, but Phase 5b
# needs the per-edge listing rather than a pass/fail return code, so it
# additionally invokes the underlying graph_cascade_targets and
# extract_doc_ids_from_path helpers the library exports.
. "$PROJECT_ROOT/hooks/lib/validate-traceability.sh"

BASE_REF=$(gh pr view "$PR_NUMBER" --repo "$ORG/$PROJECT" --json baseRefName -q .baseRefName)
HEAD_REF="$HEAD_BRANCH"

# Build the impact rows: one matrix row per touched doc_id whose cascade
# graph carries downstream targets. Format is documented in
# reference/traceability-impact-template.md.
IMPACT_TABLE=$(cd "$PROJECT_ROOT" && \
    git diff --name-only --diff-filter=ACMR "origin/$BASE_REF" "$HEAD_REF" \
    | while IFS= read -r p; do
        [ -n "$p" ] && extract_doc_ids_from_path "$PROJECT_ROOT" "$p"
    done | sort -u | while IFS= read -r doc_id; do
        [ -z "$doc_id" ] && continue
        targets=$(graph_cascade_targets "$PROJECT_ROOT/docs/.index/graph.yaml" "$doc_id")
        [ -n "$targets" ] && printf '%s\t%s\n' "$doc_id" "$(printf '%s' "$targets" | paste -sd, -)"
    done)
```

**Injection rules** (full template:
`reference/traceability-impact-template.md`):

1. The injected section is bracketed by sentinel HTML comments
   `<!-- traceability-impact:start -->` and `<!-- traceability-impact:end -->`.
   On every re-run the skill replaces the existing block between those
   sentinels rather than appending. This is the idempotency contract -- a
   reviewer who refreshes the PR page does not see duplicated sections.
2. The block is inserted at the very top of the PR body, before any
   user-supplied content, so reviewers see the cascade at a glance.
3. When `$IMPACT_TABLE` is empty (the diff touches no doc_id with cascade
   targets), the injected block still appears -- with the literal line "No
   traceability cascade impact detected for this diff." Empty-with-rationale
   is auditable; silent omission is not.
4. The PR body update goes through `gh pr edit "$PR_NUMBER" --body-file <tmp>`
   so the rest of the body is preserved verbatim. The skill writes the new
   body to a sibling `*.tmp` file and renames on success; a failed update
   leaves the existing body intact.
5. The sentinels are matched literally; the skill does not parse the markdown
   in between. Manual edits to the impact table by a reviewer are overwritten
   on the next push, which is the correct behavior -- the cascade is computed
   from the diff, not asserted by hand.

When the impact computation itself fails (e.g. the shared library exits
non-zero), Phase 5b prints a one-line warning and continues; it does not block
the PR. The next push retries.

> See `reference/traceability-impact-template.md` for the exact markdown
> template, the per-row format, sentinel comment placement, and the
> failure-mode message. The template is the single source of truth for the
> injected section's wording.

### 9. Iterate if Needed

If workflows still fail, repeat steps 2-8. Max 3 retry attempts with 30s CI polling intervals. Each fix is a separate commit. Post a follow-up failure analysis comment at the start of each iteration.

> See `reference/build-verification.md` for iteration limits, CI polling loop, and iteration rules.
> See `reference/comment-templates.md` for the per-attempt follow-up comment template.

### 9b. Evidence-attachment gate (regulated track only)

**Gate:** runs only when `$REGULATED_TRACK=true` (see Phase 0a). Skipped
entirely when the consumer project has no `compliance/` directory; non-regulated
projects see no behavior change from this extension.

After CI is green (Step 9 confirms every check passes) and immediately before
the merge in Step 10, verify that the PR has the regulated metadata an
auditor will need to reconstruct the change. The gate has two checks; both
must pass for the merge to proceed.

**Check (a) -- Linked-issue regulated YAML block.** The PR must reference at
least one issue (via `Closes #N`, `Fixes #N`, or `Resolves #N` in the body),
and the linked issue body must open with the regulated YAML block per the
six format invariants documented in
`global/skills/_internal/issue-create/reference/regulated-fields.md`
"Embedded YAML block format":

1. Block is the very first non-blank content of the issue body, fenced by
   ` ```yaml ` and three backticks.
2. Top-level key is `regulated:` (no alternative key).
3. Field order is fixed: `requirement_id` -> `risk_level` -> `clause_refs`.
4. Omitted optional fields are written as the literal `null`.
5. `clause_refs:` is always block-style YAML list with `- ` markers.
6. Exactly one blank line between the closing fence and the first 5W1H
   heading.

A linked issue without the block, or a block with only `null` fields where
the per-issue-type matrix in `regulated-fields.md` requires a value, fails
the gate. The skill prints the missing field name and the matrix row that
demanded it.

**Check (b) -- Fresh evidence pack manifest.** The PR body or one of the
repository files added in the diff must reference an `evidence/<version>/`
directory whose `manifest.yaml` was generated within the last 24 hours
(`_meta.generated` timestamp inside the manifest). The 24-hour window
matches a typical merge-window cadence; older manifests must be regenerated
via `/evidence-pack <version> --force` before the merge proceeds. The
manifest's required content per `kind` and `iso_class` follows the matrix
in `reference/evidence-attachment-policy.md`.

```bash
# Skip when the regulated track is off.
if [ "$REGULATED_TRACK" != "true" ]; then
    echo "pr-work: regulated track off -- Phase 9b skipped"
    return 0
fi

# Honor the documented override flag.
if [ "$SKIP_EVIDENCE_GATE" = "true" ]; then
    echo "pr-work: Phase 9b skipped via --skip-evidence-gate flag"
    gh pr comment "$PR_NUMBER" --repo "$ORG/$PROJECT" \
        --body "Evidence-attachment gate bypassed via --skip-evidence-gate. Reason: $SKIP_EVIDENCE_GATE_REASON"
    return 0
fi

# Check (a) -- linked-issue regulated YAML block.
PR_BODY=$(gh pr view "$PR_NUMBER" --repo "$ORG/$PROJECT" --json body -q .body)
LINKED_ISSUES=$(printf '%s\n' "$PR_BODY" \
    | grep -ioE '(closes|fixes|resolves)[[:space:]]*#[0-9]+' \
    | grep -oE '[0-9]+' | sort -u)

if [ -z "$LINKED_ISSUES" ]; then
    echo "pr-work: Phase 9b -- PR has no linked issue (Closes / Fixes / Resolves)"
    echo "         see reference/evidence-attachment-policy.md 'Failure messages'"
    return 1
fi

for issue in $LINKED_ISSUES; do
    ISSUE_BODY=$(gh issue view "$issue" --repo "$ORG/$PROJECT" --json body -q .body)
    if ! printf '%s\n' "$ISSUE_BODY" | head -1 | grep -qF '```yaml'; then
        echo "pr-work: Phase 9b -- linked issue #$issue lacks the regulated YAML block (rule 1 violated)"
        return 1
    fi
    # Per-field validation against the per-issue-type matrix is delegated to
    # reference/evidence-attachment-policy.md "Required fields by issue type".
done

# Check (b) -- fresh evidence pack manifest.
EV_DIR=$(printf '%s\n' "$PR_BODY" | grep -oE 'evidence/[A-Za-z0-9._-]+' | head -1)
if [ -z "$EV_DIR" ]; then
    EV_DIR=$(cd "$PROJECT_ROOT" && \
        git diff --name-only --diff-filter=ACMR "origin/$BASE_REF" "$HEAD_BRANCH" \
        | grep -oE '^evidence/[A-Za-z0-9._-]+' | sort -u | head -1)
fi
if [ -z "$EV_DIR" ] || [ ! -f "$PROJECT_ROOT/$EV_DIR/manifest.yaml" ]; then
    echo "pr-work: Phase 9b -- no evidence/<version>/manifest.yaml referenced or present"
    return 1
fi

# Manifest freshness: _meta.generated must be within the last 24 hours.
MANIFEST_TS=$(grep -E '^[[:space:]]*generated:' \
    "$PROJECT_ROOT/$EV_DIR/manifest.yaml" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
NOW_EPOCH=$(date -u +%s)
MANIFEST_EPOCH=$(date -u -d "$MANIFEST_TS" +%s 2>/dev/null || echo 0)
AGE_SECONDS=$(( NOW_EPOCH - MANIFEST_EPOCH ))
if [ "$AGE_SECONDS" -lt 0 ] || [ "$AGE_SECONDS" -gt 86400 ]; then
    echo "pr-work: Phase 9b -- $EV_DIR/manifest.yaml is older than 24h (generated=$MANIFEST_TS)"
    echo "         regenerate via '/evidence-pack <version> --force' before merging"
    return 1
fi
```

**Override path.** When the regulated metadata is genuinely not yet ready
but the merge cannot wait (e.g. an emergency hotfix cleared a blocking CI
issue and the audit trail will be backfilled in a follow-up), the operator
may pass `--skip-evidence-gate "<reason>"`. The skill posts the reason as a
PR comment so the bypass is permanently recorded and exits Phase 9b with
status 0. The flag is NOT a routine bypass; default-mode runs without it
and the gate enforces the checks above.

> See `reference/evidence-attachment-policy.md` for the per-issue-type and
> per-iso-class evidence requirement matrix, the formal "within the last
> 24h" definition, the full failure-message format, and the override-flag
> contract.

### 10a. Sonar Gate (sonarcloud[bot] PR Decoration)

After CI passes (Step 9) and before the ABSOLUTE CI GATE merge (Step 10),
check for a SonarCloud Quality Gate verdict on the PR. SonarCloud reports
via PR comment from `sonarcloud[bot]`, not via a GitHub Check — so the
`gh pr checks` gate in Step 10 does not see it.

```bash
# Fetch sonarcloud[bot] summary comment
SONAR_COMMENT=$(gh pr view $PR_NUMBER --repo $ORG/$PROJECT \
  --comments --json comments \
  -q '.comments[] | select(.author.login == "sonarcloud[bot]") | .body' | tail -1)
```

If no `sonarcloud[bot]` comment is present, the project is not Sonar-attached —
**skip** this step and proceed to Step 10.

If a comment is present:

- Extract the Quality Gate verdict from the comment body (look for
  `Quality Gate passed` or `Quality Gate failed`).
- If `PASS` -> proceed to Step 10.
- If `FAIL` -> invoke the `sonar-fix` skill:
  - Sub-agent: `sonar-fix $PR_NUMBER` (the skill is user-invocable per
    its frontmatter).
  - After `sonar-fix` completes, re-poll the `sonarcloud[bot]` summary
    comment until the verdict flips to PASS or `sonar-fix` reaches its
    own `max_iterations` (3).
- If still `FAIL` after `sonar-fix` exhausts `max_iterations` -> halt
  per pr-work's `halt_conditions` (`sonar-fix exhausted max_iterations
  and Quality Gate still FAIL`) and exit without merging. Convert the
  PR to draft and report the final verdict to the user.

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

When max retry attempts (3) are exceeded: post summary comment to PR (language per active `CLAUDE_CONTENT_LANGUAGE` policy — see `commit-settings.md`), add `needs-manual-review` label, and report final status to user.

> See `reference/comment-templates.md` for the escalation comment template and decision matrix.

---

## Team Mode Instructions

See `reference/team-mode.md` for the complete team mode workflow including architecture, teammate spawning, feedback loops, and cleanup.

## Policies

See [_policy.md](../_policy.md) for common rules, including the **Atomic Multi-Phase Execution** rule — when the user specifies multiple phases (e.g., "Phase 1/2/3"), complete all phases without pausing between them for confirmation.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Language** | All PR comments and commit messages follow the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`) |
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

`--reanchor-interval N` (default 5, `0` disables) controls how often the Core invariants block from `global/skills/_internal/_shared/invariants.md` is emitted inside long loops.

Loop bind points for pr-work:
- **Batch mode**: between items, same semantics as `issue-work` batch-mode (every N items).
- **Single-PR CI polling**: every N poll cycles of the 30-second monitor loop, keeping the CI gate rules adjacent to the latest `gh pr checks` output.

## Error Handling

See `reference/error-handling.md` for prerequisite checks, runtime errors, batch mode errors, and common CI failure patterns.
