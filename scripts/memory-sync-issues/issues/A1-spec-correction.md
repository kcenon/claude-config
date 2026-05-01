---
title: "spec: correct validation tooling specification based on baseline findings"
labels:
  - type/docs
  - priority/high
  - area/memory
  - size/S
  - phase/A-validation
milestone: memory-sync-v1-validation
blocked_by: []
blocks: [A2, A3, A4]
parent_epic: EPIC
---

## What

Author `docs/MEMORY_VALIDATION_SPEC.md` as the authoritative spec governing #A2 (validate.sh), #A3 (secret-check.sh), and #A4 (injection-check.sh). The spec corrects four errors discovered during baseline validation of the existing 17 memory files.

### Scope (in)

- Frontmatter field semantics and required/recommended distinction
- Filename pattern as identifier
- Owner identity allowlist (email patterns)
- Bash 3.2 compatibility constraints
- Exit-code contract for the three validators
- Acceptance behavior for the 17 existing baseline files

### Scope (out)

- Implementing validators (those are #A2 / #A3 / #A4)
- Trust-tier semantics (#B1)
- Quarantine mechanics (#B4)

## Why

The original design assumed `name` was a kebab-case identifier. Real auto-memory uses `name` as a human-readable label, and the **filename** carries the identifier. Without correction, validators reject all 17 existing valid memories.

### Concrete consequences if not corrected

1. **All 17 baseline memories fail validation** → migration blocked, can't bootstrap
2. **GitHub no-reply email** (`<id>+kcenon@users.noreply.github.com` in `user_github.md`) flagged as foreign secret
3. **Validators crash on macOS bash 3.2** due to `set -u` + empty array reference and unset `BASH_REMATCH`
4. **`grep -c | wc -l` arithmetic** breaks because output contains leading whitespace on macOS

These four errors were observed during the 2026-05-01 baseline session and are documented with line numbers in the baseline REPORT.

### Reference

`/tmp/claude/memory-validation/baseline/REPORT.md` §3 documents all four errors with concrete examples and the fixes already applied to the prototype validators in `/tmp/claude/memory-validation/scripts/`.

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — blocks Track A entirely; nothing else in Phase A can proceed without this spec
- **Estimate**: ½ day
- **Target close**: within 2 days of this issue opening

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config`
- **File**: `docs/MEMORY_VALIDATION_SPEC.md` (new)

## How

### Approach

Single document captures all four corrections plus the validator contract that #A2–#A4 must satisfy. Use the prototype validators (`/tmp/claude/memory-validation/scripts/`) as the reference implementation — they already implement the corrected spec. The spec document codifies what those scripts do.

### Detailed Design

The spec document has the following sections:

1. **Purpose and scope** — what this spec governs, what it doesn't
2. **File location and naming** — `<type>_<topic>.md` filename pattern as identifier
3. **Frontmatter schema** — required vs recommended fields with examples
4. **Field semantics** — per-field type, format, constraints
5. **Body content rules** — length bounds, structural markers (`Why:`, `How to apply:`)
6. **Owner identity allowlist** — email pattern recognition
7. **Validator exit-code contract** — table mapping exit codes to meanings per tool
8. **Bash compatibility constraints** — 3.2 + 5.x supported, with concrete patterns to use
9. **Baseline behavior expectation** — exact verdicts validators must produce on the 17 existing files
10. **Versioning** — spec version field, change-log section

### Inputs and Outputs

**Input**: Empty starting state. Author writes the document.

**Output** (the document itself, structurally):

```markdown
# Memory Validation Specification

Version: 1.0.0
Last updated: 2026-05-XX

## 1. Purpose and Scope
...

## 2. File Location and Naming

Memory files live in `claude-memory/memories/`.

Filename pattern (REQUIRED):
    ^(user|feedback|project|reference)_[a-z0-9_]+\.md$

The portion before `.md` is the canonical identifier.

Examples (valid):
    user_github.md
    feedback_ci_merge_policy.md
    project_kcenon_label_namespaces.md

Examples (invalid):
    GitHub-Account.md          (uppercase, dash)
    misc_random_thoughts.md    (type prefix not in enum)

## 3. Frontmatter Schema
...

## 7. Validator Exit-Code Contract

| Tool | Exit | Meaning |
|---|---|---|
| validate.sh | 0 | PASS |
| validate.sh | 1 | structural error (block) |
| validate.sh | 2 | format error (block) |
| validate.sh | 3 | semantic warning (warn) |
| secret-check.sh | 0 | clean |
| secret-check.sh | 1 | finding (block) |
| injection-check.sh | 0 | clean |
| injection-check.sh | 3 | flagged (warn, never block) |

## 9. Baseline Behavior Expectation

Against the 17 files at `~/.claude/projects/-Users-raphaelshin-Sources/memory/`:

- validate.sh --all: 1 PASS (MEMORY.md skipped), 17 WARN-SEMANTIC (Phase 2 fields), 0 FAIL
- secret-check.sh --all: 18 CLEAN, 0 with findings
- injection-check.sh --all: 14 CLEAN, 3 FLAGGED (legitimate CI policies)
```

### Edge Cases

- **Future memory types beyond the 4 enum values** → spec must define how to extend (e.g., spec versioning + migration note)
- **Multi-line `description` field** → spec rejects this; alternative is `when_to_use` field for additional context
- **Memory with frontmatter only, no body** → spec rejects (body min 30 chars)
- **Memory body containing legitimate secret-shaped strings** (e.g., describing a leak that happened) → spec must offer escape mechanism; recommended: `<redacted>ghp_...example...</redacted>` token convention

### Acceptance Criteria

- [ ] Spec section "File Location and Naming" states: filename pattern is `^(user|feedback|project|reference)_[a-z0-9_]+\.md$` and is the canonical identifier
- [ ] Spec section "Frontmatter Schema" states: `name` is free-form text 2–100 chars, no newlines (NOT kebab-case)
- [ ] Spec section "Owner Identity Allowlist" states: `<id>+<handle>@users.noreply.github.com` and `<handle>@users.noreply.github.com` are recognized as owner emails
- [ ] Spec section "Bash Compatibility" states: validators target bash 3.2 (macOS default), with explicit guards for empty arrays and unset `BASH_REMATCH`, and `wc -l` output normalized via `tr -d ' '` and `${var:-0}`
- [ ] Spec section "Validator Exit-Code Contract" defines all 8 exit codes per the table above
- [ ] Spec section "Frontmatter Schema" enumerates required vs recommended fields, with `name` / `description` / `type` REQUIRED and `source-machine` / `created-at` / `trust-level` / `last-verified` RECOMMENDED
- [ ] Spec section "Body Content Rules" states: 30 ≤ body chars ≤ 5000; feedback/project type RECOMMEND `Why:` and `How to apply:` markers
- [ ] Spec section "Baseline Behavior Expectation" lists exact expected verdicts on the 17 baseline files
- [ ] All four corrections traceable back to baseline REPORT.md §3
- [ ] Spec includes "Versioning" section and starts at v1.0.0
- [ ] Document committed via PR linked to this issue

### Test Plan

- Spec is internally consistent (no contradictions between sections)
- Spec applied mentally to the 17 baseline files yields the verdicts listed in section 9
- Spec compared against prototype validators in `/tmp/claude/memory-validation/scripts/` — any divergence resolved before merge
- @kcenon review pass

### Implementation Notes

- The spec document is **descriptive of intended behavior**, not a copy of validator source code. Bullet-point style for rules, code blocks for examples only.
- Use the prototype validators as a "reality check" — every rule in the spec must be implementable in bash 3.2; if a rule cannot be implemented simply, reconsider the rule.
- Avoid forward references to features that don't exist yet (no "see #B1 for trust-level details"). The spec must stand alone given just #A1 context.
- Spec is the contract for #A2/#A3/#A4 — write it as if those issues will be implemented by someone with no other context.

### Deliverable

`docs/MEMORY_VALIDATION_SPEC.md` committed to `kcenon/claude-config` via PR linked to this issue.

### Breaking Changes

None — first version of the spec.

### Rollback Plan

Revert PR. No external system depends on the spec until #A2 ships.

## Cross-references

**Issues**:
- Part of #EPIC
- Blocks: #A2, #A3, #A4
- BlockedBy: (none)

**Docs**:
- Baseline report: `/tmp/claude/memory-validation/baseline/REPORT.md` §3 (the four errors)
- Prototype validators (reference implementation): `/tmp/claude/memory-validation/scripts/`

**Commits/PRs**: (filled at PR time)
