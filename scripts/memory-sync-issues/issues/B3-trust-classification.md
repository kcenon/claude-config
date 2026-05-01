---
title: "chore(memory): review and assign initial trust-level for 17 existing memories"
labels:
  - type/chore
  - priority/medium
  - area/memory
  - size/S
  - phase/B-trust
milestone: memory-sync-v1-trust
blocked_by: [B2]
blocks: [C1]
parent_epic: EPIC
---

## What

Manually review the 17 baseline memory files and confirm or override the trust-level assigned by `backfill-frontmatter.sh`'s defaults. Produce a PR that records the per-file decision.

### Scope (in)

- Review of all 17 baseline memories for trust-level appropriateness
- Override of any auto-assigned tier that is incorrect
- Verification that 3 injection-flagged files (`feedback_ci_*`) are confirmed legitimate
- Decision on `project_steamliner_doc_approval.md` (baseline REPORT proposed `inferred`)

### Scope (out)

- Editing memory body content
- Quarantining any memory (deferred to #B4 if needed; this issue prefers verified or inferred)
- Adding new memories

## Why

Backfill defaults are best-effort heuristics. Each memory's trust level deserves explicit user confirmation before being committed to the new `claude-memory` repo, because once committed the tier influences automatic behavior across all machines.

This is the **only manual gate** in Phase B. Skipping it means a later audit might surprise the user with a memory they don't recognize.

### What this unblocks

- #C1 — claude-memory repo seeded with confirmed-tier memory
- #B4 — quarantine policy can be designed knowing initial state

## Who

- **Implementer**: @kcenon (review)
- **Reviewer**: @kcenon (self-review of decisions)

## When

- **Priority**: medium
- **Estimate**: 1 hour (review only)
- **Target close**: same day as #B2 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: working copy of memory files (location depends on whether #C1 has run)
- **Decision record**: this issue's body + the PR description

## How

### Approach

User reviews each of 17 files, either accepts default or specifies override. Decision recorded in this issue and applied via PR that updates frontmatter `trust-level` field.

### Detailed Design

**Review checklist** (per file):
1. Open the memory file
2. Read description and body
3. Ask: "Did I (the user) explicitly create or confirm this memory's content?"
   - Yes → `verified`
   - No (Claude inferred from conversation) → `inferred`, plan to confirm soon
   - Content is suspicious or stale → `quarantined`
4. Record decision

**Default assignments** (from baseline REPORT §6):

| File | Type | Default | Notes |
|---|---|---|---|
| user_github.md | user | verified | Identity, well-known |
| feedback_ci_merge_policy.md | feedback | verified | CI policy with rationale |
| feedback_ci_never_ignore_failures.md | feedback | verified | CI policy with rationale |
| feedback_explicit_option_choices.md | feedback | verified | UX preference |
| feedback_governance_gates_handoff.md | feedback | verified | Workflow rule |
| feedback_never_merge_with_ci_failure.md | feedback | verified | CI policy with rationale |
| project_claude_code_agent_lint.md | project | verified | Repo-specific lint scope |
| project_claude_code_agent_secrets_perms.md | project | verified | Pre-approved workaround |
| project_claude_config_guards.md | project | verified | Repo guard quirks |
| project_claude_docker_psanalyzer.md | project | verified | PR scope warranty |
| project_kcenon_issue_scope.md | project | verified | Org-wide observation |
| project_kcenon_label_namespaces.md | project | verified | Org-wide observation |
| project_kcenon_layout_standardization_epic.md | project | verified | Master EPIC reference |
| project_kcenon_stale_epic_checklists.md | project | verified | Org-wide observation |
| project_osx_cleaner_branching.md | project | verified | Setup history |
| project_pacs_system_ci_triggers.md | project | verified | Repo-specific correction |
| project_steamliner_doc_approval.md | project | **inferred** | Single-fact possibly Claude-inferred |

**The 3 injection-flagged files** (per #A4 baseline analysis): all justified by explicit "Why:" + "How to apply:" sections; tier remains `verified`. This is not a separate decision but a confirmation.

### Inputs and Outputs

**Input**: 17 memory files with auto-assigned tiers.

**Output**: This issue's body filled in with per-file decision; PR updates any overridden tiers.

**Decision record format** (in PR description):
```markdown
| File | Default | Decision | Reason |
|---|---|---|---|
| user_github.md | verified | verified | accept |
| project_steamliner_doc_approval.md | inferred | verified | confirmed: I added this fact explicitly during 2026-01 review |
| ... | ... | ... | ... |
```

### Acceptance Criteria

- [ ] All 17 files reviewed
- [ ] Per-file decision recorded in this issue or PR (default-accept counts as a decision)
- [ ] All overrides have a one-line reason
- [ ] `project_steamliner_doc_approval.md` has explicit user decision (not just default)
- [ ] The 3 injection-flagged files have explicit confirmation that "Never" usage is legitimate
- [ ] PR commits update only `trust-level` field per decisions; no body changes
- [ ] Final state: every memory has `trust-level` set per decision

### Test Plan

- After PR merges, run validate.sh against the 17 files → all PASS
- Run injection-check.sh → still 3 FLAGGED (the same 3); confirm they remain `verified` per explicit user decision
- @kcenon can articulate the rationale for any non-default decision

### Implementation Notes

- Decisions are user judgment — no script automates this issue
- For `inferred` cases, plan a follow-up `/memory-review` session within 7 days (#F2)
- If during review user notices a memory they don't recognize at all → set `trust-level: quarantined` and open a sub-task to investigate origin
- Decisions are recorded in PR, not memory body — keep memories themselves clean of meta-commentary

### Deliverable

- This issue's body completed with the decision table
- PR that updates `trust-level` field on any file with overridden default

### Breaking Changes

None — only metadata changes.

### Rollback Plan

Revert the PR to restore default-assigned tiers.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #B2
- Blocks: #C1
- Related: #B4 (would handle any quarantine outcome)

**Docs**:
- Default proposal: `/tmp/claude/memory-validation/baseline/REPORT.md` §6
- Trust model: `docs/MEMORY_TRUST_MODEL.md` (#B1)

**Commits/PRs**: (filled at PR time)
