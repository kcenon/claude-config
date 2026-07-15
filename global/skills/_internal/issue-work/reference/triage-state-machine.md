# Triage State Machine

Shared front-end gate for `issue-work`. Replaces the ad-hoc "Issue Selection"
(Step 1) and "Issue Size Evaluation" (Step 2) logic with a single deterministic
state machine that solo, team, and batch modes all route through before any
repository is cloned, any branch is created, or any subagent is spawned.

The reference implementation is `scripts/triage.sh` (sibling directory). This
document is the contract: states, transitions, the outcome schema, the comment
fingerprint rule, the candidate eligibility predicate, and the sort key. Code
and doc must stay in sync — when one changes, change the other in the same PR.

## Why a state machine

Selection and size-evaluation used to be two disconnected bash snippets that
re-fetched issue data implicitly and posted blocker comments unconditionally.
Re-running `issue-work` on the same issue therefore produced duplicate blocked
comments and duplicate child issues. Modeling the front end as an explicit state
machine with a visited-set and comment fingerprints makes every transition
idempotent: a second run over an unchanged issue is a no-op, and a second run
over a partially-decomposed parent only fills the gap.

## Tracked identities

The machine separates four issue identities so a parent/child traversal cannot
lose its place or loop:

| Identity | Meaning |
|----------|---------|
| `requested` | The issue number the caller passed (may be empty in auto-select). |
| `root` | The top of the parent/child tree being triaged (the requested issue, or the auto-selected issue). |
| `active` | The issue currently under consideration for actual code work. |
| `visited[]` | Every issue number already inspected this run — the cycle guard. |

## States

```
START
  └─> RESOLVE_REQUESTED   resolve requested|auto-selected issue -> root, active=root
        └─> REFRESH        re-fetch active: body, AC, assignees, deps, linked PRs, latest comments
              └─> EVALUATE_BLOCKERS  recompute blockers; fingerprint; idempotent comment
                    ├─(blocked)-> BLOCKED         (terminal)
                    └─(clear)--> plan-file supplied?
                          ├─(yes)-> DECOMPOSE   reconcile planned vs existing children;
                          │                     create only the missing; one summary
                          │                     -> DECOMPOSED (terminal)
                          └─(no)-> EVALUATE_SIZE   small enough to work?
                                ├─(work)------> CLAIM
                                └─(oversized)-> has eligible open child?
                                      ├─(yes)-> SELECT_CHILD
                                      └─(no)--> all children closed? -> SKIPPED (audit)
                                                 else no children    -> FAILED (needs --plan-file)
              SELECT_CHILD  pick eligible child deterministically; active=child; visited+=child
                    └─> REFRESH (loop, bounded by MAX_CHILD_DEPTH and visited[])
              CLAIM         assign active to current user; re-verify state/assignees/PRs
                    ├─(won)---> PROCEED     (terminal: hand active to the code-work workflow)
                    └─(lost)--> next eligible child, or SKIPPED if none
```

The presence of a `--plan-file` splits the two decomposition-adjacent
operations so they never collide:

- **Decompose** (plan supplied): the caller has designed a child split and asks
  the gate to realize it. The gate reconciles the plan against existing children
  and creates only the missing ones — `DECOMPOSED`. Because reconciliation runs
  before child selection, a partial decomposition is completed on a rerun (AC6)
  rather than the gate diving into the first existing child.
- **Pick up work** (no plan): the gate selects an eligible open child (AC2), or
  works the issue directly if it is small, or reports a completion audit when
  every child is closed (AC8).

## Outcome schema

`run_triage` prints exactly one JSON object as its final stdout line. The same
schema is the parent-side record in batch mode.

```json
{
  "outcome": "proceed|decomposed|blocked|skipped|failed",
  "requested": "<issue number or empty>",
  "root": "<root issue number>",
  "active": "<issue number to work on, empty unless outcome=proceed>",
  "visited": ["<issue number>", "..."],
  "reason": "<short human-readable explanation>",
  "fingerprint": "<state fingerprint of the active/blocked issue, or empty>"
}
```

| `outcome` | Meaning | Downstream action |
|-----------|---------|-------------------|
| `proceed` | An eligible issue was selected and claimed. | Continue to code work (clone, branch, implement). Becomes `merged` once the PR merges. |
| `decomposed` | The root was too large and had no eligible open child; children were created and a parent summary was posted. | Stop. No clone, no branch. |
| `blocked` | The active issue has an unresolved blocker, **or** the primary fetch failed the same way three times (see Failure policy). | Stop. A blocked comment was posted only if the blocker state changed. No clone, no branch. |
| `skipped` | The active issue was closed, reassigned, or every child lost a claim race. | Stop. No side effects beyond re-reads. |
| `failed` | Triage cannot proceed deterministically: the depth/cycle guard tripped, or an oversized issue with no children was given no `--plan-file` (reason begins `needs_plan`, see below). | Stop and report. A `needs_plan` failure is a "re-invoke with a plan" signal, **not** a hard error. |

**`needs_plan` failures are a two-step handshake, not a defect.** When an
oversized issue has no eligible open child and no `--plan-file`, the gate cannot
invent a child split, so it returns `failed` with a reason that begins
`needs_plan`. The caller is expected to design the sub-issue titles, write them
to a plan file, and re-invoke the gate with `--plan-file`; the second call then
returns `decomposed`. Batch reporting must treat a `needs_plan` failure as
"needs a decomposition plan" rather than tallying it as a build/CI failure.

> **Batch reporting**: `decomposed`, `blocked`, `skipped`, and `failed` are NOT
> merge successes. The batch summary counts only a `proceed` that later reaches
> a merged PR as a success. Treating a decomposition as a merge is a reporting
> bug the tests explicitly guard against.

## Candidate eligibility

An issue is an eligible candidate only when **all** of the following hold:

1. **Open** — `state == OPEN`.
2. **No unresolved dependency** — every `Blocked by #N` / `Depends on #N`
   reference in the body points to a non-open issue.
3. **Not solely assigned to another user** — either unassigned, or the current
   user is among the assignees. An issue assigned only to someone else is left
   alone.
4. **No active work in progress** — no open linked PR and no existing work
   branch for the issue.
5. **Unvisited** — the issue number is not already in `visited[]`.

## Sort key

When more than one child is eligible, order candidates by this key and take the
first. The order is total and deterministic so two concurrent runs pick the same
next candidate (and therefore race on the same claim rather than diverging):

1. **Current-user assignment** — issues already assigned to the current user
   sort first.
2. **Parent-defined order** — the order the child appears in the parent's task
   list / sub-issue list. The reference implementation approximates this with
   the order `gh issue list --search "Part of #parent"` returns rows (the search
   index order), not by parsing the parent body's checklist. This is a
   deliberate approximation: it is deterministic for a given index state and
   avoids brittle body parsing, at the cost of not honoring a hand-authored
   checklist reorder. Later tie-breakers (priority, creation time, issue number)
   keep the total order stable when the index order is not meaningful.
3. **Priority** — `priority/critical` < `high` < `medium` < `low` < none.
4. **Creation time** — oldest first.
5. **Issue number** — ascending, as the final tie-break.

## Comment fingerprint (idempotency)

Blocked comments and parent-decomposition summaries carry a machine-readable
marker so a re-run can recognize its own prior comment:

```
<!-- triage-fingerprint: <kind>:<hash> -->
```

- `<kind>` is `blocked` or `decompose`.
- `<hash>` is a stable digest of the state the comment describes.

Before posting, the machine scans the issue's existing comments for a marker
with the same `<kind>`:

| Existing marker | New fingerprint | Action |
|-----------------|-----------------|--------|
| none | — | Post the comment. |
| present | equal to existing | **Skip** — the state is unchanged (AC3). |
| present | different from existing | Post exactly one updated comment (AC4). |

The blocked fingerprint digests the sorted set of `blocker#:state` pairs plus the
required-action text, so it changes if and only if a blocker's resolution state
or the required action changes. Human-supplied information (a new comment or an
edited body) is re-read during `REFRESH` before the blocked decision is made, so
newly-provided context can flip `blocked` to `proceed` in the same run (AC5).

## Decomposition reconciliation

Decomposition runs only when the caller supplies a `--plan-file` (one child
title per line). It is idempotent across partial runs (AC6):

1. List existing children of the parent (issues whose body references
   `Part of #parent`).
2. Match each planned child against existing children by title.
3. Create only the planned children that have no existing match.
4. Post the parent summary **once**, guarded by a `decompose` fingerprint marker
   so a re-run does not add a second summary.

Because a plan file is required, "create children" (AC1: none exist -> create
all) and "complete a partial split" (AC6: some exist -> create the rest) are the
same code path with different starting states. Selecting an existing eligible
child to work on (AC2) is the **no-plan** path and never posts a decomposition
comment. This separation is what keeps AC1/AC6 (a decompose operation) from
colliding with AC2 (a work-selection operation).

## Cycle and depth guards

- `visited[]` prevents re-inspecting an issue, which breaks reference cycles
  (parent lists child, child lists parent).
- `MAX_CHILD_DEPTH` (default 5) caps how deep the parent/child traversal
  descends. Exceeding it yields `failed` with a depth-guard reason rather than
  looping.

## Claim race handling

GitHub assignment and comments are not atomic locks. After assigning `active` to
the current user, the machine re-reads the issue (state, assignees, linked PRs).
If another run won the claim in between — the issue is now assigned only to
someone else, was closed, or has a new linked PR — the machine **rolls back its
own `@me` assignment** (`--remove-assignee`) so the abandoned issue is not left
showing this run as an assignee, marks it visited, and advances to the next
eligible child. If no next candidate remains, the outcome is `skipped` (AC7).

## Failure policy

The primary external dependency is the issue fetch. It is retried up to
`TRIAGE_MAX_FAILURES` times (default 3); three identical failures in a row stop
the run with a **`blocked`** outcome and a reason naming the identical-failure
rule, rather than a blind retry loop. This realizes the issue #829 risk control
("stop after three identical failures and return a blocked result") for the
operation most likely to fail transiently.

Deterministic internal errors — the cycle/depth guard, or an oversized issue
with no plan (`needs_plan`) — yield `failed` instead, because they will not
resolve on retry. Triage never retries a failing mutation blindly.

## Scope boundary

The triage gate ends at `PROCEED` — it selects and claims the issue but does
**not** clone the repository, create a branch, or spawn subagents. Those are the
responsibility of the workspace-isolation stage (issue #830). Terminal
non-`proceed` outcomes perform no repository side effects at all, which is what
lets a `blocked` or `decomposed` result be produced from a bare gh session.
