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

For remote CI (GitHub Actions):

### Trigger and Check

```bash
# After push, wait briefly for workflow to register
sleep 5

# Get latest run ID
gh run list --branch <branch> --limit 1 --json databaseId -q '.[0].databaseId'

# Poll CI status (non-blocking)
gh run view <RUN_ID> --json status,conclusion -q '{status: .status, conclusion: .conclusion}'
```

### Interpret Result

| status | conclusion | Action |
|--------|-----------|--------|
| completed | success | Proceed |
| completed | failure | Fetch logs: `gh run view <RUN_ID> --log-failed` |
| in_progress | — | Poll again after 30s |
| queued | — | Poll again after 30s |

### Rate Limiting

- Poll CI status no more than once per 30 seconds
- Maximum poll duration: 10 minutes
- After timeout: report last known status, do not block indefinitely

## Integration with ci-debugging Skill

When build or CI failure is detected, follow the ci-debugging diagnostic flow:

1. **Environment/Auth** — TLS errors, token expired, permission denied
2. **Platform-Specific** — Works on one OS but fails on another
3. **Missing Dependencies** — Module not found, package missing
4. **Actual Code Bug** — Test assertions, logic errors

## Rules

- **Never wait indefinitely** for build or CI completion
- **Never poll in a tight loop** — minimum 10s interval for local, 30s for CI
- **Never assume success** without checking output or exit code
- **Always diagnose before retrying** — blind retries waste time
