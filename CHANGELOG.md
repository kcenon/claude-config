# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `global/hooks/bash-guard-dispatcher.ps1` is now shipped from the repository
  and registered as the sole `PreToolUse`/`Bash` hook in
  `global/settings.windows.json`, replacing 15 separate registrations. Each
  registration spawned its own `pwsh -NoProfile`, so one Bash tool call started
  15 processes; the dispatcher pays that cost once and invokes only the guards
  whose command family is present. Measured on the Windows profile (5 runs
  each): 15-hook registration p50 1,002ms (spread 919-1,063ms) versus
  dispatcher p50 541ms (spread 529-549ms). The 1,002ms baseline matches the
  p50 observed in session transcripts, so the bench tracks the shipped path.
  The collapsed spread matters as much as the median: the same scan window
  recorded 90 hook timeouts (81 Bash, 6 Read, 3 Edit), which are the tail of
  process contention rather than slow guard logic.
  The caveat from the 2026-07-27 attempt is unchanged: an isolated bench is not
  a session measurement, and that attempt's 863->446ms never reproduced in real
  sessions. Re-measure from transcript p50 once several hundred calls have
  accumulated.
  Re-measured 2026-08-23 over 61,780 transcript hook runs, and the caveat does
  not survive its own test. Segmented by configuration, `PreToolUse:Bash` p50
  runs 828ms on 15 hooks, 424ms on the 2026-07-27 prototype, 908ms after that
  prototype was reverted, and 534ms on the shipped dispatcher: -35.5% against
  the pre-consolidation baseline. So the 2026-07-27 bench did reproduce; the
  check that reported otherwise straddled the reverted window, where the
  channel was back on 15 hooks. The `Edit|Write|Read` matcher, untouched by all
  four transitions, is flat at 415/437/448/426ms across them and serves as the
  control. Table and method in `HOOKS.md`; a naive before-and-after split at
  2026-07-27 reports no improvement and should not be used.
- `tests/hooks/test-bash-guard-dispatcher.ps1` (9 assertions) covering routing,
  fail-closed behaviour, and - the property no decision-only assertion can see -
  that the payload actually reaches each guard. Verified by mutation: with the
  cache below reverted, a benign `git status --short` is denied and the suite
  fails 2 assertions.
- The enterprise install tree is manifest-tracked on Windows. It was deployed
  by two bare `Copy-Item` calls that no manifest recorded, which made it the
  only layer in the cascade with no integrity mechanism -- and the
  highest-precedence one, since Claude Code loads it as managed policy. A
  three-way audit that classified 270 of 278 tracked files could say nothing
  about these three, and the one real difference surfaced only by hashing them
  by hand: `C:\Program Files\ClaudeCode\rules\compliance.md` is 1574 B against
  the repo's 1983 B, missing the Scope note added by `e345d36` (#705), with all
  three live files dated 2026-03-04. `Install-Enterprise` now repoints
  `MANIFEST_PATH` at `<enterprise-dir>/.install-manifest.json` and copies
  through `Invoke-ManifestTrackedCopy` / `Copy-ManifestTree`. The root needs its
  own manifest file rather than a key prefix, because the global tree already
  tracks a key named `CLAUDE.md` and a shared manifest would have the two roots
  overwrite each other's stored hash. The repoint is unwound in a `finally`:
  `Write-ManifestFiles` has no error handling and the script runs under
  `$ErrorActionPreference = 'Stop'`, so a throw would otherwise leave
  `MANIFEST_PATH` aimed at `C:\Program Files` for the rest of the install. The
  helper is also loaded inside `Install-Enterprise`, since install type 4 never
  enters the global block that dot-sources it. Prune is deliberately not run
  for this root: tracking makes drift visible, while deleting out of a
  managed-policy directory is a separate decision. `enterprise/**` is added to
  the `validate-hooks.yml` paths filter, which previously matched nothing, so a
  PR touching only `enterprise/rules/*.md` ran no workflow at all. POSIX is not
  covered -- those roots are written with `sudo` and
  `scripts/install-manifest.sh` has no elevation path -- and is tracked as a
  follow-up. (#903)
- `Install-Enterprise` reports what is on disk instead of what the copy helpers
  returned. Two paths were wrong. A throw from the `CLAUDE.md` copy or the
  manifest write unwound past the function -- only the rules copy had a `catch`
  -- so under `$ErrorActionPreference = 'Stop'` the state stayed `'skipped'` and
  the closing summary never ran, which is the same failure #905 added the state
  variable to prevent. And the success lines were printed unconditionally:
  `Invoke-ManifestTrackedCopy` returns `$true` for a real write, for a
  destination already byte-identical, and for a **missing source** alike, while
  `Copy-ManifestTree` discards every per-file result, so a file kept at the
  divergence prompt was reported as installed. That mattered concretely: on a
  first run there is no manifest, so a stale file has no stored hash, falls to
  the divergence branch, and a bare Enter keeps it -- the exact drift the
  tracking exists to expose could survive a run that declared success. The
  function now records each destination's hash before the copies and reports
  `updated` / `already current` / `kept local` / `source missing` from a
  comparison afterwards, and a kept file yields a new `installed-with-kept`
  state that the summary renders by naming each file left behind. Pinned by
  seven assertions, all verified to fail against the pre-change file, plus a
  behavioural test in `test-install-manifest-helpers.ps1` fixing the
  three-outcomes-one-return-value fact the old reporting relied on. (#910)
- `scripts/install.ps1` declares `#Requires -Version 7.0` instead of `5.1`. It
  uses the three-argument `Join-Path` (`-AdditionalChildPath`, PowerShell 6+
  only) at `:335` and `:538`, so the old floor admitted an interpreter that
  cannot run the script -- measured on Windows PowerShell 5.1.26100.9168,
  `Join-Path a b c` fails with "A positional parameter cannot be found that
  accepts argument 'c'". Because `:538` runs after `Confirm-ClaudeCli` and the
  install-type prompt, a 5.1 user answered questions and then hit a parameter
  error naming `InstallPrompts.psm1`, rather than being refused up front. The
  file also contradicted itself: the comment above the directive already said
  PowerShell 7. `install.ps1` was the only outlier -- `bootstrap.ps1`,
  `scripts/backup.ps1`, `scripts/sync.ps1` and `scripts/verify.ps1` already
  declared 7.0 -- and no `Join-Path` call was changed, since the call sites are
  correct and the deployed hooks already run under `pwsh`.
  `tests/scripts/test-installer-robustness.sh` now pins the declaration on all
  five entry points so it cannot drift from the syntax again. (#911)
- `project/CLAUDE.md` now says what makes a skill invocable. The `## Skills`
  section listed eleven names and stopped there, while availability is decided
  by `skillOverrides` in `.claude/settings.local.json` -- a file no installer
  creates and `.gitignore` excludes, so the list can never reflect it. On the
  machine where this surfaced, nine of the eleven were switched off and nothing
  in `CLAUDE.md` pointed there; a disabled skill fails silently, so the reader
  has no way to connect the two. The list is kept, because it is accurate: all
  eleven names match directories under `project/.claude/skills/`, and the
  shipped `settings.local.json.template` declares no `skillOverrides`, so on a
  fresh checkout every listed skill really is enabled. That default is now
  stated too, so the caveat is not misread as "the list is unreliable".
  `## Agents` is unchanged: its eight names are equally accurate and there is no
  per-agent disable mechanism to warn about. (#908)
- The enterprise install tree is manifest-tracked on POSIX too, completing the
  Windows half above. `install_enterprise` in `scripts/install.sh` carried the
  same bare-copy defect in triplicate -- three near-identical branches (sudo
  POSIX, plain POSIX, Windows-under-bash), each with its own pair of copies --
  which is how the defect survived there at all; they are now one deployment
  path preceded by a privilege decision. The blocker was that the POSIX
  enterprise root is root-owned while every write primitive in
  `scripts/install-manifest.sh` is unprivileged. Resolved with
  `MANIFEST_ELEVATE`, an opt-in command prefix consulted by a new
  `_manifest_run`: it is empty for every existing caller, and an empty value
  makes the helper collapse to `"$@"`, so the global and project layers execute
  byte-identically to before. `install_enterprise` sets it to `sudo` only on the
  branch where the destination's parent is not writable. The merged manifest
  document is built unprivileged in a temp file and only its placement is
  elevated -- reading the existing manifest needs no privilege, and keeping the
  JSON step out of `sudo` avoids the environment stripping its inline variables
  depend on. The deployed manifest is left mode 644 so a drift audit needs no
  elevation. The helper is sourced inside `install_enterprise`, which runs
  before the global block that sources it and is skipped entirely for
  `INSTALL_TYPE=4`, and `MANIFEST_PATH` is restored afterwards because a leaked
  value would redirect the whole `~/.claude` manifest into the enterprise root.
  Prune stays off here, matching Windows. (#906)
- The installer's closing summary no longer claims an enterprise deployment
  that did not happen. It printed the enterprise paths under "Installed files:"
  for install types 4 and 5 unconditionally, including when `Install-Enterprise`
  had returned early because administrator rights were missing or because the
  operator declined to deploy an uncustomized template. Each exit path now
  records its outcome and the summary reports it. (#903)

### Changed

- `Read-HookInput` (`global/hooks/lib/CommonHelpers.psm1`) caches its parsed
  payload for the lifetime of the process. stdin can only be drained once, so
  when the dispatcher reads it and then invokes guards in-process, the guards'
  own `Read-HookInput` calls would otherwise see `$null` - fail-closed guards
  denying every call, fail-open guards silently no longer checking. The cache
  is in the GLOBAL scope on purpose: every guard re-imports the module with
  `-Force`, which resets module scope. Guards invoked standalone run in a fresh
  process, so they read stdin exactly as before (200 assertions across the five
  existing `.ps1` guard suites pass unchanged).
  This replaces the 2026-07-27 approach of adding a `-HookInput` parameter to
  all 15 guards, whose revert surface was 15 files; all 15 had in fact been
  reverted to their pre-consolidation contents by 2026-08-01, leaving the
  dispatcher unwireable.
- `bash-guard-dispatcher.ps1` now fails CLOSED on unparseable input, matching
  `dangerous-command-guard`, which denies on the same condition. Allowing there
  would have quietly weakened that guarantee once the guards stopped being
  registered individually.
- The `.sh`/`.ps1` parity audit in `.github/workflows/validate-hooks-doc.yml`
  and its `COMPATIBILITY.md` count now exempt `global/hooks/*-dispatcher.*`. The
  audit's premise is that every file there is a guard with a per-platform
  implementation; a dispatcher is an execution strategy instead. A `.sh` twin
  would be a dormant unwired file, which is the condition the audit exists to
  catch, and POSIX has nothing to consolidate anyway (a cheap `bash` per guard,
  not a `pwsh` cold start). The guard twin rule is unchanged - an unpaired guard
  still fails - and Windows guard coverage moves to the routing-table check
  below rather than disappearing. Guard counts stay 38/38, so the
  `COMPATIBILITY.md` parity row is unchanged.
- `tests/scripts/test-windows-hooks-parity.sh` expands a `bash-guard-dispatcher`
  registration to the guard names in the dispatcher's routing table before
  diffing. Comparing 14 POSIX guards against one dispatcher entry would
  otherwise have required an allow-list broad enough to void the test; the
  parity guarantee is instead preserved at the routing table, where a guard can
  now actually go missing. Verified by mutation: dropping `push-target-guard`
  from the routing table fails the test and names that guard.
- `ci-fix`, `fleet-orchestrator`, and `preflight` now carry
  `disable-model-invocation: true`, so all 19 `_internal` skills are hidden
  from the model-facing skill listing instead of 16 of them. The three held
  1,369 chars (~342 est. tokens) of resident context per session for zero
  model invocations across 50 local sessions, and all three are reached
  through the Skill Aliases table in `global/CLAUDE.md` regardless.
  `user-invocable: true` is unchanged, so the keyword path still works.
  Counting rule for anyone auditing this: alias invocation never increments
  `skillUsage`, so a zero counter is not evidence of disuse. (#896)
- `HOOKS.md` documents the `PreToolUse`/`Bash` topology as it is configured.
  Sections 10-15 described individually-registered guards with per-guard
  timeouts, which is still true on POSIX but has not been true on Windows since
  the dispatcher landed. A new "Bash Guard Dispatcher (Windows)" section covers
  the routing table, the fail-closed/fail-open classification, the 25 s
  internal budget, and the standalone-invocation contract, and the affected
  guard sections now say which platform their timeout applies to. (#898)

### Fixed

- `git-identity.md` was copied under manifest guard and then rewritten in place
  by the identity seeder, which never updated the manifest. From that moment
  the manifest described a file that no longer existed on disk, so the next
  install found `srcSha != destSha` and `destSha != storedSha`, fell through to
  the divergence branch, and prompted the user to keep or overwrite a change
  the installer itself had made -- on every run, on both platforms. A drift
  audit on 2026-08-24 classified 281 of 282 manifest-tracked files as in sync;
  the single exception was this file. The seeder now runs on a staged copy of
  the source before the guarded copy, matching the shape
  `Invoke-GuardedTemplateCopy` already uses, so the manifest records what was
  deployed. Two further defects in the same block: the substitution was
  document-wide and rewrote the sentence explaining what the placeholders are
  ("replace the `YOUR NAME` / `YOUR EMAIL` placeholders by hand" came out
  naming the substituted values), and `Set-GitIdentitySeed` reported through
  `$script:` variables from inside a module, so both PowerShell installers
  printed `auto-filled from git config ( <>)` with empty values. The
  substitution is now anchored to the `name:` and `email:` lines and the
  function returns the values it seeded. `seed_git_identity` had no behavioural
  test at all; `tests/scripts/test-install-prompts.sh` is new. (#916)
- Publishing `~/.claude/settings.json` discarded every top-level key the repo
  profile does not define. All four full-install entry points stage the
  profile, inject the language policy into the staged copy, and move it over
  the destination; the destination was never read as part of that, and the only
  reads anywhere in the install recover two language values for the policy
  prompt. Measured on a live machine: three keys gone (`model`,
  `agentPushNotifEnabled`, `skipWorkflowUsageWarning`) plus `effortLevel` reset
  from `xhigh` to the profile's `high`, all four written by in-app controls
  rather than by hand-editing, and the run printed a green success line
  regardless. The staged copy now takes machine-local keys from the deployed
  file before the policy injection, so the policy still wins on the keys it
  owns: `language`, `permissions`, and `hooks` always come from the repo, and
  `env` is merged one level with the profile winning per key. `effortLevel` is
  the sole repo-defined key treated as runtime state, since `/effort` writes
  it. The run now names what it preserved. #780 solved this shape for two keys;
  this generalizes it. (#915)
- `scripts/verify.ps1` reported two failures that no non-destructive Windows
  action could clear -- `DIFF: settings.json` and `MISS: .claudeignore`, 176 of
  178 checks passing since before this release. Two unrelated causes.
  `global/.claudeignore` was deployed only by `install.sh`, although
  `docs/CLAUDE_DOCKER_CONTRACT.md` guarantees it under `~/.claude/` after a full
  install from any of the four entry points and claude-docker's entrypoint
  mirrors that layout into the container; `install.ps1`, `bootstrap.ps1`, and
  `bootstrap.sh` now deploy it too, manifest-tracked under key `.claudeignore`.
  Separately, the `settings.json` sync check compared the deployed file against
  `global/settings.json` even on Windows, where the published file comes from
  `global/settings.windows.json` -- and, more fundamentally, compared them line
  by line when the installer republishes settings.json through
  `ConvertTo-Json` (`jq` on POSIX) rather than copying bytes. Measured against
  the correct profile, 11 of ~516 lines matched in order for two files that
  differ by three top-level keys and one value, so the check could not pass on
  either platform. Both verifiers now select the profile the platform publishes
  and compare `permissions` and `hooks` semantically, leaving machine-local
  scalar preferences to #915. Prior art the earlier gates missed: #586 and #781
  added filename-specific parity checks that a non-hook `global/` asset walks
  past, and #821 gates settings parity between the two repo profiles rather
  than between the deployed file and its source. (#914)
- `scripts/install.sh` no longer copies `global/tmux.conf` to
  `~/.claude/tmux.conf`. tmux reads `~/.tmux.conf`, which `bootstrap.sh` and
  `bootstrap.ps1` install on both platforms; the `~/.claude/` copy was read by
  nothing, is absent from the guaranteed subtree, and was the only `global/`
  payload the two installers disagreed on. (#914)
- The three `PreToolUse` guards on the `Edit|Write|Read` matcher ran with
  `timeout: 5` while the Bash channel used 30. Nineteen runs exceeded that
  budget locally, and every one was followed by a successful tool call: a
  PreToolUse timeout is fail-open, so an over-budget security guard is skipped
  rather than given the chance to deny. The timeouts arrive in bursts of three
  with near-identical durations, meaning all three guards of one call die at
  the same deadline and that call runs with no coverage at all. Raised to 30 s,
  which covers the 11,141ms worst case over 35,276 runs with 2.7x headroom and
  would have prevented all nineteen. This reduces exposure without removing it
  (the Bash channel still recorded seven timeouts at 30 s), so `HOOKS.md` now
  states the fail-open semantics and how to distinguish a timeout from an Esc
  rather than leaving them to be rediscovered. (#897)
- Both settings profiles declared `"minimumVersion": "2.2.0"`, a floor above
  every shipped Claude Code release, so installing either one pinned the CLI at
  whatever version it already had. This is an *update floor*, not a startup
  guard: the CLI launches normally, which is why the setting looked inert when
  it was checked by running `claude -p`. `claude update` is where it bites, and
  it names itself when it does -- observed on 2.1.199: "The latest channel is at
  2.1.201, which is below your minimumVersion setting (2.2.0). Staying on
  2.1.199." Removed from `global/settings.json` and
  `global/settings.windows.json`; fixing only one would have left the same trap
  armed for the other platform. `COMPATIBILITY.md` now records the update-floor
  semantics, the observed recognition at 2.1.199 (the previous "2.2.0+" implied
  the key was ignored below that), and the rule that any value must be a
  version that has already shipped. The key remains valid in
  `scripts/schemas/settings-json.schema.json`; this repo simply does not set
  it. (#902)

### Known limitation

- The POSIX channel (`global/settings.json`) still registers its 14 `.sh`
  guards individually. The same stdin-drain constraint applies there, so a
  `.sh` dispatcher needs its own payload-passing mechanism and its own
  verification; shipping one unvalidated alongside a Windows-only measurement
  would be guesswork. Tracked as follow-up.

## 1.12.0 - 2026-08-01

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

- Rule frontmatter is now gated in CI. `scripts/validate-rule-frontmatter.sh`
  requires every `project/.claude/rules/**/*.md` file to declare either
  `alwaysApply: true` or `alwaysApply: false` paired with a non-catch-all
  `paths:` trigger, reporting `NO-FRONTMATTER`, `NO-PATHS-TRIGGER`,
  `CATCH-ALL-GLOB`, or `WRONG-KEY` (`globs:` written where the loader reads
  `paths:`). The guard runs from
  `.github/workflows/validate-rule-frontmatter.yml` on PRs touching the rules
  tree, and the job seeds one fixture per violation class — requiring a
  non-zero exit — plus a valid-frontmatter set that must pass, so the guard
  cannot degrade into a check that detects nothing. Documented in
  `docs/CUSTOM_EXTENSIONS.md` (#880).
- Skill drift across the distribution layers is now contractual and gated in
  CI. `skill-drift-contract.yml` declares, per skill name, which copies are
  paired and which divergences are accepted, and `scripts/check_skill_drift.py`
  (with `.sh` and `.ps1` entrypoints) compares `project/.claude/skills/`,
  `plugin/skills/`, and `plugin-lite/skills/` on the high-risk frontmatter
  fields — `allowed-tools`/`disallowed-tools`, `disable-model-invocation`,
  `user-invocable`, `argument-hint`, `paths`, `model`, `context`, `agent`,
  `severity`, `finding_levels`, `iso_class`, `safety_class`, and
  `applies_at_or_above` — plus the body text that defines the same behavior, so
  a shared skill cannot gain different permissions, routing, or mutation
  authority by accident. Formatting-only YAML differences are not failures. The
  contract is documented in `docs/SKILL_DRIFT_CONTRACT.md` and
  `docs/PLUGIN_BUILD.md`, wired into `validate-skills.yml`, and covered by Bash
  and PowerShell test suites (#827).

### Fixed

- The PowerShell Bash-channel guards now match their shell counterparts for
  relative `secrets/`, `credentials/`, and `passwords/` reads plus bare SSH-key
  and `credentials` read-write targets, while delimiter-aware boundaries keep
  ordinary names such as `credentials.md` allowed (#878).
- The Bash write guards now reject unexpanded `*`/`?` targets that bracket an
  env-file token, closing redirect and write-tool forms such as
  `echo y > *.env*` and `tee *.env*` while preserving ordinary globs and the
  explicit env-template allow-list (#876).
- `tests/issue-work/test-triage.sh` now creates its scratch directory from an
  explicit `${TMPDIR:-/tmp}/iw-triage-test.XXXXXX` template, matching the four
  sibling Bash suites and remaining usable when a sandbox exposes a writable
  temp root outside the system default (#873).
- The `issue-work` PowerShell ports now route every git invocation through
  their stage-specific wrapper (`_workspace_git`, `_agents_git`, or
  `_cleanup_git`) instead of leaving those wrappers unused while bypassing
  them through `$script:GitBin`. The wrapper comments and Bash parity now
  match reality, and `GIT_BIN` remains a single control seam (#872).
- Sensitive-file guards now classify suffix/template hybrids such as
  `prod.env.example` and `staging.env.sample` as env files instead of letting
  the file and plugin channels allow them by fall-through. The explicit
  `*.env.*` deny class is aligned across Bash, PowerShell, and the plugin while
  the four recognised dotfile-prefix templates remain allowed (#868).
- `HOOKS.md` now scopes sensitive-file targets to the full global suite, lists
  its SSH-key and AWS-credential patterns, and identifies the plugin-only
  `private/` addition and stand-down behavior instead of presenting the union
  of both guards as one pattern set (#861).
- `docs/deep-audit-2026-05-29.md` now reconciles all 20 findings in the
  `hooks-parity`, `settings-schema`, and `hooks-correctness` clusters against
  the current working tree and landed PRs. The dated status log replaces the
  stale Executive Summary claim that Windows secret/write and memory guards
  are dormant, while preserving every original finding body as the immutable
  May audit record. The reconciliation also closes its two live residuals:
  `global/settings.windows.json` now carries the three-hook ordering note, and
  `scripts/backup.sh` makes `error()` terminal so failed initial copies cannot
  fall through to a success message; the installer robustness suite now pins
  that contract. `sync.ps1` option 4 is recorded as an accepted Bash-only
  exception because the PowerShell menu explicitly rejects it before dispatch,
  preventing the unsafe overwrite path identified by the audit (#857).
- `safe_rm_rf` now makes the same allow-list decision on Linux and macOS.
  Both deletion targets and the fixed `HOME`/`/tmp` roots are canonicalized,
  so macOS's `/tmp -> /private/tmp` symlink no longer rejects legitimate
  `claude-*` scratch paths. The helper also uses portable `realpath` instead of
  GNU-only `realpath -e`; an explicit resolved-target existence check preserves
  fail-closed behavior for broken symlinks. The regression suite now builds
  outside fixtures beneath canonical `/tmp`, avoids platform-specific
  `/etc/hostname`, runs in the Linux/macOS `validate-hooks` matrix, and is no
  longer classified as manual-only (#851).
- `bash-write-guard.ps1` no longer denies read-only `awk`. The uninspectable arm
  matched the bare command word `\b(awk|gawk|mawk)\b`, so every awk invocation was
  denied regardless of what the program did — `ps aux | awk '{print $2}'` and
  `awk -F'|' '{print $1}'` included. The guard now tokenizes the command and
  inspects only the awk PROGRAM token, denying when it carries `>` or `|`, which
  is what `bash-write-guard.sh` has always done; flag values (`-F'|'`, `-F '|'`,
  `-v sep='a|b'`) are skipped so a field separator cannot read as a write
  operator, and the tokenizer honours backslash escapes so
  `awk "BEGIN{print \"x\" > \"f\"}"` is not truncated before its redirect. The
  six read-only cases pinned in `tests/hooks/test-bash-write-guard.ps1` as an
  approximation artifact are unpinned and now assert the same decision as the
  bash suite (67 assertions, 398 across the hooks runner, all passing).
  Sensitive-target and read-before-write coverage is unchanged: both scan the raw
  command string, so an in-program `print > "~/.ssh/id_rsa"` is still denied.
- `project/.claude/rules/workflow/branching-strategy.md` no longer claims that CI
  runs only on PRs targeting `main` and that feature PRs to `develop` trigger
  nothing. CI scope is decided per workflow by the `pull_request` `branches:`
  filter; a trigger with no filter fires on every base branch, `develop`
  included. The rule is always-loaded, so the wrong claim mis-steered every
  session that read it — including into treating a `develop` PR as costing no CI
  time. It now states the mechanism and tells the reader to check the filters
  under `.github/workflows/` rather than assume either way.
- The five rule files fixed in #880 are now recorded here. `compliance/README.md`
  carried no frontmatter, `workflow/performance-analysis.md` used a catch-all
  `paths: ["**/*"]`, and `workflow/git-conflict-resolution.md`,
  `workflow/github-pr-5w1h.md`, and `workflow/github-issue-5w1h.md` declared
  `alwaysApply: false` with no `paths:` trigger — which the loader reads as "no
  condition" rather than "off", the opposite of the intent and invisible in the
  frontmatter. Each now carries a scoped trigger; no rule prose changed. The
  always-resident set went from 11 files (~6,496 est. tokens) to 6 (~2,516), and
  `docs/TOKEN_OPTIMIZATION.md`, whose 2026-03-21 measurement had drifted, was
  re-measured (#880).

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
  README one-line examples now track `VERSION_MAP.yml` `suite` (`v1.12.0`);
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
- `bootstrap.sh` and `bootstrap.ps1` now deploy the `global/scripts/` utility
  scripts into `~/.claude/scripts` during installation. The statusline,
  team-report, and weekly-usage scripts referenced by the shipped settings were
  never copied, so a fresh bootstrap produced a `settings.json` pointing at
  files that did not exist. Deployment runs before `settings.json` is replaced
  and a failure is fatal, so a partial install cannot leave the settings file
  swapped in against missing scripts; both atomic-deploy suites assert the new
  step (#818).
- The four `Write()` env deny entries are removed from `global/settings.json`
  and `global/settings.windows.json`. File permission checks never match
  `Write(path)` rules — the harness warned about each one at session startup —
  while the existing `Edit(path)` rules already cover every file-editing tool
  (`Edit`, `Write`, `NotebookEdit`), so the entries were inert rather than
  protective. The Windows permissions regression test now requires only
  `Edit(.env)` and fails if any `Write()` deny entry reappears. Bumps
  settings-schema to 1.17.1 (#836).

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

[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.12.0...HEAD
