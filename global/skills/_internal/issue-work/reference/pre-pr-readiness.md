# Pre-PR Readiness Gate and Documentation-to-Issue Gap Audit

Mandatory gate for `issue-work` that runs **after** the implementation and
documentation have been committed to the feature branch and **before** the
branch is pushed or a pull request is opened. It has two halves:

1. A deterministic **git-state gate** — refresh the base branch (`develop`) and
   integrate it into the feature branch with safe conflict handling. The
   reference implementation is `scripts/pre-pr-gate.sh` (sibling directory); it
   owns only the mechanical, non-judgemental decisions and emits a single JSON
   object.
2. An agent-driven **documentation-to-issue gap audit** — reconcile what the
   issue and its surrounding documentation require against what the PR actually
   delivers, producing a **gap ledger**. This half needs judgement (reading
   issue bodies, matching requirements to evidence) and is therefore performed
   by the agent following the procedure below, not by the script.

This document is the contract for both halves. Code and doc must stay in sync —
when one changes, change the other in the same PR (same rule as the sibling
`reference/workspace-lifecycle.md` and `reference/triage-state-machine.md`).

## Handoff

The gate picks up after Step 7 (Documentation Update) of the Solo Mode workflow,
with impl + docs already committed to the feature branch, and hands off to
Step 8 (Push and Create PR) only on a `ready` outcome.

```
Step 7 (docs committed on feature branch)
        |
        v
pre-pr-gate.sh --repo <owner/name> --base develop --branch <feature>
        -> {"outcome":"ready", ...}       -> gap audit -> Step 8 (push + PR)
        -> {"outcome":"blocked", "reason":...} -> STOP, report, no push/PR
```

## Git-state gate ordering

`run_pre_pr_gate <repo> <base> <branch> [<remote>] [<max_base_moves>]
[<integrate>]` runs these steps in order and stops at the first that blocks:

1. **Clean-worktree precondition.** If the feature-branch worktree has tracked
   staged/unstaged changes, block with `dirty_worktree`. Untracked files do not
   block (they never impede a rebase). *Commit the implementation and docs
   first — this gate integrates committed history, not a dirty tree.*
2. **Checkout the feature branch** (defensive; the workflow is already on it).
3. **Fetch the remote base** through the injected git (never GitHub network from
   the script's own logic — the fetch is the only remote touch, and tests inject
   a local bare remote via `GIT_BIN`).
4. **Refresh the local base branch** per the develop-refresh rules below.
5. **Integrate** the refreshed base into the feature branch (rebase by default,
   merge for shared branches).
6. **Re-fetch** and, if the remote base moved, **re-integrate** up to
   `--max-base-moves` times (base-movement retry rule below).
7. On a clean integration against a stable base, emit `ready`.

### Outcome schema

`run_pre_pr_gate` prints exactly one JSON object as its final stdout line. Keys
are stable so a test can parse them:

```json
{
  "outcome": "ready|blocked",
  "reason": "<slug>",
  "base": "develop",
  "remote_base_sha": "<sha or empty>",
  "local_base_sha_before": "<sha or empty>",
  "local_base_sha_after": "<sha or empty>",
  "attempts": 0
}
```

`local_base_sha_before` and `local_base_sha_after` bracket the local base branch
across the run, so a blocked `base_ahead` / `base_diverged` can prove the base
was **not** rewound (`after == before`). `attempts` counts integration cycles.

### Outcome table

| `outcome` | `reason` | Meaning | Downstream action |
|-----------|----------|---------|-------------------|
| `ready` | `ready` | Clean worktree, base refreshed (fast-forwarded or already current), feature integrated cleanly onto a stable base. | Proceed to the gap audit, then Step 8 (push + PR). |
| `blocked` | `dirty_worktree` | The feature worktree has uncommitted tracked changes. | Commit impl + docs, then rerun the gate. |
| `blocked` | `base_ahead` | The local base has commits the remote lacks; the base was left untouched. | Investigate the unshared base commits; never rewind. Resolve upstream, then rerun. |
| `blocked` | `base_diverged` | The local and remote base histories forked; the base was left untouched. | Reconcile the base manually; never reset. Then rerun. |
| `blocked` | `conflict` | Integrating the base into the feature branch conflicted; the rebase/merge was aborted and the feature branch restored exactly. | Apply the conflict rule below (hand-resolve only unambiguous conflicts), then rerun. |
| `blocked` | `base_unstable` | The remote base kept moving; re-integration hit the `--max-base-moves` cap. | Wait for the base to settle, then rerun. Do not loop indefinitely. |
| `blocked` | `fetch_failed` | The base fetch failed. | Check connectivity/remote, then rerun. |
| `blocked` | `checkout_failed` | The feature branch could not be checked out. | Verify the branch exists locally, then rerun. |
| `blocked` | `missing_args` / `bad_integrate_mode` | Invalid invocation (missing `--repo`/`--base`/`--branch`, or an `--integrate` value other than `rebase`/`merge`). | Fix the invocation. |

Only `ready` continues into the gap audit and PR creation. Every `blocked`
outcome is terminal for the invocation: **stop, report the reason, and do not
push or open a PR.**

## Develop-refresh rules

The gate classifies the local base against the freshly fetched remote base
(`classify_base_relationship <local_sha> <remote_sha>` -> `equal` / `behind` /
`ahead` / `diverged`) and acts:

- **`equal`** — the local base is already current. No-op.
- **`behind`** — the local base is strictly an ancestor of the remote base, so
  advancing it is a **true fast-forward**. The gate moves the local base ref
  forward to the remote sha (without a checkout, staying on the feature branch).
- **`ahead`** — the remote base is an ancestor of the local base, i.e. the local
  base carries commits the remote does not. **Block (`base_ahead`); never
  rewind or reset the base.** A base branch that is ahead of its remote is a
  signal something is wrong (a stray local commit, a wrong branch) that a script
  must not paper over by discarding history.
- **`diverged`** — neither sha is an ancestor of the other. **Block
  (`base_diverged`); never reset.** Divergence requires human reconciliation.

The refresh only ever **fast-forwards** the local base; it never rewinds it.
This is why `local_base_sha_after == local_base_sha_before` on every `ahead` /
`diverged` block.

### Rebase private, merge shared

Integration defaults to **rebase** (`--integrate rebase`): the feature branch is
a private branch, so rebasing it onto the refreshed base keeps history linear
and is the private-history policy from `workflow/git-conflict-resolution.md`
("rebase private history, merge shared history"). Pass **`--integrate merge`**
for a branch other people have already based work on — merging preserves the
shared commits others depend on. The default is rebase; choose merge
deliberately.

## Conflict rule

The script **cannot judge semantic ambiguity**, so on **any** integration
conflict it aborts the operation (`git rebase --abort` / `git merge --abort`),
leaving the feature branch exactly as it was before the integration attempt, and
returns `blocked` / `conflict`. It never guesses a resolution.

The agent then decides, per `workflow/git-conflict-resolution.md`:

- The agent may hand-resolve a conflict **only** when the intent is
  unambiguous — a lockfile it can regenerate, a changelog/append where both
  sides clearly stack, a formatting-only clash. After resolving, it **reruns the
  affected verification** (build/tests for the touched area) and then reruns the
  gate.
- For anything where both sides made substantial, overlapping semantic changes,
  the agent **does not guess**. It surfaces the conflict to the user.
- The agent **never creates the PR while an ambiguous conflict remains
  unresolved.** A `conflict` block is not a "resolve however and proceed"
  signal; it is a "stop unless the resolution is verifiably correct" signal.

## Base-movement retry rule

The remote base can move while the gate (and the gap audit) runs. After a clean
integration the gate **re-fetches** the remote base; if its sha changed, it
**re-integrates** the feature onto the new base. A `PRE_PR_ON_FETCH` command
seam runs after every fetch so tests can push a new remote commit between
fetches and simulate movement deterministically.

Re-integration is **capped at `--max-base-moves` (default 3)**. If the base
never stabilizes within that many cycles, the gate stops with `base_unstable`
and reports `attempts`. This realizes the global 3-fail rule for the
"base keeps moving" case: do not chase a moving target forever — stop, report,
and let the base settle before rerunning.

## Documentation-to-issue gap audit

Performed by the agent on a `ready` outcome, before push/PR. It reconciles
**what is required** against **what was delivered** and records the result in a
gap ledger.

### Audit scope

Gather requirements and evidence from, in priority order:

1. **The active issue** — its acceptance criteria, body, and comments.
2. **Its parent and child issues** — the epic it is `Part of #N`, and any
   sub-issues it decomposed into.
3. **Directly linked issues and their closing PRs** — open or closed issues
   referenced from the active issue (and the PRs that closed the closed ones),
   for prior-art and contract context.
4. **Same-milestone / component / label candidates** — issues sharing the
   milestone, component, or labels that plausibly overlap this change.
5. **Documentation tied to the changed paths** — README, design, architecture,
   roadmap, spec, and changelog material that the changed files are governed by.

**Index issue metadata first** (numbers, titles, states, labels, links); fetch
full bodies and comments **only** for the candidates that survive that first
pass as relevant. This keeps the audit bounded and avoids pulling every issue in
the repository into context.

### Gap ledger row schema

Each requirement discovered in scope becomes one ledger row with **exactly**
these fields:

| Field | Meaning |
|-------|---------|
| `requirement` | The single obligation being checked (one acceptance criterion, one documented contract). |
| `documentation evidence` | Where the requirement is documented (doc path + anchor), or "none". |
| `implementation evidence` | The code that satisfies it (path + symbol), or "none". |
| `test evidence` | The test that exercises it (path + case), or "none". |
| `issue evidence` | The issue/PR that owns it (`#N`), or "none". |
| `disposition` | One of the four dispositions below. |
| `action` | The concrete next step implied by the disposition. |

### Dispositions (exactly four)

| Disposition | Definition |
|-------------|------------|
| `fix-in-pr` | The requirement is in scope for the **active** issue's acceptance criteria and is not yet fully satisfied. Fix it in the current PR before pushing. |
| `followup-issue` | A genuine gap that is **out of scope** for the active issue. File a **deduplicated, non-duplicate** follow-up issue (search first; do not open a second issue for an already-tracked gap). |
| `already-satisfied` | The requirement is met — implementation, test, and documentation evidence all line up. No action. |
| `blocked` | The requirement cannot be dispositioned because retrieval was incomplete (see the incomplete-data rule) or an external dependency is unresolved. Report; do not proceed as if it were satisfied. |

### Incomplete-data rule

**Never report "no gap" when documentation or issue retrieval was incomplete.**
If an issue body/comment fetch failed, a linked issue could not be read, or a
governing document could not be located, the affected rows are `blocked`, not
`already-satisfied`. Absence of evidence is not evidence of coverage.

### Scope discipline

Only gaps required by the **active** issue's acceptance criteria are fixed in
the current PR (`fix-in-pr`). Independent, out-of-scope gaps become
**deduplicated** follow-up issues (`followup-issue`) — never silently folded
into this PR, and never opened twice. This mirrors the surgical-precision
principle: the PR stays scoped to its issue.

### Korean PR validation

The PR's natural-language **title and body must be Korean** (the repo's active
`CLAUDE_CONTENT_LANGUAGE` policy for this workflow). Machine tokens — code
identifiers, file paths, URLs, and GitHub closing keywords such as
`Closes #N` — remain ASCII and are allowed inside the Korean text. The PR body
must contain these sections:

- **Changes** — what changed.
- **Rationale** — why.
- **Scope** — what is in and out of scope (ties back to the gap ledger).
- **Verification** — how it was verified (builds/tests run).
- **Risks** — residual risks.
- **Follow-up Work** — the `followup-issue` rows from the ledger.

*(The gate and this document are English per repo policy for code and
reference prose; the Korean requirement applies to the PR artifact the
orchestrator writes, not to this file.)*

### Post-creation checks

After the PR is created, verify:

- the PR **targets `develop`** (not `main`), per `workflow/branching-strategy.md`;
- the PR **closes the active issue** (a `Closes #<active>` keyword is present).

If either check fails, correct the PR before considering the workflow done.

## Acceptance criteria

Anchors the git-state test suite (`tests/issue-work/test-pre-pr-gate.sh`) maps
to. AC1–AC6 are script-verifiable; AC7–AC12 are the agent-side gap-audit
contract.

> **AC1**: A dirty feature worktree (uncommitted tracked changes) blocks with
> `dirty_worktree` before any fetch; the local base is untouched.
> **AC2**: A local base strictly behind the remote is fast-forwarded to the
> remote head and the feature is replayed onto it (`ready`); a base already
> current reaches `ready` without being moved.
> **AC3**: A local base that is ahead blocks with `base_ahead`, and a diverged
> base blocks with `base_diverged`; in both cases `local_base_sha_after ==
> local_base_sha_before` (never reset).
> **AC4**: A clean integration replays the feature commits onto the refreshed
> base (`ready`); `--integrate merge` integrates via a merge commit.
> **AC5**: Any integration conflict aborts the rebase/merge and blocks with
> `conflict`, leaving the feature branch HEAD unchanged and the worktree clean.
> **AC6**: Repeated remote-base movement blocks with `base_unstable` after
> `--max-base-moves` integration cycles, reporting `attempts`.
> **AC7**: The gap ledger uses exactly the seven fields of the row schema.
> **AC8**: Dispositions are exactly the four defined slugs.
> **AC9**: Incomplete documentation/issue retrieval yields `blocked`, never a
> "no gap" report.
> **AC10**: Out-of-scope gaps become deduplicated follow-up issues; only
> active-issue acceptance criteria are fixed in the current PR.
> **AC11**: The PR title/body are Korean (machine tokens excepted) with the
> Changes / Rationale / Scope / Verification / Risks / Follow-up Work sections.
> **AC12**: After creation, the PR targets `develop` and closes the active issue.

## Risks

- **Automatic conflict resolution is limited to verifiable-intent cases.** The
  script never resolves; the agent resolves only unambiguous conflicts and
  reruns the affected verification. Anything ambiguous stops and surfaces to the
  user — the PR is never created over an unresolved ambiguous conflict.
- **Never reopen closed issues.** A closing PR referenced during the audit is
  read for context only; the audit files new deduplicated follow-ups instead of
  reopening.
- **Never fabricate regulated evidence.** A missing test or document is a
  `blocked` / `fix-in-pr` / `followup-issue` row, never an invented citation.
- **Stop after three repeated base movements or identical failures.** The
  base-movement cap and the global 3-fail rule both apply: do not chase a moving
  base or retry an identical failure indefinitely — report and hand off.
