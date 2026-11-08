---
paths:
  - "**/CMakeLists.txt"
  - "**/*.cmake"
  - "**/Makefile"
  - "**/makefile"
  - "**/package.json"
  - "**/build.gradle*"
  - "**/settings.gradle*"
  - "**/pom.xml"
  - "**/Cargo.toml"
  - "**/pyproject.toml"
  - "**/go.mod"
  - "**/*.csproj"
  - "**/*.sln"
alwaysApply: false
---

# Build Verification Workflow

## Strategy Selection

Choose strategy based on expected build duration:

| Build Duration Estimate | Strategy | Method |
|------------------------|----------|--------|
| < 30 seconds | Inline | Run synchronously, read output directly |
| 30s - 5 minutes | Background + Poll | `run_in_background: true` + `TaskOutput` polling |
| > 5 minutes (CI) | CI Log Check | `gh run view --log-failed` after trigger |

### Duration Estimates by Build System

| Build System | Typical Duration | Default Strategy |
|-------------|-----------------|------------------|
| `go build` / `go test` | < 30s | Inline |
| `cargo check` | < 30s | Inline |
| `npm run build` (small) | < 30s | Inline |
| `cmake --build` | 30s - 5min | Background + Poll |
| `gradle build` | 30s - 5min | Background + Poll |
| `cargo build` (full) | 30s - 5min | Background + Poll |
| `npm run build` (large) | 30s - 5min | Background + Poll |
| Full test suites | 1 - 10min | Background + Poll |
| GitHub Actions CI | 5min+ | CI Log Check |

## Inline Strategy

For builds expected under 30 seconds, run synchronously:

```
Bash(command="go build ./...", timeout=60000)
Bash(command="cargo check", timeout=60000)
```

Read output directly. If it fails, diagnose from the error output.

## Background + Poll Strategy

For builds expected over 30 seconds:

### Step 1: Launch in Background

```
Bash(command="cmake --build build/ --config Release 2>&1", run_in_background=true)
# Returns task_id for later polling
```

### Step 2: Poll for Results

Check build progress periodically using non-blocking reads:

```
TaskOutput(task_id="<id>", block=false, timeout=10000)
# Returns current output without waiting for completion
```

Poll at reasonable intervals (every 10-15 seconds). Do NOT poll in a tight loop.

### Step 3: Detect Outcome

Scan output for success/failure indicators:

| Language | Success Indicator | Failure Indicator |
|----------|------------------|-------------------|
| C++/CMake | `Built target`, clean exit | `error:`, `fatal error:` |
| Node.js | `Successfully compiled`, `✓` | `ERROR in`, `Failed to compile` |
| Gradle | `BUILD SUCCESSFUL` | `BUILD FAILED` |
| Rust | `Finished` | `error[E` |
| Go | Clean exit (no output) | `cannot find`, `undefined:` |
| Python | Clean exit | `SyntaxError`, `ImportError`, `ModuleNotFoundError` |
| C# | `Build succeeded` | `Build FAILED`, `error CS` |

### Step 4: On Failure — Diagnose

When failure is detected:

1. Read the error lines from build output
2. Categorize: compile error, linker error, missing dependency, test failure
3. Apply fix based on error pattern
4. Re-run build to verify fix

Do NOT retry the same build without making changes — diagnose first.

## CI Pipeline Verification

For remote CI (GitHub Actions), wait with one watch call per push. Run each
command below as its own call (see the `gh` invariant in `~/.claude/CLAUDE.md`):

### Wait and Check

```bash
# Wait for every check (in the background, or in the foreground with a 10-minute timeout)
gh pr checks <PR> --repo <owner/repo> --watch --interval 30 --fail-fast

# Read the result (exit 8: still pending, exit 1: a check failed)
gh pr checks <PR> --repo <owner/repo>
```

Without a PR, watch the run instead: get its ID with
`gh run list --repo <owner/repo> --branch <branch> --limit 1 --json databaseId -q '.[0].databaseId'`,
then run `gh run watch <RUN_ID> --repo <owner/repo> --exit-status`.

### Interpret Result

| Result | Action |
|--------|--------|
| All checks pass | Proceed |
| A check failed | Fetch logs: `gh run view <RUN_ID> --repo <owner/repo> --log-failed` |
| Checks still pending | Watch again |

### Wait Limits

- `--interval 30`: query CI status no more than once per 30 seconds
- Maximum wait: 10 minutes after the push
- After timeout: report last known status, do not block indefinitely

## Integration with ci-debugging Skill

When build or CI failure is detected, follow the ci-debugging diagnostic flow:

1. **Environment/Auth** — TLS errors, token expired, permission denied
2. **Platform-Specific** — Works on one OS but fails on another
3. **Missing Dependencies** — Module not found, package missing
4. **Actual Code Bug** — Test assertions, logic errors

## Batch Error Fixing

After large refactoring or migration, run a full build, collect ALL errors, and fix them
in one batch before rebuilding. Do not fix one error at a time — this wastes rebuild cycles.

## Failure Escape Hatch

If the same approach fails 3 consecutive times, stop and propose alternative strategies
to the user. Do not continue retrying the same fix.

## Rules

- **Never wait indefinitely** for build or CI completion
- **Never poll in a tight loop** — minimum 10s interval for local, 30s for CI
- **Never assume success** without checking output or exit code
- **Always diagnose before retrying** — blind retries waste time
