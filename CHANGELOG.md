# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `markdown-anchor-validator` hook (both PowerShell and bash variants): cross-file
  anchor resolution now works against unstaged target files via lazy parsing with
  per-file caching (#646). Previously the anchor registry was built exclusively
  from `git diff --cached --name-only`, so inter-file references like
  `[text](other.md#anchor)` were reported as broken whenever `other.md` was on
  disk but not staged in the current commit. Single-file edit PRs that
  legitimately reference sibling documents (e.g. SDS slices referencing IDS / SRS
  anchors) were systematically blocked. The fix preserves the staged-file
  registry as a fast path and falls back to disk parsing only when an inter-file
  reference misses the primary registry; results are cached per file so the same
  target is never parsed twice.

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
- Phase 1 supply-chain parity (#620). The download → verify → run contract
  introduced for `bootstrap.sh` is now extracted into a shared library and
  applied to the two remaining install entry points:
  - `hooks/lib/installer-fetch.sh` and `hooks/lib/InstallerFetch.psm1` are
    the new single source of truth for download + sha256 verify + run.
    Typed exit codes (`0=OK`, `10=DOWNLOAD`, `11=CHECKSUM`, `12=MISMATCH`,
    `13=RUN`, `64=usage`) are mirrored in both implementations.
  - `bootstrap.sh` and `bootstrap.ps1` now clone the repo before invoking
    the Claude Code CLI installer so the lib is available; the GITHUB_REF
    tag is therefore the integrity root for every subsequent verification.
  - `bootstrap.ps1` no longer pipes `irm | iex`; pins the Anthropic
    PowerShell installer at sha256
    `acc15c3d844b8952e702a24b584d2fdc0b589ee1061c11202529cdd5702711df`
    (`# pinned 2026-05-09`).
  - `bootstrap.ps1` repo clone now uses `--branch $GitHubRef --depth 1`
    with the same `v1.10.0` default as the bash side. `GITHUB_BRANCH`
    remains a one-release deprecation alias.
  - `scripts/install.sh` `ensure_claude_cli` no longer pipes `curl | bash`;
    sources the shared lib and verifies sha256 before executing.
  - Regression suite `tests/scripts/installer-fetch-tests.sh` covers
    happy path, download failure, sha mismatch, run failure, and usage
    errors with local `file://` fixtures (no network dependency).
  - Windows runner CI for `bootstrap.ps1` and a TTY-aware non-interactive
    default are deferred to a follow-up.

### Added

- Phase 2 memory CI workflow (#621). Adds
  `.github/workflows/validate-memory.yml`, gating PRs that touch
  `scripts/memory-sync.sh`, `scripts/memory/`, or `tests/memory/` on the four
  existing test runners (`run-sync-tests.sh`, `run-validation-tests.sh`,
  `run-semantic-review-tests.sh`, `run-notify-tests.sh`). The sync-tests job
  exercises the T5 auto-quarantine reproducer that the #617 `set -e` fix
  restored. A nightly schedule (`17 4 * * *` UTC) additionally runs the
  multi-machine simulation harness; the multi-machine job is skipped on fork
  PRs. Workflow exports `OWNER_EMAILS` so tests run cleanly under the
  post-#618 fail-closed contract. `docs/MEMORY_SYNC.md` Section 7 cross-
  references the workflow.
- Phase 2 plugin/fleet CI wiring (#622). Two test areas that had passing
  test code but no CI integration are now connected:
  - `tests/plugin/smoke-test.sh` runs on every PR via
    `validate-hooks.yml`, catching plugin packaging regressions
    (manifest mismatches, missing skills) before release. PR triggers
    expanded from `plugin/hooks/**` to the full `plugin/**` and
    `plugin-lite/**` plus `tests/plugin/**`.
  - `tests/fleet_orchestrator/` pytest suite (17 cases) runs on every
    PR via `validate-skills.yml`. Pins `topk_scorer.py` routing
    behavior — silent breakage previously meant wrong agent
    assignments to work items in any consumer using the
    fleet-orchestrator skill. Path triggers expanded with
    `scripts/fleet_orchestrator/**` and `tests/fleet_orchestrator/**`.
  - `docs/PLUGIN_BUILD.md` and the fleet-orchestrator SKILL.md cross-
    reference the new CI lanes.

### Changed

- Phase 3 doc-index description extraction (#625). The /doc-index
  manifest.yaml stored `'<p align="center">'` as the description for
  files that opened with a centered badge block (most prominently
  `README.ko.md`, the Korean entry point). New
  `scripts/extract-doc-description.sh` skips frontmatter, headings, and
  pure-HTML structural lines, then strips inline tags from mixed prose
  and truncates to 200 characters. The doc-index SKILL.md flat-mode
  Phase 3F now references the helper as the canonical extraction path.
  Both `README.md` and `README.ko.md` entries in
  `docs/.index/manifest.yaml` were regenerated with meaningful prose
  descriptions. New `tests/doc-index/` directory contains 4 fixtures
  (normal, html-only, frontmatter-only, empty) and a 10-case test
  suite wired into `validate-skills.yml`.
- Phase 3 ADR metadata headers (#624). The eight `docs/design/*.md`
  files plus the two long-lived performance/regression docs
  (`docs/tier2-benchmark-results.md`, `docs/batch-drift-regression.md`)
  now carry a five-field YAML frontmatter (`status`, `audience`,
  `last_reviewed`, `supersedes`, `superseded_by`). Status assignments
  reflect implementation reality: `Active` for shipped systems,
  `Draft` for proposals or design concepts not yet implemented. The
  new `scripts/validate-adr-headers.sh` lint enforces presence and
  basic shape on every PR via `validate-skills.yml`. Schema documented
  in `docs/CUSTOM_EXTENSIONS.md`.
- Phase 3 README.ko.md sync (#623). Korean README brought back into
  shape parity with English:
  - Translated v1.8.0 and v1.9.0 changelog entries (the v1.7.0 — v1.10.0
    gap noted in the audit). v1.10.0 has no changelog body in either
    README yet; both will be filled at the next release.
  - Added 시나리오 D (Use Case D — batch-issue-work / batch-pr-work) and
    the matching quickstart-table rows. Externally-orchestrated batch
    flows are now visible to Korean readers without bouncing through
    the English README.
  - Added "Memory sync (다중 머신)" and "Related Projects" sections that
    were English-only. With these the two READMEs now have matching
    heading counts at every level.
  - Removed the hardcoded "현재: 1.7.0" line in favor of pointing at
    `VERSION_MAP.yml` as the single source of truth (mirrors the
    English approach added in v1.9-era).
  - New `scripts/diff-readme.sh` compares ATX heading counts at every
    level between the two files. Awareness of fenced code blocks
    avoids false positives on `# 1.` style comments. Wired into
    `validate-skills.yml` (which already triggered on README changes)
    and added to the `/release` skill checklist between the version
    drift check and the staging step.

[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.10.0...HEAD
