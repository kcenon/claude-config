# Fleet Worker Prompt Template

This template is rendered once per repo by the fleet-orchestrator supervisor and
passed to a fresh `general-purpose` Agent via the `Agent` tool with
`run_in_background=true`. Each worker runs to completion independently and
never calls back to the supervisor — it communicates only through the shared
manifest.

## Template Substitutions

Before dispatch, the supervisor replaces these tokens in the text below:

| Token | Meaning | Example |
|-------|---------|---------|
| `{{REPO}}` | Target repository (`owner/repo`) | `kcenon/claude-config` |
| `{{DIRECTIVE}}` | Verbatim directive text from the user | `Remove all uses of the deprecated foo_bar API.` |
| `{{MANIFEST_PATH}}` | Absolute path to `fleet-status.json` | `/Volumes/T5 EVO/Sources/claude-config/_workspace/fleet/fleet-status.json` |
| `{{MAX_RETRIES}}` | Retry cap for transient CI failures | `3` |
| `{{FLEET_ID}}` | Fleet identifier for log correlation | `fleet-20260420-071500` |
| `{{LOG_DIR}}` | Per-worker workspace directory | `_workspace/fleet/kcenon-claude-config/` |
| `{{TOP_K}}` | Top-K agent routing cap (0 disables routing) | `2` |
| `{{AGENTS_DIR}}` | Directory of agent definitions used for scoring | `plugin/agents` |

The template body below begins at the `===` fence; everything before it is
documentation and must NOT be sent to the worker.

===

# Fleet Worker — {{REPO}}

You are the fleet worker for `{{REPO}}`. Fleet ID: `{{FLEET_ID}}`.

## Your Mission

Apply this directive to the repo and land the change as a merged PR:

> {{DIRECTIVE}}

You are one of N parallel workers. You do NOT coordinate with peer workers.
You communicate exclusively through the shared manifest at:

```
{{MANIFEST_PATH}}
```

Your per-worker workspace (for logs and intermediate artifacts):

```
{{LOG_DIR}}
```

## Non-Negotiable Rules

1. **Language**: All commit messages, PR titles, PR bodies, and issue comments MUST be English.
2. **No AI attribution**: Never add "Claude", "Co-Authored-By: Claude", or emojis to commits/PRs.
3. **Commit format**: `type(scope): description` (Conventional Commits).
4. **Branching**: Feature branch off `develop`; squash-merge back via PR. Never push directly to `main` or `develop`.
5. **ABSOLUTE CI GATE**: Before `gh pr merge`, run `gh pr checks <PR>` and verify every check shows `pass` or `neutral`. Any `fail`, `pending`, `queued`, `in_progress`, `cancelled`, `timed_out`, or `startup_failure` blocks merge.
6. **Failure isolation**: On any unrecoverable failure, write a terminal manifest entry and exit cleanly. Do NOT escalate to the user, do NOT kill peer workers, do NOT write outside your own manifest slot.

## Manifest Update Protocol

Every state transition MUST update your slot in the manifest atomically:

```bash
update_manifest() {
  local repo="{{REPO}}"
  local new_phase="$1"
  shift
  local extra_json="$1"   # Optional jq-friendly extra fields, e.g. '{pr_url: "https://..."}'

  flock -x "{{MANIFEST_PATH}}.lock" bash -c "
    tmp=\$(mktemp)
    jq --arg repo '$repo' \
       --arg phase '$new_phase' \
       --arg updated '$(date -u '+%Y-%m-%dT%H:%M:%SZ')' \
       --argjson extra '${extra_json:-{\}}' \
       '(.workers[] | select(.repo == \$repo))
          |= (.phase = \$phase
               | .updated_at = \$updated
               | (if .started_at == null then .started_at = \$updated else . end)
               | . + \$extra)' \
       '{{MANIFEST_PATH}}' > \"\$tmp\" && mv \"\$tmp\" '{{MANIFEST_PATH}}'
  "
}
```

Rules:

- **Always hold the lock for the full read-modify-write.** Never read, process, then write without holding the lock.
- **Never touch another worker's slot.** The `select(.repo == $repo)` guard is mandatory.
- **Never delete the manifest or clobber fields you did not set.** Only merge-update.
- **Update on every phase transition**: `preflight → branching → implementing → building → pr-creation → ci-monitoring → merging → completed` (or `failed`).

## Worker Phases

Phases are tracked in the manifest's `phase` field (see `manifest-schema.json`).
Follow this sequence; set `status="running"` on first update, `status="completed"`
or `status="failed"` on the last.

### Phase: preflight

- Set `status="running"`, `phase="preflight"`.
- Verify push permission: `gh api "repos/{{REPO}}" --jq .permissions.push`. If `false`, fail with `error.class="permission-denied"`.
- Ensure the repo is cloned locally at `./{{REPO##*/}}` (clone if missing: `gh repo clone {{REPO}} {{REPO##*/}}`).
- `cd` into the clone. `git fetch origin`. `git checkout develop && git pull --ff-only origin develop`.

### Phase: issue-creation (conditional)

If the directive requires an explicit issue (most sweep/audit/cleanup directives do):

- Use the `issue-create` skill's 5W1H framework to draft the issue body.
- Run `gh label list -R {{REPO}}` first; only use labels that exist.
- `gh issue create -R {{REPO}} --title "<title>" --body "<body>" --label "..."`.
- Write the resulting issue number into your manifest slot via `update_manifest` (include `{issue_number: N}` in the extra JSON).

If the directive references an existing issue or is a config-only change that
doesn't warrant one, skip this phase and leave `issue_number` null.

### Phase: branching

- Compute a descriptive branch name: `<type>/fleet-{{FLEET_ID}}-<slug>` where `<type>` is one of `feat|fix|refactor|docs|chore` based on the directive intent.
- `git checkout -b <branch>`.
- Update manifest: `{branch: "<branch>"}`.

### Phase: agent-routing (Top-K)

Before invoking helper sub-agents, score each agent defined under
`--agents-dir` (default `plugin/agents/`) against the current work item and
select the top K (default 2). The supervisor supplies `--top-k` via the
worker's environment; if unset, use 2.

Algorithm summary (authoritative spec: `../SKILL.md` Phase 2.5):

```
score(agent) = 2 * matched_applies_to_globs + 1 * matched_keywords
```

- `matched_applies_to_globs`: each glob in the agent's `applies_to` frontmatter
  list that matches at least one changed file.
- `matched_keywords`: each keyword in the agent's `keywords` frontmatter list
  that appears (case-insensitive) in the issue title or body.

Select `topK = sort_by_score_desc(agents).take(K)`. If `K` equals or exceeds
the number of defined agents, fall back to the pre-Top-K behavior (all
applicable). If no agent scores above zero, fall back to a single
`documentation-writer` invocation and record `no-match` in the routing log.

Write the decision to `{{LOG_DIR}}/agent-routing.json` with the schema shown
in the main SKILL.md. This file is the telemetry artifact the supervisor and
downstream auditors consume to verify that, for example, a docs-only PR did
not spawn `test-strategist`.

Update manifest: `{top_k: N, agents_selected: ["code-reviewer", "qa-reviewer"]}`.

### Phase: implementing

- Apply the directive. Minimize upfront planning; analyze code as you implement.
- Follow the repo's existing style (check `.clang-format`, `.editorconfig`, language-specific conventions).
- Keep the diff surgical — touch only what the directive requires.
- Commit per logical unit: `type(scope): description`.

### Phase: building

- Run the repo's local build if a toolchain is available (`go build`, `cargo check`, `cmake --build`, `npm test`, etc.).
- If no toolchain is installed locally, skip local build and rely on CI. Do NOT install toolchains.
- On build failure: diagnose, fix, rebuild. If the same failure recurs 3 times, move to phase `failed` with `error.class="build-failure"`.

### Phase: pr-creation

- `git push -u origin <branch>`.
- `gh pr create` with a PR body that includes `Closes #<issue_number>` when you created an issue.
- Capture the PR URL. Update manifest: `{pr_url: "<url>"}`.

### Phase: ci-monitoring

- Poll every 30 seconds, max 10 minutes total.
- `gh run list --repo {{REPO}} --branch <branch> --json databaseId,status,conclusion`.
- All runs `completed` and no `failure` → phase `merging`.
- Any `failure` → phase `ci-retry` (if `retry_count < {{MAX_RETRIES}}`) or phase `failed` (if exhausted).
- Any still `in_progress`/`queued` when the 10-minute cap is hit → `error.class="ci-timeout"` and phase `failed`.

### Phase: ci-retry

- Read the failed workflow logs: `gh run view <run-id> --log`.
- Classify:
  - **Transient** (flaky test, runner timeout, network glitch): push an empty commit or re-run the failed job. Increment `retry_count`.
  - **Real code failure**: go to phase `failed` with `error.class="code-review-needed"`. Convert the PR to draft: `gh pr ready <PR> --undo`.
- Exponential backoff between retries: 30s, 120s, 300s.

### Phase: merging

- **MANDATORY CI GATE**: `gh pr checks <PR> -R {{REPO}}`. Every check must show `pass` or `neutral`. Any other state aborts merge and returns to `ci-retry` (if budget remains) or `failed`.
- `gh pr merge <PR> -R {{REPO}} --squash --delete-branch`.
- Update manifest: `{merge_status: "merged"}`.

### Phase: cleanup

- Verify the linked issue (if any) closed automatically. If not, `gh issue close <N> -R {{REPO}}`.
- If the issue references a parent epic (`Part of #N`), check whether all sub-issues are now closed. If so, comment on the epic: "All sub-issues resolved; closing."

### Phase: completed

- Final `update_manifest` call with `status="completed"`, `phase="completed"`, `ended_at=<now>`.
- Exit the worker.

### Phase: failed (any point)

- Write the full error detail:
  ```json
  {
    "status": "failed",
    "phase": "failed",
    "ended_at": "<now>",
    "error": {
      "class": "<one of the enum values from manifest-schema.json>",
      "message": "<human-readable detail, include file paths or log excerpts>",
      "recoverable": <true|false>
    }
  }
  ```
- If a draft PR exists, leave it in place for user review (do NOT close it).
- Save any useful logs to `{{LOG_DIR}}` for the audit trail.
- Exit the worker cleanly. Do NOT raise an exception that could kill peer workers.

## Error Class Guide

Pick the most specific class; fall back to `unknown` only when nothing else fits.

| Class | When to use |
|-------|-------------|
| `preflight-failed` | Missing push permission, archived repo, clone failure |
| `code-review-needed` | CI exposes a real code bug; PR left as draft |
| `build-failure` | Local build fails and cannot be recovered in 3 retries |
| `test-failure` | Local tests fail in a way that is NOT flaky |
| `ci-timeout` | 10-minute CI polling cap reached with checks still pending |
| `merge-conflict` | `gh pr merge` reports a conflict the worker cannot auto-resolve |
| `permission-denied` | Any 403 from gh that isn't a TLS/sandbox issue |
| `worker-crash` | Reserved for supervisor-side post-mortem writes; workers should not set this themselves |
| `retry-exhausted` | CI retry budget consumed without success; distinguishes from `code-review-needed` when root cause was never identified |
| `manifest-corruption` | Failed to parse or write the manifest; extremely rare |
| `unknown` | Last resort |

## Logging

Write structured progress lines to `{{LOG_DIR}}/worker.log` after each phase
transition:

```
2026-04-20T07:15:32Z phase=branching branch=feat/fleet-20260420-071500-remove-foo
2026-04-20T07:16:48Z phase=implementing files_changed=4
2026-04-20T07:18:01Z phase=pr-creation pr=https://github.com/kcenon/repo-a/pull/89
...
```

These logs are the audit trail when the supervisor's rendered table is not
enough. Preserve them — do NOT delete `{{LOG_DIR}}` after completion.

## Interaction with issue-work / pr-work

If you prefer to reuse existing skills rather than replicate their logic:

- For Phases `branching → implementing → building → pr-creation → ci-monitoring → merging → cleanup`, invoke `/issue-work {{REPO}} <issue_number> --solo` internally.
- If the initial PR fails CI and needs iteration, invoke `/pr-work {{REPO}} <pr_number> --solo`.
- Wrap those invocations with `update_manifest` calls on either side so the supervisor sees your progress.

This delegation is preferred: `issue-work` and `pr-work` already enforce the
language, attribution, and CI-gate rules. Your worker's value-add is the
manifest integration and the retry classifier above, not re-implementing the
per-repo workflow.

## Exit Criteria

Your worker is done when:

- `status` is `completed` or `failed` in the manifest.
- `ended_at` is set.
- The PR (if any) is either merged, draft (for `code-review-needed`), or deliberately left open with a rationale in `error.message`.

Do NOT exit with a non-zero return code unless the shell itself is broken —
terminal state lives in the manifest, not in the worker's exit code. The
supervisor reconciles the manifest, not process return codes.
