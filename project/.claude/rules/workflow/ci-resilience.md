---
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/workflows/*.yaml"
  - "**/Makefile"
  - "**/CMakeLists.txt"
  - "**/go.mod"
  - "**/Cargo.toml"
  - "**/package.json"
alwaysApply: false
---

# CI Resilience Patterns

Strategies for handling common CI/CD friction points: TLS errors, congested runners,
missing toolchains, and first-run build failures.

## TLS / Sandbox Errors

When `gh` CLI commands fail with TLS certificate errors in sandbox mode:

```
x509: certificate signed by unknown authority
tls: failed to verify certificate
```

**Resolution priority**:
1. Retry the command with `dangerouslyDisableSandbox: true`
2. If that fails, verify authentication: `gh auth status`
3. Never assume authentication has failed without checking — TLS errors are not auth errors

**Common false positive**: Claude may incorrectly flag a TLS error as an authentication
failure. Always distinguish between network/TLS errors and actual auth failures.

## Congested Runner Handling

GitHub Actions runners may become congested, causing jobs to stay `queued` for extended
periods. Do NOT block indefinitely waiting for CI.

| Queue Duration | Action |
|---------------|--------|
| < 2 minutes | Normal — continue polling |
| 2-5 minutes | Report wait to user, continue polling |
| > 5 minutes | Report wait to user, continue polling up to 10-minute limit |

```bash
# Check individual job statuses when run is slow
gh run view $RUN_ID --repo $ORG/$PROJECT --json jobs -q '.jobs[] | {name: .name, status: .status, conclusion: .conclusion}'
```

**Do NOT** merge while any check is `queued` or `in_progress`, even if all completed
checks have passed. If the 10-minute polling limit is reached, stop polling, report
current status to the user, and let the user decide next steps.

## Missing Toolchain Fallback

When local toolchains (Go, Rust, CMake, npm) are not installed:

1. **Do NOT** attempt to install toolchains without asking the user
2. **Skip** local build verification for that toolchain
3. **Rely on CI** for build and test verification
4. **Report** what was verified locally vs what needs CI verification

```bash
# Check toolchain availability
for tool in go cargo cmake npm python3; do
    if command -v $tool &>/dev/null; then
        echo "$tool: available"
    else
        echo "$tool: unavailable (will rely on CI)"
    fi
done
```

## Reducing First-CI-Run Failures

Common causes of first CI failure (from usage data: 15 sessions with buggy code friction):

| Error Type | Prevention | Local Check |
|-----------|-----------|-------------|
| Missing imports/includes | Build locally before push | `go build ./...`, `cargo check` |
| Field name mismatches | Run tests locally | `go test ./...`, `pytest` |
| Type definition issues | Compile check | `cmake --build`, `tsc --noEmit` |
| Lint/format violations | Run formatter before commit | `gofmt`, `black`, `clang-format` |
| Namespace errors (C++) | Forward declaration check | `cmake --build` |

**Incremental validation pattern**: Build and test after each logical change, not after
all changes are complete. This catches errors early when the diff is small and the cause
is obvious.

```
implement change A → build → test → commit
implement change B → build → test → commit
push all commits → CI should pass on first run
```

## CI Polling Best Practices

| Setting | Value | Rationale |
|---------|-------|-----------|
| Poll interval | 30 seconds | Respect GitHub API rate limits |
| Max poll duration | 10 minutes | Typical CI completion time |
| Max retry attempts | 3 | Balance between automation and human review |
| Wait before first poll | 5 seconds | Allow workflow to register |

**Never** use `gh run watch` — it blocks the entire session.
**Never** poll in a tight loop — minimum 30-second intervals for CI.
**Always** diagnose before retrying — blind retries waste time.
