# Build Verification Strategies

Strategies for verifying fixes locally before pushing, based on expected build duration.

---

Follow the build verification workflow rule (`build-verification.md`) to select the
appropriate strategy based on expected build duration.

## Strategy Selection

| Build System | Typical Duration | Strategy |
|-------------|-----------------|----------|
| `go build` / `cargo check` | < 30s | Inline (synchronous) |
| `cmake --build` / `gradle build` | 30s - 5min | Background + log polling |
| Full test suites (`ctest` / `pytest`) | 1 - 10min | Background + log polling |

## Inline Strategy (short builds)

For builds expected under 30 seconds:

```
Bash(command="go build ./... && go test ./...", timeout=60000)
Bash(command="cargo check && cargo test", timeout=60000)
```

## Background + Log Polling Strategy (long builds)

For builds expected over 30 seconds:

**Step A**: Launch build in background
```
Bash(command="cmake --build build/ --config Release 2>&1", run_in_background=true)
# -> Returns task_id
```

**Step B**: Poll build output (non-blocking, every 10-15 seconds)
```
TaskOutput(task_id="<id>", block=false, timeout=10000)
# -> Check for error patterns or completion indicators
```

**Step C**: Detect outcome from output

| Outcome | Indicators | Action |
|---------|-----------|--------|
| Success | `Built target`, `Finished`, clean exit | Proceed to tests |
| Failure | `error:`, `FAILED`, `Error` | Diagnose and fix |
| Timeout | No output after 30s of polling | Check system resources |

**Step D**: Run tests with same pattern
```
Bash(command="ctest --test-dir build/ --output-on-failure 2>&1", run_in_background=true)
```

## On Build/Test Failure

1. Read the error output from build logs
2. Categorize failure (compile error, linker error, test assertion, missing dependency)
3. Apply fix based on error pattern
4. Re-run build/test to verify fix

Do NOT retry the same build without changes -- diagnose first.

---

## CI Monitoring After Push

After push, wait for CI with one watch call. Follow the `gh` invariant in
`~/.claude/CLAUDE.md`: one `gh` command per Bash call, never in a loop, never
inside `$(...)` or a pipe, and no `sleep`.

**Step A**: Watch the PR's checks
```bash
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT --watch --interval 30 --fail-fast
```

Run it as the only command of the call: in the background
(`run_in_background: true`) when there is other work to do, otherwise in the
foreground with the Bash tool's `timeout` set to 600000 ms, which enforces the
10-minute limit below. `--fail-fast` ends the watch at the first failed check.
To follow a single run, `gh run watch <RUN_ID> --repo $ORG/$PROJECT --exit-status`
is the equivalent.

**Step B**: Read the result with one plain call
```bash
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT
```

Exit 0: every check passed. Exit 8: checks are still pending. Exit 1: a check
failed. Right after a push the checks may not be registered yet, and the watch
can return at once: while Step B shows pending checks, run Step A again.

**Step C**: Interpret result

| Check state | Action |
|-------------|--------|
| all `pass` (or `skipping` by design) | Proceed to summary |
| any `fail` | Fetch failed logs, go to Step 9 |
| any `cancel` | Report cancellation, investigate or re-trigger |
| any `pending` | Still running or queued: watch again (Step A) |

**Step D**: On failure, fetch the failed logs. Get the run ID with its own
call, then pass the printed ID to the next one:
```bash
gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run view <RUN_ID> --repo $ORG/$PROJECT --log-failed
```

## Final Pre-Merge Verification (MANDATORY)

After the watch shows every check passed, you MUST run `gh pr checks` as a final gate right before the merge:

```bash
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT
```

This catches individual sub-checks (e.g., platform-specific jobs) that `gh run list`/`gh run view` may miss. **Do NOT skip this step.** If any check shows `fail`, `pending`, or any non-pass status, do NOT merge.

## CI Wait Limits

**Do NOT** wait in a loop or with `sleep`, or put `gh` inside `$(...)` or a pipe — use the watch in Step A.
**Do NOT** query CI more often than every 30 seconds — `--interval 30` respects API rate limits.
**Do NOT** block indefinitely — stop waiting about 10 minutes after the push.
**Do NOT** merge while any check is `queued`, `in_progress`, or has `failure` conclusion.
**Do NOT** rationalize any failure as "unrelated" or "pre-existing" — all failures block merge.

If CI is still running about 10 minutes after the push:
1. Stop waiting
2. Report current status of all checks to the user
3. **Do NOT merge** — the user decides next steps

---

## Iteration Limits (Step 9)

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max retry attempts | 3 | Balance between automation and human review |
| CI watch interval | 30 seconds (`--interval 30`) | Respect GitHub API rate limits |
| CI max wait | about 10 minutes per push | Typical CI completion time |
| Pause between retries | Wait for CI with the watch in Step A | No loop, no `sleep` |

### Waiting for CI Between Attempts

After each fix push, wait as in "CI Monitoring After Push": one
`gh pr checks ... --watch --interval 30 --fail-fast` call, then one plain
`gh pr checks` call to read the result.

- `--fail-fast` ends the watch at the first failed check, so a failure is diagnosed as soon as it appears, not after the 10-minute limit
- A watch in the background leaves the session free to report status to the user meanwhile
- On a failure, fetch logs, diagnose, fix, and go to the next attempt; if CI is still running after about 10 minutes, report and escalate

### Iteration Rules

1. Each fix should be a separate commit
2. Track attempt count (max 3 attempts)
3. **Post failure analysis comment** (see `comment-templates.md`) at the start of each iteration
4. After each fix, wait for CI with the watch in "CI Monitoring After Push"
5. Continue until all workflows pass OR max attempts reached
