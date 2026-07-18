# issue-work triage tests

Unit tests for the issue-work triage state machine
(`global/skills/_internal/issue-work/scripts/triage.sh`). The suite shadows `gh`
with `fake-gh.sh`, so no network or GitHub auth is required.

## Run

```bash
bash tests/issue-work/test-triage.sh
```

The suite is wired into CI by `.github/workflows/validate-skills.yml`.

## Files

| File | Role |
|------|------|
| `test-triage.sh` | Test runner: pure-function unit tests + end-to-end scenarios. |
| `fake-gh.sh` | Canned `gh` for the subset of commands triage.sh calls; records mutations to `mutations.log` and appends posted comments so idempotency reruns observe prior state. |
| `test-workspace.sh` | Test runner for the workspace lifecycle stage (`scripts/workspace.sh`); see the dedicated section below. |
| `test-agents.sh` | Test runner for the subagent spawn-contract + single-writer-lease stage (`scripts/agents.sh`); see the dedicated section below. |

## Acceptance-criteria coverage (issue #829)

| AC | Scenario | Assertion |
|----|----------|-----------|
| AC1 | Oversized issue, no children, plan supplied | `decomposed`; two children created; exactly one parent summary. |
| AC2 | Oversized parent with an eligible open child | `proceed` on the child; no children created; no decomposition comment. |
| AC3 | Documented, unchanged blocker | Rerun posts no additional comment (fingerprint match). |
| AC4 | Blocker set changed between runs | Exactly one updated comment. |
| AC5 | Blocker resolved between runs (new human info) | Fresh state re-read flips `blocked` -> `proceed`. |
| AC6 | Partial decomposition (one of two children exists) | Rerun creates only the missing child. |
| AC4b | Multi-blocker: first unchanged, a later blocker flips state | Exactly one updated comment (M1 fingerprint-leak regression). |
| AC7 | Claim race lost on the first child | Advances to the next eligible child, rolls back the speculative `@me` assignment (m4), and proceeds. |
| AC8 | Parent whose children are all closed | `skipped` with a completion-audit reason; no closed child is claimed. |
| AC9 | Blocked/decomposed outcomes | No assignment and no child/branch creation. |

## Verification matrix coverage

| Verification item | Scenario |
|-------------------|----------|
| Unchanged vs changed blocker, new human comment | AC3, AC4, AC5. |
| Existing children, partial decomposition | AC2, AC6. |
| Concurrent claim | AC7. |
| Cyclic parent/child relationship | `VER cycle` — visited guard terminates the traversal. |
| Max child traversal depth | `VER max-depth` — depth guard yields `failed`, never loops. |
| Three identical fetch failures | `VER m1` — retry helper stops with a `blocked` outcome (issue #829 risk control). |
| Batch reporting does not treat decomposition as a merge success | `VER batch reporting` — asserts the accounting guard in `reference/batch-mode.md` B-5. |

## Scope note

These are bash tests. PowerShell parity for the triage gate is deferred to issue
#832 (team/batch/cross-platform regression integration), per the epic #828 split.

## Workspace lifecycle tests (issue #838)

Unit and end-to-end tests for the workspace lifecycle stage
(`global/skills/_internal/issue-work/scripts/workspace.sh`), which turns a
triage `proceed` outcome into an isolated, identity-verified clone
(`CLAIMED -> CLONING -> READY`). The suite drives a real local bare git
repository rather than a fake — this stage never calls `gh`, so no shim is
needed to exercise it without network access. See
`reference/workspace-lifecycle.md` for the full contract.

### Run

```bash
bash tests/issue-work/test-workspace.sh
```

The suite is wired into CI by `.github/workflows/validate-skills.yml`.

### Acceptance-criteria coverage (issue #838)

| AC | Scenario | Assertion |
|----|----------|-----------|
| AC1 | Run-root layout | Run root sits under the temp base, uniquely named per invocation, with a valid `.iw-run-marker` recording the issue number. |
| AC2 | Clone from `develop` | Reaches `READY` with a `baseline` matching the seeded `develop` HEAD sha; the working tree is actually checked out. |
| AC3 | Identity/origin mismatch | Outcome is `REJECTED`, never `READY`; the manifest never advances past `REJECTED`. |
| AC4 | Credential redaction | Neither stdout nor the manifest ever contains a token, including on the real clone-failure path (a `GIT_BIN`-shimmed git that fails with a credential-bearing error message). |
| AC5 | Manifest atomicity | `key=value` round-trips via `workspace_manifest_read`; a repeated key updates in place (no duplicate lines, no leftover `.tmp.$$` file). |
| UNIT | Pure-function coverage | `workspace_redact_credentials`, `workspace_verify_identity` (https and SSH-shorthand origins, missing origin, empty expected value), `workspace_manifest_write`/`_read`/`_state`, `workspace_run_root`. |

### Scope note

PowerShell parity for the workspace stage is delivered as
`scripts/workspace.ps1`; cross-platform PS regression coverage is integrated
in #832 (consistent with the existing #829 note above).

## Subagent spawn / lease tests (issue #839)

Unit and scenario tests for the subagent spawn-contract + single-writer-lease
stage (`global/skills/_internal/issue-work/scripts/agents.sh`), which turns a
`READY` workspace into an orchestrated one and advances the manifest
`READY -> AGENTS_RUNNING -> COMMITTED`. The suite drives a real local git
repository for the worktree scenarios rather than a fake — this stage never
calls `gh`, so no shim is needed to exercise it without network access.
Sourcing `agents.sh` also loads `workspace.sh`, so the #838 manifest primitive
is available for assertions. See `reference/workspace-lifecycle.md` (the #839
sections) for the full contract.

### Run

```bash
bash tests/issue-work/test-agents.sh
```

The suite is wired into CI by `.github/workflows/validate-skills.yml`.

### Acceptance-criteria coverage (issue #839)

| AC | Scenario | Assertion |
|----|----------|-----------|
| AC1 | Path normalization | A relative path (existing or not-yet-existing) resolves to an absolute, lexically collapsed path; empty input fails. |
| AC2 | Spawn-prompt contract | `agents_build_prompt` output contains every required field — normalized absolute repo path, active issue number, target branch, baseline sha, explicit write scope — plus a prohibition clause forbidding remote pushes, the GitHub CLI, opening/merging a PR, and workspace cleanup. |
| AC3 | Lease mutual exclusion | First writer acquires; a second writer is refused while the lease is held; after the owner releases, the lease is re-acquirable. |
| AC4 | Lease fail-safe | A non-owner release is refused (lease survives); releasing a non-existent lease fails cleanly; a non-lease path is refused (guarded removal). |
| AC5 | Per-agent worktree | Adding a worktree on a new branch creates it and lists it; removing it deletes the directory and leaves no orphan in `git worktree list`. |
| AC6 | State transitions | From `state=READY`, the start phase advances to `AGENTS_RUNNING` (recording `lease_owner`) and the commit phase to `COMMITTED`; an out-of-order transition is refused and leaves state unchanged. |
| AC7 | Capability guard | `agents.sh` contains no `git push`, no `gh` invocation (word-boundary match), and no `gh` injection seam. |

### Scope note

PowerShell parity for the subagent/lease stage is delivered as
`scripts/agents.ps1`; it is not runtime-verified here (no `pwsh`) and not wired
into CI. Cross-platform PS regression coverage is integrated in #832
(consistent with the #829 and #838 notes above).
