---
title: "epic: cross-machine memory sync system"
labels:
  - type/epic
  - area/memory
  - priority/medium
milestone: memory-sync-v1-validation
blocked_by: []
blocks: []
---

## What

Build a system that synchronizes Claude Code's auto-memory across multiple machines using a private git-backed shared store with validation and a 3-tier trust model.

### Scope (in)

- New private repository: `kcenon/claude-memory` (data + validation tooling)
- Sync engine, hooks, and install integration in `kcenon/claude-config`
- launchd / systemd scheduler for hourly bidirectional sync
- Audit and review tooling for memory hygiene
- 3-tier trust model: `verified`, `inferred`, `quarantined`
- 5-layer defense against contaminated memory: write-time, pre-commit, sync-pre-push, sync-post-pull, weekly audit

### Scope (out)

- Cloud-storage-based sync (Dropbox / iCloud / Drive) — rejected: conflict resolution non-deterministic
- Memory entries shared across users — single-user, multi-machine only
- Real-time sync below 1-hour granularity
- Cross-account / org-wide memory sharing

### Stakeholders

- **Primary user**: @kcenon (sole user across N machines, currently 1 active)
- **Affected systems**: Every Claude Code session on every machine where this user works

## Why

Currently each machine accumulates its own auto-memory in isolation under `~/.claude/projects/<encoded-cwd>/memory/`. Insights gained on one machine never propagate to other machines, and there is no mechanism to detect tampered, stale, or contaminated memory before it influences future sessions.

### Concrete problems being solved

1. **Knowledge fragmentation** — feedback rules ("Never merge with CI failure"), project context (org-specific label namespaces), user preferences (commit attribution off) diverge per machine
2. **Re-learning cost** — each new machine independently re-discovers the same lessons through trial and correction
3. **No oversight against memory poisoning** — prompt-injection-driven self-reinforcing memory could persist undetected across sessions because the malicious instruction looks like a legitimate user-saved memory
4. **No backup** — machine loss = memory loss with no recovery path
5. **No history** — cannot diff "what changed in my memory last week" or revert a regrettable feedback rule

### Business value

Memory becomes a versioned, auditable, multi-machine asset rather than per-machine state. Specifically:

- Every change has an author (signed commit), timestamp, and rationale
- Suspicious changes can be reviewed, rolled back, or quarantined
- Adding a new machine takes one bootstrap command instead of weeks of re-learning
- Audit trail enables post-hoc analysis when Claude behavior surprises the user

### Reference

Design discussion: 2026-05-01 session. Baseline validation report: `/tmp/claude/memory-validation/baseline/REPORT.md`.

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon (single-developer project)
- **Affected end-users**: @kcenon
- **No external sign-offs required** (private repos, single user)

## When

- **Phase A target**: 2026-05 (validation tooling)
- **Phase B–E target**: 2026-Q3 (sync to single-machine stable)
- **Phase F–G target**: 2026-Q4 (multi-machine stable, documented runbook)

### Dependencies

- GitHub private repo allowance (already available)
- SSH signing key on each participating machine (set up at #C4 time)
- launchd (macOS) / systemd (Linux) — both standard

### Sequencing constraint

Validation infrastructure (Phase A) **must** ship before sync engine (Phase D), because the sync engine is what propagates contaminated memory across machines if validation is missing. Trust model (Phase B) **must** ship before repo bootstrap (Phase C), because quarantine semantics need to be defined before the first commits land in the new repo.

## Where

- **Issue tracker**: `kcenon/claude-config` (this repo, single source of truth for all 28 child issues)
- **Work trees**:
  - `kcenon/claude-config` — sync engine, hooks, install scripts, operational docs
  - `kcenon/claude-memory` (new private repo, created in #C1) — memory data, validators, audit job

### File-level deliverables

| Repo | Path | Created in |
|---|---|---|
| claude-config | `docs/MEMORY_VALIDATION_SPEC.md` | #A1 |
| claude-config | `docs/MEMORY_TRUST_MODEL.md` | #B1 |
| claude-config | `docs/MEMORY_SYNC.md` | #G3 |
| claude-config | `docs/THREAT_MODEL.md` | #G3 |
| claude-config | `scripts/memory-sync.sh` | #D1 |
| claude-config | `global/hooks/memory-write-guard.sh` | #D2 |
| claude-config | `global/hooks/memory-integrity-check.sh` | #D3 |
| claude-config | `scripts/memory-status.sh` | #D4 |
| claude-config | `scripts/launchd/com.kcenon.claude-memory-sync.plist` | #E3 |
| claude-memory | `scripts/validate.sh` | #A2 |
| claude-memory | `scripts/secret-check.sh` | #A3 |
| claude-memory | `scripts/injection-check.sh` | #A4 |
| claude-memory | `scripts/regen-index.sh` | #C2 |
| claude-memory | `scripts/backfill-frontmatter.sh` | #B2 |
| claude-memory | `scripts/audit.sh` | #F1 |
| claude-memory | `.git/hooks/pre-commit` (installed) | #C3 |
| claude-memory | `.github/workflows/memory-validation.yml` | #C5 |

## How

### Approach

Seven sequential phases. Each phase corresponds to one milestone and produces independently valuable artifacts (validation tooling alone is useful; trust model alone is useful; etc.). Single-machine deployment delivers most of the value at Phase E; Phase F–G expand to multi-machine.

### Phases

| Phase | Milestone | Issues | Output value if work stops here |
|---|---|---|---|
| A | memory-sync-v1-validation | A1–A5 | Standalone validation tools usable on existing memory |
| B | memory-sync-v1-trust | B1–B4 | Trust-tagged memory, quarantine mechanism |
| C | memory-sync-v1-bootstrap | C1–C5 | Memory repo with CI gate but no automatic sync |
| D | memory-sync-v1-engine | D1–D5 | Sync engine functional but not yet scheduled |
| E | memory-sync-v1-single | E1–E3 | Single-machine sync running on schedule |
| F | memory-sync-v1-audit | F1–F4 | Weekly audit + interactive review |
| G | memory-sync-v1-multi | G1–G3 | Multi-machine deployment + final docs |

### Child issues

<!-- BEGIN CHILD-ISSUES — populated after all children are registered -->
- [ ] #A1 — spec: correct validation tooling specification based on baseline findings
- [ ] #A2 — feat(memory): implement validate.sh structural and format validator
- [ ] #A3 — feat(memory): implement secret-check.sh PII/token scanner
- [ ] #A4 — feat(memory): implement injection-check.sh suspicious-pattern flagger
- [ ] #A5 — test(memory): integration tests for validate/secret/injection tools
- [ ] #B1 — docs(memory): define trust-level taxonomy and lifecycle
- [ ] #B2 — feat(memory): backfill-frontmatter.sh adds source-machine/created-at/trust-level
- [ ] #B3 — chore(memory): review and assign initial trust-level for 17 existing memories
- [ ] #B4 — feat(memory): quarantine directory mechanism
- [ ] #C1 — chore(memory): create kcenon/claude-memory private repository
- [ ] #C2 — feat(memory): deterministic MEMORY.md index generator
- [ ] #C3 — feat(memory): pre-commit hook in claude-memory repo
- [ ] #C4 — chore(memory): enforce SSH commit signing across machines
- [ ] #C5 — ci(memory): GitHub Actions runs validation on every push
- [ ] #D1 — feat(memory): memory-sync.sh bidirectional sync with integrated validation
- [ ] #D2 — feat(memory): PreToolUse hook validates memory writes
- [ ] #D3 — feat(memory): SessionStart hook displays memory health summary
- [ ] #D4 — feat(memory): memory-status.sh diagnostic CLI
- [ ] #D5 — feat(memory): conflict alerting channel
- [ ] #E1 — docs(memory): single-machine migration runbook
- [ ] #E2 — chore(memory): single-machine stabilization observation checklist
- [ ] #E3 — feat(memory): launchd plist and install_memory_sync() integration
- [ ] #F1 — feat(memory): weekly audit.sh report generator
- [ ] #F2 — feat(memory): /memory-review interactive review skill
- [ ] #F3 — feat(memory): monthly AI semantic review (optional)
- [ ] #F4 — feat(memory): memory access logger
- [ ] #G1 — docs(memory): second-machine onboarding runbook
- [ ] #G2 — test(memory): multi-machine conflict scenario validation
- [ ] #G3 — docs(memory): MEMORY_SYNC.md and THREAT_MODEL.md
<!-- END CHILD-ISSUES -->

> Child issue numbers above are placeholders (`#A1`–`#G3`). After registration the automation script `scripts/memory-sync-issues/create-issues.sh` replaces each token with the real GitHub issue number.

### Acceptance Criteria (EPIC closure)

- [ ] All 28 child issues closed
- [ ] Two machines running stable sync for 14 consecutive days with no critical alerts
- [ ] Zero secret/injection findings in baseline post-migration
- [ ] Documented threat model (`docs/THREAT_MODEL.md`) covers all 7 threat categories
- [ ] Documented operational runbook (`docs/MEMORY_SYNC.md`) covers daily ops, troubleshooting, rollback
- [ ] Rollback procedure tested end-to-end (real teardown + restore on a non-primary machine)
- [ ] Audit job has produced ≥ 4 consecutive weekly reports without manual intervention
- [ ] Trust-level promotion lifecycle exercised: at least one `inferred` → `verified` and one `inferred` → `quarantined`

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Sync silent failure (launchd dies, no alert) | Medium | High | SessionStart integrity check displays last-sync age; >24h triggers alert |
| R2 | Contaminated memory propagates to all machines | Low | Critical | 5-layer defense: write-guard, pre-commit, sync-pre-push, sync-post-pull, weekly audit |
| R3 | Machine SSH signing key lost | Low | Medium | Per-machine key (not shared); loss affects one machine only, easy to rotate |
| R4 | User overwhelmed by audit findings | Medium | Low | Audit batches by week; `/memory-review` paginates; only flagged items surface |
| R5 | Backfill destroys existing data | Low | High | `backfill-frontmatter.sh` is idempotent + auto-creates timestamped backup; dry-run mode default |
| R6 | False-positive validators block valid memory | Medium | Medium | injection-check is warn-only (exit 3); validators never delete data |
| R7 | claude-memory repo loss / GitHub outage | Low | High | Local clones on every machine = effective replication; weekly `git bundle` to local backup |

### References

- Design discussion: 2026-05-01 session
- Baseline validation report: `/tmp/claude/memory-validation/baseline/REPORT.md`
- Existing auto-memory location: `~/.claude/projects/<encoded-cwd>/memory/`
- Spec (created in #A1): `docs/MEMORY_VALIDATION_SPEC.md`

## Cross-references

**Issues**: (none — this is the EPIC)

**Docs**:
- `~/.claude/CLAUDE.md` (auto-memory description)
- Baseline report: `/tmp/claude/memory-validation/baseline/REPORT.md`
- Phase 1 prototype validators: `/tmp/claude/memory-validation/scripts/`

**Commits/PRs**: (filled as work progresses)
