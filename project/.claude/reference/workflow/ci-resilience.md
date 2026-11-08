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

The global profile sets `SSL_CERT_FILE` and `SSL_CERT_DIR` in `env`, so `git`, `curl`, `npm`, `pip`, and similar tools succeed inside the sandbox without `dangerouslyDisableSandbox`. The `gh` binary on macOS is a separate case (links `Security.framework`, ignores `SSL_CERT_FILE`): it runs outside the sandbox through `sandbox.excludedCommands`, which matches only a call that is `gh` alone — follow the `gh` invariant in `~/.claude/CLAUDE.md` rather than bypassing the sandbox.

Full coverage matrix and platform fallback ladder: `docs/SANDBOX_TLS.md` in the claude-config repository (not installed). The same repository's `scripts/verify-tls.sh` checks the local CA-bundle setup.

**Diagnostic note**: TLS errors (`x509: certificate signed by unknown authority`, `tls: failed to verify certificate`) are not authentication errors. Never flag one as the other without running the canonical verifier.

## Congested Runner Handling

GitHub Actions runners may become congested, causing jobs to stay `queued` for extended
periods. Do NOT block indefinitely waiting for CI.

| Queue Duration | Action |
|---------------|--------|
| < 2 minutes | Normal — keep waiting |
| 2-5 minutes | Report wait to user, keep waiting |
| > 5 minutes | Report wait to user, keep waiting up to the 10-minute limit |

```bash
# Check individual job statuses when a run is slow (one gh command per call)
gh run view $RUN_ID --repo $ORG/$PROJECT --json jobs -q '.jobs[] | {name: .name, status: .status, conclusion: .conclusion}'
```

**Do NOT** merge while any check is `queued` or `in_progress`, even if all completed
checks have passed. If CI is still running 10 minutes after the push, stop waiting,
report current status to the user, and let the user decide next steps.

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

## Waiting for CI

Wait with one watch call per push: `gh pr checks <n> --repo <owner/repo> --watch --interval 30 --fail-fast`,
in the background or in the foreground with a 10-minute timeout, then read the result with one
plain `gh pr checks` call. Right after a push the checks may not be registered yet; while the
plain call shows pending checks, watch again. The full protocol is in
`~/.claude/skills/_internal/pr-work/reference/build-verification.md`.

| Setting | Value | Rationale |
|---------|-------|-----------|
| Watch interval | 30 seconds (`--interval 30`) | Respect GitHub API rate limits |
| Max wait | 10 minutes after the push | Typical CI completion time |
| Max retry attempts | 3 | Balance between automation and human review |

**Never** wait in a loop or with `sleep`, and never put `gh` inside `$(...)` or a pipe.
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
