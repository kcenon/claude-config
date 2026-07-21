# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- PowerShell test suites for the Bash-channel guards. The
  `bash-sensitive-read-guard.ps1`/`bash-write-guard.ps1` pair carried zero
  assertions while their bash counterparts carried 60 and 67, so `.ps1`
  changes shipped on review and manual probing alone. Both bash suites are
  now ported case-by-case in the `test-sensitive-file-guard.ps1` assertion
  style (`tests/hooks/test-bash-sensitive-read-guard.ps1`, 61 assertions;
  `tests/hooks/test-bash-write-guard.ps1`, 67 assertions), auto-discovered
  by `tests/hooks/test-runner.ps1` on both the pwsh matrix job and the
  native Windows job, and recognised by the unwired-test meta-check through
  the shared-runner rule. Every ported case was probed against the real
  `.ps1` guard first and asserted at its actual behaviour: approximation
  artifacts of the whole-command regex design (the read-tool prefix
  matching `echo cat .env`, the blanket `awk` arm denying read-only awk)
  are marked as such in place, and the six security-relevant arm gaps the
  port surfaced (relative sensitive directories and bare credential
  filenames) are pinned at today's allow with pointers at #878, which will
  flip them (#869).
- `issue-work` now routes issue selection and size evaluation through a
  shared triage state machine
  (`global/skills/_internal/issue-work/scripts/triage.sh`) that solo, team,
  and batch modes run before any repository is cloned or branch created. The
  gate emits one of five outcomes (`proceed`, `decomposed`, `blocked`,
  `skipped`, `failed`), makes blocked and parent-decomposition comments
  idempotent through a `triage-fingerprint` marker so re-running over an
  unchanged issue is a no-op, and stops with a `blocked` result after three
  identical issue fetches instead of retrying blindly. The state contract is
  documented in `reference/triage-state-machine.md` and covered by a
  fake-`gh` unit suite in `tests/issue-work/` (#829).
- Added the isolated-workspace and subagent lifecycle for `issue-work`: a
  reference implementation and contract for turning a triage `proceed` outcome
  into a private, identity-verified clone, orchestrating subagents against it,
  and tearing it down safely. The target repository's `develop` branch is
  cloned into a unique run root under the OS temp directory, its origin
  identity is verified against the expected `owner/name`, and lifecycle
  progress is recorded in an atomic, credential-redacted manifest through
  `CLAIMED -> CLONING -> READY -> AGENTS_RUNNING -> COMMITTED -> PUSHED ->
  PR_OPEN -> CI_PENDING -> MERGED -> CLEANUP_PENDING -> CLEANED`. Subagents run
  under a strict prompt contract and a single-writer lease while every push,
  PR, merge, and cleanup stays the coordinator's exclusive responsibility; on
  resume the state is reconciled against live Git and GitHub rather than
  trusted from the manifest; and the workspace is removed only after the PR has
  merged, the tree is clean, the work is recoverable from the remote, and all
  agents have terminated, with recursive deletion gated by path- and Git-state
  validation and preserved after three identical failures. The contract is
  documented in `reference/workspace-lifecycle.md` with Bash and PowerShell
  reference implementations (`scripts/workspace.sh`, `scripts/agents.sh`,
  `scripts/cleanup-workspace.sh`) and fake-`gh` / bare-remote unit suites in
  `tests/issue-work/` (#838, #839, #840).
- Added a mandatory pre-PR readiness gate for `issue-work` that runs after the
  implementation and documentation are committed and before any push or PR. A
  deterministic git-state helper
  (`global/skills/_internal/issue-work/scripts/pre-pr-gate.sh`) refuses a dirty
  worktree, fetches the base branch, fast-forwards the local base only when it
  is strictly behind (an `ahead` or `diverged` base blocks and is never
  rewound), integrates the refreshed base into the feature branch (rebase by
  default, merge for shared branches), aborts and blocks on any conflict rather
  than guessing intent, and re-integrates when the remote base moves — stopping
  with `base_unstable` after a capped number of movements. It emits a single
  `ready`/`blocked` JSON outcome that the skill routes on. The agent-side
  documentation-to-issue gap audit reconciles each required behavior against
  implementation, test, documentation, and issue evidence in a seven-field gap
  ledger whose rows carry exactly one of four dispositions (`fix-in-pr`,
  `followup-issue`, `already-satisfied`, `blocked`), never reports "no gap" when
  retrieval was incomplete, and requires the resulting PR to target `develop`,
  close the active issue, and use a Korean title and body. The contract is
  documented in `reference/pre-pr-readiness.md` and covered by a bare-remote
  unit suite in `tests/issue-work/test-pre-pr-gate.sh` (#831).
- `issue-work` now invokes the triage state machine, isolated-workspace
  lifecycle, and pre-PR readiness gate from the actual solo, team, batch, and
  external-orchestrator paths, so the standalone scripts added in #829, #830,
  and #831 run in order instead of existing unused. Solo and team setup clone
  through `scripts/workspace.sh` and tear down through
  `scripts/cleanup-workspace.sh` instead of an in-place checkout; team
  teammates are spawned only after the clone, with prompts built by the
  `agents.sh` `agents_build_prompt` contract so each carries the absolute
  repository path, active issue, baseline commit, and write scope; batch
  results and resume state record the triage `requested`/`root`/`active`
  triple, deduplicate by the resolved active issue, and pause on a decomposed
  or blocked item instead of counting it as merged; and the Bash and
  PowerShell batch orchestrators branch on a structured `ISSUE_WORK_RESULT:`
  result marker rather than the process exit code alone. The triage,
  workspace, and pre-PR gates are documented as mandatory in every
  skill-loading tier, including `light` (#845).
- Regression-test wiring coverage now extends repo-wide. A second gate,
  `tests/scripts/test-nonstandard-test-wiring.sh`, fails when any tracked test
  entrypoint OUTSIDE `tests/scripts/test-*` is neither executed by a workflow
  run command, swept by a wired shared runner, nor explicitly classified in
  `tests/nonstandard-test-registry.txt`. The wiring-detection logic is factored
  into `tests/scripts/lib/ci-wiring-lib.sh` and shared with the focused
  `tests/scripts/test-ci-wiring.sh` gate (#823) so path-filter mentions,
  comments, and echo statements never count as wiring in either. The previously
  orphaned `hook-json-escape-group1.sh`, `hook-json-escape-group2.sh`,
  `sonar-fix/test-fixtures.sh`, and `batch_drift_regression/test-run-regression.sh`
  suites are now wired into `validate-hooks.yml`; the registry records the
  remaining nonstandard entrypoints as sourced helpers, or as manual-only tests
  with a reason, risk, and removal condition (#833).
- `docs/deep-audit-2026-05-29.md` now declares a maintenance model and carries a
  dated reconciliation log. The document is kept as an immutable point-in-time
  record: finding bodies are never rewritten when a finding closes, and
  resolution is tracked additively in a dated status section instead. The first
  reconciliation covers the `tests-ci` cluster, recording three findings as
  resolved by the landed CI wiring (#821, #823, #833, #850) and the fourth as
  still open (#855) (#853).

### Fixed

- `bash-write-guard` no longer allows writes to sensitive directories named
  by a relative path. `echo y > secrets/db.yml` was permitted while the same
  write to `/srv/secrets/db.yml` was denied: `resolve_path` does not
  absolutise a relative path whose target does not exist, and
  `is_sensitive_target` carried only the anchored `*/secrets/*` arm, so
  repo-root-relative writes to all three directory tokens (`secrets/`,
  `credentials/`, `passwords/`) matched nothing — while
  `bash-sensitive-read-guard` denied the same paths, leaving the two
  Bash-channel guards disagreeing about the same directory class. The shell
  guard gains the bare-anchored arm mirroring the read guard, plus — from
  the arm-by-arm comparison the issue required — the read guard's bare
  credential-filename block (the `id_rsa` family and `credentials`) and an
  `ssh_host_*_key` arm, with the deliberate omissions (`*password*`
  substring, `*.crt`/`*.cer`, and the write-only `/etc/passwd` and
  `/etc/hosts` arms) recorded in place with reasons. The PowerShell
  counterpart replaces its two separator-anchored directory alternates with
  one arm covering all three tokens in both anchored and bare forms —
  `passwords/` was previously missing even in the anchored form. Relative
  non-sensitive writes (`build/out.txt`) and boundary-adjacent names
  (`docs/secrets-of-git.md`) stay allowed (#871).
- `bash-sensitive-read-guard` no longer allows an unexpanded glob that
  brackets the env token. `cat *.env*` reached the guard as a literal path
  matching no deny arm — it does not end in `.env` and holds no `.env.`
  run — so the guard answered allow and the shell then expanded the pattern
  over every env file in the directory. The hook inspects the command before
  expansion, so the fix keys on the pattern rather than the expansion: the
  `.sh` guard strips glob metacharacters from a wildcard-bearing token and
  re-checks the remainder, denying when the de-globbed core is itself
  sensitive — generalising past the one reported literal to any bracket
  form — and the `.ps1` guard adds `*` and `?` to the `.env` boundary
  classes, which also closes its latent `*.env` and `*.env.local`
  divergences from the shell implementation. Env-mentioning non-globs
  (`environment.txt`) and globs outside the env class (`cat *.md`,
  `cat env*`) stay allowed, and the #866 template allow-list is
  unaffected (#867).
- The Bash-channel guards no longer deny env-file templates that the
  file-channel guards allow. `bash-sensitive-read-guard` and
  `bash-write-guard` matched the env class as `.env`, `*.env`, and `.env.*`
  with no template exemption, so `.env.example` — a file that by definition
  holds no secret and is committed on purpose — could be opened with the
  `Read` tool but not with `cat`, and written with the `Write` tool but not
  with a shell redirect. All four implementations (both `.sh` guards and both
  `.ps1` counterparts, which the issue did not enumerate) now carry the same
  four-name allow-list the file channel has used since #582: `.env.example`,
  `.env.example.*`, `.env.sample`, `.env.template`. The direction follows
  #863, which denied the mirrored `example.env` suffix form precisely because
  the recognised template convention is the dotfile prefix. The allow-list
  does not widen the bypass surface: in the `.sh` guards it is a no-op `case`
  arm rather than an early allow, so the `secrets/` and credential-extension
  checks below it still apply to a template under a secrets directory; in the
  `.ps1` guards the template mention is masked out of the scanned string
  rather than exiting early, so a template named alongside a real secret
  (`cat .env.example && cat .env`) still denies. Unexpanded glob literals
  (`.env.*`, `.env.example*`) never satisfy the allow-list and remain denied
  (#866).
- `sensitive-file-guard.sh` and `sensitive-file-guard.ps1` no longer allow
  env files written in the bare suffix form. Both matched the env class as
  `.env`, `.env.*`, and `.envrc` against the basename, so `production.env`
  and `staging.env` matched no arm and fell through to an allow — while
  `.env.production`, the same artifact under the other common naming
  convention, was denied by the same guard under the reason `(env file)`.
  Both gain a `*.env` arm, keeping the file-channel pair in the lockstep
  #856 established. The two Bash-channel guards (`bash-write-guard.sh`,
  `bash-sensitive-read-guard.sh`) and the plugin's inline guard already
  denied this form, so the `*.env` row in the retained-divergence table in
  `docs/plugin-vs-global.md` is removed rather than rewritten: the
  divergence no longer exists. `example.env` and `template.env` are denied
  on purpose — the recognised template convention is the dotfile prefix
  (`.env.example`), which the allow-list still admits because it is
  evaluated first, and both Bash-channel guards already deny the mirrored
  form (#863).
- The plugin distribution's inline sensitive-file guard
  (`plugin/hooks/hooks.json`) no longer allows files the canonical
  `sensitive-file-guard.sh` denies. Its extension alternation was anchored
  against the full path, so the entire `.env.*` family passed unblocked —
  including `.env.local`, which routinely holds real credentials. The guard
  now extracts the basename, trims surrounding whitespace, folds case, and
  matches a `case` block mirroring the canonical guard: the template
  allow-list (`.env.example`, `.env.sample`, `.env.template`) is evaluated
  first, then `.env` / `.env.*` / `.envrc`, credential extensions, SSH
  private keys (`id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` and their
  suffixed forms), and `credentials` / `config` under a `.aws/` path. The
  plugin stays deliberately broader than the canonical guard for the
  `private` directory pattern. Inline symlink
  resolution is still out of scope and is now recorded as a retained
  divergence in `docs/plugin-vs-global.md`, which no longer claims full
  parity between the two surfaces (#860).
- `sensitive-file-guard.ps1` no longer allows paths its bash counterpart
  denies. The guard now canonicalizes the incoming path through a new
  `Resolve-HookPath` helper in `CommonHelpers.psm1` — the PowerShell port of
  `resolve_path()` from `path-utils.sh` — and matches every filename-based
  rule against the resolved, trimmed, lowercased basename. This closes the
  `.envrc` (direnv config) gap in the env-file pattern set and the
  whitespace-padded and tilde-prefixed bypasses that previously slipped past
  the raw-string env and credential-extension checks. The template allow-list
  (`.env.example`, `.env.sample`, `.env.template`) is still evaluated first
  and still allows; the sensitive-directory rule still matches the raw input,
  as the bash variant does (#856).
- Every `tests/scripts/test-*` regression is now executed by an explicit CI
  run command, and a meta-test fails when a new test is neither wired nor
  recorded with a reviewed manual-only reason. The previously orphaned
  installer-fetch test now follows the `test-*` naming contract, and the
  full PowerShell installer test uses fake external tools to prevent network
  or global package side effects in native Windows CI (#823).
- Native Windows hook CI now runs the PowerShell hook behavior suite on
  `windows-latest`, and settings parity gates fail on unexpected top-level,
  `env`, `permissions.allow`, or `permissions.deny` drift between
  `global/settings.json` and `global/settings.windows.json`. The Windows Bash
  allow-list now mirrors the Unix profile; only the Windows PowerShell
  read-only allow-list and POSIX CA environment variables remain documented
  exceptions (#821).
- Installers now record managed-file hashes for global and project install
  trees and prune removed upstream files only when the deployed copy still
  matches the managed hash. Locally edited removed files are preserved and
  reported, and legacy command files removed before directory manifests are
  pruned only when they match known upstream hashes (#820).
- Default installer `GITHUB_REF` pins in `bootstrap.sh`, `bootstrap.ps1`, and
  README one-line examples now track `VERSION_MAP.yml` `suite` (`v1.11.0`);
  `check_versions` and `sync_versions` cover those pins.
- The `tests/hook-json-escape.sh` smoke test now matches the split allow
  contract of `global/hooks/dangerous-command-guard.sh` instead of the
  pre-refactor `allow_response(reason)` shape. `allow_with_context()` is
  asserted to round-trip its reason through `additionalContext`, while the
  plain `allow_response()` pass path is asserted to emit no reason field at
  all, pinning the silent-pass contract from #715 rather than leaving it
  unasserted. Both allow helpers are exercised against the adversarial
  quote/backslash/CR/LF/tab reason and the historical
  `permissionDecision` injection string. The suite is wired into
  `validate-hooks.yml` ahead of the group 1/2 suites, so the
  dangerous-command-guard allow path is gated in CI, and its manual-only row
  is removed from `tests/nonstandard-test-registry.txt` (#850).
- The nightly batch-drift regression now grades only a result file produced by
  the current run. `run-regression.sh` captures a run-start marker before
  invoking the benchmark and considers only result files newer than that
  marker, so the committed benchmark results under
  `tests/batch_drift_benchmark/results/` can no longer satisfy the selection
  glob, and a run that writes no fresh result fails instead of grading a
  pre-existing file. A non-zero exit from the benchmark runner is now fatal
  rather than a warning that falls through to grading. Together these close a
  false-pass path in which a benchmark that produced nothing was graded
  against a months-old committed file and reported `passed: true`, so the
  nightly job reported success while measuring nothing from that run. The
  stale-result path is covered by regression cases that inject a stub
  benchmark through the new `BATCH_DRIFT_BENCHMARK_DIR` override (#855).

## 1.11.0 - 2026-07-03

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
  - Regression suite `tests/scripts/test-installer-fetch.sh` covers
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

## 1.10.0 - 2026-04-20

- **Release scope**: Fleet-orchestrator, preflight, ci-fix, and research skills.
- **Hooks**: Added pre-edit-read-guard, post-task-checkpoint,
  pr-language-guard, merge-gate-guard, and an attribution-guard extension.
- **Platform and release hardening**: Added the `SSL_CERT_FILE` sandbox TLS
  fix, unified version declarations in `VERSION_MAP.yml`, and shipped
  batch-mode drift mitigations.

## 1.9.0 - 2026-04-13

- **Multi-layered branch defense**: Four enforcement layers to prevent non-release merges to `main`
  - PreToolUse hook (`pr-target-guard`): blocks `gh pr create --base main` unless `--head develop`
  - GitHub Actions (`validate-pr-target.yml`): auto-closes PRs targeting `main` from non-develop branches
  - Release skill integrity check: detects main/develop divergence before release
  - Documentation: enforcement layers table in `branching-strategy.md`
- **CI fix**: Removed invalid inline Python heredoc blocks from `validate-skills.yml` that caused every workflow run to fail with YAML parse errors.
- **README updates**: Added "When you create PRs" section and updated the directory tree with missing hooks and workflows.

## 1.8.0 - 2026-04-13

- **Simplified git-flow branching strategy**: `develop` is the default branch, and CI runs only on PRs targeting `main`.
- **Pre-push hook**: Blocks direct pushes to protected branches (`main`, `develop`).
- **Branching documentation**: Added a comprehensive branch model, CI policy, and release workflow guide.

## 1.7.0 - 2026-04-06

- **Windows PowerShell coverage**: Added substantial PowerShell (`.ps1`) parity for utility, hook, and helper scripts. The earlier "All 42 bash scripts now have PowerShell counterparts" wording was inaccurate; see [COMPATIBILITY.md > PowerShell parity status](COMPATIBILITY.md#powershell-parity-status) for the live count and the list of bash hooks without `.ps1` counterparts.
  - Most utility scripts: `install`, `verify`, `sync`, `backup`, `validate_skills`, `bootstrap`
  - Most hook scripts with identical security behavior
  - All 8 GitHub CLI helper scripts (`scripts/gh/`)
  - All 3 global scripts (`statusline-command`, `team-report`, `weekly-usage`)
  - All 7 test scripts for hook validation
  - Git hooks installer (`hooks/install-hooks.ps1`)
- **Shared PowerShell module**: Added `CommonHelpers.psm1` with 20 exported functions.
  - Message helpers, hook response builders, stdin JSON reader
  - Platform detection, version comparison, log rotation
  - Eliminates `jq` dependency on Windows by using native `ConvertFrom-Json`
  - Uses .NET `GZipStream` for log compression

## 1.6.0 - 2026-04-03

- **Harness meta-skill**: Added `/harness` for designing domain-specific agent team architectures.
  - 6 architecture patterns: Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical
  - Generates `.claude/agents/` and `.claude/skills/` with orchestration
  - Reference docs: agent design patterns, orchestrator templates, skill writing/testing guides, QA agent guide
- **QA reviewer agent**: Added `qa-reviewer` agent for integration coherence verification.
- **Version check hook**: Added SessionStart hook to warn about known Claude Code cache bugs.
- **Batch processing**: Added batch mode to `/issue-work` and `/pr-work` skills.
- **CI validation**: Extended skill validation with description quality and global skills checks.
- **Skill descriptions**: Enhanced trigger accuracy across all skills.
- **Third-party notices**: Added `THIRD_PARTY_NOTICES.md` for harness content attribution.

## 1.5.0 - 2026-03-21

- **Skills migration**: Migrated all global commands to Skills format for context isolation and model override support.
  - `/branch-cleanup`, `/release`, `/issue-create`, `/issue-work`, `/pr-work` are now skills
  - Added new global skills: `/doc-review`, `/implement-all-levels`
  - Added new project skills: `ci-debugging`, `code-quality`, `git-status`, `pr-review`
  - Skills support `argument-hint`, `model`, `allowed-tools`, and adaptive execution frontmatter
- **Agent Teams**: Added experimental multi-agent collaboration framework.
  - Shared task lists, direct messaging, and team coordination
  - Teammates modes: `auto`, `in-process`, `tmux`
  - Team hooks: `TeammateIdle`, `TaskCompleted`
- **Windows PowerShell support**: Added Windows installer, hook script variants, and Windows-specific settings.
- **New hooks**: Added GitHub API preflight, markdown anchor validation, prompt validation, logging, config-change, pre-compact, and worktree lifecycle hooks.
- **tmux auto-logging**: Added `tmux.conf` for automatic session logging.
- **Plugin enhancements**: Bundled agent definitions and updated manifests.
- **GitHub helper scripts**: Added `scripts/gh/` with 8 helper scripts for issues and PRs.
- **Rule files restructured**: Updated `coding/`, `core/`, `operations/`, and `tools/` rules to match current best practices.
- **Context optimization**: Reduced always-on context by 77% via SSOT refactoring.

## 1.4.0 - 2026-01-22

- Adopted Import syntax (`@path/to/file`) for modular references.
- Updated all `CLAUDE.md` files to use Import syntax.
- Updated all `SKILL.md` files to use Import syntax for reference documents.

## 1.3.0 - 2026-01-15

- Added `/release` command for automated changelog generation.
- Added `/branch-cleanup` command for merged and stale branches.
- Added `/issue-create` command with 5W1H framework.
- Added `/issue-work` and `/pr-work` commands for GitHub workflow automation.
- Added common policy files (`_policy.md`) for shared command rules.
- Updated all global commands to reference shared policy.

## 1.2.0 - 2026-01-15

- Optimized `CLAUDE.md` for official best practices compliance.
- Simplified `project/CLAUDE.md`.
- Added emphasis expressions for key rules.
- Created `common-commands.md`.
- Optimized `conditional-loading.md`.
- Split `github-issue-5w1h.md` with Progressive Disclosure.

## 1.1.0 - 2025-01-15

- Added `.claude/rules/` directory with path-based conditional loading.
- Added `.claude/commands/` for custom slash commands.
- Added `.claude/agents/` for specialized agent configurations.
- Added MCP configuration template (`.mcp.json`).
- Added local settings templates (`CLAUDE.local.md.template`, `settings.local.json.template`).
- Extended hooks with `UserPromptSubmit` and `Stop` events.
- Added `alwaysThinkingEnabled` setting to all settings.json files.
- Enhanced all `SKILL.md` files with `allowed-tools` and `model` options.

## 1.0.0 - 2025-12-03

- Initial release with global and project configurations.
- Added Claude Code Skills with progressive disclosure pattern.
- Added hook settings for security and auto-formatting.

[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.11.0...HEAD
