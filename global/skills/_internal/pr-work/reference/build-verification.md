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

After push, monitor CI with non-blocking polling:

**Step A**: Get the triggered run ID
```bash
# Wait briefly for workflow to register
sleep 5
RUN_ID=$(gh run list --repo $ORG/$PROJECT --branch "$HEAD_BRANCH" --limit 1 --json databaseId -q '.[0].databaseId')
```

**Step B**: Poll CI status (non-blocking, every 30 seconds)
```bash
gh run view $RUN_ID --repo $ORG/$PROJECT --json status,conclusion -q '{status: .status, conclusion: .conclusion}'
```

**Step C**: Interpret result

| status | conclusion | Action |
|--------|-----------|--------|
| completed | success | Proceed to summary |
| completed | failure | Fetch failed logs, go to Step 9 |
| completed | cancelled | Report cancellation, investigate or re-trigger |
| completed | timed_out | Report timeout, check workflow config |
| in_progress | — | Poll again after 30s interval |
| queued | — | Poll again after 30s interval |
| waiting | — | Poll again after 30s interval (approval gate) |

**Step D**: On failure, fetch specific error logs
```bash
gh run view $RUN_ID --repo $ORG/$PROJECT --log-failed 2>&1 | head -100
```

## Final Pre-Merge Verification (MANDATORY)

After polling shows all runs completed + success, you MUST run `gh pr checks` as a final gate:

```bash
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT
```

This catches individual sub-checks (e.g., platform-specific jobs) that `gh run list`/`gh run view` may miss. **Do NOT skip this step.** If any check shows `fail`, `pending`, or any non-pass status, do NOT merge.

## CI Polling Limits

**Do NOT** use `gh run watch` — it blocks the entire session.
**Do NOT** poll more frequently than every 30 seconds — respect API rate limits.
**Do NOT** block indefinitely — max 10 minutes of polling per run.
**Do NOT** merge while any check is `queued`, `in_progress`, or has `failure` conclusion.
**Do NOT** rationalize any failure as "unrelated" or "pre-existing" — all failures block merge.

If the 10-minute polling limit is reached with CI still running:
1. Stop polling immediately
2. Report current status of all checks to the user
3. **Do NOT merge** — the user decides next steps

---

## Iteration Limits (Step 9)

| Setting | Value | Rationale |
|---------|-------|-----------|
| Max retry attempts | 3 | Balance between automation and human review |
| CI poll interval | 30 seconds | Respect GitHub API rate limits |
| CI max poll duration | 10 minutes | Typical CI completion time |
| Pause between retries | Wait for CI result via polling | No blocking watch |

### CI Status Polling Loop

Instead of blocking with `gh run watch`, use non-blocking status polling:

```
For each poll (max 20 iterations x 30s = 10 minutes):
  1. Check: gh run view $RUN_ID --repo $ORG/$PROJECT --json status,conclusion
  2. If completed + failure -> fetch logs, diagnose, fix, go to next attempt
  3. If completed + success -> done
  4. If in_progress -> wait 30s, poll again
  5. If max polls reached -> report timeout, escalate
```

This approach:
- Detects failures as soon as CI completes (not after 10min timeout)
- Provides status updates to the user between polls
- Allows early intervention when failure is detected

**Do NOT** use `gh run watch` -- it blocks the entire session.

### Iteration Rules

1. Each fix should be a separate commit
2. Track attempt count (max 3 attempts)
3. **Post failure analysis comment** (see `comment-templates.md`) at the start of each iteration
4. After each fix, monitor CI via polling
5. Continue until all workflows pass OR max attempts reached
