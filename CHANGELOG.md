# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- Phase 0 audit hotfix bundle (#616, #617, #618, #619). Four critical defense
  layers had bypasses that the post-audit triage flagged simultaneously; this
  release fixes them as a single coordinated patch so reviewers see all four
  surfaces at once.
  - `pr-target-guard.sh` (#616) — when `gh pr create` was invoked without
    `--base`, the hook unconditionally allowed, assuming the repo's default
    branch was `develop`. Repositories whose default branch is `main` or
    `master` (e.g. `vcpkg-registry`) silently bypassed the branching policy.
    The hook now resolves the default branch via
    `gh api repos/{owner}/{repo} --jq .default_branch` and applies the same
    develop-or-release-only protection when the resolved base is `main`/`master`.
    `PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE` exposes the resolution to tests
    so the new `tests/hooks/fixtures/pr-target-guard/main-default-repo.json`
    fixture and 9 new test cases run without depending on `gh` authentication.
  - `memory-sync.sh` (#617) — `post_pull_validate` captured `$?` after a raw
    validator call. Under `set -euo pipefail`, a non-zero validator exit
    terminated the whole script before the assignment ran, so the
    auto-quarantine branch — the last line of defense in the memory sync's
    five-layer model — never executed. Switched to the standard
    `rc=0; cmd || rc=$?` idiom so the validator's exit code is preserved
    without aborting on failure.
  - `secret-check.sh` (#618) — **BREAKING**. The script shipped with
    `DEFAULT_OWNER_EMAILS="kcenon@gmail.com"`, embedding the maintainer's
    personal email in a public repository and giving every fresh installation
    an owner allowlist that allow-listed the maintainer instead of the
    operator. The default is now empty; missing `OWNER_EMAILS` exits 2 with
    a helpful message. Migration:
    `export OWNER_EMAILS="you@example.com"`
    See `scripts/memory/secret-check.env.example` for the full template and
    `docs/MEMORY_TRUST_BASELINE.md` Section 8 for the trust-model rationale.
    Bootstrap.sh first-run integration is deferred (the memory opt-in flow
    does not yet exist there).
  - `install-hooks.sh` (#619) — option 2 ("병합") appended claude-config
    validators after the existing hook content. If the existing hook called
    `exit 0` in its primary path, the appended validators never ran and the
    install appeared to succeed but the gate was silently disabled. Switched
    to PREPEND so the new validators always run first; an `exit 0` downstream
    is now dead code unless validators explicitly fall through. Added
    `tests/hooks/test-merge-installation.sh` covering prepend ordering, the
    new merge-order summary message, and invalid-message rejection. Users
    who previously chose "병합" should re-run the installer and choose
    option 1 (덮어쓰기) to clean up the legacy duplicated block.
- `bootstrap.sh` pins the install source to a release tag instead of the floating
  `main` branch (SLSA-aligned supply-chain hardening). The default `GITHUB_REF`
  is `v1.10.0`, and `git clone` now uses `--branch "$GITHUB_REF" --depth 1`,
  which both anchors integrity to a tagged release and reduces clone size on
  bandwidth-constrained networks.
- `GITHUB_BRANCH` is preserved as a one-release deprecation alias for the new
  `GITHUB_REF` variable; setting it emits a stderr warning. Migrate any
  automation that overrides `GITHUB_BRANCH` to `GITHUB_REF` before the next
  major release.

[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.10.0...HEAD
