# Memory Trust Baseline Classification

**Version**: 1.0.0
**Decided**: 2026-05-01
**Decided by**: @kcenon (self-review)
**Issue**: [#513](https://github.com/kcenon/claude-config/issues/513)
**Status**: Active

---

## 1. Purpose

Records the per-file initial trust-level decision for the 17 baseline memory
files that pre-date the Phase 2 trust model (`docs/MEMORY_TRUST_MODEL.md`).
Once committed, these tiers govern auto-application behavior across every
machine that syncs `claude-memory` (#515).

This document is the canonical decision record. It supplements the
default-assignment heuristics in `scripts/memory/backfill-frontmatter.sh`
(#512) by recording the user's explicit confirmation of each tier.

## 2. Methodology

For each of the 17 baseline files, the reviewer applied the four-step
checklist from `docs/MEMORY_TRUST_MODEL.md` Section 9 ("Migration of Existing
Memories"):

1. Open the memory file.
2. Read description and body.
3. Ask: *Did the user explicitly create or confirm this memory's content?*
   - Yes -> `verified`.
   - No (Claude inferred from conversation) -> `inferred`; plan to confirm
     within the 7-day observation window.
   - Content is suspicious or stale -> `quarantined`.
4. Record the decision in the table below; default-accept counts as a
   decision.

The default tier proposed by `backfill-frontmatter.sh` follows the migration
table in `docs/MEMORY_TRUST_MODEL.md` Section 9: `user`, `feedback`, and
`project` types default to `verified`; `reference` defaults to `inferred`.
The conservative-default rule (`docs/MEMORY_TRUST_MODEL.md` Section 9) further
demands `inferred` whenever origin is ambiguous.

## 3. Per-File Decision Table

| # | File | Type | Default | Decision | Reason |
|---|---|---|---|---|---|
| 1 | `user_github.md` | user | verified | verified | accept; user identity, well-known, non-controversial |
| 2 | `feedback_ci_merge_policy.md` | feedback | verified | verified | accept; CI policy with explicit Why and How-to-apply rationale |
| 3 | `feedback_ci_never_ignore_failures.md` | feedback | verified | verified | accept; CI policy with explicit Why and How-to-apply rationale |
| 4 | `feedback_explicit_option_choices.md` | feedback | verified | verified | accept; UX preference dictated by the user |
| 5 | `feedback_governance_gates_handoff.md` | feedback | verified | verified | accept; explicit workflow rule |
| 6 | `feedback_never_merge_with_ci_failure.md` | feedback | verified | verified | accept; CI policy with explicit Why and How-to-apply rationale |
| 7 | `project_claude_code_agent_lint.md` | project | verified | verified | accept; repo-specific lint scope confirmed by the user |
| 8 | `project_claude_code_agent_secrets_perms.md` | project | verified | verified | accept; pre-approved workaround documented during a prior session |
| 9 | `project_claude_config_guards.md` | project | verified | verified | accept; repo guard quirks observed and confirmed |
| 10 | `project_claude_docker_psanalyzer.md` | project | verified | verified | accept; PR scope warranty captured from explicit user direction |
| 11 | `project_kcenon_issue_scope.md` | project | verified | verified | accept; org-wide observation confirmed by the user |
| 12 | `project_kcenon_label_namespaces.md` | project | verified | verified | accept; org-wide observation confirmed by the user |
| 13 | `project_kcenon_layout_standardization_epic.md` | project | verified | verified | accept; master EPIC reference under active stewardship |
| 14 | `project_kcenon_stale_epic_checklists.md` | project | verified | verified | accept; org-wide observation confirmed by the user |
| 15 | `project_osx_cleaner_branching.md` | project | verified | verified | accept; setup history confirmed by the user |
| 16 | `project_pacs_system_ci_triggers.md` | project | verified | verified | accept; repo-specific correction confirmed by the user |
| 17 | `project_steamliner_doc_approval.md` | project | inferred | inferred | accept; single-fact memory possibly Claude-inferred -- keep on observation track per `MEMORY_TRUST_MODEL.md` Section 4 |

## 4. Distribution Summary

| Tier | Count | Files |
|---|---|---|
| `verified` | 16 | items 1-16 |
| `inferred` | 1 | item 17 (`project_steamliner_doc_approval.md`) |
| `quarantined` | 0 | -- |

Default-accept rate: 17/17 (100%). No overrides applied. The user's
self-review confirmed the heuristic defaults proposed by
`scripts/memory/backfill-frontmatter.sh` are correct for every file.

## 5. Injection-Flagged Files (Confirmation)

The injection-check pre-screen (#509) flagged three files in the baseline
analysis:

- `feedback_ci_merge_policy.md`
- `feedback_ci_never_ignore_failures.md`
- `feedback_never_merge_with_ci_failure.md`

These are flagged because each uses the absolute commands `Never` /
`Always` three or more times -- the absolute-command-density heuristic
defined in `docs/MEMORY_VALIDATION_SPEC.md` Section 6, Pattern 7.

**Confirmation**: The reviewer verified that each "Never" / "Always" usage
is paired with an explicit Why section and How-to-apply guidance, and the
absolute commands describe legitimate CI safety policy (do not merge
broken builds, do not ignore failing checks). These are accepted false
positives, not injection attempts. All three files remain `verified`.

This confirmation is the explicit user decision required by Acceptance
Criterion 5 of issue #513.

## 6. Follow-Up

- `project_steamliner_doc_approval.md` is the only `inferred` baseline
  entry. Per `MEMORY_TRUST_MODEL.md` Section 4, the user reviews it in
  `/memory-review` (#529) after the 7-day observation window completes
  (i.e., on or after 2026-05-08). The expected outcome is promotion to
  `verified`; demotion to `quarantined` would be unexpected.
- The 16 `verified` entries are eligible for the 90-day staleness check
  per `MEMORY_TRUST_MODEL.md` Section 4. The earliest re-affirmation
  prompt is 2026-07-30 (90 days from this baseline date).
- If a future audit (#528) flags any of the 16 `verified` entries via
  `validate.sh`, `secret-check.sh`, or any blocking validator, the trust
  model auto-demotes them to `quarantined`. This document is not a
  bypass.

## 7. Application

The decisions in Section 3 are applied by running:

```bash
scripts/memory/backfill-frontmatter.sh --execute --target-dir <memories-dir>
```

against the operator's live memory directory. The script is idempotent
and the heuristic defaults match every decision in this document; no
override pass is required.

For the one `inferred` entry (item 17), the operator may verify the
result with:

```bash
grep '^trust-level:' <memories-dir>/project_steamliner_doc_approval.md
# expected: trust-level: inferred
```

## 8. Cross-References

- `docs/MEMORY_TRUST_MODEL.md` (#511) -- trust-level taxonomy and
  lifecycle.
- `docs/MEMORY_VALIDATION_SPEC.md` (#506, extended in #509) -- frontmatter
  rules and injection-check pattern definitions.
- `scripts/memory/backfill-frontmatter.sh` (#512) -- backfill tool whose
  defaults this document confirms.
- `scripts/memory/injection-check.sh` (#509) -- pre-screen that flagged
  the three CI-policy files referenced in Section 5.
- Issue [#513](https://github.com/kcenon/claude-config/issues/513) --
  authoritative requirement for this decision record.
- Epic [#505](https://github.com/kcenon/claude-config/issues/505) --
  Phase B trust-tier rollout.

## 9. Change Log

### v1.0.0 -- 2026-05-01

Initial baseline classification of the 17 pre-Phase-2 memory files.
All 17 default tiers accepted; no overrides applied. Three injection-
flagged CI-policy files explicitly confirmed as accepted false positives
remaining at `verified`.
