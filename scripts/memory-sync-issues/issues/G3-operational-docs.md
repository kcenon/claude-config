---
title: "docs(memory): MEMORY_SYNC.md and THREAT_MODEL.md"
labels:
  - type/docs
  - priority/medium
  - area/memory
  - size/M
  - phase/G-rollout
milestone: memory-sync-v1-multi
blocked_by: [G2]
blocks: []
parent_epic: EPIC
---

## What

Consolidate and finalize the two operational documents that are the system's user-facing interface: `docs/MEMORY_SYNC.md` (operations runbook) and `docs/THREAT_MODEL.md` (security analysis). Both reach v1.0.0 and are linked from the main claude-config README.

### Scope (in)

- `docs/MEMORY_SYNC.md` — full operations doc with all sections from prior issues consolidated
- `docs/THREAT_MODEL.md` — new doc covering 7 threat categories and 5-layer defense
- Cross-links between both docs, and to `MEMORY_VALIDATION_SPEC.md` (#A1) and `MEMORY_TRUST_MODEL.md` (#B1)
- Main claude-config README updated to link to both
- Both docs at v1.0.0

### Scope (out)

- Implementation work
- Updates to other docs (CLAUDE.md, README.ko.md) beyond a single linking line each
- Ongoing maintenance (subsequent versions)

## Why

Throughout Phases A–F, sections of `docs/MEMORY_SYNC.md` were authored in pieces (single-machine migration in #E1, multi-machine onboarding in #G1, install/uninstall in #E3, audit operations in #F1, etc.). Without this consolidation issue, the doc would be fragmented and inconsistent.

`THREAT_MODEL.md` has been referenced throughout but never written. Without it, the security claims of the system are scattered across issue descriptions and not easily auditable.

This issue produces the **two canonical user-facing docs** for the system. Their existence at v1.0.0 closes Phase G and the EPIC.

### What this unblocks

- EPIC closure
- Future maintenance — a centralized doc is much easier to keep current than scattered fragments
- Onboarding any future user / contributor (even if currently single-user, the docs serve as memory)

## Who

- **Author**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium — final phase
- **Estimate**: 1 day
- **Target close**: within 1 week of #G2 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**:
  - `kcenon/claude-config/docs/MEMORY_SYNC.md`
  - `kcenon/claude-config/docs/THREAT_MODEL.md`
  - `kcenon/claude-config/README.md` (link update)

## How

### Approach

`MEMORY_SYNC.md` already exists in fragments — this issue mostly consolidates, smooths transitions, and adds missing sections. `THREAT_MODEL.md` is greenfield but follows a known structure (threats × mitigations matrix).

### Detailed Design

**`docs/MEMORY_SYNC.md` final structure** (v1.0.0):

```markdown
# Memory Sync — Operations Guide

Version: 1.0.0
Last updated: 2026-MM-DD

## What this is

Memory sync is a system that keeps Claude Code's auto-memory in sync across multiple
machines using a private git-backed store. ...

## Architecture

[Diagram or ASCII showing: machines ↔ claude-memory remote ↔ validators ↔ Claude
sessions]

## Installation

[merged from #E3]

## Single-machine migration

[merged from #E1]

## Adding a new machine

[merged from #G1]

## Daily operations

### Manual sync
### Reading memory-status.sh output
### Acting on integrity-check warnings at SessionStart

## Validators

[Brief overview, link to MEMORY_VALIDATION_SPEC.md for spec details]

## Trust tiers

[Brief overview, link to MEMORY_TRUST_MODEL.md for spec details]

## Audit

### Weekly audit (audit.sh)
### Monthly semantic review (semantic-review.sh, optional)
### /memory-review interactive review

## Conflict resolution

When `memory-sync.sh` aborts on conflict (exit 3), follow this procedure:

1. Read `~/.claude/logs/memory-sync.log` for the failing files
2. Decide which side wins per the rules below
3. Manually resolve in the working tree
4. Run `memory-sync.sh` again

[Resolution rules table]

## Rollback procedures

### Single-machine rollback
### Whole-system rollback (return to per-machine memory)

## SSH commit signing

### Initial setup
### Rotation procedure
### Compromise procedure

## Privacy

- Access log records file paths only, never content
- Repo is private; data does not leave kcenon's GitHub
- Local logs do not sync between machines

## Troubleshooting

### "memory-sync.sh exits 5 (lock contention)"
### "Last sync 28h ago — sync may be stuck"
### "auto-quarantine on post-pull validation"
### "merge conflict — manual resolution required"
### "memory-write-guard hook blocked write"
### Common pitfalls cross-reference

## Glossary

- verified, inferred, quarantined
- backfill
- write-guard
- index drift

## Versioning

v1.0.0 — initial publication after EPIC #N closed
```

**`docs/THREAT_MODEL.md` structure** (new, v1.0.0):

```markdown
# Memory Sync — Threat Model

Version: 1.0.0
Last updated: 2026-MM-DD

## Scope

This threat model covers the cross-machine memory sync system. Out of scope:
threats to the host OS, network infrastructure, GitHub itself.

## Assets

| Asset | Sensitivity | Notes |
|---|---|---|
| Memory content | Medium | May reference projects, decisions; not secrets |
| User identity (email, GitHub handle) | Low | Already public via commits |
| Session-specific transient state | High | Never written to disk; not in scope |

## Threats

### T1 — Prompt injection via memory poisoning

**Vector**: Malicious content reaches a memory file (via prompt injection in
external doc Claude reads, or via direct write).

**Impact**: Persistent self-reinforcing instruction across all future sessions.

**Mitigations**: see "5-layer defense" below.

### T2 — Secret leak

**Vector**: User pastes terminal output containing token; Claude auto-saves a
memory containing co-worker's email.

**Impact**: Secret committed to git, replicated to all clones, available in
GitHub history forever.

**Mitigations**: secret-check.sh at write-guard, pre-commit, sync-pre-push,
GitHub Actions, weekly audit.

### T3 — Stale memory misleading future behavior

**Vector**: A memory written about a now-removed feature stays applied indefinitely.

**Impact**: Claude follows obsolete instructions.

**Mitigations**: 90-day stale flag in audit; /memory-review prompt.

### T4 — Memory propagation of bad data across machines

**Vector**: Bad data lands on machine A; sync propagates to machine B before
detection.

**Impact**: All machines act on bad data.

**Mitigations**: post-pull validation (#D1) auto-quarantines on machine B;
GitHub Actions (#C5) rejects bad pushes server-side.

### T5 — Sync silent failure

**Vector**: launchd / systemd dies; sync stops without alerting.

**Impact**: Machines drift; user surprised when changes don't propagate.

**Mitigations**: SessionStart integrity check (#D3) flags last-sync > 24h.

### T6 — Repository or signing-key compromise

**Vector**: Attacker gains write access to claude-memory remote OR signing key.

**Impact**: Forged memory entries appear legitimate.

**Mitigations**: Branch protection requires signed commits; per-machine signing
keys (loss affects one machine); rotation procedure (#C4 docs).

### T7 — User error / typo

**Vector**: User mis-edits a memory and loses content.

**Impact**: One memory damaged.

**Mitigations**: backfill auto-backup; git history; `quarantine-restore.sh`;
`/memory-review` edit path with revert option.

## 5-layer defense

| Layer | Where | Catches | Gate type |
|---|---|---|---|
| 1 | memory-write-guard.sh (#D2) | Bad writes at the moment Claude attempts | Block |
| 2 | pre-commit hook (#C3) | Bad commits at the moment author commits | Block |
| 3 | memory-sync.sh pre-push (#D1) | Bad commits before pushing | Block |
| 4 | memory-sync.sh post-pull (#D1) | Bad commits incoming from other machine | Quarantine |
| 5 | weekly audit.sh (#F1) | Slow rot, stale, broken refs | Surface for review |

Plus orthogonal layers:
- GitHub Actions (#C5) — server-side mirror of layers 2–3
- Monthly semantic review (#F3, optional) — AI-based deeper analysis

## Trust model

Three tiers per `docs/MEMORY_TRUST_MODEL.md`:
- verified — automatically applied
- inferred — applied with marker, awaiting user promotion
- quarantined — never auto-applied

## Residual risks

- Compositional injection across multiple memories — partially mitigated by F3
- Insider threat by user account itself — out of scope (single-user system)
- GitHub outage prevents sync — out of scope (degrades gracefully via local clone)
- Time-window between bad write and validators catching — minutes; mitigated by 5-layer overlap

## Versioning

v1.0.0 — initial publication
```

**README link update**:
```markdown
## Memory sync (multi-machine)

Memory sync keeps Claude Code's auto-memory consistent across all your machines
via a private git store. See:

- [Operations guide](docs/MEMORY_SYNC.md)
- [Threat model](docs/THREAT_MODEL.md)
- [Validation spec](docs/MEMORY_VALIDATION_SPEC.md)
- [Trust model](docs/MEMORY_TRUST_MODEL.md)
```

### Inputs and Outputs

**Input**: Fragmented `MEMORY_SYNC.md` from prior issues + design discussions for THREAT_MODEL.md.

**Output**: Two completed docs at v1.0.0; README updated.

### Edge Cases

- **Doc length** → MEMORY_SYNC.md will be 1500+ lines; that's expected for an operational guide; pages should be subdivided with H2/H3 properly so the TOC is navigable
- **Inconsistencies between fragmented sections** → reconciled during consolidation (this issue's main work)
- **References to "future enhancements"** in fragmented sections → tagged consistently; some retained, some deleted as they're now done
- **THREAT_MODEL claims that no longer match implementation** → caught here; cross-check before merging
- **Glossary terms used inconsistently** → unified during consolidation

### Acceptance Criteria

- [ ] `docs/MEMORY_SYNC.md` v1.0.0 with all sections per Detailed Design
- [ ] `docs/THREAT_MODEL.md` v1.0.0 with 7 threats + 5-layer defense
- [ ] Cross-links between MEMORY_SYNC, THREAT_MODEL, MEMORY_VALIDATION_SPEC, MEMORY_TRUST_MODEL all working (no broken links)
- [ ] Main claude-config README has "Memory sync" section with all 4 doc links
- [ ] All commands and code blocks tested for currency
- [ ] Glossary in MEMORY_SYNC defines: verified / inferred / quarantined / backfill / write-guard / index drift
- [ ] Troubleshooting section covers ≥ 5 common error messages with resolution
- [ ] Versioning sections start both docs at v1.0.0
- [ ] No "TODO" or "TBD" markers remain
- [ ] Internal consistency: a reader following links from one doc to another never encounters contradictions

### Test Plan

- @kcenon reads both docs end-to-end and notes inconsistencies; resolves before merge
- All hyperlinks tested (`./check-links.sh` or manual)
- All command examples copy-paste-ready
- Spell check pass
- Doc-review skill (`/doc-review`) run on both docs

### Implementation Notes

- Use `claude-config/.claude/rules/workflow/github-pr-5w1h.md` and similar style as the doc tone reference (terse, table-heavy)
- Mermaid diagrams not supported in this repo's default render — use ASCII art or omit
- Cross-link format: `[Operations guide](docs/MEMORY_SYNC.md)` (relative paths)
- Do **not** dump entire issue bodies into the docs — distill to user-facing operational content; design rationale stays in issues
- THREAT_MODEL.md: be honest about residual risks; "all threats fully mitigated" is never true
- Versioning: v1.0.0 published; subsequent versions per change

### Deliverable

- `docs/MEMORY_SYNC.md` v1.0.0
- `docs/THREAT_MODEL.md` v1.0.0
- README link update
- PR linked to this issue
- @kcenon's read-through confirmation in PR description

### Breaking Changes

None — documentation only.

### Rollback Plan

Revert PR. Existing fragmented sections still accessible via git history.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #G2
- Blocks: (none — final issue)
- Related: ALL prior issues — this consolidates their doc fragments

**Docs (final state after this PR)**:
- `docs/MEMORY_SYNC.md` (final operational guide)
- `docs/THREAT_MODEL.md` (new, security analysis)
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1, unchanged)
- `docs/MEMORY_TRUST_MODEL.md` (#B1, unchanged)

**Commits/PRs**: (filled at PR time)
