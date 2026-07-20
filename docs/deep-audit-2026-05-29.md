# Deep Audit — claude-config (2026-05-29)

> **Maintenance model**: this document is a point-in-time record of the audit taken on 2026-05-29. Finding bodies are preserved exactly as written and are **not** rewritten when a finding is resolved, so the state the audit actually observed stays auditable. Resolution is recorded additively in the reconciliation log below, which is the authoritative status source. Consult it before acting on any finding — an unreconciled cluster carries no implication either way.

Multi-agent audit across 12 dimensions. Each finding was adversarially verified (a second agent read the actual files and checked whether the issue was a genuine defect or an intentional, documented design choice).


- **Confirmed findings**: 67 (of 82 raw; 15 rejected as intentional/speculative)
- **Severity**: high 5, medium 26, low 30, info 6
- **Category**: defect 19, inconsistency 28, risk 10, tech-debt 9, improvement 1


## Status as of 2026-07-20 — `tests-ci`

Reconciliation scope: the `tests-ci` cluster and the two sub-items of the [P0] CI-enforcement roadmap entry that cover it. Every other cluster in this document is unreconciled and still reads as of 2026-05-29.

| Finding | Status | Closed by | Verified state on 2026-07-20 |
|---------|--------|-----------|------------------------------|
| `hook-json-escape-tests-orphaned` | Resolved | #833 (PR #852), #850 (PR #854) | All three suites run as explicit steps in the `test` job of `validate-hooks.yml`. |
| `powershell-hooks-never-executed-in-ci` | Resolved | #821 (PR #826) | `tests/hooks/test-runner.ps1` executes twice per PR: under `pwsh` on the ubuntu/macos matrix in the `test` job, and natively in the dedicated `windows-powershell-hooks` job on `windows-latest`. |
| `orphaned-script-and-regression-tests` | Resolved | #823 (PR #834), #833 (PR #852) | All thirteen named suites are wired across `validate-hooks.yml` and `validate-skills.yml`. `test-windows-hooks-parity.sh` is wired and now passes, contradicting the finding's "currently FAILS" note. |
| `batch-drift-regression-stale-result-pass` | Resolved | #855 | Grading is now restricted to result files written after a run-start marker, and a non-zero benchmark exit is fatal instead of a warning, so a run that produces no fresh result fails rather than grading a pre-existing file. The committed results the finding names are retained as benchmark evidence and are excluded by the timestamp guard rather than by deletion. |

Two meta-gates now enforce the wiring contract the resolved findings asked for, so this class of finding is self-detecting rather than dependent on the next manual audit:

- `tests/scripts/test-ci-wiring.sh` (#823, PR #834) owns `tests/scripts/test-*` and counts only executable workflow run commands as wiring — path-filter mentions and comments do not qualify.
- `tests/scripts/test-nonstandard-test-wiring.sh` (#833, PR #852) extends the same contract repo-wide to every other tracked `.sh`/`.ps1` under `tests/`, requiring each to be wired, swept by a wired shared runner, or classified in `tests/nonstandard-test-registry.txt` with a recorded risk and removal condition.

**[P0] "Add CI enforcement that catches the parity gaps this audit found"** — sub-items (2) (wire the orphaned suites) and (3) (a windows-latest or pwsh leg running `tests/hooks/test-runner.ps1`) are satisfied by the wiring above; sub-item (3) was implemented as both legs, not one. Sub-item (1) (settings-file hook-set and `permissions.allow` diffing) belongs to the `settings-schema` cluster and is outside this reconciliation's scope; note only that equivalent gates have since landed in `validate-hooks.yml` rather than in `validate-hooks-doc.yml` as the roadmap specified, so it should not be read as outstanding — confirming it is the `settings-schema` reconciliation's job. The supporting paragraph's claim that `test-windows-hooks-parity.sh` "fails today but runs in no workflow" is stale on both counts.

Fragments of the resolved findings that remain factually accurate, recorded so a future reader does not discard a whole finding as stale:

- `tests/hooks/test-runner.sh` still globs only its own directory, so the `tests/` root suites are reached by explicit workflow steps rather than by runner discovery.
- The parity job in `validate-hooks-doc.yml` still asserts only that same-basename `.ps1` counterparts exist and that the counts match; it executes nothing.
- The "exercised when the InstallerFetch matrix lands a Windows runner" concession still exists in `validate-hooks.yml`, but has moved and now scopes only to `tests/plugin/smoke-test.ps1`.

## Executive Summary

This audit of the claude-config repository confirms 56 real findings, dominated by a single structural problem: the repo maintains the same logical artifact in multiple parallel copies (bash hooks vs. PowerShell hooks, global settings vs. Windows settings, rules/ SSOT vs. plugin/ inlined copies, README vs. actual inventory) but enforces consistency on only a fraction of these pairings. The result is silent drift, and in several cases that drift has concrete security and correctness consequences.

The most serious cluster is cross-platform security divergence. On Windows, three Bash-channel secret guards (bash-sensitive-read-guard, bash-write-guard, gh-write-verb-guard) and three memory-protection hooks exist as fully-implemented .ps1 files but are never wired into settings.windows.json, so `cat .env`, `type ~/.aws/credentials`, writes to existing files, and unscoped gh write verbs are unguarded — while the documentation (ENFORCEMENT.md, HOOKS.md) advertises these as active fail-closed layers with no Windows caveat. The merge-gate squash-only enforcement and PR-target hardening (#616) are also missing from their .ps1 ports, and a case-sensitivity bug lets `.ENV`/`.NETRC` bypass the POSIX secret guards entirely on case-insensitive filesystems (macOS/Windows).

A second cluster is missing CI enforcement. The CI parity audit checks only that a same-basename .ps1 file EXISTS, never that it is wired into settings.windows.json or that it behaves correctly — which is precisely why the dormant-guard gap shipped on the default branch. No CI job ever executes PowerShell hooks behaviorally, and roughly a dozen genuine regression suites (including three JSON-injection suites covering 15 guards, plus test-windows-hooks-parity.sh which currently FAILS) are invoked by no workflow at all.

A third cluster is the unguarded plugin/rules drift: ~29 plugin reference files inline rules/ content but only 4 are sync-checked, and they have measurably diverged; plugin agents are near-duplicate copies with no SSOT.

The remaining findings are documentation staleness (counts, version footers, hook catalogs, README trees), a dead `hooks` version track that no tool reads or syncs, and the /release skill's inability to bump or tag non-suite tracks correctly. Two installer/backup scripts have silent-data-loss / wrong-config defects from a non-exiting error() helper used as `cmd || error`.

Root cause across nearly all findings: the repo creates parallel copies faster than it builds the SSOT + CI-diff machinery to keep them in sync. The fix architecture already exists (sync_references.sh, the hooks/lib validate-commit-message diff check, VERSION_MAP.yml) — it simply needs to be extended to cover every parallel pair, and CI must verify wiring and behavior, not just file existence.


## Root-Cause Themes

- Cross-platform parity is asserted but not enforced: .ps1 hooks are authored as 'mirrors' of canonical .sh hooks and CI claims 100% parity, but parity is only file-existence-deep. Behavioral logic, wiring into settings.windows.json, regex sets, exit-code handling, and permission allowlists have all silently diverged — several with direct security impact (dormant secret guards, missing squash-only/PR-target enforcement, attribution false-positives, typographic false-denies).
- Parallel copies without an enforced single-source-of-truth: the repo duplicates the same logical artifact across trees (rules/ vs plugin/ reference files, plugin/agents vs project/.claude/agents, global vs Windows settings, README trees vs actual inventory, CHANGELOG.md vs README changelog) but wires the sync/diff guard for only a small subset. The machinery to prevent this (sync_references.sh, hooks/lib diff check) exists but was never extended to all pairs.
- CI verifies existence, not behavior or wiring: the parity audit greps for same-basename files; no job runs PowerShell hooks behaviorally, no job diffs the hook arrays between the two settings files, and ~12 real regression suites (including one that currently fails) are discovered by no runner — so whole classes of regression and drift ship green.
- Case-sensitivity and pattern-matching bugs in shell guards: secret-file deny-lists compute a lowercased copy but then match against the un-lowered path, and a scope-gate regex matches 'gh ' unanchored as a substring — both producing wrong allow/deny decisions that the structured-tool channel handles correctly.
- Documentation drift from hardcoded values that outran reality: hook counts (32 vs 37), version footers (v1.6.0 vs 1.10.0), event-type tables, README directory/agent/skill trees, and HOOKS.md section content all hold stale literals where a generated/SSOT-derived value should be — the same VERSION_MAP/auto-gen SSOT pattern the repo already uses elsewhere.
- Incomplete lifecycle/governance for declared-but-unwired constructs: the 'hooks' version track is declared in VERSION_MAP.yml with governance prose but read by no checker/syncer/release path; the /release skill cannot bump or correctly tag non-suite tracks; expired P4 timeline hooks fire permanently as no-ops; tier presets are 'Required' in policy but adopted only incrementally in practice.
- Shell-script robustness anti-pattern: a non-exiting error() helper used as `cmd || error` under set -e suppresses errexit, so failed copies in backup.sh (after a destructive delete) and install.sh (enterprise policy file) continue and report success — silent data loss / silently incomplete install.

## Prioritized Roadmap


### [P0] Wire the six missing security/memory hooks into settings.windows.json: add bash-sensitive-read-guard.ps1, bash-write-guard.ps1, gh-write-verb-guard.ps1, and traceability-guard.ps1 to the Bash matcher (preserving the POSIX .sh ordering and timeouts), and add memory-write-guard.ps1 (after pre-edit-read-guard.ps1), memory-integrity-check.ps1 (SessionStart), and memory-access-logger.ps1 (PostToolUse Read, async 5s). These .ps1 files already exist and are fully implemented; they are simply unregistered, leaving Windows users with no Bash-channel secret-read/write protection and no memory guarding that the docs claim are active.  _(effort: S)_

Highest-impact, lowest-effort fix in the audit: a documented fail-closed security control (secret exfiltration / unguarded writes / memory protection) is completely inactive on Windows. The fix is purely additive JSON registration of existing scripts, with no logic to write. Also fix the stale two-hook _note comment in the Windows Edit|Write|Read matcher to match the POSIX three-hook wording (#521) once memory-write-guard is wired.


_Findings: `win-missing-bash-tool-guards`, `win-missing-memory-hooks`, `windows-bash-secret-guards-not-wired`, `win-note-comment-stale`_

### [P0] Fix the case-sensitivity secret-guard bypass in bash-write-guard.sh and bash-sensitive-read-guard.sh: match the .env-family, SSH-key, .aws, .netrc/.npmrc/.pypirc, and system-credential globs against the already-computed $lower (as is already done for *.pem and the secrets/ dirs), mirroring sensitive-file-guard.sh's deliberate case-folding. Add deny fixtures for .ENV/.Env/.Envrc/.NETRC and uppercased SSH-key names to both test corpora.  _(effort: S)_

On case-insensitive filesystems (macOS default, Windows), `.ENV` is the same file as `.env`, so `cat .ENV` / `echo secret > .ENV` bypass the only guard covering the cat/grep/redirect channel (permissions.deny covers only the Read/Write/Edit tools). The lowercased variable is already computed — this is a one-line-per-branch fix that closes a live secret read/write bypass.


_Findings: `bwg-env-case-bypass`, `bsrg-env-case-bypass`_

### [P0] Add CI enforcement that catches the parity gaps this audit found: (1) extend the parity job in validate-hooks-doc.yml to parse both settings files, normalize each hook to its basename, and fail if per-event hook sets diverge except for a documented POSIX-only allowlist; also diff the permissions.allow arrays. (2) Wire the orphaned regression suites into CI — add the three tests/hook-json-escape*.sh suites and the unrun tests/scripts/*.sh suites (especially test-hook-ordering.sh, test-windows-hooks-parity.sh which currently FAILS, and test-installer-fetch.sh) to validate-hooks.yml/validate-skills.yml. (3) Add a windows-latest (or pwsh) leg that runs tests/hooks/test-runner.ps1 so .ps1 hooks get behavioral execution, not just file-existence parity.  _(effort: M)_

The wiring/behavior gaps in the two P0 security items above shipped on the default branch precisely because CI checks only same-basename file existence. test-windows-hooks-parity.sh already encodes the correct assertion and fails today but runs in no workflow. Wiring these gates is what prevents this entire class of finding from recurring, and converts ~12 existing-but-dark regression suites into active protection.


_Findings: `no-ci-parity-check-for-hook-wiring`, `parity-ci-checks-files-not-wiring`, `powershell-hooks-never-executed-in-ci`, `hook-json-escape-tests-orphaned`, `orphaned-script-and-regression-tests`_

### [P1] Restore behavioral parity in the divergent PowerShell guard logic: (1) merge-gate-guard.ps1 — add the squash-only --merge/--rebase deny block after the scope gate; (2) pr-target-guard.ps1 — block both main and master and resolve the repo default branch (with the override env var) when --base is absent, mirroring the #616 hardening; (3) commit-message-guard.ps1 — replace the broad attribution substring regex with the three-pattern logic (factor a Test-NoAttribution helper from attribution-guard.ps1); (4) memory-write-guard.ps1 — fail-closed on secret-check exit code 2 (#618); (5) LanguageValidator.psm1 — allowlist the English typographic code points (U+2014/2013/201C/201D/2018/2019/2026/00A0) per #583; (6) sensitive-file-guard.ps1 — add SSH-key and .aws cases; (7) bash-write-guard.ps1 — extend Read-before-Edit to argv targets (or document the redirect-only limit). Add or extend the corresponding parity/behavioral tests for each.  _(effort: L)_

These are all confirmed behavioral divergences between a canonical .sh and its supposed-mirror .ps1, several with real impact: merge-gate and pr-target weaken branching enforcement on Windows; the attribution and typographic regexes over-block legitimate commits/PRs on Windows; memory-write-guard fails open in the common OWNER_EMAILS-unset state. The project's documented invariant is byte-for-byte decision parity, so each gap is a defect against a stated contract. Effort is moderate because each is a contained, well-specified port with an existing test pattern to follow.


_Findings: `merge-gate-guard-ps1-missing-squash-only`, `pr-target-guard-ps1-stale-master-and-default-branch`, `commit-msg-guard-ps1-broad-attribution-regex`, `memory-write-guard-ps1-missing-secret-rc2`, `language-validator-ps1-missing-typographic-allowlist`, `sensitive-file-guard.ps1`, `windows-sensitive-file-guard-missing-ssh-aws`, `bash-write-guard-ps1-no-readbefore-on-argv-targets`_

### [P1] Establish an enforced SSOT for the plugin reference files and agents. Extend the canonical->mirror map in scripts/check_references.sh + sync_references.sh (and their .ps1 twins) to cover ALL plugin/skills/*/reference/* files that mirror rules/ (not just the 4 project-workflow files), then run sync to re-sync the ~29 currently-drifted copies — including the github-pr-5w1h.md mirror that drifted even within the declared scope. For the 8 near-duplicate agents, add a CI diff that asserts the shared body sections match between plugin/agents and project/.claude/agents (or adopt a body+per-layer-frontmatter overlay generated by sync), reusing the diff -q pattern already proven for hooks/lib/validate-commit-message.sh.  _(effort: M)_

PLUGIN_BUILD.md mandates plugin trees be self-contained copies that MUST match canonical, enforced by CI diff — but that enforcement is wired for only the commit-message lib and 4 refs, while ~29 reference files have silently diverged and are actively imported (security-audit/SKILL.md @./reference/security.md). The remedy aligns with the documented design; the agents need the same proven diff-guard before they drift on the next edit.


_Findings: `plugin-skill-refs-drift-unguarded`, `plugin-agents-near-duplicate-unguarded`_

### [P1] Fix the bootstrap.ps1 wrong-settings defect and the silent-data-loss script helpers. (1) bootstrap.ps1 Install-GlobalSettings: source global/settings.windows.json on Windows (mirroring install.ps1:441), not the Unix settings.json whose hooks point at .sh scripts; add a drift test asserting bootstrap.ps1 and install.ps1 select the same settings source per platform. (2) backup.sh and install.sh: make error() exit (or replace `cmd || error` with `cmd || { error; exit 1; }`) for destructive/critical copies; in backup.sh prefer copy-then-swap so a failed copy never leaves a wiped backup directory; fix the same non-exiting pattern in backup.ps1.  _(effort: M)_

bootstrap.ps1 installs a config that points every hook at a nonexistent .sh script on native Windows. backup.sh can delete a backup directory then silently fail to repopulate it and still print success (true data loss reported as success); install.sh can report install-complete with the highest-precedence enterprise policy file never written. All three stem from the non-exiting error()-as-guard anti-pattern that the sibling bootstrap.sh avoids.


_Findings: `bootstrap-ps1-wrong-settings-windows`, `backup-sh-silent-dataloss-cp-after-delete`, `install-sh-error-fn-suppresses-errexit`_

### [P1] Fix the github-api-preflight scope-gate overmatch and the markdown-anchor-validator CJK divergence. (1) Anchor the gh detection in github-api-preflight.sh to a word boundary `(^|[[:space:]`(])gh[[:space:]]` (reusing gh-write-verb-guard's pre-filter) so benign words like 'high'/'weigh' no longer trigger a network curl on every Bash call; also drop the `^` anchor on the auth-status branch so `cd x && gh ...` gets the diagnostic. (2) Make markdown-anchor-validator anchor generation Unicode-aware on both sides — switch the .sh from locale-dependent `[:alnum:]` to a perl `\p{L}\p{N}\p{Pc}` transform matching the .ps1, and add Korean/CJK fixtures asserting byte-identical anchors across platforms.  _(effort: M)_

The unanchored 'gh ' matcher fires a network curl (timeout 10) on unrelated commands, adding latency and false 'GitHub unreachable' context. The anchor validator can build different anchor registries on the same tree when the .sh locale fallback lands on C (Hangul stripped to empty anchor) vs the always-Unicode .ps1 — a real allow/deny divergence in a repo that uses Korean headings heavily and has only ASCII fixtures.


_Findings: `gap-matcher-overmatch`, `gap-authcheck-undermatch`, `markdown-anchor-validator-cjk-charclass-divergence`_

### [P1] Fix the /release multi-track defects and govern the hooks version track. (1) Add `hooks` to the /release --target alternation, argument-hint, Options, and Version Source table; add the hooks consumer to sync_versions and check_versions so --target hooks actually bumps and propagates instead of silently falling back to suite. (2) In release Step 8, use the $TAG_NAME computed in Step 7 for `gh release create` and the Output template, so non-suite releases tag and publish consistently instead of creating a mismatched v$VERSION tag. (3) Either give the hooks track a real consumer (e.g. gen-hooks-md.sh emits a 'Hooks bundle version' line into HOOKS.md and check_versions asserts it) or correct VERSION_MAP.yml line 14 to drop the false 'surfaced to operators' claim and document hooks as an ungoverned label with a SemVer-validity assertion.  _(effort: M)_

VERSION_MAP.yml declares hooks as a governed, /release-bumpable, operator-surfaced track, but no checker/syncer/release path reads it, --target hooks degrades to suite, the value appears in neither HOOKS.md nor ENFORCEMENT.md, and Step 8 hardcodes v$VERSION so plugin/plugin-lite/settings-schema releases create a wrong tag pointing at an unpushed/colliding ref. These are self-contradicting governance defects that produce wrong release artifacts for every non-suite track.


_Findings: `hooks-field-never-checked-or-synced`, `release-target-excludes-hooks`, `release-gh-create-hardcodes-suite-tag`, `version-map-false-doc-claim-hooks-surfaced`_

### [P2] Reconcile the documentation that drifted from reality, preferring SSOT-derived values over hardcoded literals. Update: COMPATIBILITY.md parity count 32->37 (or derive from the CI-tracked HOOKS.md total), its hook-event table (rename PostToolUseFailure->ToolFailure, add CwdChanged/InstructionsLoaded/TaskCreated/PostCompact rows), and its stale v1.6.0/2026-04-17 footer. Fix HOOKS.md section 12 heading (H2->H3) and rewrite its no-base PR-target behavior to match the shipped #616 default-branch resolution. Sync README.md/README.ko.md Agents tables (add dependency-auditor, test-strategist), the _internal skills trees (add the 6 missing skills; rewrite the ko tree's structure), the hooks trees (replace the hand list of 19 with a pointer to the CI-verified HOOKS.md catalog), and the lib/ subtree listings; align plugin-lite README/plugin-vs-global.md hooks rows and plugin/README structure block with shipped contents.  _(effort: L)_

These are confirmed factual inaccuracies in user- and maintainer-facing docs, several internally self-contradicting (COMPATIBILITY's hardcoded 32 sits two lines above a live-count command returning 37; HOOKS.md section 12 documents the exact pre-#616 vulnerable behavior the fix removed). Grouping them is efficient and the durable fix is to point at the existing auto-generated/CI-verified SSOTs rather than maintain hand lists that re-drift.


_Findings: `compat-pwsh-parity-count-stale`, `compat-hook-event-table-incomplete-and-wrong`, `compat-footer-stale-version-date`, `hooks-md-section12-h2-and-stale-content`, `readme-agents-section-missing-two-agents`, `readme-internal-skills-tree-missing-six`, `readme-hooks-tree-missing-17`, `readme-tree-lib-dirs-understated`, `plugin-lite-readme-hooks-contradiction`, `plugin-readme-structure-omits-shipped-dirs`, `plugin-bundled-lib-no-consumer`_

### [P2] Finalize the expired P4 timeline rollout and harden the dangerous-command-guard allow-shape and JSON-emission consistency. (1) P4: decide the terminal state (flip p4_strict_schema to true and retire the hooks, or remove strict mode), then delete the four p4-timeline hook files, their six settings registrations, the policy file, and the HOOKS.md entries — they currently fire on every Bash/Edit/Write/SessionStart but can never block or print. (2) Convert github-api-preflight.sh and prompt-validator.sh JSON emitters to `jq -nc --arg` to match the rest of the hardened suite. (3) Standardize the dangerous-command-guard allow-path diagnostic field (additionalContext vs permissionDecisionReason) across .sh/.ps1.  _(effort: M)_

The P4 windows all expired 2026-05-20, leaving dead always-firing guards as pure overhead; the rollout needs a terminal decision. The two heredoc-interpolation emitters are the exact injection class issues #567/#578/#579 banned elsewhere — harmless today (static literals only) but a regression waiting to be reintroduced. The dangerous-command-guard field mismatch is cosmetic but trivially unifiable.


_Findings: `p4-timeline-windows-all-expired`, `gap-heredoc-not-jq`, `dangerous-command-guard-allow-shape-mismatch`_

### [P2] Add self-documenting loop-safety/side-effect sections and reconcile the tier-preset policy wording. (1) Add a short '### Side Effects and Loop-Safety' note to the 9 loop_safe:false skills that lack one (issue-work, pr-work, release, harness, branch-cleanup, issue-create, implement-all-levels, fleet-orchestrator, sonar-fix) and to traceability (whose loop metadata has no body content), using the evidence-pack section as template; optionally tighten validate_skills.sh to grep only the post-frontmatter body so the drift check cannot be self-satisfied by frontmatter keys. (2) Soften _policy.md line 135 tier presets from 'Required' to 'Recommended; adopted incrementally' with a cross-link to the TOKEN_OPTIMIZATION.md phased rollout (or schedule tier adoption for the ~10 oversized skills).  _(effort: M)_

The validator already warns for these, and the non-idempotency contract currently lives only in a frontmatter boolean rather than self-documenting prose. The tier 'Required' wording makes a strict reader conclude 10 skills are non-conformant while the rollout doc says they are not — a normative-vs-practice contradiction the same file knows how to mark (it uses grace-period language elsewhere).


_Findings: `loop-safe-false-missing-side-effect-section`, `traceability-loop-metadata-no-loop-body`, `tier-presets-missing-on-oversized-skills`_

### [P3] Clean up the remaining low-impact consistency and robustness nits: reconcile fleet-orchestrator flag drift (--retry->--max-retries in the argument-hint, document or remove --dry-run, add --resume to the hint) including the docs/fleet-orchestrator.md copy-paste examples; tighten the Windows git fetch allowlist to the two scoped origin/upstream entries; quote $BACKUP_DIR in backup.sh's ls -A summary checks and add 2>/dev/null to the two missing lines; add a Test-Path guard before bootstrap.sh sources installer-fetch.sh; add an explicit non-interactive (--yes / env-flag + TTY detection) mode to the installers; constrain sync_versions' global "version" sed to the first/top-level match plus a uniqueness assertion; document the per-call pwsh cold-start cost in COMPATIBILITY.md; port sync.ps1's missing option-4 interactive merge (or explicitly reject 4); add a behavioral test for conflict-guard.sh; add tests/markdown-anchor-validator/** to the validate-hooks.yml path filter; backfill the CHANGELOG per-version sections at next release; and delete the stale err.log scratch artifact.  _(effort: L)_

Individually minor (low/info severity, mostly doc/UX/robustness polish or latent risks), but cheap to batch and they remove rough edges, untested gaps, and brittle assumptions that could become real defects later (e.g. a second JSON version key, a path with spaces, an out-of-range sync direction silently overwriting a backup).


_Findings: `fleet-orchestrator-arg-hint-flag-drift`, `fleet-orchestrator-resume-flag-missing-from-hint`, `git-fetch-allow-divergence`, `backup-sh-unquoted-backupdir-wordsplit`, `installer-fetch-source-unguarded-bootstrap-sh`, `installers-no-noninteractive-flag`, `sync-json-version-global-regex-fragility`, `windows-pwsh-cold-spawn-per-hook`, `sync-ps1-missing-interactive-merge`, `conflict-guard-no-behavioral-test`, `validate-hooks-path-missing-anchor-fixtures`, `changelog-no-released-sections`, `changelog-only-tracks-suite-no-per-version-sections`, `markdown-validator-double-registered`, `win-permissions-allow-narrower`, `deny-list-narrower-than-guards-by-design-gap`, `p4-guard-unbounded-gh-diff`, `batch-drift-regression-stale-result-pass`, `stale-err-log-root`_


## Confirmed Findings (by severity)


| Sev | Dim | ID | Title | Files |
|---|---|---|---|---|
| high | hooks-correctness | `bsrg-env-case-bypass` | bash-sensitive-read-guard allows reading .ENV/.Env (same case-sensitivity bypass) | global/hooks/bash-sensitive-read-guard.sh |
| high | hooks-parity | `merge-gate-guard-ps1-missing-squash-only` | merge-gate-guard.ps1 omits the squash-only enforcement block, allowing gh pr merge --merge/--rebase on Windows | global/hooks/merge-gate-guard.ps1, global/hooks/merge-gate-guard.sh |
| high | hooks-parity | `sensitive-file-guard-ps1-missing-ssh-aws` | sensitive-file-guard.ps1 does not block SSH private keys or AWS credential files that the .sh blocks | global/hooks/sensitive-file-guard.ps1, global/hooks/sensitive-file-guard.sh |
| high | security-surface | `windows-bash-secret-guards-not-wired` | bash-sensitive-read-guard / bash-write-guard / gh-write-verb-guard exist as .ps1 but are NOT wired into settings.windows.json — Windows users get no Bash-channel secret protection | global/settings.windows.json, global/hooks/bash-sensitive-read-guard.ps1 |
| high | settings-schema | `win-missing-bash-tool-guards` | Four PreToolUse Bash-matcher guards wired on POSIX are absent on Windows though their .ps1 files exist | global/settings.json, global/settings.windows.json |
| medium | architecture | `plugin-skill-refs-drift-unguarded` | plugin/ skill reference files inline rules/ content but only 4 of ~33 are drift-guarded; the rest have already diverged | plugin/skills/coding-guidelines/reference/quality.md, plugin/skills/security-audit/reference/security.md |
| medium | architecture | `plugin-agents-near-duplicate-unguarded` | plugin/agents and project/.claude/agents are near-identical duplicates (2-5 differing lines each) with no SSOT or drift guard | plugin/agents/code-reviewer.md, project/.claude/agents/code-reviewer.md |
| medium | docs-consistency | `compat-pwsh-parity-count-stale` | COMPATIBILITY.md PowerShell parity table says 32/32 hooks; actual is 37/37 | D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/HOOKS.md |
| medium | docs-consistency | `hooks-md-section12-h2-and-stale-content` | HOOKS.md section 12 is H2 (breaks numbered hierarchy) and its no-base behavior is stale vs the shipped #616 fix | D:/Sources/claude-config/HOOKS.md, D:/Sources/claude-config/global/hooks/pr-target-guard.sh |
| medium | hooks-correctness | `bwg-env-case-bypass` | bash-write-guard allows writes to .ENV/.Env (case-sensitivity bypass of .env protection) | global/hooks/bash-write-guard.sh |
| medium | hooks-correctness | `gap-matcher-overmatch` | github-api-preflight matcher fires a network curl on any command ending in 'gh ' | global/hooks/github-api-preflight.sh |
| medium | hooks-parity | `commit-msg-guard-ps1-broad-attribution-regex` | commit-message-guard.ps1 uses the old broad attribution substring match the .sh deliberately replaced (false-positive divergence) | global/hooks/commit-message-guard.ps1, global/hooks/commit-message-guard.sh |
| medium | hooks-parity | `pr-target-guard-ps1-stale-master-and-default-branch` | pr-target-guard.ps1 is stale: it never blocks 'master' and never resolves the repo default branch, unlike the hardened .sh | global/hooks/pr-target-guard.ps1, global/hooks/pr-target-guard.sh |
| medium | hooks-parity | `memory-write-guard-ps1-missing-secret-rc2` | memory-write-guard.ps1 does not fail-closed on secret-check.sh exit code 2 (OWNER_EMAILS not configured) | global/hooks/memory-write-guard.ps1, global/hooks/memory-write-guard.sh |
| medium | hooks-parity | `language-validator-ps1-missing-typographic-allowlist` | LanguageValidator.psm1 'english' policy rejects em-dash/en-dash/curly-quotes/ellipsis/NBSP that the bash validators allow (issue #583) | global/hooks/lib/LanguageValidator.psm1, hooks/lib/validate-language.sh |
| medium | hooks-parity | `markdown-anchor-validator-cjk-charclass-divergence` | markdown-anchor-validator anchor generation uses POSIX [:alnum:] (.sh) vs Unicode \p{L}\p{N} (.ps1), risking different anchors for Korean/CJK headings | global/hooks/markdown-anchor-validator.sh, global/hooks/markdown-anchor-validator.ps1 |
| medium | scripts-robustness | `bootstrap-ps1-wrong-settings-windows` | bootstrap.ps1 installs Unix settings.json (sh-based hooks) on Windows instead of settings.windows.json | D:\Sources\claude-config\bootstrap.ps1, D:\Sources\claude-config\scripts\install.ps1 |
| medium | scripts-robustness | `backup-sh-silent-dataloss-cp-after-delete` | backup.sh can wipe a backup directory then silently fail to repopulate it (cp \|\| error with non-exiting error) | D:\Sources\claude-config\scripts\backup.sh |
| medium | scripts-robustness | `install-sh-error-fn-suppresses-errexit` | install.sh error() is non-exiting and used as `cp \|\| error`, so failed enterprise/lib copies continue silently | D:\Sources\claude-config\scripts\install.sh |
| medium | scripts-robustness | `sync-ps1-missing-interactive-merge` | sync.ps1 omits the interactive-merge direction (option 4) that sync.sh implements — behavioral drift | D:\Sources\claude-config\scripts\sync.sh, D:\Sources\claude-config\scripts\sync.ps1 |
| medium | security-surface | `parity-ci-checks-files-not-wiring` | CI parity audit only checks .sh/.ps1 file-count parity, not whether each .ps1 is wired into settings.windows.json — masks the dormant-guard gap | .github/workflows/validate-hooks-doc.yml, COMPATIBILITY.md |
| medium | settings-schema | `win-missing-memory-hooks` | Three memory-protection hooks (write-guard, integrity-check, access-logger) wired on POSIX are absent on Windows despite .ps1 files existing | global/settings.json, global/settings.windows.json |
| medium | settings-schema | `no-ci-parity-check-for-hook-wiring` | CI parity audit only checks .sh/.ps1 file existence, not that hooks are equivalently WIRED in both settings files | .github/workflows/validate-hooks-doc.yml, global/settings.json |
| medium | skills-quality | `fleet-orchestrator-arg-hint-flag-drift` | fleet-orchestrator argument-hint advertises --retry and --dry-run, but body uses --max-retries and never documents dry-run | global/skills/_internal/fleet-orchestrator/SKILL.md |
| medium | tests-ci | `hook-json-escape-tests-orphaned` | Three JSON-escape injection-regression suites covering 15 guard hooks are run by no CI workflow | tests/hook-json-escape.sh, tests/hook-json-escape-group1.sh |
| medium | tests-ci | `powershell-hooks-never-executed-in-ci` | No CI job runs PowerShell hook tests; the 37 .ps1 hooks get file-existence parity only, never behavioral execution | .github/workflows/validate-hooks.yml, .github/workflows/validate-hooks-doc.yml |
| medium | tests-ci | `batch-drift-regression-stale-result-pass` | Nightly batch-drift regression can report PASS by asserting against a stale committed result file when the live benchmark produces none | tests/batch_drift_regression/run-regression.sh, tests/batch_drift_benchmark/run-benchmark.sh |
| medium | tests-ci | `orphaned-script-and-regression-tests` | About a dozen genuine regression suites under tests/scripts and tests/batch_drift_regression are invoked by no workflow | tests/scripts/test-hook-ordering.sh, tests/scripts/test-windows-hooks-parity.sh |
| medium | versioning | `hooks-field-never-checked-or-synced` | hooks version track is declared in VERSION_MAP.yml but is read by NO checker, syncer, or release tooling — it can drift silently forever | D:\Sources\claude-config\VERSION_MAP.yml, D:\Sources\claude-config\scripts\check_versions.sh |
| medium | versioning | `release-target-excludes-hooks` | /release --target cannot bump the hooks track — the argument-hint and parse regex omit `hooks`, so `--target hooks` silently falls back to suite | D:\Sources\claude-config\global\skills\_internal\release\SKILL.md |
| medium | versioning | `release-gh-create-hardcodes-suite-tag` | release skill Step 8 `gh release create v$VERSION` ignores the <target>-v tag scheme it set in Step 7, so non-suite releases create a mismatched/wrong tag | D:\Sources\claude-config\global\skills\_internal\release\SKILL.md |
| low | architecture | `plugin-lite-readme-hooks-contradiction` | plugin-lite README states 'Hooks: No' but plugin-lite ships hooks/lib/validate-commit-message.sh | plugin-lite/README.md, plugin-lite/hooks/lib/validate-commit-message.sh |
| low | architecture | `plugin-bundled-lib-no-consumer` | Bundled validate-commit-message.sh has no consumer inside either plugin tree — the PLUGIN_BUILD rationale assumes a commit-message-guard.sh that the plugins do not ship | plugin/hooks/lib/validate-commit-message.sh, plugin-lite/hooks/lib/validate-commit-message.sh |
| low | architecture | `plugin-readme-structure-omits-shipped-dirs` | plugin/README Directory Structure diagram omits agents/, .lsp.json, and .claudeignore that the plugin actually ships | plugin/README.md |
| low | docs-consistency | `compat-hook-event-table-incomplete-and-wrong` | COMPATIBILITY.md Hook Event Types table omits 4 event types and mislabels tool-failure-logger | D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/global/hooks/tool-failure-logger.sh |
| low | docs-consistency | `readme-agents-section-missing-two-agents` | README.md and README.ko.md Agents tables list 6 agents; project ships 8 | D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md |
| low | docs-consistency | `readme-internal-skills-tree-missing-six` | README directory trees list 13 of 19 internal skills (6 missing in both languages) | D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md |
| low | docs-consistency | `readme-hooks-tree-missing-17` | README directory trees enumerate ~19 of 37 hooks under global/hooks/ | D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md |
| low | docs-consistency | `readme-tree-lib-dirs-understated` | README directory tree under-lists hooks/lib/ and global/hooks/lib/ contents | D:/Sources/claude-config/README.md |
| low | docs-consistency | `compat-footer-stale-version-date` | COMPATIBILITY.md footer says 'v1.6.0 / 2026-04-17' while suite is 1.10.0 and file was edited 2026-05-29 | D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/VERSION_MAP.yml |
| low | docs-consistency | `changelog-no-released-sections` | CHANGELOG.md keeps everything under [Unreleased] with no released-version sections; v1.10.0 changelog body is empty in both READMEs | D:/Sources/claude-config/CHANGELOG.md, D:/Sources/claude-config/README.md |
| low | hooks-correctness | `gap-authcheck-undermatch` | github-api-preflight auth pre-check skips common 'cd x && gh ...' invocations | global/hooks/github-api-preflight.sh |
| low | hooks-correctness | `gap-heredoc-not-jq` | github-api-preflight and prompt-validator emit JSON via heredoc interpolation instead of jq | global/hooks/github-api-preflight.sh, global/hooks/prompt-validator.sh |
| low | hooks-parity | `bash-write-guard-ps1-no-readbefore-on-argv-targets` | bash-write-guard.ps1 enforces Read-before-Edit only on redirect targets, not on cp/mv/tee/sed-i/dd argv targets like the .sh | global/hooks/bash-write-guard.ps1, global/hooks/bash-write-guard.sh |
| low | hooks-performance | `p4-guard-unbounded-gh-diff` | p4-timeline-guard's `gh pr diff` network call has no timeout wrapper, can hang up to the hook's 10s limit | global/hooks/p4-timeline-guard.sh, global/settings.json |
| low | hooks-performance | `markdown-validator-double-registered` | markdown-anchor-validator (heaviest non-network hook, 30s timeout) is registered in BOTH global and project settings — runs twice per Bash call | global/settings.json, project/.claude/settings.json |
| low | hooks-performance | `windows-pwsh-cold-spawn-per-hook` | Windows Bash chain cold-spawns a fresh pwsh.exe process per hook (10 processes/Bash call) on top of a 110s timeout budget | global/settings.windows.json |
| low | scripts-robustness | `backup-sh-unquoted-backupdir-wordsplit` | backup.sh summary uses unquoted $BACKUP_DIR in ls -A, breaking on paths containing spaces | D:\Sources\claude-config\scripts\backup.sh |
| low | scripts-robustness | `installer-fetch-source-unguarded-bootstrap-sh` | bootstrap.sh sources hooks/lib/installer-fetch.sh without a Test-Path guard, unlike install.sh and bootstrap.ps1 | D:\Sources\claude-config\bootstrap.sh |
| low | security-surface | `windows-sensitive-file-guard-missing-ssh-aws` | Windows sensitive-file-guard.ps1 does not block SSH private keys or ~/.aws/credentials that the bash version blocks, and the deny-list does not cover them either | global/hooks/sensitive-file-guard.ps1, global/hooks/sensitive-file-guard.sh |
| low | settings-schema | `win-permissions-allow-narrower` | permissions.allow on Windows omits nearly all gh write-verbs and gh api allowlist present on POSIX | global/settings.json, global/settings.windows.json |
| low | settings-schema | `win-note-comment-stale` | Edit\|Write\|Read matcher _note on Windows is stale relative to POSIX (omits memory-write-guard ordering and issue #521) | global/settings.json, global/settings.windows.json |
| low | skills-quality | `fleet-orchestrator-resume-flag-missing-from-hint` | fleet-orchestrator body documents --resume <fleet-id> but argument-hint omits it | global/skills/_internal/fleet-orchestrator/SKILL.md |
| low | skills-quality | `traceability-loop-metadata-no-loop-body` | traceability declares max_iterations/halt_conditions/loop_safe but its body has zero loop/iteration content; passes the validator's drift check only because the regex matches the frontmatter keys | global/skills/_internal/traceability/SKILL.md, scripts/validate_skills.sh |
| low | skills-quality | `loop-safe-false-missing-side-effect-section` | Most loop_safe:false skills omit the side-effect / non-idempotency body section the validator checks for | global/skills/_internal/issue-work/SKILL.md, global/skills/_internal/pr-work/SKILL.md |
| low | tech-debt-lifecycle | `p4-timeline-windows-all-expired` | P4 EPIC #454 timeline windows all expired — guard/reminder hooks now permanently no-op | global/policies/p4-timeline.json, global/hooks/p4-timeline-guard.sh |
| low | tests-ci | `conflict-guard-no-behavioral-test` | conflict-guard.sh is the only active PreToolUse guard with no decision-logic test | global/hooks/conflict-guard.sh, tests/hooks/ |
| low | tests-ci | `validate-hooks-path-missing-anchor-fixtures` | validate-hooks.yml path filter omits tests/markdown-anchor-validator/** so changes to those fixtures do not trigger the suite that consumes them | .github/workflows/validate-hooks.yml, tests/markdown-anchor-validator/fixtures/baseline-valid.md |
| low | versioning | `version-map-false-doc-claim-hooks-surfaced` | VERSION_MAP.yml claims the hooks version is surfaced to operators via HOOKS.md and ENFORCEMENT.md, but neither file contains the version | D:\Sources\claude-config\VERSION_MAP.yml, D:\Sources\claude-config\HOOKS.md |
| low | versioning | `changelog-only-tracks-suite-no-per-version-sections` | CHANGELOG tracks only the suite version and has no released per-version sections, so plugin/plugin-lite/settings-schema/hooks bumps are invisible and the file violates the project's own Keep-a-Changelog standard | D:\Sources\claude-config\CHANGELOG.md, D:\Sources\claude-config\VERSION_MAP.yml |
| low | versioning | `sync-json-version-global-regex-fragility` | bash sync_versions.sh rewrites every "version" key globally; safe today only because settings.json has exactly one such key, but the invariant is undocumented and brittle | D:\Sources\claude-config\scripts\sync_versions.sh, D:\Sources\claude-config\global\settings.json |
| info | hooks-parity | `dangerous-command-guard-allow-shape-mismatch` | dangerous-command-guard allow response carries the reason under different JSON keys (.sh permissionDecisionReason vs .ps1 additionalContext) | global/hooks/dangerous-command-guard.sh, global/hooks/dangerous-command-guard.ps1 |
| info | scripts-robustness | `installers-no-noninteractive-flag` | install.sh/.ps1 and bootstrap.sh/.ps1 provide no non-interactive (--yes/CI) mode; curl\|bash relies on read returning defaults | D:\Sources\claude-config\scripts\install.sh, D:\Sources\claude-config\bootstrap.sh |
| info | security-surface | `deny-list-narrower-than-guards-by-design-gap` | permissions.deny is a strict subset of what the bash guards block (.crt/.cer, .gnupg, .netrc/.npmrc/.pypirc, .kube/config, docker config, /etc/shadow) — defense-in-depth gap if a guard is ever disabled | global/settings.json, global/hooks/bash-sensitive-read-guard.sh |
| info | settings-schema | `git-fetch-allow-divergence` | git fetch allowlist differs: POSIX scopes to origin/upstream, Windows uses broad git fetch:* | global/settings.json, global/settings.windows.json |
| info | skills-quality | `tier-presets-missing-on-oversized-skills` | _policy.md calls tier presets 'Required' for >5KB bodies, but ~10 skills exceed 5KB without tiers; the rollout is documented as phased, leaving policy text and practice divergent | global/skills/_policy.md, docs/TOKEN_OPTIMIZATION.md |
| info | tech-debt-lifecycle | `stale-err-log-root` | Stale err.log scratch artifact left in repository root | err.log |


## Finding Details


### `bsrg-env-case-bypass` — high/defect (hooks-correctness)

**bash-sensitive-read-guard allows reading .ENV/.Env (same case-sensitivity bypass)**


- Files: global/hooks/bash-sensitive-read-guard.sh

- Evidence: is_sensitive() computes `lower=...` but matches the .env / SSH / .aws / .netrc / .kube patterns against UN-lowered $p: `case "$p" in */.env|*.env|*/.env.*|*.env.*) return 0 ;;`. Live test: `cat /home/u/.ENV` => "allow"; `cat /home/u/.env` => "deny". Identical root cause to bash-write-guard. Because the Bash channel is the ONLY guard for `cat`/`grep` (permissions.deny only covers the Read tool), this is a real secret-exfiltration bypass on case-insensitive FS for `.ENV` and is also a divergence from sensitive-file-guard.sh's lowercased-basename design.

- Recommendation: Apply the same fix: run the .env-family and credential-filename case branches against $lower. Keep parity with sensitive-file-guard.sh and bash-write-guard.sh so all three channels fold case identically.

- Confidence: high


### `merge-gate-guard-ps1-missing-squash-only` — high/defect (hooks-parity)

**merge-gate-guard.ps1 omits the squash-only enforcement block, allowing gh pr merge --merge/--rebase on Windows**


- Files: global/hooks/merge-gate-guard.ps1, global/hooks/merge-gate-guard.sh

- Evidence: merge-gate-guard.sh lines 82-88 ("Squash-only enforcement (Issue #478)") deny the merge: `if echo "$CMD" | grep -qE -- '(^|[[:space:]])--(merge|rebase)([[:space:]]|=|$)'; then deny_response "gh pr merge --merge/--rebase blocked: branching strategy requires squash merges (use --squash)..."`. merge-gate-guard.ps1 has no equivalent — after the scope gate (line 47) it jumps straight to PR-number extraction. There is even a dedicated test tests/hooks/test-merge-gate-squash-only.sh for the .sh behavior, but no .ps1 counterpart. On Windows `gh pr merge 123 --merge` bypasses the squash policy.

- Recommendation: Add the squash-only check to merge-gate-guard.ps1 immediately after the scope gate: `if ($CMD -match '(^|\s)--(merge|rebase)($|\s|=)') { New-HookDenyResponse -Reason 'gh pr merge --merge/--rebase blocked: branching strategy requires squash merges (use --squash). See workflow/branching-strategy.md.'; exit 0 }`.

- Confidence: high


### `sensitive-file-guard-ps1-missing-ssh-aws` — high/defect (hooks-parity)

**sensitive-file-guard.ps1 does not block SSH private keys or AWS credential files that the .sh blocks**


- Files: global/hooks/sensitive-file-guard.ps1, global/hooks/sensitive-file-guard.sh, tests/hooks/test-sensitive-file-guard.ps1

- Evidence: sensitive-file-guard.sh denies SSH private keys (`id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|...`) and AWS credentials (`credentials|config` under `*/.aws/*`) at lines 85-94. sensitive-file-guard.ps1 only checks `.env*` (line 51), `.(pem|key|p12|pfx)$` (line 56), and secrets/credentials/passwords directories (line 62) — it has NO id_rsa/id_ed25519 pattern and NO .aws/credentials pattern. So `Read ~/.ssh/id_rsa` or `Read ~/.aws/credentials` is blocked on macOS/Linux but ALLOWED on Windows. tests/hooks/test-sensitive-file-guard.ps1 has no SSH-key or AWS-credentials test cases, so the gap is untested.

- Recommendation: Add the SSH-key and AWS-credential checks to sensitive-file-guard.ps1, mirroring the .sh basename cases: deny when basename matches `id_(rsa|dsa|ecdsa|ed25519)(\..*)?$`, and when basename is `credentials`/`config` and the path contains `\.aws\`. Add corresponding Assert-Deny cases to tests/hooks/test-sensitive-file-guard.ps1.

- Confidence: high


### `windows-bash-secret-guards-not-wired` — high/defect (security-surface)

**bash-sensitive-read-guard / bash-write-guard / gh-write-verb-guard exist as .ps1 but are NOT wired into settings.windows.json — Windows users get no Bash-channel secret protection**


- Files: global/settings.windows.json, global/hooks/bash-sensitive-read-guard.ps1, global/hooks/bash-write-guard.ps1, global/hooks/gh-write-verb-guard.ps1, global/settings.json, ENFORCEMENT.md

- Evidence: global/settings.json Bash matcher (lines 139-211) registers `bash-sensitive-read-guard.sh`, `bash-write-guard.sh`, and `gh-write-verb-guard.sh`. The Windows Bash matcher in global/settings.windows.json (lines 82-135) registers only dangerous-command-guard.ps1, github-api-preflight.ps1, markdown-anchor-validator.ps1, commit-message-guard.ps1, conflict-guard.ps1, pr-target-guard.ps1, pr-language-guard.ps1, merge-gate-guard.ps1, attribution-guard.ps1, p4-timeline-guard.ps1 — `bash-sensitive-read-guard.ps1`, `bash-write-guard.ps1`, and `gh-write-verb-guard.ps1` are ABSENT, even though those .ps1 files exist and are fully implemented (bash-sensitive-read-guard.ps1 carries a full sensitive-path regex set). install.ps1 (line 441-445) installs settings.windows.json verbatim as ~/.claude/settings.json, so on Windows `cat .env`, `Get-Content .env`, `type ~\.aws\credentials`, and `cat > existing.py <<EOF` over the Bash channel are unguarded. ENFORCEMENT.md lines 18-19 and 45 advertise these three as active fail-closed enforcement layers with no platform caveat; HOOKS.md line 818 claims 'All hooks have PowerShell (.ps1) equivalents for native Windows support'.

- Recommendation: Add the three guards to the Bash matcher in global/settings.windows.json (pwsh -NoProfile -File ~/.claude/hooks/bash-sensitive-read-guard.ps1, bash-write-guard.ps1, gh-write-verb-guard.ps1), matching the .sh ordering in settings.json. Either fix this or add an explicit Windows-gap caveat to ENFORCEMENT.md/HOOKS.md until fixed.

- Confidence: high


### `win-missing-bash-tool-guards` — high/inconsistency (settings-schema)

**Four PreToolUse Bash-matcher guards wired on POSIX are absent on Windows though their .ps1 files exist**


- Files: global/settings.json, global/settings.windows.json, global/hooks/bash-sensitive-read-guard.ps1, global/hooks/bash-write-guard.ps1, global/hooks/gh-write-verb-guard.ps1, global/hooks/traceability-guard.ps1

- Evidence: settings.json Bash matcher wires 13 hooks including bash-sensitive-read-guard.sh (line 148), bash-write-guard.sh (153), gh-write-verb-guard.sh (158), and traceability-guard.sh (179). settings.windows.json Bash matcher (lines 83-135) wires only 10 hooks and OMITS all four. The omission is NOT a platform limitation: bash-sensitive-read-guard.ps1, bash-write-guard.ps1, gh-write-verb-guard.ps1, and traceability-guard.ps1 all exist in global/hooks/ (confirmed via Glob). The 'bash-' prefix refers to the Bash TOOL matcher, not a POSIX shell dependency. Result: Windows users lose sensitive-read blocking, bash-write guarding, gh write-verb guarding, and traceability gating on every Bash tool call.

- Recommendation: Add the four missing entries to the Bash matcher in settings.windows.json as `pwsh -NoProfile -File ~/.claude/hooks/<name>.ps1` (e.g. bash-sensitive-read-guard.ps1 timeout 5, bash-write-guard.ps1 timeout 5, gh-write-verb-guard.ps1 timeout 5, traceability-guard.ps1 timeout 10), preserving the POSIX hook order. If any is intentionally POSIX-only, document that in COMPATIBILITY.md and delete the unused .ps1 to remove ambiguity.

- Confidence: high


### `plugin-skill-refs-drift-unguarded` — medium/tech-debt (architecture)

**plugin/ skill reference files inline rules/ content but only 4 of ~33 are drift-guarded; the rest have already diverged**


- Files: plugin/skills/coding-guidelines/reference/quality.md, plugin/skills/security-audit/reference/security.md, plugin/skills/api-design/reference/api-design.md, scripts/check_references.sh, docs/CUSTOM_EXTENSIONS.md

- Evidence: In project/.claude/skills/ the reference files are real git symlinks (mode 120000) into project/.claude/rules/ — e.g. `git ls-files -s` shows `120000 ... project/.claude/skills/coding-guidelines/reference/quality.md`, content `../../../rules/coding/standards.md`. The matching plugin/ files are independent regular files (mode 100644) holding full inlined copies, and they have measurably drifted from the rules SSOT: `diff plugin/skills/coding-guidelines/reference/quality.md project/.claude/rules/coding/standards.md` => DIFFERENT (4574 B vs 4031 B); `diff plugin/skills/security-audit/reference/security.md project/.claude/rules/security.md` => DIFFERENT (11421 B vs 12933 B); api-design.md and architecture.md also differ. The only drift guard, scripts/check_references.sh, hard-codes FILES=(git-commit-format.md github-issue-5w1h.md github-pr-5w1h.md performance-analysis.md) for the project-workflow mirror ONLY. CUSTOM_EXTENSIONS.md lines 192-196 explicitly scope the SSOT to those same 4 files. Every other inlined reference (coding-guidelines/*, security-audit/*, api-design/*, documentation/*, performance-review/*, and 8 more project-workflow/* files like build.md, testing.md, problem-solving.md — all confirmed DIFFERENT from their rules/ counterparts) is unguarded and silently stale. plugin/skills/security-audit/SKILL.md line 44 `@./reference/security.md` actively imports the drifted copy.

- Recommendation: Either (a) extend the SSOT canonical->mirror map in scripts/check_references.sh + scripts/sync_references.sh (and their .ps1 twins) to cover ALL plugin reference files that mirror rules/, then run sync to re-sync the currently-drifted copies; or (b) explicitly document in CUSTOM_EXTENSIONS.md that plugin skill references are independently maintained and NOT derived from rules/ (renaming/restructuring them so they don't look like the same logical file). Today the relationship is implied by identical filenames but neither synced nor disclaimed, which is the worst of both.

- Confidence: high


### `plugin-agents-near-duplicate-unguarded` — medium/tech-debt (architecture)

**plugin/agents and project/.claude/agents are near-identical duplicates (2-5 differing lines each) with no SSOT or drift guard**


- Files: plugin/agents/code-reviewer.md, project/.claude/agents/code-reviewer.md, plugin/agents/refactor-assistant.md

- Evidence: Both trees ship the same 8 agent filenames (code-reviewer, codebase-analyzer, dependency-auditor, documentation-writer, qa-reviewer, refactor-assistant, structure-explorer, test-strategist). Per-agent diff counts: code-reviewer 4, codebase-analyzer 4, dependency-auditor 2, documentation-writer 3, qa-reviewer 2, refactor-assistant 5, structure-explorer 2, test-strategist 2 differing lines. The differences are layer-appropriate frontmatter (plugin has `temperature: 0.3`, project has `color: purple`) plus one path-reference tweak (`If language-specific rules exist...` vs `If rules/coding/cpp-specifics.md ... exists`). Bodies are otherwise byte-identical. No doc under docs/ describes a plugin<->project agent sync relationship (grep for 'plugin/agents'|'agents.*sync'|'agents.*mirror' in docs/README/HOOKS returns only unrelated index/memory files), and no CI step compares them.

- Recommendation: Add the 8 agents to a documented SSOT-with-overlay scheme (canonical body + per-layer frontmatter overlay generated by sync) OR add a CI diff check that the shared body sections match, OR document in plugin-vs-global.md/CUSTOM_EXTENSIONS.md that agents are intentionally maintained per-layer. As-is they will drift the moment one copy is edited without the other.

- Confidence: high


### `compat-pwsh-parity-count-stale` — medium/inconsistency (docs-consistency)

**COMPATIBILITY.md PowerShell parity table says 32/32 hooks; actual is 37/37**


- Files: D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/HOOKS.md

- Evidence: COMPATIBILITY.md line 230: '| `global/hooks/*.sh` | 32 | 32 | 32/32 (100%) |'. Actual `ls global/hooks/*.sh | wc -l` = 37 and `*.ps1` = 37; HOOKS.md auto-generated catalog line 1048 confirms '_Total: 37 bash hooks, 37 with PowerShell counterparts._'. The COMPATIBILITY.md table even embeds the live-count command on line 234 (`b=$(ls global/hooks/*.sh | wc -l)...`) which now returns 37, directly contradicting the hardcoded 32 above it.

- Recommendation: Update the parity table count from 32 to 37 (both bash and PowerShell columns). Better: replace the hardcoded number with a CI-checked value, since the auto-generated HOOKS.md catalog already tracks the real count and validate-hooks-doc.yml fails on drift there.

- Confidence: high


### `hooks-md-section12-h2-and-stale-content` — medium/defect (docs-consistency)

**HOOKS.md section 12 is H2 (breaks numbered hierarchy) and its no-base behavior is stale vs the shipped #616 fix**


- Files: D:/Sources/claude-config/HOOKS.md, D:/Sources/claude-config/global/hooks/pr-target-guard.sh, D:/Sources/claude-config/CHANGELOG.md

- Evidence: HOOKS.md line 259 is '## 12. PR Target Guard (PreToolUse)' — an H2 — while sibling sections 1-11 and 13-20 are all H3 ('### N.'). More importantly, line 275 states the logic: 'If no `--base` flag: allow (defaults to `develop`)'. That contradicts the shipped behavior: pr-target-guard.sh lines 66-81 now query the repo default branch (`gh api repos/{owner}/{repo} --jq .default_branch`) when `--base` is absent, and CHANGELOG.md lines 30-39 (#616) explicitly describe this as a security fix because repos defaulting to `main` previously 'silently bypassed the branching policy' under the old allow-by-default logic.

- Recommendation: Change line 259 from '## 12.' to '### 12.' to restore the H3 numbering, and rewrite step 4 of the Logic block (line 275) to describe the default-branch resolution from #616 (resolve default branch via gh api; apply main/master protection; PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE for tests).

- Confidence: high


### `bwg-env-case-bypass` — medium/defect (hooks-correctness)

**bash-write-guard allows writes to .ENV/.Env (case-sensitivity bypass of .env protection)**


- Files: global/hooks/bash-write-guard.sh

- Evidence: is_sensitive_target() computes `lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')` but then matches the .env / SSH / .aws / system-file patterns against the UN-lowered $p: `case "$p" in */.env|*.env|*/.env.*|*.env.*) return 0 ;; ...`. Only the *.pem/secrets-dir patterns use $lower. Live test: `echo secret > /home/u/.ENV` => permissionDecision "allow"; `> /home/u/.env` => "deny". sensitive-file-guard.sh (the Edit/Write/Read channel) deliberately lowercases the basename for exactly this defense, so the Bash channel diverges. On case-insensitive filesystems (macOS default, Windows) .ENV is the same file as .env, making this an exploitable secret-write bypass.

- Recommendation: Match the .env / SSH-key / .aws / .netrc / system-credential globs against $lower (as is already done for *.pem and secrets dirs), or lowercase a single working copy and run every case branch against it. Add deny fixtures for .ENV/.Env/.Envrc to the test corpus.

- Confidence: high


### `gap-matcher-overmatch` — medium/defect (hooks-correctness)

**github-api-preflight matcher fires a network curl on any command ending in 'gh '**


- Files: global/hooks/github-api-preflight.sh

- Evidence: Scope gate is `if ! echo "$CMD" | grep -qE '(gh |github\.com|api\.github\.com)'; then allow_response; fi`. The `gh ` alternative is not anchored, so benign commands `high priority task`, `weigh the options`, `echo enough rope` all MATCH (verified: all printed MATCH). On every such Bash command the hook then runs `curl --connect-timeout 3 https://api.github.com/zen` plus `gh auth status`, adding network latency and false 'GitHub unreachable' context to unrelated commands. It is registered with timeout 10 in settings.json, so this can stall the PreToolUse chain on slow networks for words merely containing 'gh '.

- Recommendation: Anchor the gh detection to a command head / word boundary, e.g. `grep -qE '(^|[[:space:]`(])gh[[:space:]]|github\.com'` (mirroring gh-write-verb-guard's pre-filter `(^|[[:space:]`(])gh[[:space:]]`).

- Confidence: high


### `commit-msg-guard-ps1-broad-attribution-regex` — medium/inconsistency (hooks-parity)

**commit-message-guard.ps1 uses the old broad attribution substring match the .sh deliberately replaced (false-positive divergence)**


- Files: global/hooks/commit-message-guard.ps1, global/hooks/commit-message-guard.sh, hooks/lib/validate-commit-message.sh

- Evidence: commit-message-guard.ps1 Rule 4: `if ($msg -imatch '(claude|anthropic|ai-assisted|co-authored-by:\s*claude|generated\s+with)')`. The .sh delegates Rule 4 to validate_commit_message() -> validate_no_attribution() in hooks/lib/validate-commit-message.sh, whose header states the broad form 'caused false positives on legitimate technical writing ("docs: clarify Claude API behavior", "feat: add Anthropic SDK")' and was replaced by a three-pattern design (trailer at line start, emoji adjacent, 'Generated|Created|Authored {with|by|using} {Claude|Anthropic}' prose). global/commit-settings.md confirms casual mentions are allowed. Result: `git commit -m "feat: add claude API integration"` is ALLOWED on bash but DENIED on PowerShell.

- Recommendation: Replace the broad substring match in commit-message-guard.ps1 Rule 4 with the three-pattern logic. The module global/hooks/lib/LanguageValidator.psm1 already exists for Rule 2; add a Test-NoAttribution helper (mirroring the AttributionTrailer/Emoji/Prose regexes already inlined in attribution-guard.ps1 lines 25-27) and call it from commit-message-guard.ps1 so the bash and PowerShell commit-message gates accept/reject identical messages.

- Confidence: high


### `pr-target-guard-ps1-stale-master-and-default-branch` — medium/inconsistency (hooks-parity)

**pr-target-guard.ps1 is stale: it never blocks 'master' and never resolves the repo default branch, unlike the hardened .sh**


- Files: global/hooks/pr-target-guard.ps1, global/hooks/pr-target-guard.sh

- Evidence: pr-target-guard.sh blocks both main and master: `if [ "$BASE" != "main" ] && [ "$BASE" != "master" ]; then allow_response; fi` (line 94), and when --base is absent it resolves the repo default branch via `gh api "repos/$REPO" --jq .default_branch` (lines 70-88, added because repos with default_branch=main bypassed the policy). pr-target-guard.ps1 only blocks main (`if ($base -ne 'main') { New-HookAllowResponse; exit 0 }`, line 59) and on a missing --base simply allows (lines 50-53, comment 'Allow it -- this is the normal feature-to-develop workflow'). On Windows, a PR targeting master, or a feature PR with no --base into a main-default repo, bypasses the branching policy.

- Recommendation: Port the .sh logic to pr-target-guard.ps1: (1) treat both 'main' and 'master' as protected; (2) when no --base flag is found, honor PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE then query `gh api repos/{owner}/{repo} --jq .default_branch`, allowing only on resolution failure; (3) accept release/* heads (already present). Update the deny reason to interpolate the actual base branch.

- Confidence: high


### `memory-write-guard-ps1-missing-secret-rc2` — medium/defect (hooks-parity)

**memory-write-guard.ps1 does not fail-closed on secret-check.sh exit code 2 (OWNER_EMAILS not configured)**


- Files: global/hooks/memory-write-guard.ps1, global/hooks/memory-write-guard.sh

- Evidence: memory-write-guard.sh blocks on both secret exit 1 and 2: `if [ "$SECRET_RC" -eq 1 ] || [ "$SECRET_RC" -eq 2 ]; then BLOCK=1; fi` (lines 272-274), with the header documenting 'secret-check.sh exit 2 -> deny (OWNER_EMAILS not configured, #618)' and 'without OWNER_EMAILS we cannot tell owner emails from foreign emails, so fail-closed is the safe choice.' memory-write-guard.ps1 only blocks on exit 1: `if ($secretRc -eq 1) { $block = $true }` (line 171) and its deny-reason builder (lines 174-182) has no exit-2 branch. On Windows, a memory write proceeds even when secret-check signals it cannot safely classify emails.

- Recommendation: In memory-write-guard.ps1, change the block condition to `if ($secretRc -eq 1 -or $secretRc -eq 2) { $block = $true }` and add a deny-reason branch for exit 2 ('secret-check.sh requires configuration (#618)') matching the .sh build_deny_reason().

- Confidence: high


### `language-validator-ps1-missing-typographic-allowlist` — medium/inconsistency (hooks-parity)

**LanguageValidator.psm1 'english' policy rejects em-dash/en-dash/curly-quotes/ellipsis/NBSP that the bash validators allow (issue #583)**


- Files: global/hooks/lib/LanguageValidator.psm1, hooks/lib/validate-language.sh, global/hooks/pr-language-guard.sh

- Evidence: validate-language.sh::validate_english_only strips an allowlist before the ASCII check (issue #583): `s/[\x{2014}\x{2013}\x{201C}\x{201D}\x{2018}\x{2019}\x{2026}\x{00A0}]//g` (lines 57-59); the pr-language-guard.sh inline fallback repeats it (lines 107-110). LanguageValidator.psm1::Test-CodePointAllowed for the english policy only permits 0x20-0x7E and 0x09-0x0D (lines 51-53) with no allowlist for U+2014/2013/201C/201D/2018/2019/2026/00A0. So `gh pr create --title "Refactor — phase 1"` (em-dash) is allowed on bash/Linux but DENIED by pr-language-guard.ps1 on Windows under the default english policy.

- Recommendation: In LanguageValidator.psm1::Test-CodePointAllowed (or as a pre-strip in Find-FirstDisallowedElement / Test-ContentLanguage), allowlist the same code points the bash side strips: U+2014, U+2013, U+201C, U+201D, U+2018, U+2019, U+2026, U+00A0 for the english (and exclusive_bilingual english-mode) path.

- Confidence: high


### `markdown-anchor-validator-cjk-charclass-divergence` — medium/risk (hooks-parity)

**markdown-anchor-validator anchor generation uses POSIX [:alnum:] (.sh) vs Unicode \p{L}\p{N} (.ps1), risking different anchors for Korean/CJK headings**


- Files: global/hooks/markdown-anchor-validator.sh, global/hooks/markdown-anchor-validator.ps1

- Evidence: The .sh strips non-allowed chars with `sed -e 's/[^[:alnum:]_ -]//g'` under `LC_ALL=C.UTF-8` (lines 27, 145, 211). Whether `[:alnum:]` matches Hangul/CJK is locale- and platform-dependent (GNU sed under C.UTF-8 matches; BSD/macOS does not — the line 26 comment asserts it 'matches Korean' but this is not guaranteed). The .ps1 uses `-replace '[^\p{L}\p{N}\p{Pc} -]', ''` (line 69) which always preserves Unicode letters/numbers. For a heading like `## 개요`, the .ps1 yields anchor '개요' while the .sh may strip the Hangul to an empty anchor (skipped). Same staged tree -> potentially different anchor registry -> different allow/deny decision. This repo uses Korean headings heavily.

- Recommendation: Make the anchor character class explicit and identical on both sides. Either change the .sh to a Unicode-aware approach (perl `s/[^\p{L}\p{N}\p{Pc} -]//g` like the .ps1) instead of relying on locale-dependent [:alnum:], or document a shared, tested set of CJK fixtures (extend tests/hooks/test-markdown-anchor-validator.{sh,ps1}) to assert byte-identical anchors for Korean/CJK headings on every platform.

- Confidence: high


### `bootstrap-ps1-wrong-settings-windows` — medium/defect (scripts-robustness)

**bootstrap.ps1 installs Unix settings.json (sh-based hooks) on Windows instead of settings.windows.json**


- Files: D:\Sources\claude-config\bootstrap.ps1, D:\Sources\claude-config\scripts\install.ps1, D:\Sources\claude-config\global\settings.json, D:\Sources\claude-config\global\settings.windows.json

- Evidence: bootstrap.ps1:318 `$settingsSrc = Join-Path $InstallDir 'global' 'settings.json'` then copies it to ~/.claude/settings.json. By contrast install.ps1:441 uses `global/settings.windows.json`. The two files differ materially: global/settings.json hooks invoke `~/.claude/hooks/<name>.sh` directly (e.g. line 118 `"command": "~/.claude/hooks/sensitive-file-guard.sh"`) and have no statusLine, while settings.windows.json invokes `pwsh -NoProfile -File ~/.claude/hooks/<name>.ps1` (line 67) and sets a pwsh.exe statusLine (line 46). On a native Windows host the bootstrap-installed config points every hook at a .sh script.

- Recommendation: In bootstrap.ps1 Install-GlobalSettings, source `global/settings.windows.json` (mirroring install.ps1:441) when on Windows, falling back to settings.json only on non-Windows pwsh. Add a drift test asserting bootstrap.ps1 and install.ps1 select the same settings source per platform.

- Confidence: high


### `backup-sh-silent-dataloss-cp-after-delete` — medium/defect (scripts-robustness)

**backup.sh can wipe a backup directory then silently fail to repopulate it (cp || error with non-exiting error)**


- Files: D:\Sources\claude-config\scripts\backup.sh

- Evidence: error() is defined as a non-exiting echo: backup.sh:40 `error() { echo -e "${RED}❌ $1${NC}"; }`. The replace block deletes then copies: line 226 `safe_rm_rf "$BACKUP_DIR/global"`, line 227 `mkdir -p "$BACKUP_DIR/global"`, line 228 `cp -r "$TEMP_BACKUP/global"/* "$BACKUP_DIR/global/" || error "글로벌 백업 업데이트 실패"`. Because `cp ... || error` returns 0 (echo succeeds), errexit is suppressed and the script continues even though the destination was just emptied and the copy failed — leaving an empty backup and a success summary. Same pattern at lines 220 and 236.

- Recommendation: Make error() exit (as bootstrap.sh:62 does) or change the pattern to `cp ... || { error "..."; exit 1; }`. Safer still: copy into the new location first and only remove the old one after the copy verifiably succeeds (copy-then-swap), so a failed copy never leaves a wiped destination.

- Confidence: high


### `install-sh-error-fn-suppresses-errexit` — medium/defect (scripts-robustness)

**install.sh error() is non-exiting and used as `cp || error`, so failed enterprise/lib copies continue silently**


- Files: D:\Sources\claude-config\scripts\install.sh

- Evidence: install.sh:46-48 `error() { echo -e "${RED}❌ $1${NC}"; }` (no exit). It is used as a guard on critical copies, e.g. line 277 `sudo cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/" || error "CLAUDE.md 복사 실패"` and line 282/291 for rules. Under `set -euo pipefail` the `|| error` idiom turns a hard copy failure into a printed message plus continued execution, so the installer can report '설치 완료' while the enterprise policy file (highest-precedence config) was never written.

- Recommendation: Either define error() to exit non-zero, or replace each `|| error "..."` with `|| { error "..."; exit 1; }` for copies whose failure must halt installation (enterprise CLAUDE.md, rules, shared libs).

- Confidence: high


### `sync-ps1-missing-interactive-merge` — medium/inconsistency (scripts-robustness)

**sync.ps1 omits the interactive-merge direction (option 4) that sync.sh implements — behavioral drift**


- Files: D:\Sources\claude-config\scripts\sync.sh, D:\Sources\claude-config\scripts\sync.ps1

- Evidence: sync.sh:142-144 offers four directions including `4) 대화형 병합 (양쪽 변경 병합)` and implements `interactive_merge_file` (sync.sh:248-321) plus the `elif [ "$SYNC_DIRECTION" = "4" ]` branch (sync.sh:347, 443). sync.ps1:106-109 only lists three options `선택 (1-3)` and has no merge branch — its dispatch is binary: `if ($syncDirection -eq '1') {...} else {...}` (sync.ps1:329/407), so a user entering 4 silently falls into the system→backup path.

- Recommendation: Port `interactive_merge_file` and the option-4 menu/branch to sync.ps1, or, if interactive merge is intentionally bash-only, remove the asymmetry by documenting it and rejecting `4` explicitly in sync.ps1 rather than silently treating it as system→backup.

- Confidence: high


### `parity-ci-checks-files-not-wiring` — medium/risk (security-surface)

**CI parity audit only checks .sh/.ps1 file-count parity, not whether each .ps1 is wired into settings.windows.json — masks the dormant-guard gap**


- Files: .github/workflows/validate-hooks-doc.yml, COMPATIBILITY.md, global/settings.windows.json

- Evidence: .github/workflows/validate-hooks-doc.yml parity job (lines 52-80) only verifies that for every global/hooks/*.sh there is a same-basename *.ps1 and counts match ('MISSING PowerShell counterpart for $sh'). It never checks that the .ps1 is referenced in settings.windows.json. COMPATIBILITY.md line 232 states the parity job 'fails the PR if *.sh and *.ps1 counts diverge' and claims parity is enforced — but a guard can exist as a file (counted, passes CI) while being unregistered (dormant), exactly the state of the three Bash-channel guards. The HOOKS.md per-hook 'PowerShell counterpart | present' lines (1083, 1100, 1219) reinforce the false sense of coverage because 'present' means 'file exists', not 'active'.

- Recommendation: Extend the parity job to assert that every guard hook referenced in settings.json (Bash/Edit/Write/Read matchers) has a corresponding entry in the equivalent settings.windows.json matcher, so a wired-on-Linux-but-dormant-on-Windows guard fails the PR.

- Confidence: high


### `win-missing-memory-hooks` — medium/inconsistency (settings-schema)

**Three memory-protection hooks (write-guard, integrity-check, access-logger) wired on POSIX are absent on Windows despite .ps1 files existing**


- Files: global/settings.json, global/settings.windows.json, global/hooks/memory-write-guard.ps1, global/hooks/memory-integrity-check.ps1, global/hooks/memory-access-logger.ps1

- Evidence: settings.json wires memory-write-guard.sh in the Edit|Write|Read matcher (line 128), memory-integrity-check.sh in SessionStart (line 246), and memory-access-logger.sh in the PostToolUse Read matcher (line 308). settings.windows.json omits all three: its Edit|Write|Read matcher (lines 62-80) lacks memory-write-guard, its SessionStart block (lines 148-168) lacks memory-integrity-check, and its PostToolUse Read matcher (lines 215-224) lacks memory-access-logger. All three .ps1 counterparts exist in global/hooks/. The POSIX _note at line 114 explicitly states memory-write-guard ordering is load-bearing ('memory-write-guard runs after pre-edit-read-guard so it only validates writes the harness has cleared. See ... issues #424, #521'), so its absence on Windows is a functional protection gap, not cosmetic.

- Recommendation: Add to settings.windows.json: memory-write-guard.ps1 after pre-edit-read-guard.ps1 in the Edit|Write|Read matcher; memory-integrity-check.ps1 in SessionStart; memory-access-logger.ps1 in the PostToolUse Read matcher. Mirror the POSIX timeouts (5s) and async flag on the access-logger.

- Confidence: high


### `no-ci-parity-check-for-hook-wiring` — medium/risk (settings-schema)

**CI parity audit only checks .sh/.ps1 file existence, not that hooks are equivalently WIRED in both settings files**


- Files: .github/workflows/validate-hooks-doc.yml, global/settings.json, global/settings.windows.json

- Evidence: validate-hooks-doc.yml `parity` job (lines 43-80) only verifies that for every global/hooks/*.sh there is a same-basename *.ps1 and vice versa ('every bash hook ... must have a PowerShell counterpart of the same basename'). It does NOT compare the hook arrays inside settings.json vs settings.windows.json. This is exactly why findings win-missing-bash-tool-guards and win-missing-memory-hooks can ship: the .ps1 files exist (so parity passes) but are never wired into settings.windows.json. No workflow has settings.windows.json under a job that diffs hook wiring against settings.json (grep confirms only validate-skills.yml references the two files, and only as path triggers).

- Recommendation: Add a CI step that parses both settings files (jq), normalizes each hook command to its basename (stripping `~/.claude/hooks/`, `.sh`/`.ps1`, and the `pwsh -NoProfile -File` prefix), and fails if the per-event hook basename sets diverge except for an explicit documented allowlist of POSIX-only hooks. Also diff the permissions.allow arrays in the same job.

- Confidence: high


### `fleet-orchestrator-arg-hint-flag-drift` — medium/defect (skills-quality)

**fleet-orchestrator argument-hint advertises --retry and --dry-run, but body uses --max-retries and never documents dry-run**


- Files: global/skills/_internal/fleet-orchestrator/SKILL.md

- Evidence: Frontmatter line 4: argument-hint: "<repos-spec> <directive-spec> [--max-parallel N] [--retry N] [--poll-interval SEC] [--dry-run] [--reanchor-interval N] [--top-k N] [--agents-dir PATH]". The body never uses the token `--retry`; instead it documents `--max-retries` and `{{MAX_RETRIES}}` (line 274 `| {{MAX_RETRIES}} | Retry cap...`, line 397 `Worker retries up to --max-retries...`, line 120 `max_retries: '$MAX_RETRIES'`). A grep of the post-frontmatter body for flag tokens yields `--max-retries` but zero `--retry`. Separately, `--dry-run` appears only in the argument-hint: an exhaustive scan of the body for `dry` returns `(no dry-run mention in body)`.

- Recommendation: Reconcile the flag names: rename the argument-hint token `[--retry N]` to `[--max-retries N]` to match the body and template variable, and either document the `--dry-run` behavior in the body (what it prints / skips) or remove `[--dry-run]` from the argument-hint. A user copying the hint and passing `--retry 3` or `--dry-run` would otherwise hit a flag the skill body does not consume.

- Confidence: high


### `hook-json-escape-tests-orphaned` — medium/risk (tests-ci)

**Three JSON-escape injection-regression suites covering 15 guard hooks are run by no CI workflow**


- Files: tests/hook-json-escape.sh, tests/hook-json-escape-group1.sh, tests/hook-json-escape-group2.sh, .github/workflows/validate-hooks.yml, tests/hooks/test-runner.sh

- Evidence: tests/hooks/test-runner.sh line 18 globs only `"$SCRIPT_DIR"/test-*.sh` (i.e. tests/hooks/), so the three files at tests/ root are not picked up. Grep of .github/workflows for 'hook-json-escape' returns zero matches; the only CI test invocation is `bash tests/hooks/test-runner.sh`. These suites assert that the historical exploit string `inj"; "permissionDecision":"allow` cannot flip deny->allow across 15 hooks (group1 header lists attribution-guard, bash-sensitive-read-guard, bash-write-guard, commit-message-guard, conflict-guard, gh-write-verb-guard, memory-write-guard; group2 lists merge-gate-guard, p4-timeline-guard, pr-language-guard, pr-target-guard, pre-edit-read-guard, sensitive-file-guard, team-limit-guard; the root file covers dangerous-command-guard).

- Recommendation: Add `bash tests/hook-json-escape.sh`, `bash tests/hook-json-escape-group1.sh`, `bash tests/hook-json-escape-group2.sh` as steps in validate-hooks.yml (or move them under tests/hooks/ so test-runner.sh discovers them). As written, a regression that reintroduces unescaped heredoc interpolation in any of these 15 deny/allow helpers — the exact class of bug issues #567/#578/#579 fixed — would not be caught by CI.

- Confidence: high


### `powershell-hooks-never-executed-in-ci` — medium/risk (tests-ci)

**No CI job runs PowerShell hook tests; the 37 .ps1 hooks get file-existence parity only, never behavioral execution**


- Files: .github/workflows/validate-hooks.yml, .github/workflows/validate-hooks-doc.yml, tests/hooks/test-runner.ps1, tests/hooks/test-language-validator.ps1, tests/hooks/test-dangerous-command-guard.ps1, tests/hooks/test-sensitive-file-guard.ps1

- Evidence: All workflow `runs-on` values are ubuntu-latest or macos-latest; there is no windows-latest runner anywhere. Grep for 'test-runner.ps1' and the eight tests/hooks/test-*.ps1 files in .github/workflows returns zero hits — `pwsh tests/hooks/test-runner.ps1` is never invoked. The only pwsh step is `pwsh tests/scripts/test-install-manifest-helpers.ps1` (validate-hooks.yml line 96). validate-hooks-doc.yml's parity job (lines 52-80) only checks that `.ps1` counterparts EXIST and that counts match (37=37) — it never runs them. validate-hooks.yml line 84 even concedes the Windows runner is future work ('exercised when the InstallerFetch matrix lands a Windows runner').

- Recommendation: Add a windows-latest matrix leg (or a pwsh job) that runs `pwsh tests/hooks/test-runner.ps1`. The maintainer's own environment is Windows and the global memory records a real PowerShell-only bug class ('$home/$args/$input read-only automatic-variable collision -> hook silently fails'); such a regression in any .ps1 hook would ship green because parity only verifies the file exists.

- Confidence: high


### `batch-drift-regression-stale-result-pass` — medium/defect (tests-ci)

**Nightly batch-drift regression can report PASS by asserting against a stale committed result file when the live benchmark produces none**


- Files: tests/batch_drift_regression/run-regression.sh, tests/batch_drift_benchmark/run-benchmark.sh, .github/workflows/batch-drift-regression.yml, tests/batch_drift_benchmark/results/subagent-30item-20260416T043000Z.json

- Evidence: run-regression.sh line 168-170 treats a non-zero benchmark exit as only a WARNING and continues; line 176 then selects `LATEST_RESULT=$(ls -t "$RESULTS_DIR"/${STRATEGY}-*.json | head -1)` with no check that the file was produced by THIS run. run-benchmark.sh `--reset` (lines 160-163) re-seeds the scratch repo but never clears RESULTS_DIR, and the repo already ships matching committed results (tests/batch_drift_benchmark/results/subagent-30item-20260416T043000Z.json, subagent-baseline-...json) that satisfy the `subagent-*.json` glob. Combined with `continue-on-error: true` (batch-drift-regression.yml line 84), a benchmark that fails before writing a fresh JSON yields PASS off the old file.

- Recommendation: Capture a run-start timestamp and assert LATEST_RESULT is newer (or write the result path to a known file and read only that), or fail (exit 3) when the benchmark runner exits non-zero instead of warning. Also gitignore/remove the committed results/*.json fixtures so a stale file cannot be selected.

- Confidence: high


### `orphaned-script-and-regression-tests` — medium/risk (tests-ci)

**About a dozen genuine regression suites under tests/scripts and tests/batch_drift_regression are invoked by no workflow**


- Files: tests/scripts/test-hook-ordering.sh, tests/scripts/test-windows-hooks-parity.sh, tests/scripts/test-killswitch.sh, tests/scripts/test-installer-fetch.sh, tests/scripts/test-no-duplicate-formatter.sh, tests/scripts/test-install-preserves-customization.sh, tests/batch_drift_regression/test-run-regression.sh

- Evidence: Grepping .github/workflows for `tests/scripts/` shows only test-plugin-*, test-install-manifest-helpers.*, test-install-permissions-policy.sh, test-language-policy-drift.sh, test-installer-prompt-drift.sh, and (validate-skills) test-spec-lint.sh are run. NOT run: test-hook-ordering.sh (issue #424 — its header states it guards a 'load-bearing contract' that sensitive-file-guard precede pre-edit-read-guard), test-windows-hooks-parity.sh (settings.json<->settings.windows.json hook tuple parity, #421), test-killswitch.sh (#469 P4 strict-schema toggle), test-installer-fetch.sh (#620 supply-chain installer-fetch lib exit codes), test-no-duplicate-formatter.sh, test-install-preserves-customization.sh, test-install-deploys-bash-lib.sh, test-migrate-halt-conditions.sh, test-severity-enum.sh, test-strict-lenient-dispatch.sh, test-workspace-prefix.sh, test-install-dual-variant.ps1, and tests/batch_drift_regression/test-run-regression.sh.

- Recommendation: Wire these into validate-hooks.yml / validate-skills.yml (and a windows leg for the .ps1 / parity tests). At minimum add test-hook-ordering.sh and test-windows-hooks-parity.sh, since the hook ordering they validate is explicitly documented as load-bearing in settings.json line 114 yet has no executing gate; and test-installer-fetch.sh, which is the only coverage for the sha256-pinned installer-fetch supply-chain lib.

- Confidence: high


### `hooks-field-never-checked-or-synced` — medium/defect (versioning)

**hooks version track is declared in VERSION_MAP.yml but is read by NO checker, syncer, or release tooling — it can drift silently forever**


- Files: D:\Sources\claude-config\VERSION_MAP.yml, D:\Sources\claude-config\scripts\check_versions.sh, D:\Sources\claude-config\scripts\check_versions.ps1, D:\Sources\claude-config\scripts\sync_versions.sh, D:\Sources\claude-config\scripts\sync_versions.ps1

- Evidence: VERSION_MAP.yml line 23 declares `hooks: 1.1.0` and the header (lines 12-14) describes it as a real consumer track: `hooks -> global/hooks/* shipping bundle; bumped per rollout`. But check_versions.sh reads only four fields (lines 37-40: SUITE/PLUGIN/PLUGIN_LITE/SETTINGS_SCHEMA) and runs only six consumer checks (lines 84-89) — none for hooks. check_versions.ps1 is identical (lines 37-40, 86-91). sync_versions.sh likewise reads only four fields (lines 35-38) and propagates only six consumers (lines 72-77); sync_versions.ps1 the same (lines 35-38, 70-75). A grep of all of scripts/ for read_map_field/Read-MapField finds calls for suite/plugin/plugin-lite/settings-schema only — never `hooks`.

- Recommendation: Either (a) make `hooks` a governed track by giving it a real consumer file (e.g. a `version:` marker emitted into HOOKS.md's auto-generated header by gen-hooks-md.sh, or a `global/hooks/VERSION` file) and adding a check/sync line for it in all four scripts; or (b) if hooks is intentionally an operator-facing label with no machine consumer, document that explicitly in VERSION_MAP.yml and add a check_versions.sh assertion that at least confirms the value is a valid SemVer, so the field is not silently dead.

- Confidence: high


### `release-target-excludes-hooks` — medium/defect (versioning)

**/release --target cannot bump the hooks track — the argument-hint and parse regex omit `hooks`, so `--target hooks` silently falls back to suite**


- Files: D:\Sources\claude-config\global\skills\_internal\release\SKILL.md

- Evidence: SKILL.md line 45 documents `--target` as `One of: suite (default), plugin, plugin-lite, settings-schema` — hooks is absent. The Version Source table (lines 58-63) lists only those four fields. The actual parse at line 211 is `if [[ "$ARGUMENTS" =~ --target[[:space:]]+(suite|plugin|plugin-lite|settings-schema) ]]; then TARGET="${BASH_REMATCH[1]}"` with `TARGET="suite"` default on line 210 — so `/release 1.2.0 --target hooks` does not match the alternation and silently bumps `suite` instead of `hooks`. There is no documented or scripted path to bump the hooks version at all.

- Recommendation: Add `hooks` to the alternation on line 211 and to the argument-hint (line 4) / Options (line 45) / Version Source table (lines 58-63), and add the hooks consumer to sync_versions so the propagation rule on lines 68-72 actually covers it. If hooks must be bumped manually, state that exception in the skill rather than letting an invalid --target degrade to suite.

- Confidence: high


### `release-gh-create-hardcodes-suite-tag` — medium/defect (versioning)

**release skill Step 8 `gh release create v$VERSION` ignores the <target>-v tag scheme it set in Step 7, so non-suite releases create a mismatched/wrong tag**


- Files: D:\Sources\claude-config\global\skills\_internal\release\SKILL.md

- Evidence: Step 7 (lines 387-391) correctly computes `TAG_NAME="v$VERSION"` then `if [ -f VERSION_MAP.yml ] && [ "${TARGET:-suite}" != "suite" ]; then TAG_NAME="${TARGET}-v$VERSION"` and pushes that tag (line 397). But Step 8 (lines 435 and 448-451) builds the GitHub release against the hardcoded literal: `RELEASE_CMD="gh release create v$VERSION ..."`. For `--target plugin` this pushes git tag `plugin-v2.3.1` (Step 7) yet `gh release create v2.3.1` (Step 8) — creating a GitHub release pointing at a tag `v2.3.1` that was never pushed (or colliding with the suite track). The Output template (line 502-503) similarly hardcodes `vVERSION`.

- Recommendation: In Step 8 use the `$TAG_NAME` already computed in Step 7 (e.g. `gh release create "$TAG_NAME" --title "$TAG_NAME"`), and reuse it in the Output template, so per-track releases tag and publish consistently.

- Confidence: high


### `plugin-lite-readme-hooks-contradiction` — low/inconsistency (architecture)

**plugin-lite README states 'Hooks: No' but plugin-lite ships hooks/lib/validate-commit-message.sh**


- Files: plugin-lite/README.md, plugin-lite/hooks/lib/validate-commit-message.sh, docs/plugin-vs-global.md

- Evidence: plugin-lite/README.md line 34: `| Hooks | Yes | No |` (Full=Yes, Lite=No). Yet `find plugin-lite/hooks -type f` returns `plugin-lite/hooks/lib/validate-commit-message.sh`. docs/plugin-vs-global.md line 115 also lists plugin-lite's layout as only `.claude-plugin/, skills/, README.md` — omitting the shipped hooks/ directory. PLUGIN_BUILD.md line 31 deliberately mandates this bundled copy for CI parity, so the file is intentional, but the user-facing README and the spec-compliance table both deny the directory exists.

- Recommendation: Reconcile: either footnote the README/Hooks row to explain the bundled commit-message lib is shipped for the terminal git commit-msg hook (not a PreToolUse hook), and add hooks/ to the plugin-vs-global.md layout row for plugin-lite; or, if the lib is genuinely unused by plugin-lite (see related finding), remove it and the README is correct.

- Confidence: high


### `plugin-bundled-lib-no-consumer` — low/tech-debt (architecture)

**Bundled validate-commit-message.sh has no consumer inside either plugin tree — the PLUGIN_BUILD rationale assumes a commit-message-guard.sh that the plugins do not ship**


- Files: plugin/hooks/lib/validate-commit-message.sh, plugin-lite/hooks/lib/validate-commit-message.sh, plugin/hooks/hooks.json, docs/PLUGIN_BUILD.md

- Evidence: PLUGIN_BUILD.md lines 13-18 justify bundling the lib because `global/hooks/commit-message-guard.sh` sources it and 'each plugin tree must ship its own copy.' But `find plugin plugin-lite -name 'commit-message-guard*'` returns nothing — neither plugin ships that script. `grep -rln validate-commit-message plugin/ plugin-lite/` returns ONLY the two lib files themselves. plugin/hooks/hooks.json (read in full) wires sensitive-file-guard, dangerous-command-guard, and format-on-save inline — it never sources the lib. So the bundled lib has no runtime path in either plugin; it is forward-provisioned dead weight whose stated rationale does not hold for the current plugin contents.

- Recommendation: Either ship the plugin-side commit-message-guard.sh (or a hooks.json entry) that actually sources the bundled lib so the PLUGIN_BUILD rationale becomes true, or drop the bundled lib from the plugin trees and remove the corresponding CI diff + PLUGIN_BUILD section until a consumer exists. Keep the CI parity check only for libs that are actually sourced.

- Confidence: high


### `plugin-readme-structure-omits-shipped-dirs` — low/inconsistency (architecture)

**plugin/README Directory Structure diagram omits agents/, .lsp.json, and .claudeignore that the plugin actually ships**


- Files: plugin/README.md

- Evidence: plugin/README.md 'Directory Structure' (lines 67-84) lists only `.claude-plugin/`, `skills/`, `hooks/hooks.json`, `README.md`. But `ls -la plugin/` shows additionally a populated `agents/` directory (8 agent files), `.lsp.json`, and `.claudeignore`. The same README's 'Plugin Manifest Compatibility' section (line 92) even references `agents/` and `.lsp.json` as auto-discovered components — contradicting its own structure diagram three lines earlier. docs/plugin-vs-global.md line 114 correctly lists all of these, so the README is the stale surface.

- Recommendation: Update the plugin/README.md structure block to include `agents/`, `.lsp.json`, and `.claudeignore`, matching the accurate inventory already in docs/plugin-vs-global.md and the README's own manifest-compatibility paragraph.

- Confidence: high


### `compat-hook-event-table-incomplete-and-wrong` — low/inconsistency (docs-consistency)

**COMPATIBILITY.md Hook Event Types table omits 4 event types and mislabels tool-failure-logger**


- Files: D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/global/hooks/tool-failure-logger.sh

- Evidence: COMPATIBILITY.md line 32 lists '| `PostToolUseFailure` | tool-failure-logger | ...', but the actual script header declares 'Hook Type: ToolFailure' (tool-failure-logger.sh) and the HOOKS.md catalog index line 1042 lists it as 'ToolFailure'. The Feature Dependencies table (lines 29-44) also has no rows for event types now in use: `CwdChanged` (cwd-change-logger), `InstructionsLoaded` (instructions-loaded-reinforcer), `TaskCreated` (task-created-validator), and `PostCompact` (post-compact-restore) — grep counts of those strings in COMPATIBILITY.md are all 0.

- Recommendation: Rename the `PostToolUseFailure` row to `ToolFailure` to match the script and catalog, and add rows for `CwdChanged`, `InstructionsLoaded`, `TaskCreated`, and `PostCompact`. Note the catalog already lists these as the SSOT, so the COMPATIBILITY table should defer to it or be regenerated.

- Confidence: high


### `readme-agents-section-missing-two-agents` — low/inconsistency (docs-consistency)

**README.md and README.ko.md Agents tables list 6 agents; project ships 8**


- Files: D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md, D:/Sources/claude-config/project/CLAUDE.md

- Evidence: README.md 'Available Agents' table (lines 650-657) lists only code-reviewer, documentation-writer, refactor-assistant, codebase-analyzer, qa-reviewer, structure-explorer (6). README.ko.md lines 607-612 list the same 6. But `project/.claude/agents/` contains 8 files including `dependency-auditor.md` and `test-strategist.md`, and the authoritative `project/CLAUDE.md` line 47 lists all 8: 'code-reviewer, codebase-analyzer, dependency-auditor, documentation-writer, qa-reviewer, refactor-assistant, structure-explorer, test-strategist'. The README directory trees (README.md lines 331-337, README.ko.md lines 293-298) also omit both.

- Recommendation: Add `dependency-auditor` and `test-strategist` rows to the Available Agents tables and directory trees in both README.md and README.ko.md to match project/CLAUDE.md and the actual agent files.

- Confidence: high


### `readme-internal-skills-tree-missing-six` — low/inconsistency (docs-consistency)

**README directory trees list 13 of 19 internal skills (6 missing in both languages)**


- Files: D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md

- Evidence: README.md directory tree (lines 264-278) under `global/skills/_internal/` lists branch-cleanup, ci-fix, doc-index, doc-review, fleet-orchestrator, harness, implement-all-levels, issue-create, issue-work, pr-work, preflight, release, research (13). Actual `ls global/skills/_internal/*/` returns 19 skill dirs (excluding `_shared`): the 13 plus `evidence-pack`, `memory-review`, `risk-control`, `sonar-fix`, `soup-inventory`, `traceability`. Grep confirms all six are absent from both README.md and README.ko.md. Five of the six (evidence-pack, risk-control, sonar-fix, soup-inventory, traceability) are even documented as Skill Aliases in the user's global CLAUDE.md.

- Recommendation: Add evidence-pack, memory-review, risk-control, sonar-fix, soup-inventory, and traceability to the `_internal/` directory tree in both READMEs.

- Confidence: high


### `readme-hooks-tree-missing-17` — low/inconsistency (docs-consistency)

**README directory trees enumerate ~19 of 37 hooks under global/hooks/**


- Files: D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md

- Evidence: README.md tree (lines 240-255) lists 19 hook basenames. 17 shipped hooks are absent from README.md: bash-sensitive-read-guard, bash-write-guard, cwd-change-logger, gh-write-verb-guard, instructions-loaded-reinforcer, memory-access-logger, memory-integrity-check, memory-write-guard, merge-gate-guard, p4-timeline-guard, p4-timeline-reminder, post-compact-restore, post-task-checkpoint, pr-language-guard, pre-edit-read-guard, task-created-validator, traceability-guard (verified by grep). README.ko.md has the same gap (e.g. traceability-guard, memory-write-guard, p4-timeline-guard, bash-write-guard all absent).

- Recommendation: Since HOOKS.md already provides a CI-verified authoritative catalog, replace the exhaustive hook enumeration in the README trees with a pointer to HOOKS.md (e.g. '... 37 hook scripts — see HOOKS.md for the full catalog') rather than maintaining a hand list that drifts. If keeping the list, sync it to all 37.

- Confidence: high


### `readme-tree-lib-dirs-understated` — low/inconsistency (docs-consistency)

**README directory tree under-lists hooks/lib/ and global/hooks/lib/ contents**


- Files: D:/Sources/claude-config/README.md

- Evidence: README.md tree lines 372-373 show `hooks/lib/` containing only `validate-commit-message.sh`, but actual contents are 5 files (also InstallerFetch.psm1, installer-fetch.sh, validate-language.sh, validate-traceability.sh). Lines 256-258 show `global/hooks/lib/` with only `rotate.sh/.ps1` and `CommonHelpers.psm1`, but actual is 7 files (also LanguageValidator.psm1, path-utils.sh, timeout-wrapper.sh, tokenize-shell.sh). timeout-wrapper.sh is in fact described elsewhere in COMPATIBILITY.md lines 236-246, so its omission from the tree is an internal inconsistency.

- Recommendation: Update the two `lib/` subtrees to include the installer-fetch, language-validation, traceability, path-utils, timeout-wrapper, and tokenize-shell helpers, or trim the trees to representative entries with an explicit '...' marker so they no longer read as exhaustive.

- Confidence: high


### `compat-footer-stale-version-date` — low/inconsistency (docs-consistency)

**COMPATIBILITY.md footer says 'v1.6.0 / 2026-04-17' while suite is 1.10.0 and file was edited 2026-05-29**


- Files: D:/Sources/claude-config/COMPATIBILITY.md, D:/Sources/claude-config/VERSION_MAP.yml

- Evidence: COMPATIBILITY.md line 250: '*Last updated: 2026-04-17 | claude-config v1.6.0*'. VERSION_MAP.yml line 19 declares 'suite: 1.10.0', and git shows COMPATIBILITY.md was last committed 2026-05-29 09:34. The Minimum Requirements table (lines 9-17) also stops at 1.6.0, so a reader cannot tell that 1.7.0-1.10.0 exist. The footer's hardcoded version is exactly the kind of drift the repo's VERSION_MAP SSOT design (README 'Versioning' section, lines 428-440) exists to prevent.

- Recommendation: Update the footer date to the real last-edit date and either bump the version reference to the current suite (1.10.0) or remove the hardcoded version in favor of pointing at VERSION_MAP.yml, consistent with how README.md's version section was de-hardcoded.

- Confidence: high


### `changelog-no-released-sections` — low/tech-debt (docs-consistency)

**CHANGELOG.md keeps everything under [Unreleased] with no released-version sections; v1.10.0 changelog body is empty in both READMEs**


- Files: D:/Sources/claude-config/CHANGELOG.md, D:/Sources/claude-config/README.md, D:/Sources/claude-config/README.ko.md

- Evidence: CHANGELOG.md has only a '## [Unreleased]' heading (line 8) and no released-version sections, yet its compare link (line 178) reads '[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.10.0...HEAD' — i.e. v1.10.0 is tagged but has no '## [1.10.0]' section anywhere in CHANGELOG.md. Separately, the README.md collapsible Changelog (lines 1031-1138) stops at v1.9.0 and has no v1.10.0 body; CHANGELOG.md line 159-160 (#623 entry) self-acknowledges this: 'v1.10.0 has no changelog body in either README yet; both will be filled at the next release.' There are thus two parallel changelogs (CHANGELOG.md vs the README <details> block) that do not reference each other.

- Recommendation: On the next release, cut the accumulated [Unreleased] entries into a '## [1.11.0]' (or appropriate) section in CHANGELOG.md and backfill the missing v1.10.0 body, then cross-link CHANGELOG.md and the README changelog so readers know which is authoritative (or consolidate to one).

- Confidence: high


### `gap-authcheck-undermatch` — low/defect (hooks-correctness)

**github-api-preflight auth pre-check skips common 'cd x && gh ...' invocations**


- Files: global/hooks/github-api-preflight.sh

- Evidence: The auth-status branch is gated by `if echo "$CMD" | grep -qE '^gh '`. The `^` anchor only matches when `gh ` is the very first token. Verified: `cd /tmp && gh pr list` => skip (no auth pre-check), while `gh pr list` => auth check runs. Compound commands that change directory first (a routine pattern in this repo's skills) miss the early 'not authenticated' hint.

- Recommendation: Drop the `^` anchor and reuse the same word-boundary gh detection used for the scope gate, so chained `... && gh ...` also gets the auth diagnostic.

- Confidence: high


### `gap-heredoc-not-jq` — low/inconsistency (hooks-correctness)

**github-api-preflight and prompt-validator emit JSON via heredoc interpolation instead of jq**


- Files: global/hooks/github-api-preflight.sh, global/hooks/prompt-validator.sh

- Evidence: Every decision-bearing guard was hardened (issue #567/#578/#579) to build JSON with `jq -nc --arg`, with comments stating the heredoc form is an injection class that 'could flip the decision'. github-api-preflight still uses `cat <<EOF ... "additionalContext": "$message" ... EOF` and prompt-validator uses `"additionalContext": "$warning"`. Today both interpolate only static literal strings, so there is no live injection, but the pattern is exactly the one banned elsewhere and would silently produce malformed/injectable JSON if a dynamic value is ever interpolated.

- Recommendation: Convert both allow/warning emitters to `jq -nc --arg` (these are PreToolUse-allow and UserPromptSubmit additionalContext outputs), matching the rest of the hook suite, so future edits cannot reintroduce the injection class.

- Confidence: high


### `bash-write-guard-ps1-no-readbefore-on-argv-targets` — low/inconsistency (hooks-parity)

**bash-write-guard.ps1 enforces Read-before-Edit only on redirect targets, not on cp/mv/tee/sed-i/dd argv targets like the .sh**


- Files: global/hooks/bash-write-guard.ps1, global/hooks/bash-write-guard.sh

- Evidence: bash-write-guard.sh builds write_targets from BOTH extract_target_from_argv (cp/mv/tee/sed -i/dd/truncate/ln/chmod...) and the redirect target, then runs the Read-before-Edit loop over all of them (lines 394-444). bash-write-guard.ps1's Read-before-Edit loop iterates only `Get-RedirectTarget $cmd` (lines 80-97); it never extracts or checks argv destinations, so `tee existing.py` or `sed -i ... existing.py` without a prior Read is denied on bash but allowed on Windows. (The .ps1 header documents itself as a weaker regex approximation, so this is a known-weaker port rather than a silent regression.)

- Recommendation: If full parity is desired, extend bash-write-guard.ps1 to extract argv destinations for the write-tool set and run the same tracker check. Otherwise, explicitly state in the .ps1 header that Read-before-Edit is enforced for redirect targets only, so the limitation is documented rather than implied.

- Confidence: high


### `p4-guard-unbounded-gh-diff` — low/risk (hooks-performance)

**p4-timeline-guard's `gh pr diff` network call has no timeout wrapper, can hang up to the hook's 10s limit**


- Files: global/hooks/p4-timeline-guard.sh, global/settings.json

- Evidence: p4-timeline-guard.sh line 118: `DIFF_FILES=$(gh pr diff $REPO_ARG "$PR_NUM" --name-only 2>/dev/null || true)` — no `_run_with_timeout` wrapper, unlike merge-gate-guard.sh which deliberately bounds its gh call (`GH_CHECKS_TIMEOUT_SEC=10`, lib/timeout-wrapper.sh). github-api-preflight.sh's `gh auth status` (line 64) is also unbounded. On a slow network these block until Claude Code's own 10s hook timeout kills the process.

- Recommendation: Source lib/timeout-wrapper.sh in p4-timeline-guard.sh and wrap the `gh pr diff` call (and github-api-preflight's `gh auth status`) the same way merge-gate-guard does, so the gh internal default (~30s, longer than the hook timeout) cannot pin the chain.

- Confidence: high


### `markdown-validator-double-registered` — low/defect (hooks-performance)

**markdown-anchor-validator (heaviest non-network hook, 30s timeout) is registered in BOTH global and project settings — runs twice per Bash call**


- Files: global/settings.json, project/.claude/settings.json, docs/hooks-ownership.md

- Evidence: global/settings.json:168 registers `~/.claude/hooks/markdown-anchor-validator.sh` (timeout 30) on PreToolUse Bash, AND project/.claude/settings.json:23 registers the identical hook (timeout 30). docs/hooks-ownership.md line 21 declares the owner is `project/.claude/settings.json (project-only override)` and lines 3-7 state: "Claude Code merges the hooks arrays from every active settings source ... without deduplication. Every entry runs. To prevent latency and message noise from duplicate registrations, each hook is owned by exactly one settings file." With both surfaces active the validator (single-pass awk + sed/tr pipeline + git diff + lazy cross-file parse) executes twice on every `git commit`, doubling its cost against a 30s budget.

- Recommendation: Remove markdown-anchor-validator from global/settings.json (and global/settings.windows.json:97) per the documented ownership, leaving it only in project/.claude/settings.json; or update hooks-ownership.md if global ownership is now intended. Extend tests/scripts/test-no-duplicate-formatter.sh to assert markdown-anchor-validator appears in exactly one Bash-matcher surface, matching the doc's own guidance (line 9-11, 63-66).

- Confidence: high


### `windows-pwsh-cold-spawn-per-hook` — low/risk (hooks-performance)

**Windows Bash chain cold-spawns a fresh pwsh.exe process per hook (10 processes/Bash call) on top of a 110s timeout budget**


- Files: global/settings.windows.json

- Evidence: global/settings.windows.json Bash matcher runs 10 hooks each invoked as `pwsh -NoProfile -File ~/.claude/hooks/<hook>.ps1` (lines 87-134): dangerous(5)+github-api-preflight(10)+markdown-anchor-validator(30)+commit-message(5)+conflict(5)+pr-target(5)+pr-language(5)+merge-gate(30)+attribution(5)+p4-timeline(10) = 110s budget. Each `pwsh -NoProfile` cold start is ~100-300ms even when the hook's own work is trivial, so the happy-path overhead is ~1-3s of pure process startup per Bash command before any logic runs — distinct from the sh variant where bash startup is cheap.

- Recommendation: Document the per-call pwsh startup cost in COMPATIBILITY.md. Where feasible, batch the always-allow scope-gate guards (commit-message, pr-target, pr-language, attribution, conflict — all of which exit `allow` for non-matching commands) into a single dispatcher .ps1 so one pwsh process handles the cheap gates, reserving separate processes only for the network/heavy hooks.

- Confidence: low


### `backup-sh-unquoted-backupdir-wordsplit` — low/defect (scripts-robustness)

**backup.sh summary uses unquoted $BACKUP_DIR in ls -A, breaking on paths containing spaces**


- Files: D:\Sources\claude-config\scripts\backup.sh

- Evidence: Seven summary checks pass $BACKUP_DIR unquoted to ls, e.g. backup.sh:257 `if [ -d "$BACKUP_DIR/enterprise" ] && [ "$(ls -A $BACKUP_DIR/enterprise 2>/dev/null)" ]; then` and lines 262/270/279/282/285/288. If the repo is cloned under a path with spaces (e.g. a Windows MSYS path like `/c/Program Files/...` matching the script's own MINGW enterprise handling) the `ls -A` argument word-splits. Lines 279 and 282 additionally lack `2>/dev/null`.

- Recommendation: Quote the operand: `[ "$(ls -A "$BACKUP_DIR/enterprise" 2>/dev/null)" ]` and add `2>/dev/null` to lines 279/282 for consistency. Prefer a glob/`compgen` test over parsing `ls`.

- Confidence: high


### `installer-fetch-source-unguarded-bootstrap-sh` — low/risk (scripts-robustness)

**bootstrap.sh sources hooks/lib/installer-fetch.sh without a Test-Path guard, unlike install.sh and bootstrap.ps1**


- Files: D:\Sources\claude-config\bootstrap.sh

- Evidence: bootstrap.sh:168 `source "$INSTALL_DIR/hooks/lib/installer-fetch.sh"` runs unconditionally inside ensure_claude_cli. install.sh:117-120 guards it (`if [ ! -f "$repo_root/hooks/lib/installer-fetch.sh" ]; then warning ...; return 0; fi`) and bootstrap.ps1:114-117 guards the module (`if (-not (Test-Path -LiteralPath $modulePath)) { Write-Warn ...; return }`). If the cloned tag is missing the lib (older fork, partial clone, network truncation) bootstrap.sh aborts the whole run via `set -e` instead of warning and continuing.

- Recommendation: Add a `[ -f "$INSTALL_DIR/hooks/lib/installer-fetch.sh" ] || { warning 'installer-fetch.sh missing — refusing unverified install'; return 0; }` guard before the source, matching the other two entry points.

- Confidence: high


### `windows-sensitive-file-guard-missing-ssh-aws` — low/inconsistency (security-surface)

**Windows sensitive-file-guard.ps1 does not block SSH private keys or ~/.aws/credentials that the bash version blocks, and the deny-list does not cover them either**


- Files: global/hooks/sensitive-file-guard.ps1, global/hooks/sensitive-file-guard.sh, global/settings.windows.json, global/settings.json

- Evidence: sensitive-file-guard.sh blocks SSH private keys (lines 85-87: `id_rsa|id_rsa.*|id_ed25519|...`) and AWS credential/config files under ~/.aws (lines 88-94). sensitive-file-guard.ps1 only matches `\.env`, `\.(pem|key|p12|pfx)$`, and the `(secrets|credentials|passwords)[/\\]` directory pattern (lines 51-65) — it has NO id_rsa/id_ed25519 case and NO .aws/credentials case. permissions.deny in both settings files (settings.json lines 89-108, settings.windows.json lines 423-442) likewise lacks SSH-key and bare-file `.aws/credentials` patterns (it only has `**/credentials/**` as a directory glob, which does not match the bare file `~/.aws/credentials`). Net effect: a structured Read of `~/.ssh/id_rsa` or `~/.aws/credentials` is blocked on macOS/Linux (by sensitive-file-guard.sh) but NOT on Windows (neither deny-list nor sensitive-file-guard.ps1 catches it). No parity test guards this divergence (only test-p4-timeline-guard-parity.sh exists; test-sensitive-file-guard.{sh,ps1} do not exercise id_rsa or .aws/credentials).

- Recommendation: Add the SSH-private-key and `.aws/credentials`+`config` cases to sensitive-file-guard.ps1 to match the .sh version, and add a sensitive-file-guard sh-vs-ps1 parity fixture test. Optionally add `Read(**/.ssh/id_*)`, `Read(**/.aws/credentials)`, `Read(**/.aws/config)` to permissions.deny for defense-in-depth on both platforms.

- Confidence: high


### `win-permissions-allow-narrower` — low/inconsistency (settings-schema)

**permissions.allow on Windows omits nearly all gh write-verbs and gh api allowlist present on POSIX**


- Files: global/settings.json, global/settings.windows.json

- Evidence: settings.json permissions.allow (lines 19-88) lists ~70 entries including gh pr create/edit/merge/close/reopen/ready/comment/review/checkout, gh issue create/edit/close/reopen/comment/develop, gh label list/create/edit/delete, gh run rerun/cancel/download/watch, gh workflow run/enable/disable, gh release create/edit/delete/upload, and the full gh api allowlist (lines 80-87: `gh api -X GET:*`, `gh api repos/*:*`, `gh api graphql:*`, etc.). settings.windows.json permissions.allow (lines 392-421) has only 28 entries — read-only verbs plus gh auth status — and omits every write verb and the entire gh api block. A Windows user running the same /issue-work or /pr-work skill will hit a permission prompt on `gh pr create`, `gh issue comment`, `gh api ...`, etc., that a POSIX user does not. The allowlists are tool-level (not shell-level), so there is no platform reason for the divergence.

- Recommendation: Synchronize settings.windows.json permissions.allow with the POSIX list. Either copy the full ~70-entry allowlist verbatim, or extract the allowlist into a shared fragment that both files derive from (the repo already centralizes other policy via scripts/lib). Add a CI check that diffs the two allow arrays.

- Confidence: high


### `win-note-comment-stale` — low/inconsistency (settings-schema)

**Edit|Write|Read matcher _note on Windows is stale relative to POSIX (omits memory-write-guard ordering and issue #521)**


- Files: global/settings.json, global/settings.windows.json

- Evidence: settings.json line 114 _note documents three-hook ordering: 'sensitive-file-guard must run before pre-edit-read-guard ... memory-write-guard runs after pre-edit-read-guard so it only validates writes the harness has cleared. See docs/hooks-ownership.md and issues #424, #521.' settings.windows.json line 63 _note is the older two-hook version: 'sensitive-file-guard must run before pre-edit-read-guard so denied files are not tracked. See docs/hooks-ownership.md and issue #424.' — it omits the memory-write-guard ordering rationale and the #521 reference, consistent with memory-write-guard never being wired on Windows (see win-missing-memory-hooks).

- Recommendation: Once memory-write-guard.ps1 is added to the Windows Edit|Write|Read matcher, update the Windows _note to match the POSIX wording including the #521 reference. Until then the stale note is a symptom of the larger wiring gap.

- Confidence: high


### `fleet-orchestrator-resume-flag-missing-from-hint` — low/inconsistency (skills-quality)

**fleet-orchestrator body documents --resume <fleet-id> but argument-hint omits it**


- Files: global/skills/_internal/fleet-orchestrator/SKILL.md

- Evidence: Body line 401: "Resume is manual: re-invoke the skill with `--resume <fleet-id>`; it re-reads the manifest and re-launches workers in non-terminal states". The frontmatter argument-hint (line 4) lists --max-parallel, --retry, --poll-interval, --dry-run, --reanchor-interval, --top-k, --agents-dir but not --resume.

- Recommendation: Add `[--resume <fleet-id>]` to the argument-hint so the documented resume path is discoverable from the skill signature, consistent with how every other accepted flag is listed.

- Confidence: high


### `traceability-loop-metadata-no-loop-body` — low/inconsistency (skills-quality)

**traceability declares max_iterations/halt_conditions/loop_safe but its body has zero loop/iteration content; passes the validator's drift check only because the regex matches the frontmatter keys**


- Files: global/skills/_internal/traceability/SKILL.md, scripts/validate_skills.sh

- Evidence: traceability/SKILL.md frontmatter declares `loop_safe: true`, `max_iterations: 1`, and a halt_conditions block. grep -niE "(loop|retry|iteration|poll)" matches only line 13 `loop_safe: true` and line 14 `max_iterations: 1` — there is no body match. The validator's drift guard (validate_skills.sh line 221-229) greps the whole file, so the frontmatter keys `loop_safe`/`max_iterations` self-satisfy the `loop|iteration` regex and the check passes vacuously. Sibling single-pass skills risk-control (line 268), soup-inventory (line 289), and evidence-pack (line 235) all include a `### Side Effects and Loop-Safety` body section; traceability does not. Per _policy.md line 42 iteration-control metadata is 'Required for skills whose body contains a polling loop... Optional otherwise' — a max_iterations:1 single-pass skill has no loop.

- Recommendation: Either add a short `### Side Effects and Loop-Safety` section to traceability/SKILL.md (matching its risk-control/soup-inventory/evidence-pack siblings, explaining why a single-pass loop_safe:true skill is idempotent), or, if the loop metadata is purely expressing exit semantics, document that intent inline. Optionally tighten the validator to grep only the post-frontmatter body so the drift check cannot be self-satisfied by the `loop_safe`/`max_iterations` keys.

- Confidence: high


### `loop-safe-false-missing-side-effect-section` — low/inconsistency (skills-quality)

**Most loop_safe:false skills omit the side-effect / non-idempotency body section the validator checks for**


- Files: global/skills/_internal/issue-work/SKILL.md, global/skills/_internal/pr-work/SKILL.md, global/skills/_internal/release/SKILL.md, global/skills/_internal/harness/SKILL.md, global/skills/_internal/branch-cleanup/SKILL.md, global/skills/_internal/issue-create/SKILL.md, global/skills/_internal/implement-all-levels/SKILL.md, global/skills/_internal/fleet-orchestrator/SKILL.md, global/skills/_internal/sonar-fix/SKILL.md

- Evidence: validate_skills.sh lines 237-244 warn when a `loop_safe: false` skill lacks a heading matching side-effect/idempoten/loop-safety. Of the 11 loop_safe:false skills, only evidence-pack and memory-review have such a heading. For issue-work, release, harness, branch-cleanup, issue-create, implement-all-levels, fleet-orchestrator the ONLY occurrence of `loop_safe`/`idempoten`/`side-effect` is the frontmatter line itself (e.g. issue-work: the single match is line 13 `loop_safe: false`; release: line 15; harness: line 7) — the body never explains what external artifacts (PRs/issues/releases/branch deletions) make the skill non-idempotent. _policy.md line 57 defines loop_safe:false as 'invocations create external artifacts ... Wrapping in /loop would produce duplicates or destructive cascades.'

- Recommendation: Add a one- to three-line side-effect/loop-safety note to each loop_safe:false skill body (the evidence-pack `### Side Effects and Loop-Safety` section is a good template), stating which external artifact the skill creates and why repeated invocation is unsafe. This silences the warn-only validator check and makes the non-idempotency contract self-documenting rather than living only in a frontmatter boolean.

- Confidence: high


### `p4-timeline-windows-all-expired` — low/tech-debt (tech-debt-lifecycle)

**P4 EPIC #454 timeline windows all expired — guard/reminder hooks now permanently no-op**


- Files: global/policies/p4-timeline.json, global/hooks/p4-timeline-guard.sh, global/hooks/p4-timeline-reminder.sh, global/hooks/p4-timeline-guard.ps1, global/hooks/p4-timeline-reminder.ps1

- Evidence: Today is 2026-05-29. global/policies/p4-timeline.json pins all windows in the past: "p4_grace_until": "2026-05-03T22:15:57Z", "p4_observation_until": "2026-05-17T22:15:57Z", "p4_freeze_until": "2026-05-20T22:15:57Z". p4-timeline-reminder.sh exits silently once now() >= p4_freeze_until (line 57: 'if [ -n "$FREEZE_EPOCH" ] && [ "$NOW_EPOCH" -ge "$FREEZE_EPOCH" ]; then exit 0'), and p4-timeline-guard.sh allow_responses once now() >= the relevant deadline (line 102 'if [ "$NOW_EPOCH" -ge "$GRACE_EPOCH" ]; then allow_response' / line 136 same for observation). With every window expired, both hooks fire on every Bash/Edit/Write/SessionStart but can never block or print anything — pure overhead still registered in settings.json (global/settings.json lines 133, 209, 241; global/settings.windows.json lines 77, 132, 164).

- Recommendation: The P4 rollout is complete (freeze ended 2026-05-20). Decide the terminal state: either (a) flip p4_strict_schema to true to lock in strict-schema dispatch and then retire the timeline hooks + policy file, or (b) if strict mode is being abandoned, remove the four p4-timeline hook files, their six settings.json/settings.windows.json registrations, the policy file, and the HOOKS.md entries (lines 1027-1028, 1342-1364). Either way, stop shipping dead always-firing guards.

- Confidence: high


### `conflict-guard-no-behavioral-test` — low/tech-debt (tests-ci)

**conflict-guard.sh is the only active PreToolUse guard with no decision-logic test**


- Files: global/hooks/conflict-guard.sh, tests/hooks/, global/settings.json

- Evidence: conflict-guard.sh is wired as an active Bash PreToolUse hook (settings.json line 184). A per-guard cross-reference shows every other active guard has a dedicated behavioral test under tests/hooks/ or tests/scripts/ (e.g. test-merge-gate-squash-only.sh, test-sensitive-file-guard.sh), but there is no test-conflict-guard.sh. Its only coverage is in the orphaned hook-json-escape-group1.sh, which exercises only its deny_response/allow_response helpers — not its four real checks (conflict-guard.sh lines 51,64,67,70,79-82: the `git (merge|rebase|cherry-pick|pull)` scope regex, MERGE_HEAD/REBASE_HEAD/CHERRY_PICK_HEAD detection, and the dirty-tree `git status --porcelain` gate).

- Recommendation: Add tests/hooks/test-conflict-guard.sh that drives the hook with synthesized PreToolUse payloads against a temp git repo (mirroring test-markdown-anchor-validator.sh's temp-repo pattern): assert deny when MERGE_HEAD/REBASE_HEAD/CHERRY_PICK_HEAD exist or the tree is dirty, and allow on a clean repo / non-conflict-prone commands. Without it, a change to the scope regex or git-dir paths silently disables conflict prevention.

- Confidence: high


### `validate-hooks-path-missing-anchor-fixtures` — low/inconsistency (tests-ci)

**validate-hooks.yml path filter omits tests/markdown-anchor-validator/** so changes to those fixtures do not trigger the suite that consumes them**


- Files: .github/workflows/validate-hooks.yml, tests/markdown-anchor-validator/fixtures/baseline-valid.md, tests/hooks/test-markdown-anchor-validator.sh

- Evidence: validate-hooks.yml paths (lines 7-26) include 'tests/hooks/**' and 'tests/hooks/fixtures/**' but not 'tests/markdown-anchor-validator/**'. test-markdown-anchor-validator.sh line 23-24 reads its fixtures from tests/markdown-anchor-validator/fixtures/ (e.g. bug-a-excessive-hashes.md, bug-b-inline-code.md). A PR that edits only those fixtures (e.g. to adjust an expected case) would not trigger validate-hooks.yml, so the fixture change goes unvalidated until the next unrelated hook change.

- Recommendation: Add 'tests/markdown-anchor-validator/**' to the validate-hooks.yml paths list so fixture edits run the suite that depends on them.

- Confidence: high


### `version-map-false-doc-claim-hooks-surfaced` — low/inconsistency (versioning)

**VERSION_MAP.yml claims the hooks version is surfaced to operators via HOOKS.md and ENFORCEMENT.md, but neither file contains the version**


- Files: D:\Sources\claude-config\VERSION_MAP.yml, D:\Sources\claude-config\HOOKS.md, D:\Sources\claude-config\ENFORCEMENT.md, D:\Sources\claude-config\scripts\gen-hooks-md.sh

- Evidence: VERSION_MAP.yml line 14 states the hooks track is `Surfaced to operators via HOOKS.md and ENFORCEMENT.md.` A grep for the literal value `1.1.0` returns no matches in HOOKS.md or ENFORCEMENT.md, and a case-insensitive search for any 'hooks version / hooks bundle version' phrase in those files also returns nothing. HOOKS.md's authoritative catalog is machine-generated by scripts/gen-hooks-md.sh, whose build_generated_section (lines 160-213) emits per-hook fields and a `_Total: N bash hooks_` line but never reads VERSION_MAP.yml or stamps any bundle version. The documented surfacing simply does not exist.

- Recommendation: Make the claim true: have gen-hooks-md.sh read VERSION_MAP.yml's `hooks` field and emit a `Hooks bundle version: <X>` line into the auto-generated HOOKS.md header (and reference it from ENFORCEMENT.md), then add a check_versions assertion comparing it to VERSION_MAP. Otherwise correct VERSION_MAP.yml line 14 to remove the false surfacing claim.

- Confidence: high


### `changelog-only-tracks-suite-no-per-version-sections` — low/tech-debt (versioning)

**CHANGELOG tracks only the suite version and has no released per-version sections, so plugin/plugin-lite/settings-schema/hooks bumps are invisible and the file violates the project's own Keep-a-Changelog standard**


- Files: D:\Sources\claude-config\CHANGELOG.md, D:\Sources\claude-config\VERSION_MAP.yml

- Evidence: CHANGELOG.md declares it `adheres to Semantic Versioning` (line 6) but a grep for released-version headers `^## \[?[0-9]` / `^## v[0-9]` returns NO matches — the entire body sits under `## [Unreleased]` (line 8) and the only version reference is the single compare link `[Unreleased]: .../compare/v1.10.0...HEAD` (line 178), which is the suite track only. There are no per-track or per-version sections for plugin 2.3.0, plugin-lite 1.1.0, settings-schema 1.16.0, or hooks 1.1.0. The project's own documentation standard (rules .../project-management/documentation.md) prescribes `## [1.2.0] - YYYY-MM-DD` released sections, which this CHANGELOG lacks.

- Recommendation: On each release, cut the `[Unreleased]` content into a dated, versioned section (e.g. `## [suite 1.11.0] - 2026-XX-XX` or per the chosen track) and add a matching compare link, so released history is recoverable and the independent tracks are each represented. Consider a release-skill step that performs this CHANGELOG roll-over alongside the VERSION_MAP bump in Step 1.5.

- Confidence: high


### `sync-json-version-global-regex-fragility` — low/risk (versioning)

**bash sync_versions.sh rewrites every "version" key globally; safe today only because settings.json has exactly one such key, but the invariant is undocumented and brittle**


- Files: D:\Sources\claude-config\scripts\sync_versions.sh, D:\Sources\claude-config\global\settings.json

- Evidence: sync_versions.sh set_json_version (line 56) runs `sed -E 's/("version"[[:space:]]*:[[:space:]]*")[^"]+(")/.../'` with no occurrence limit, replacing ALL `"version"` occurrences in the file. This currently works because grep confirms settings.json has only one `"version"` (line 514) and settings.windows.json one (line 4). But if a future nested object (e.g. a hook config or schema block) introduces a second `"version"` key, sync would silently overwrite it with the settings-schema value. The PowerShell checker Test-JsonVersion takes the safer first-match-line approach (check_versions.ps1 line 52), but the bash syncer does not, and the single-version assumption is nowhere asserted.

- Recommendation: Constrain the sed to the first match (or anchor it to a top-level key), and/or add a check_versions assertion that each settings file contains exactly one top-level `version` key, so an accidental second occurrence is caught rather than silently clobbered.

- Confidence: high


### `dangerous-command-guard-allow-shape-mismatch` — info/inconsistency (hooks-parity)

**dangerous-command-guard allow response carries the reason under different JSON keys (.sh permissionDecisionReason vs .ps1 additionalContext)**


- Files: global/hooks/dangerous-command-guard.sh, global/hooks/dangerous-command-guard.ps1, global/hooks/lib/CommonHelpers.psm1

- Evidence: dangerous-command-guard.sh allow_response emits `permissionDecision: "allow", permissionDecisionReason: $reason` (lines 66-72). dangerous-command-guard.ps1 Respond-Allow calls `New-HookAllowResponse -AdditionalContext $Reason`, and CommonHelpers.psm1::New-HookAllowResponse places the string under `additionalContext` (lines 50-64), not `permissionDecisionReason`. Both still allow, so behavior is unaffected; only the diagnostic field name differs across hosts.

- Recommendation: Pick one field for the allow-path diagnostic and use it on both sides (the harness treats `additionalContext` as model-visible context and `permissionDecisionReason` is primarily meaningful for deny), or drop the reason on allow in both. Low priority — no functional impact.

- Confidence: high


### `installers-no-noninteractive-flag` — info/improvement (scripts-robustness)

**install.sh/.ps1 and bootstrap.sh/.ps1 provide no non-interactive (--yes/CI) mode; curl|bash relies on read returning defaults**


- Files: D:\Sources\claude-config\scripts\install.sh, D:\Sources\claude-config\bootstrap.sh, D:\Sources\claude-config\scripts\install.ps1, D:\Sources\claude-config\bootstrap.ps1

- Evidence: install.sh has 7 interactive `read -p` prompts and no `[ -t 0 ]` stdin check or `--yes` flag (grep: 7 occurrences; only CI reference is a comment at line 338 about LAUNCHD/SYSTEMD test overrides). The documented bootstrap entrypoint `curl -sSL ... | bash` (bootstrap.sh:8) feeds the script via stdin, so every `read` gets EOF and silently takes its default (install type 3, content-language english, npm yes, etc.) — workable but means the one-line installer makes consequential choices with no operator confirmation and no way to script a specific profile.

- Recommendation: Add an explicit non-interactive mode (e.g. `--yes` / `CLAUDE_CONFIG_NONINTERACTIVE=1`) that selects documented defaults, and detect `! [ -t 0 ]` to either require that flag or print which defaults are being assumed. This also makes the installers testable in CI without here-doc input.

- Confidence: high


### `deny-list-narrower-than-guards-by-design-gap` — info/tech-debt (security-surface)

**permissions.deny is a strict subset of what the bash guards block (.crt/.cer, .gnupg, .netrc/.npmrc/.pypirc, .kube/config, docker config, /etc/shadow) — defense-in-depth gap if a guard is ever disabled**


- Files: global/settings.json, global/hooks/bash-sensitive-read-guard.sh, global/hooks/bash-write-guard.sh

- Evidence: bash-sensitive-read-guard.sh is_sensitive() (lines 94-146) and bash-write-guard.sh is_sensitive_target() (lines 62-82) cover a much wider set than permissions.deny: `.crt`/`.cer`, `*/.gnupg/*`, `.netrc`, `.npmrc`, `.pypirc`, `.dockerconfigjson`, `.docker/config.json`, `.kube/config`, `/etc/shadow`, `/etc/sudoers`, `/etc/ssh/ssh_host_*_key`. permissions.deny (settings.json lines 89-108) only lists `.env*`, `**/secrets/**`, `**/credentials/**`, `*.pem`, `*.key`, `*.p12`, `*password*`. permissions.deny is the only layer that also gates non-Bash tool channels (e.g. a future MCP file-read tool) — so these extra secret shapes rely entirely on the Bash/Edit guards. The guard comments claim the patterns 'mirror permissions.deny[]' (bash-sensitive-read-guard.sh line 93, bash-write-guard.sh line 60) but they are in fact a superset, so the mirror claim is inaccurate.

- Recommendation: Either extend permissions.deny to include the high-value extra shapes (`Read(**/*.crt)`, `Read(**/.gnupg/**)`, `Read(**/.netrc)`, `Read(**/.npmrc)`, `Read(**/.kube/config)`) so the declarative layer is not strictly weaker than the imperative guards, or correct the 'mirror permissions.deny' comments to 'superset of permissions.deny' to avoid implying parity that does not exist.

- Confidence: high


### `git-fetch-allow-divergence` — info/inconsistency (settings-schema)

**git fetch allowlist differs: POSIX scopes to origin/upstream, Windows uses broad git fetch:***


- Files: global/settings.json, global/settings.windows.json

- Evidence: settings.json allows two scoped entries: `"Bash(git fetch origin:*)"` (line 32) and `"Bash(git fetch upstream:*)"` (line 33). settings.windows.json allows a single broader entry `"Bash(git fetch:*)"` (line 405). The Windows form is strictly more permissive (allows `git fetch <any-remote>`), an inconsistency in the permission posture between platforms.

- Recommendation: Pick one form for both files. Either tighten Windows to the two scoped `git fetch origin:*` / `git fetch upstream:*` entries to match POSIX, or relax POSIX to `git fetch:*` if the broad form is intended — and apply the same decision to both.

- Confidence: high


### `tier-presets-missing-on-oversized-skills` — info/inconsistency (skills-quality)

**_policy.md calls tier presets 'Required' for >5KB bodies, but ~10 skills exceed 5KB without tiers; the rollout is documented as phased, leaving policy text and practice divergent**


- Files: global/skills/_policy.md, docs/TOKEN_OPTIMIZATION.md, global/skills/_internal/fleet-orchestrator/SKILL.md, global/skills/_internal/harness/SKILL.md, global/skills/_internal/release/SKILL.md, global/skills/_internal/research/SKILL.md, global/skills/_internal/doc-index/SKILL.md, global/skills/_internal/doc-review/SKILL.md, global/skills/_internal/issue-create/SKILL.md, global/skills/_internal/memory-review/SKILL.md, global/skills/_internal/implement-all-levels/SKILL.md, global/skills/_internal/branch-cleanup/SKILL.md

- Evidence: _policy.md line 135: 'Required for skills whose SKILL.md body exceeds 5 KB (current examples: issue-work, pr-work).' Measured body sizes (frontmatter stripped) exceeding 5KB without a `tiers:` block: fleet-orchestrator (20082B), harness (16730B), release (16241B), research (12919B), doc-index (12150B), issue-create (10730B), doc-review (10458B), memory-review (10161B), implement-all-levels (7363B), branch-cleanup (6266B). Only issue-work, pr-work, plus the regulated-track quartet (evidence-pack/risk-control/soup-inventory/traceability) declare tiers. TOKEN_OPTIMIZATION.md line 490-496 frames this as expected: 'Tiered Skills (this PR): pr-work, issue-work ... Additional skills will adopt the schema as their bodies cross the 5 KB threshold.'

- Recommendation: Resolve the wording mismatch so the normative contract matches reality: either soften _policy.md line 135 from 'Required' to 'Recommended; adopted incrementally (see docs/TOKEN_OPTIMIZATION.md rollout)' and cross-link the phased-rollout note, or schedule tier adoption for the listed oversized skills. As-is, a strict reader of _policy.md would conclude 10 skills are non-conformant, while the rollout doc says they are not.

- Confidence: high


### `stale-err-log-root` — info/tech-debt (tech-debt-lifecycle)

**Stale err.log scratch artifact left in repository root**


- Files: err.log

- Evidence: err.log (139 bytes, mtime 2026-04-10) sits in the repo root containing leftover doc-index tool output: '[INFO] Project: /project/claude-config / [INFO] Found 195 markdown files / [INFO] Generating manifest.yaml...'. It is matched by .gitignore '*.log' (line 24) so it is not tracked, but it remains physically present in the working tree as a forgotten run artifact from a containerized run (path /project/claude-config indicates a Docker/CI run, not this Windows checkout).

- Recommendation: Delete err.log from the working tree. It is ignored output, not a source file; leaving it confuses anyone inspecting the repo root and serves no purpose.

- Confidence: high


## Rejected (verified as intentional design or not a defect)

- `info-cmg-singlequote-defer` (intentional design): commit-message-guard only inspects double-quoted -m messages (single-quoted bypass deferred to git hook)
- `info-dcg-relative-rm-scope` (intentional design): dangerous-command-guard does not flag rm -rf on relative targets (., *, ../..)
- `bash-chain-blocking-budget-135s` (intentional design): Bash PreToolUse chain: 14 synchronous hooks, 135s worst-case timeout budget added to every Bash call
- `gh-merge-triple-network-roundtrip` (intentional design): `gh pr merge` triggers up to 3 separate blocking GitHub network round-trips across the chain
- `jq-stdin-reparse-14x` (intentional design): Redundant work: the same JSON stdin is read and re-parsed by jq 14 times per Bash command
- `plugin-finding-levels-without-severity` (intentional design): Plugin code-review skills declare finding_levels but no severity, leaving no declared primary triage tier
- `win-env-missing-ssl-cert` (intentional design): env SSL_CERT_FILE / SSL_CERT_DIR present on POSIX are absent on Windows env block
- `safe-rm-allowlist-aborts-backup` (intentional design): backup.sh aborts (set -e) when run from any clone path outside the safe-rm allow-list
- `sync-versions-ps1-strips-trailing-newline` (intentional design): sync_versions.ps1 writes consumers with Set-Content -NoNewline, dropping the trailing newline that sync_versions.sh preserves
- `validate-hooks-skills-skip-develop` (intentional design): validate-hooks and validate-skills only trigger on PRs to main, never on feature->develop PRs where merges actually happen
- `p4-parity-test-silently-skips-without-pwsh` (speculative/resolved): The only cross-implementation behavioral test (p4-timeline parity) silently skips when pwsh is absent, and validate-hooks.yml never installs pwsh
- `p4-phase2-fallback-dead-code` (intentional design): p4-timeline hooks still carry the 'Phase 2 will drop' settings.json fallback after relocation (#652) already removed the fallback source
- `p4-strict-schema-never-flipped` (intentional design): P4 migration final step never executed: p4_strict_schema still false after its observation gate closed 2026-05-17
- `changelog-missing-652-relocation` (intentional design): CHANGELOG.md has no entry for the #652 harness_policies relocation (most recent commit, a Phase 2 milestone)
- `validate-skills-iso-class-grace-todo` (intentional design): validate_skills.sh iso_class check stuck in 'P1 grace period' WARNING with open-ended 'next release' TODO


## Completeness Critic (gaps the per-dimension audit may have missed)

The agent diff shows the `plugin/agents` copies still carry `temperature: 0.3` (the unsupported field the recent commit 1212107 removed from project agents) and lack the `color`/`permissionMode` fields added in commit e9569f4 — so the two trees have **genuinely diverged**: a spec-correctness fix was applied to one copy but not its mirror. This is the SSOT-gap theme with security/correctness weight. `batch-drift-scratch/` is gitignored (just local clutter), and `err.log` is untracked clutter. I have enough confirmed evidence. Let me compile the gap analysis.

Based on reading the actual repository and deployed state, here are the concrete gaps the single-dimension audit likely MISSED, plus issues I confirmed:

## Gaps the audit likely missed

**1. Orphaned test suites are far broader than "~12" — and include the parity test itself.** 17 test scripts are referenced by NO workflow and run by no runner: `tests/scripts/test-windows-hooks-parity.sh`, `test-killswitch.sh`, `test-hook-ordering.sh`, `test-install-deploys-bash-lib.sh`, `test-install-preserves-customization.sh`, `test-migrate-halt-conditions.sh`, `test-no-duplicate-formatter.sh`, `test-severity-enum.sh`, `test-strict-lenient-dispatch.sh`, `test-workspace-prefix.sh`, `test-installer-fetch.sh`, plus `tests/safe-rm-rf.sh`, `tests/hook-json-escape{,-group1,-group2}.sh`, `tests/sonar-fix/test-fixtures.sh`, and `tests/batch_drift_regression/test-run-regression.sh`. The self-referential failure: the suite designed to catch settings.json↔settings.windows.json drift is the one CI never runs. (I confirmed it exits 1 correctly when run manually and currently FAILS — the audit's "currently-failing suite" is this one, and it correctly reports drift; the bug is wiring, not the test's exit code.)

**2. The Windows-parity finding has a concrete, confirmed 7-hook security gap.** Running the orphaned test shows `settings.windows.json` is missing: `bash-write-guard`, `bash-sensitive-read-guard`, `gh-write-verb-guard`, `traceability-guard`, `memory-write-guard` (PreToolUse), `memory-access-logger` (PostToolUse Read), and `memory-integrity-check` (SessionStart). The installer (`install.ps1:441`) copies `settings.windows.json` → `~/.claude/settings.json` on Windows, so Windows users genuinely run without these guards. The audit named the theme but may not have enumerated which guards are dormant on Windows.

**3. Deployed `~/.claude/` state vs source was not audited (end-to-end install→use).** The live `~/.claude/settings.windows.json` (dated Apr 23) does NOT match source — it's a vestigial file the installer doesn't even consume on Windows (the operative file is `settings.json` filled with pwsh commands). There is NO checker that the deployed hooks/settings match source after install, and no `.install-manifest.json` integrity verification on re-sync. A `settings.json.bak-20260529` and stale `settings.windows.json` sit in the deployed tree unmanaged.

**4. `plugin/agents/` vs `project/.claude/agents/` is an unguarded SSOT pair with confirmed correctness drift.** All 8 agents differ. `plugin/agents/*` still carry `temperature: 0.3` (the unsupported field that commit 1212107 removed from the project copies) and lack the `color`/`permissionMode` fields added in e9569f4. A spec-correctness fix landed on one copy only. `sync_references.sh`/`check_references.sh` cover neither tree.

**5. The error-helper anti-pattern is confirmed in BOTH scripts and is worse than described.** `install.sh:46` and `backup.sh:40` define `error()` as pure echo (no exit). Under `set -euo pipefail`, every `cp … || error "…"` (install.sh enterprise policy copies at lines 277-313; backup.sh at lines 98,143,220-236) suppresses errexit and continues reporting success after a failed copy. The same helpers also emit emoji (❌✅⚠️) — which the repo's own commit policy bans — an untested output-content inconsistency.

**6. Dimensions/trees with little or no inspection:** `enterprise/` (3 files: CLAUDE.md + rules/compliance.md + rules/security.md) is covered by no behavioral test and no SSOT guard despite being the org-policy authority and an install target with the silent-copy bug above. `bootstrap.sh`/`bootstrap.ps1` (18-23KB top-level, parallel install logic to `scripts/install.*`) are a fourth duplication pair not in the audit's SSOT list and exercised by no test. `docs/.index/` (manifest/router/graph/bundles.yaml) integrity is validated by no workflow — stale doc-index entries would ship green. `plugin-lite/` skill/manifest content is only file-existence-checked.

**7. `.ps1` test siblings are dead weight.** `tests/hooks/` contains `test-cleanup.ps1`, `test-dangerous-command-guard.ps1`, `test-language-validator.ps1`, `test-markdown-anchor-validator.ps1`, `test-prompt-validator.ps1`, `test-runner.ps1`, `test-sensitive-file-guard.ps1`, `test-team-limit-guard.ps1` plus `tests/scripts/*.ps1` — no CI job invokes a PowerShell runner for hook behavior (only two `pwsh` manifest-helper steps exist), so the PowerShell hooks have behavioral tests that never execute. This is the structural reason behavioral parity silently diverged.

**8. Systemic gap not catchable per-dimension:** there is no single "deployed reality vs source vs declared" reconciliation. VERSION_MAP declares `hooks: 1.1.0` but no consumer reads it; the parity test exists but isn't wired; the deployed Windows settings are stale; agent trees diverged. Each is plausible in isolation; together they show the repo's verification machinery is built but **selectively wired**, and nothing audits the wiring coverage itself (a meta-check: "every test file is referenced by some runner; every duplicated artifact is covered by some diff guard"). That meta-check is the missing keystone.

Files of record: `tests/scripts/test-windows-hooks-parity.sh`, `global/settings.windows.json`, `scripts/install.ps1` (L436-451), `scripts/install.sh` (L46, 277-313), `scripts/backup.sh` (L40, 98-236), `plugin/agents/*.md` vs `D:\Sources\claude-config\project\.claude\agents\*.md`, `.github/workflows/validate-hooks.yml`, `.github/workflows/validate-skills.yml`, `VERSION_MAP.yml`, `bootstrap.sh`/`bootstrap.ps1`, `enterprise/`.


---

*Generated by the `claude-config-deep-audit` workflow (96 agents, 12 dimensions, adversarial verification). Run 2026-05-29.*
