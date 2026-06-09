# Memory Trust Model

**Version**: 1.0.0
**Last updated**: 2026-05-01
**Status**: Active

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Tier Definitions](#2-tier-definitions)
3. [State Transitions](#3-state-transitions)
4. [Lifecycle Rules](#4-lifecycle-rules)
5. [Auto-Application Matrix](#5-auto-application-matrix)
6. [Operator Actions](#6-operator-actions)
7. [Frontmatter Representation](#7-frontmatter-representation)
8. [Storage Layout](#8-storage-layout)
9. [Migration of Existing Memories](#9-migration-of-existing-memories)
10. [Versioning](#10-versioning)

---

## 1. Purpose

Validation tools (`validate.sh`, `secret-check.sh`, `injection-check.sh`, specified in
`MEMORY_VALIDATION_SPEC.md`) tell the system **whether** a memory is structurally
clean and free of secrets or injection-shaped content. They do not tell the system
**how much to trust** the content for the purpose of influencing future sessions.

The trust model addresses an orthogonal question: should a given memory automatically
shape Claude's behavior, or should the user confirm it first? This question matters
because:

- A memory written by Claude through inference carries the same authority as one the
  user explicitly approved unless the system distinguishes them. Without that
  distinction, a hallucinated memory propagates to all machines on first sync.
- A memory verified two years ago that references a now-removed feature flag is
  applied identically to one verified yesterday. Without temporal weight, stale
  guidance compounds.
- A memory that fails revalidation has only two possible fates without an
  intermediate state: keep (risking propagation of bad data) or delete (losing the
  artifact entirely). A third state — "isolate but retain" — is required for
  forensic and recovery use cases.

The trust model adds a third tier and a temporal dimension. Trust is **orthogonal**
to validation: a memory may be structurally valid and still be untrusted, and a
trusted memory may later fail validation (in which case validation is authoritative
and the memory is demoted).

### In scope

- Definition of three trust tiers and their semantics
- State transition rules between tiers
- Observation period for `inferred` (7 days) and stale handling for `verified`
  (`last-verified > 90 days`)
- Auto-application gating per tier
- Operator actions: promote, demote, restore
- Frontmatter representation of `trust-level`
- Storage layout (`memories/` vs `quarantine/`)
- Migration defaults for existing memories without `trust-level`

### Out of scope

- Implementing the backfill tool (#512)
- Implementing the quarantine directory mechanism (#514)
- Implementing `/memory-review` (#529) or audit (#528) — this document is *consumed
  by* those features
- AI-based semantic review (#530)
- The cross-machine sync transport itself

---

## 2. Tier Definitions

There are three trust tiers. Every memory file occupies exactly one tier at any
given time, recorded in the `trust-level` frontmatter field.

| Tier | Meaning | Frontmatter | Storage path | Sync transport | Auto-apply |
|---|---|---|---|---|---|
| `verified` | User explicitly confirmed; `last-verified ≤ 90d` | `trust-level: verified` | `memories/` | yes | yes |
| `inferred` | Saved by Claude through inference; awaiting user confirmation | `trust-level: inferred` | `memories/` | yes | with marker |
| `quarantined` | Failed validation OR user demoted | `trust-level: quarantined` | `quarantine/` | yes | no |

### `verified`

A memory the user explicitly confirmed or directly authored. The user-approval
signal may take any of the following forms:

- The user dictated the memory content directly in conversation.
- The user reviewed an `inferred` memory and chose **promote** in `/memory-review`.
- The user manually edited the file and saved it (a clear user gesture).
- During backfill, a reviewer confirmed the memory content reflects the user's
  intent and promoted it.

A `verified` memory has authority to influence Claude's behavior automatically and
silently — no per-session prompt, no marker in the loaded context. Verification is
treated as the user's standing instruction.

Verification is not eternal. Section 4 specifies the staleness threshold
(`last-verified > 90 days`) at which a `verified` memory is flagged for re-review.

### `inferred`

A memory written by Claude through inference from conversation context, where no
explicit user-approval signal exists at the moment of writing. Examples:

- During a long debugging session, Claude infers the user prefers a particular
  workflow and saves it as a project memory.
- A reference memory pointing to an external dashboard is inferred from a URL the
  user pasted in passing.

`inferred` memories are loaded into context with a `🟡 inferred` marker so Claude
treats them as advisory rather than authoritative. They may influence behavior but
should not produce silent, irreversible actions. Once per session (at most), the
user is prompted to promote or demote inferred memories that have completed their
observation period.

### `quarantined`

A memory that has been isolated from active use. Quarantine is reached by either of
two paths:

- **Validator-driven**: A validator (`validate.sh`, `secret-check.sh`,
  `injection-check.sh`) produces a hard failure (FAIL-STRUCT, FAIL-FORMAT, or
  SECRET-DETECTED) on a memory that previously passed. Validators are authoritative;
  failed memories are demoted to `quarantined` regardless of prior tier.
- **User-driven**: The user explicitly demotes a memory via `/memory-review` because
  the content is no longer accurate, no longer relevant, or appears to contain
  unintended content.

A `quarantined` memory is moved physically to the `quarantine/` directory (Section
8). It is retained on disk and synced across machines, but is not loaded into
context for any conversation. Recovery requires an explicit user action (Section 6,
**restore**), and the validator that originally rejected the file must pass again
before restoration is permitted.

---

## 3. State Transitions

Every transition is one of: a tier change driven by a user action via
`/memory-review`, a tier change driven by validator output, or a one-time creation
event. There are no other paths.

### State diagram (ASCII)

```
              user confirms
   inferred ─────────────────> verified
       │                          │
       │  user demotes            │  user demotes
       │  OR validators fail      │  OR validators fail
       ▼                          ▼
   quarantined <────────────── quarantined
       ▲    │                     ▲
       │    │ user restores       │  last-verified > 90d
       │    │ + revalidation      │  + user reaffirms
       │    ▼ passes              │  in /memory-review
       │ verified                 │
       │                          │
       │ (no direct path: must go via verified after restore)
       │
   New memory write (Claude inference) ─> inferred
   New memory write (explicit user)    ─> verified

   Validator hard-fail (any tier) ─> quarantined (validators authoritative)
```

The diagram is the authoritative source. Any prose elsewhere in this document that
appears to permit a transition not shown above is incorrect.

### Transition rules

| From | To | Trigger | Where recorded |
|---|---|---|---|
| (none) | `inferred` | New memory written by Claude through inference | `created-at`, `trust-level: inferred` |
| (none) | `verified` | New memory written by explicit user gesture (dictation, `/memory-review --add`, manual edit-and-save) | `created-at`, `trust-level: verified`, `last-verified` set to creation date |
| `inferred` | `verified` | User chose **promote** in `/memory-review` after observation period | `trust-level: verified`, `last-verified` updated to today |
| `inferred` | `quarantined` | User chose **demote** in `/memory-review`, OR any validator hard-fails | `trust-level: quarantined`, file moved to `quarantine/` |
| `verified` | `quarantined` | User chose **demote** in `/memory-review`, OR any validator hard-fails | `trust-level: quarantined`, file moved to `quarantine/` |
| `quarantined` | `verified` | User chose **restore** in `/memory-review` AND the validator that originally rejected the file now passes | `trust-level: verified`, `last-verified` updated to today, file moved back to `memories/` |
| `verified` | `verified` (re-affirmed) | User re-affirms staleness prompt for a memory whose `last-verified > 90 days` | `last-verified` updated to today, tier unchanged |

### Forbidden transitions

The following transitions do **not** exist in v1.0.0 and must not be implemented:

- `quarantined` → `inferred` directly. A restored memory always lands at `verified`
  (the user has just reviewed it). There is no notion of "partially trusted again".
- `verified` → `inferred`. A `verified` memory the user is no longer sure about
  should be demoted to `quarantined`, not stepped back to `inferred`. The
  observation period is for new inference, not for re-evaluation.
- Any auto-promotion from `inferred` to `verified` without an explicit user signal.
  The observation period prompts the user; it does not silently elevate trust.
- Any auto-promotion from `quarantined` to anywhere. Validator success is
  necessary but not sufficient for restore; the user must also act.

---

## 4. Lifecycle Rules

The lifecycle rules are the temporal constraints that drive the prompts surfaced by
`/memory-review` and the audit reports produced by the audit tool (#528).

### Inferred observation period (7 days)

When a memory is created at tier `inferred`, the **observation period** begins at
its `created-at` timestamp and lasts 7 days. During this window:

- The memory is loaded into context with the `🟡 inferred` marker.
- It is **not** surfaced for promotion review. The user has not yet had time to
  observe whether the inferred guidance is correct in practice.

After 7 days have elapsed:

- `/memory-review` includes this memory in its **promote-or-demote** queue.
- Until the user acts, the memory remains `inferred` indefinitely. The system does
  not auto-promote and does not auto-demote based on age alone.
- Each `/memory-review` invocation surfaces such memories at most once per session.

### Verified staleness threshold (90 days)

When a memory at tier `verified` has `last-verified` more than 90 days in the past,
it becomes **stale**. Stale memories:

- **Continue to apply.** Stale verification is not the same as failed verification.
  The memory still influences behavior because the user previously confirmed it.
- Are flagged in the SessionStart hook display (#522) so the user is aware of the
  count.
- Appear in `/memory-review` for re-affirmation. The user can either:
  - **Re-affirm**: tier remains `verified`, `last-verified` is updated to today.
  - **Demote**: tier becomes `quarantined`.

A stale memory that the user has not acted on after a long delay is still treated as
`verified` for context-loading purposes. Audit reports (#528) include staleness
counts so operators can detect drift.

### Quarantine retention (90 days, then archive candidate)

Quarantined memories are retained on disk to support forensic review and possible
restore.

- **Days 0–30**: Passive retention. No automatic action. The file lives in
  `quarantine/` and is synced across machines but never loaded into context.
- **Days 31–90**: Audit-candidate window. The audit tool (#528) lists these
  memories with their original failure reason in monthly reports.
- **Day 91 onward**: Archive candidate. The audit tool suggests moving the file to
  `archive/YYYY-MM/` (where `YYYY-MM` is the original quarantine month). Archiving
  is **always operator-driven** in v1.0.0; no automatic deletion.

The quarantine timestamp used for these calculations is the `last-verified` field at
the moment of demotion (which becomes the demotion date) or, if absent, the file's
`mtime` at quarantine time.

### Summary of temporal thresholds

| Threshold | Tier affected | Effect |
|---|---|---|
| 7 days from `created-at` | `inferred` | Eligible for `/memory-review` promote-or-demote prompt |
| 90 days since `last-verified` | `verified` | Marked stale; flagged in SessionStart and audit |
| 90 days in `quarantine/` | `quarantined` | Suggested as archive candidate |

---

## 5. Auto-Application Matrix

"Auto-application" means: at session start, the memory is loaded into Claude's
working context and influences responses without an explicit user step. The matrix
below is the authoritative rule for what each tier produces.

| Tier | Loaded into context | Applied to behavior | User prompted |
|---|---|---|---|
| `verified` | yes | yes | no |
| `inferred` | yes (with `🟡 inferred` marker) | yes (with reminder to confirm) | once per session, max |
| `quarantined` | no | no | only via explicit `/memory-review` |

### Definitions

- **Loaded into context**: The memory file's body is concatenated into the system
  prompt for the conversation.
- **Applied to behavior**: Claude treats the memory's content as guidance that
  shapes responses, not merely as text.
- **User prompted**: A visible message asks the user to take action on the memory.

### `verified` row

`verified` memories are silent. They are loaded, they apply, and the user is not
asked anything. This is the standing-instruction state — the user already approved
this memory and has not signaled doubt.

### `inferred` row

`inferred` memories are loaded but rendered with a `🟡 inferred` marker so Claude
recognizes them as advisory. The marker is for Claude's internal consumption,
implemented as a frontmatter-level convention in the loaded context, not a literal
emoji shown to the user.

When at least one `inferred` memory has completed its observation period (Section
4), Claude prompts the user **at most once per session** with a message of the form:

> You have N inferred memories awaiting review. Run `/memory-review` to promote
> or demote them.

Only one such prompt per session, regardless of N. The user may dismiss the prompt;
the memories remain `inferred` until acted on.

### `quarantined` row

`quarantined` memories are not loaded into context under any normal flow. The only
way to access their content is through the explicit `/memory-review` skill. They
remain on disk and are synced across machines for forensic continuity.

---

## 6. Operator Actions

The operator (the user, via `/memory-review`) has exactly three actions in v1.0.0.
Each action corresponds to a specific transition in Section 3.

### Promote (`inferred` → `verified`)

**Precondition**: The memory is `inferred` and has completed its 7-day observation
period.

**Effect**:

- `trust-level` updated to `verified`.
- `last-verified` updated to today (ISO 8601 date).
- File remains in `memories/`; no path change.

**Recorded in**: The frontmatter of the memory file. No separate audit log entry is
required by this spec, though `/memory-review` (#529) may add one for traceability.

### Demote (`verified | inferred` → `quarantined`)

**Precondition**: The memory is currently `verified` or `inferred`. The trigger is
either a user gesture in `/memory-review` or a validator hard-failure.

**Effect**:

- `trust-level` updated to `quarantined`.
- `last-verified` updated to today (records the demotion date for retention math).
- File moved from `memories/` to `quarantine/`.

**Validator-driven demotion**: When `validate.sh`, `secret-check.sh`, or
`injection-check.sh` (with hard-fail exit codes 1, 2, or SECRET-DETECTED) runs over
a memory and produces a failure, the memory is demoted automatically. This may
happen during scheduled audits (#528). The audit tool records the failure reason in
its report.

### Restore (`quarantined` → `verified`)

**Precondition**: The memory is `quarantined` AND the validator that originally
caused (or now governs) its rejection passes when re-run against the current file
contents. If multiple validators apply, all must pass.

**Effect**:

- `trust-level` updated to `verified`.
- `last-verified` updated to today.
- File moved from `quarantine/` to `memories/`.

**No partial restore**: Restoration goes directly to `verified`, not to `inferred`.
The user has just reviewed the memory; further observation is unnecessary. If the
user is unsure, they should leave the memory in `quarantine/`.

### Actions explicitly NOT in v1.0.0

The following are deferred to future spec revisions. Implementers should not add
them ad hoc:

- **Bulk-promote** of multiple inferred memories — `#529` proposes
  `/memory-review --batch` for this; the bulk operation is a UX concern, not a new
  trust transition.
- **Edit-in-place** of a quarantined memory before restoring — quarantine is
  intentionally read-only at the trust-model level. To edit, the user must restore
  first (which requires re-validation), edit, and the change creates a fresh
  `last-verified`.
- **Disable inferred tier** at the system level (some users may prefer 2-tier).
  Documented as a future enhancement; not implemented in v1.0.0.

---

## 7. Frontmatter Representation

Trust state is recorded in three frontmatter fields, all defined in
`MEMORY_VALIDATION_SPEC.md` Section 4. This document is the authoritative source for
their **values and semantics**; the validation spec is the authoritative source for
their **format constraints**.

### Fields

```yaml
trust-level: verified | inferred | quarantined
last-verified: 2026-05-01           # ISO 8601 date
created-at: 2026-04-15T09:30:00Z    # ISO 8601 datetime UTC
```

### `trust-level`

- **Type**: enum, one of `verified`, `inferred`, `quarantined`.
- **Required after backfill**: Yes. After the migration in Section 9 completes,
  every memory must have a `trust-level`. Before backfill, absence is tolerated and
  produces a `WARN-SEMANTIC` from `validate.sh` per `MEMORY_VALIDATION_SPEC.md`
  Section 3.
- **Validator behavior**: A `trust-level` value not in the enum is rejected by
  `validate.sh` with FAIL-FORMAT (exit 2), per `MEMORY_VALIDATION_SPEC.md` Section
  4.

### `last-verified`

- **Type**: ISO 8601 date (`YYYY-MM-DD`).
- **Set by**: Promote, demote, restore, and re-affirm transitions (Sections 3, 6).
- **Initial value on backfill**: For memories migrated to `verified`, set to the
  backfill date. For memories migrated to `inferred`, may be omitted; for memories
  migrated to `quarantined`, set to the backfill date (records when quarantine
  began).
- **Absence on a `verified` memory**: Treated as **stale**. The next
  `/memory-review` prompts the user to re-affirm.

### `created-at`

- **Type**: ISO 8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`).
- **Set by**: Memory creation only. Never updated by transitions.
- **Used by**: The 7-day observation period for `inferred` memories (Section 4).
- **Default on backfill**: File modification time (`mtime`), per
  `MEMORY_VALIDATION_SPEC.md` Section 4.

### Example

A `verified` memory with full frontmatter:

```markdown
---
name: CI merge policy enforcement
description: Never merge when any CI check is incomplete or failing.
type: feedback
source-machine: raphaelshin-mbp
created-at: 2026-04-15T09:30:00Z
trust-level: verified
last-verified: 2026-05-01
---

Never merge when any CI check is incomplete.

**Why:** Prior incident (2026-Q1) where a skipped check masked a broken migration.
**How to apply:** Run `gh pr checks` before triggering any merge tool call.
```

---

## 8. Storage Layout

Tiers map to storage paths under the canonical sync root `claude-memory/`:

```
claude-memory/
├── memories/         # tier ∈ {verified, inferred}
│   ├── user_*.md
│   ├── feedback_*.md
│   ├── project_*.md
│   └── reference_*.md
└── quarantine/       # tier == quarantined
    ├── user_*.md
    ├── feedback_*.md
    ├── project_*.md
    └── reference_*.md
```

### Rules

- A memory's tier is the **single source of truth** for which directory it lives in.
  After every transition, the file is moved or kept according to:

  | Tier | Directory |
  |---|---|
  | `verified` | `memories/` |
  | `inferred` | `memories/` |
  | `quarantined` | `quarantine/` |

- Filename pattern is preserved across the move. A memory named
  `feedback_ci_merge_policy.md` keeps that filename whether it lives in `memories/`
  or `quarantine/`. The filename is the canonical identifier per
  `MEMORY_VALIDATION_SPEC.md` Section 2.

- Both directories are part of the sync transport. A memory demoted to `quarantine/`
  on one machine appears in `quarantine/` on every other machine after sync.

- The `archive/YYYY-MM/` directory (Section 4, quarantine retention) is **not**
  part of the sync transport in v1.0.0. Archived memories remain on the machine
  where archiving was performed. This is a deliberate simplification; future
  versions may revisit.

### Recovery

To recover a quarantined memory's content for diagnostic inspection without
restoring it:

```bash
cat ~/.claude/claude-memory/quarantine/<filename>.md
```

The `quarantine/` directory is plain markdown; no opaque encoding. This makes
forensic review and manual repair tractable.

### Implementation

The `demote` and `restore` operator actions (Section 6) are implemented by two
shell utilities. They are the single source of truth for the directory move
plus frontmatter rewrite that this section requires. Other tools (write-guard
hook #521, audit job #528, `/memory-review` #529) call into these CLIs rather
than re-implementing the move.

| Script | Action | Tier transition |
|---|---|---|
| `scripts/quarantine-move.sh` | Demote | `verified \| inferred` -> `quarantined` |
| `scripts/quarantine-restore.sh` | Restore | `quarantined` -> `verified` |

`quarantine-move.sh` is idempotent: invoking it on a file that already lives in
`quarantine/` is a no-op (exit 0). `quarantine-restore.sh` re-runs the three
validators (`validate.sh`, `secret-check.sh`, `injection-check.sh`) and refuses
the restore (exit 2) if any blocking check fails. `injection-check.sh` is
warn-only and never blocks restore, consistent with `MEMORY_VALIDATION_SPEC.md`
Section 7.

Both scripts modify only frontmatter; body content is preserved verbatim. They
prefer `git mv` when run inside a git working tree so the move is recorded as a
rename rather than a delete-plus-create.

### Quarantine retention markers

The quarantine retention thresholds (Section 4: 0-30 day passive, 31-90 day
audit, 91+ day archive candidate) are computed from the `quarantined-at`
timestamp written by `quarantine-move.sh`. The audit consumer (#528) reads
this field to classify each quarantined entry into one of the three retention
windows.

---

## 9. Migration of Existing Memories

When the trust model first applies to a memory directory that pre-dates it (the
17 baseline memories at `~/.claude/projects/-Users-raphaelshin-Sources/memory/`,
plus any other pre-existing entries), each memory must be assigned an initial tier.

The backfill tool (#512) implements the migration. This section is the
authoritative rule the tool must follow.

### Default tier by `type`

| `type` value | Default tier | Reason |
|---|---|---|
| `user` | `verified` | User identity is non-controversial and was always added through explicit user gesture. |
| `feedback` | `verified` | Feedback memories are added in response to explicit user direction. |
| `project` | `verified` (default), `inferred` (case-by-case) | Most project memories reflect facts the user confirmed. Memories Claude inferred from session context (without explicit user confirmation) are migrated as `inferred` — flagged in the baseline classification proposal (#513). |
| `reference` | `inferred` | External pointers benefit from re-verification. The user pasted a URL once; whether the link is still authoritative or even active should be reconfirmed. |

### Conservative-default rule

When the origin of a memory is ambiguous (no clear signal whether it came from the
user's explicit direction or from Claude's inference), the migration **defaults to
`inferred`**, not `verified`. The asymmetry is deliberate:

- Wrongly classifying a verified memory as inferred costs the user one prompt at
  next `/memory-review`. They click "promote", and the memory is restored to its
  rightful tier. Recoverable.
- Wrongly classifying an inferred memory as verified causes silent, automatic
  application of unverified guidance — possibly across all synced machines.
  Recovery requires noticing the bad behavior, finding the memory, and demoting it.
  Less recoverable.

The conservative default minimizes the cost of the worse error. This rule is
consistent with `MEMORY_VALIDATION_SPEC.md` Section 4, which states the same
default for `trust-level` on backfill.

### Initial frontmatter values on backfill

For each migrated memory, the backfill tool sets:

- `trust-level`: per the table above.
- `created-at`: file `mtime` if absent.
- `last-verified`:
  - For `verified` migrations: the backfill date (today).
  - For `inferred` migrations: omitted. The 7-day observation period starts from
    `created-at`.
- `source-machine`: current machine's `hostname -s` if absent.

### Baseline target verdicts

After backfill is applied to the 17 baseline memories, the resulting tier
distribution is documented in the baseline classification proposal
(`/tmp/claude/memory-validation/baseline/REPORT.md` §6) and is consumed by issue
#513. This document does not enumerate the per-file outcomes; the proposal is the
canonical source for that mapping.

---

## 10. Versioning

### Spec version

This document is **v1.0.0**. The version follows Semantic Versioning:

- **MAJOR**: Breaking change to the trust model (e.g., adding a fourth tier,
  removing a transition, changing the meaning of an existing tier).
- **MINOR**: Backward-compatible addition (e.g., new operator action, new lifecycle
  rule that does not affect existing memories).
- **PATCH**: Clarification or typo fix with no behavioral change.

Implementations that consume this document (#512 backfill, #514 quarantine, #521
write-guard, #522 SessionStart, #528 audit, #529 `/memory-review`) must declare
which spec version they target. An implementation targeting v1.0.0 must satisfy
every rule in this document.

### Compatibility with `MEMORY_VALIDATION_SPEC.md`

This document v1.0.0 is consistent with `MEMORY_VALIDATION_SPEC.md` v1.0.1. The
two documents share the following fields and must remain aligned across revisions:

- `trust-level` enum (`verified`, `inferred`, `quarantined`)
- `last-verified` format and semantics
- `created-at` format and semantics
- `type` enum (`user`, `feedback`, `project`, `reference`)
- Default tier on backfill (Section 9 of this document; Section 4 of the validation
  spec)

If a future revision of one document changes any of those, the other must be
revised in the same release.

### Change log

#### v1.0.0 — 2026-05-01

Initial release. Defines:

- Three-tier trust model: `verified`, `inferred`, `quarantined`.
- State transition diagram and rules.
- Lifecycle thresholds: 7-day observation, 90-day stale, 90-day quarantine archive
  candidate.
- Auto-application matrix per tier.
- Three operator actions: promote, demote, restore.
- Frontmatter representation (`trust-level`, `last-verified`, `created-at`).
- Storage layout (`memories/` vs `quarantine/`).
- Migration defaults for the four `type` values.

Consumed by: #512 (backfill), #513 (baseline classification), #514 (quarantine
mechanism), #521 (write-guard), #522 (SessionStart), #528 (audit), #529
(`/memory-review`).
