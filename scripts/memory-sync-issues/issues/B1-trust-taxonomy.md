---
title: "docs(memory): define trust-level taxonomy and lifecycle"
labels:
  - type/docs
  - priority/medium
  - area/memory
  - size/S
  - phase/B-trust
milestone: memory-sync-v1-trust
blocked_by: [A5]
blocks: [B2, B3, B4, F2]
parent_epic: EPIC
---

## What

Author `docs/MEMORY_TRUST_MODEL.md` defining the 3-tier trust model (`verified`, `inferred`, `quarantined`), state transitions between tiers, observation windows, auto-application rules, and operator actions.

### Scope (in)

- Definition of each trust level
- State transition diagram
- Promotion / demotion rules
- Observation period for `inferred` (7 days)
- Stale handling for `verified` (`last-verified > 90 days`)
- Auto-application gating per tier

### Scope (out)

- Implementing the backfill tool (#B2) or quarantine mechanism (#B4)
- Implementing `/memory-review` (#F2) or audit (#F1) — this doc *is consumed by* those
- AI-based semantic review (#F3)

## Why

Validation tools (#A2–#A4) tell us **whether** a memory passes structural and content checks. They don't tell us **how much to trust** what's inside. Trust tier addresses the orthogonal question: should this memory automatically influence future sessions, or should the user confirm first?

### Concrete consequences

- A new memory Claude saves through inference gets the same authority as a memory the user explicitly approved → poisoned memory propagates to all machines on first sync
- A 2-year-old memory referencing a removed feature flag gets applied identically to a memory verified yesterday
- No mechanism to "isolate but keep" a suspicious memory (binary keep/delete is too coarse)

The trust model adds a third state and a temporal dimension.

### What this unblocks

- #B2 — backfill tool needs trust-level rules to assign defaults
- #B3 — initial classification of the 17 baseline memories
- #B4 — quarantine directory implementation depends on this taxonomy
- #F2 — `/memory-review` skill walks user through tier transitions
- #D2 — write-guard hook respects auto-application rules
- #D3 — SessionStart hook displays counts by tier

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium — gates Phase B
- **Estimate**: ½ day
- **Target close**: within 3 days of #A5 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config`
- **File**: `docs/MEMORY_TRUST_MODEL.md` (new)

## How

### Approach

Single document with a state diagram, definition table, and operator-action matrix. No code in this issue — pure design specification consumed by later issues.

### Detailed Design

**Document sections**:

1. **Purpose** — why a trust tier exists alongside validation
2. **Tier definitions** — verified / inferred / quarantined
3. **State transitions** — diagram + rules
4. **Lifecycle rules** — observation period, stale handling
5. **Auto-application matrix** — what Claude does at each tier
6. **Operator actions** — promote / demote / restore
7. **Frontmatter representation** — how the trust level is recorded
8. **Storage layout** — how tiers map to disk (`memories/` vs `quarantine/`)
9. **Migration rules** — how existing memories without `trust-level` are classified
10. **Versioning** — start at v1.0.0

**Tier definitions** (initial draft):

| Tier | Meaning | Frontmatter | Storage path | Sync transport | Auto-apply |
|---|---|---|---|---|---|
| verified | User explicitly confirmed; last-verified ≤ 90d | `trust-level: verified` | `memories/` | yes | yes |
| inferred | Saved by Claude through inference; awaiting user confirmation | `trust-level: inferred` | `memories/` | yes | with marker |
| quarantined | Failed validation OR user demoted | `trust-level: quarantined` | `quarantine/` | yes | no |

**State transitions**:

```
              user confirms
   inferred ─────────────────> verified
       │                          │
       │ user demotes             │ user demotes
       │ OR validators fail       │ OR validators fail
       ▼                          ▼
   quarantined <────────────── quarantined
       │                          ▲
       │ user restores            │
       │ + revalidation passes    │ last-verified > 90d
       ▼                          │ + user reaffirms
   verified                      verified (re-affirmed)

   New memory write (Claude)  ──>  inferred
   New memory write (user)    ──>  verified (with explicit user gesture)
```

**Auto-application matrix**:

| Tier | Loaded into context | Applied to behavior | User prompted |
|---|---|---|---|
| verified | yes | yes | no |
| inferred | yes (with "🟡 inferred" marker) | yes (with reminder to confirm) | once per session, max |
| quarantined | no | no | only via explicit `/memory-review` |

**Lifecycle rules**:

- **Inferred observation period**: 7 days from `created-at`. After 7 days, `/memory-review` prompts user to promote (→ verified) or demote (→ quarantined). Until user acts, stays inferred.
- **Verified staleness**: `last-verified > 90d` triggers `/memory-review` reminder. Memory still applied, but flagged in SessionStart and audit reports.
- **Quarantined retention**: 30 days passive (no automatic action), then 60 more days as candidate for archive. After 90 days total, audit suggests archiving to `archive/YYYY-MM/`.

**Migration rules** (for existing memories without `trust-level`):

- type=`user`: → verified (user identity is non-controversial)
- type=`feedback`: → verified (always added through explicit user feedback)
- type=`project`: → verified by default; case-by-case review for memories Claude inferred (#B3)
- type=`reference`: → inferred (external pointers benefit from re-verification)

### Inputs and Outputs

**Input**: Empty document.

**Output** (final document, abridged):

```markdown
# Memory Trust Model

Version: 1.0.0

## 1. Purpose

Validation tells us whether a memory is structurally and semantically clean.
Trust tells us how much authority to grant it. ...

## 2. Tier Definitions

[table with 3 tiers]

## 3. State Transitions

[diagram]

## 4. Lifecycle

- Inferred observation period: 7 days
- Verified staleness threshold: 90 days
- Quarantine archive threshold: 90 days

## 5. Auto-Application Matrix

[table]

## 6. Operator Actions

- Promote: inferred → verified (via /memory-review)
- Demote: verified|inferred → quarantined (via /memory-review or auto on validation fail)
- Restore: quarantined → verified (via /memory-review, requires re-validation)

## 7. Frontmatter

trust-level: verified | inferred | quarantined
last-verified: 2026-05-01    (ISO 8601 date)
created-at: 2026-04-15T...   (ISO 8601 datetime UTC)

## 8. Storage Layout

claude-memory/
├── memories/      (verified, inferred)
└── quarantine/    (quarantined only)

## 9. Migration of Existing Memories

[mapping table, type → default tier]

## 10. Versioning

v1.0.0 — initial publication
```

### Edge Cases

- **Memory promoted then later validators detect injection** → demote to quarantined regardless of prior tier (validators are authoritative)
- **`last-verified` field absent on a verified memory** → treat as stale; prompt at next `/memory-review`
- **User wants to bulk-promote 10 inferred memories** → `/memory-review --batch` mode (specified in #F2)
- **Tier value not in enum** → validate.sh rejects (#A2 spec)
- **Memory in `quarantine/` whose validation now passes** → still quarantined; user explicit restore required (validators don't auto-promote)
- **System-wide setting to disable inferred tier** → not in v1; documented as future enhancement (some users may prefer 2-tier)

### Acceptance Criteria

- [ ] Document `docs/MEMORY_TRUST_MODEL.md` v1.0.0 created
- [ ] Section 2 defines all 3 tiers with semantics
- [ ] Section 3 includes state transition diagram (ASCII or mermaid acceptable)
- [ ] Section 4 specifies: 7-day observation, 90-day stale, 90-day quarantine archive
- [ ] Section 5 specifies auto-application rules per tier including "marker in context for inferred"
- [ ] Section 6 lists 3 operator actions: promote, demote, restore
- [ ] Section 7 specifies frontmatter representation: `trust-level`, `last-verified`, `created-at`
- [ ] Section 8 specifies storage layout: `memories/` vs `quarantine/`
- [ ] Section 9 specifies migration defaults for type ∈ {user, feedback, project, reference}
- [ ] Document is internally consistent — no rule contradicts another
- [ ] Document includes "Versioning" section starting at v1.0.0
- [ ] Document linked from `docs/MEMORY_VALIDATION_SPEC.md` (#A1) and from claude-memory README (#C1)

### Test Plan

- @kcenon walks through 5 hypothetical scenarios using only the document; no missing rules
- Apply migration defaults to the 17 baseline files; result matches the classification proposed in baseline REPORT §6
- Cross-check with #A1 spec — `trust-level` enum and `last-verified` field semantics align

### Implementation Notes

- ASCII state diagram is preferred over mermaid for portability (claude-config repo has no mermaid renderer set up)
- "Auto-application matrix" rows align with the same model used in `docs/MEMORY_VALIDATION_SPEC.md` to avoid duplicate semantics in two docs
- Section 9 (Migration) is consumed by #B2 — keep it precise enough to be implementable as a default-tier function

### Deliverable

- `docs/MEMORY_TRUST_MODEL.md` v1.0.0
- Cross-link added to `docs/MEMORY_VALIDATION_SPEC.md`
- PR linked to this issue

### Breaking Changes

None — first version.

### Rollback Plan

Revert PR. No code consumes this doc until #B2 ships.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #A5
- Blocks: #B2, #B3, #B4, #F2
- Related: #D2 (consumer), #D3 (consumer)

**Docs**:
- Sibling: `docs/MEMORY_VALIDATION_SPEC.md` (#A1)
- Baseline classification proposal: `/tmp/claude/memory-validation/baseline/REPORT.md` §6

**Commits/PRs**: (filled at PR time)
