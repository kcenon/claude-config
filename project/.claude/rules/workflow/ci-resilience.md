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

See **Environment Workarounds** in `global/CLAUDE.md` for the canonical rule — `SSL_CERT_FILE` and `SSL_CERT_DIR` are wired in `global/settings.json` so `git`, `curl`, `npm`, `pip`, and similar tools succeed inside the sandbox without `dangerouslyDisableSandbox`. The `gh` binary on macOS is a separate case (links `Security.framework`, ignores `SSL_CERT_FILE`) — remediate via a Bash allowlist rather than sandbox bypass.

Full coverage matrix and platform fallback ladder: `docs/SANDBOX_TLS.md`.
Verify the local CA-bundle setup with `scripts/verify-tls.sh`.

**Diagnostic note**: TLS errors (`x509: certificate signed by unknown authority`, `tls: failed to verify certificate`) are not authentication errors. Never flag one as the other without running the canonical verifier.

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

## Post-Task CI Verification

After completing issue work or PR creation, always verify CI status before considering
the task done. If CI is still pending, note it explicitly in the task summary rather
than marking the task as completed.

## CI Failure Policy

Any CI failure — including test timeouts — must be investigated and fixed before merging.
Never treat a failing check as "flaky" or ignorable. If a test times out, adjust the test
workload, increase the timeout, or fix the underlying performance issue before proceeding.

## Multi-Repo Parallel Strategy

When working on multi-repo tasks, use parallel agents (one per repo) rather than processing
sequentially. Each agent should independently implement, test, and create PRs.
