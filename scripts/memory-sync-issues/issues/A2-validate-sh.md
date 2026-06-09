---
title: "feat(memory): implement validate.sh structural and format validator"
labels:
  - type/feature
  - priority/high
  - area/memory
  - size/M
  - phase/A-validation
milestone: memory-sync-v1-validation
blocked_by: [A1]
blocks: [A5]
parent_epic: EPIC
---

## What

Implement `scripts/validate.sh` per the spec from #A1. Validates frontmatter structure, field formats, body length, and semantic patterns (`Why:` / `How to apply:` for feedback/project types) on a single memory file or a directory of them.

### Scope (in)

- Single bash script, executable, no compilation step
- Single-file mode and `--all <dir>` batch mode
- Self-contained (only bash, grep, sed, awk required at runtime)
- Per-file verdict + violation list output
- Summary line in batch mode

### Scope (out)

- Secret detection (#A3)
- Injection-pattern flagging (#A4)
- Auto-fixing detected errors
- Modifying input files (read-only tool)

## Why

The validator is the foundation of every defense layer (write-guard at #D2, pre-commit at #C3, sync-time pre-push and post-pull at #D1, weekly audit at #F1). Without it, the trust-tier model and sync engine have nothing to ground their decisions on.

### What this unblocks

- #A5 — integration tests need this tool to test
- #B2 — backfill-frontmatter.sh shares the frontmatter parser
- #C2 — regen-index.sh shares the frontmatter parser
- #C3 — pre-commit hook calls validate.sh on staged files
- #D1 — sync engine calls validate.sh pre-push and post-pull
- #D2 — write-guard hook calls validate.sh on Edit/Write to memory paths

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — gates Phase A
- **Estimate**: 1 day
- **Target close**: within 1 week of #A1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree** (final): `kcenon/claude-memory/scripts/validate.sh` after #C1 lands
- **Work tree** (interim, before #C1): `kcenon/claude-config/scripts/memory/validate.sh`; will be moved to claude-memory in #C1
- **Reference implementation**: `/tmp/claude/memory-validation/scripts/validate.sh` (197 lines, drafted during 2026-05-01 baseline session, already passes corrected-spec verdicts)

## How

### Approach

Promote the prototype draft to production. The draft already implements the corrected `name` semantics, filename pattern check, `set -u` guards, and `wc -l` normalization. This issue formalizes it, adds fixture tests, documents the exit-code contract, and establishes the executable as a reusable library (frontmatter parser callable from #C2 and #B2).

### Detailed Design

**Script signature**:
```
validate.sh <path/to/memory.md>          # single-file mode
validate.sh --all <dir>                  # batch mode
validate.sh --help                       # usage
```

**Exit codes** (per #A1 spec):
- `0` — PASS (all rules satisfied)
- `1` — structural error (frontmatter delimiters, required fields)
- `2` — format error (field type/length/regex)
- `3` — semantic warning (recommended fields missing, missing `Why:`, etc.)
- `64` — usage error (bad CLI args)

**Internal flow** (per file):
1. Read file; reject if missing
2. Verify line 1 is `---` (frontmatter open)
3. Find closing `---`; reject if absent
4. Extract frontmatter block, body block
5. Parse frontmatter into key→value map (single-line YAML only)
6. Check required fields present and non-empty
7. Check recommended fields; warn if missing
8. Validate field formats (`name` length, `description` length, `type` enum, `trust-level` enum)
9. Validate filename pattern
10. Validate body length bounds
11. Run semantic checks (Why:/How to apply:, absolute-command justification)
12. Print verdict + violations
13. Return appropriate exit code

**Data structures**:
- Frontmatter parsed into two parallel arrays: `keys[]`, `values[]` (bash 3.2 has no associative arrays without `declare -A` from 4+; use linear scan)
- Errors and warnings collected in two arrays; printed in fixed order

**State and side effects**:
- **Read-only** on input files
- Stdout: per-file verdict and violations
- Stderr: usage errors only
- No temp files, no network

**External dependencies**: bash 3.2+, `grep`, `sed`, `head`, `awk` (for closing-delimiter line number lookup), `tr`. All POSIX or commonly available.

### Inputs and Outputs

**Input** (PASS case, hypothetical post-#B2 file with all Phase 2 fields):
```
$ ./validate.sh feedback_ci_merge_policy.md
```

**Output** (PASS):
```
feedback_ci_merge_policy.md                        PASS
```
Exit code: `0`

**Input** (WARN case — current baseline, before backfill):
```
$ ./validate.sh feedback_ci_merge_policy.md
```

**Output** (WARN-SEMANTIC):
```
feedback_ci_merge_policy.md                        WARN-SEMANTIC
    [W] missing field: source-machine (Phase 2)
    [W] missing field: created-at (Phase 2)
    [W] missing field: trust-level (Phase 2)
```
Exit code: `3`

**Input** (FAIL case):
```
$ ./validate.sh broken.md
```

**Output** (FAIL-STRUCT):
```
broken.md                                          FAIL-STRUCT
    [E] missing closing frontmatter delimiter
```
Exit code: `1`

**Input** (batch):
```
$ ./validate.sh --all /tmp/claude/memory-validation/sample-memories/
```

**Output** (last lines of batch):
```
...
user_github.md                                     WARN-SEMANTIC
    [W] missing field: source-machine (Phase 2)
    [W] missing field: created-at (Phase 2)
    [W] missing field: trust-level (Phase 2)

Summary: 1 pass, 17 warn, 0 fail
```
Exit code: `3` (since at least one warn, no fail)

### Edge Cases

- **Empty file** → exit 1, message "missing opening frontmatter delimiter"
  Verify: `: > /tmp/empty.md && validate.sh /tmp/empty.md`
- **Frontmatter delimiter present but body empty** → exit 1, message "body too short: 0 chars (min 30)"
  Verify: synthetic fixture
- **Frontmatter has BOM byte** → exit 1, "missing opening frontmatter delimiter" (BOM is treated as content before the `---`)
  Verify: `printf '\xEF\xBB\xBF---\n' > fixture.md`
- **Frontmatter has `name: "value with quotes"`** → quotes stripped before validation
  Verify: synthetic fixture comparing quoted vs unquoted names
- **`MEMORY.md` (the index file) passed in** → returns PASS without running checks (special case)
  Verify: real `MEMORY.md` from baseline returns 0
- **File with permissions error** → bash read fails, exit code propagates
  Verify: `chmod 000 fixture.md && validate.sh fixture.md`
- **Filename pattern violated but frontmatter clean** → WARN, not FAIL (filename mismatch is a warning per #A1)
  Verify: `cp valid.md weird-name.md` and check exit 3 not 1
- **`type: feedback` body lacks both `Why:` and `How to apply:`** → 2 warnings, exit 3
  Verify: synthetic fixture
- **Body has 5001 chars** → exit 3 with body-too-long warning, NOT a fail
  Verify: synthetic fixture
- **Frontmatter line `name:` with no value** → required-field-missing error, exit 1

### Acceptance Criteria

- [ ] Exit codes match #A1 spec: 0=PASS, 1=structural, 2=format, 3=warning, 64=usage
- [ ] **Required fields enforced** (FAIL on missing): `name`, `description`, `type`
- [ ] **Recommended fields warned** (WARN on missing): `source-machine`, `created-at`, `trust-level`, `last-verified`
- [ ] `name`: 2–100 chars, no newlines (free-form per #A1; quotes stripped)
- [ ] `description`: 1–256 chars, no newlines
- [ ] `type` ∈ `{user, feedback, project, reference}` (case-sensitive)
- [ ] `trust-level` ∈ `{verified, inferred, quarantined}` when present
- [ ] Body 30–5000 chars; outside range emits warning (not fail)
- [ ] feedback/project types: warn if body lacks `Why:` or `How to apply:` markers (case-insensitive bold or plain prefix)
- [ ] Filename pattern check: warn if not `^(user|feedback|project|reference)_[a-z0-9_]+\.md$`
- [ ] Absolute-command justification: warn if "always/never/from now on/must always/must never" appears AND no "because/reason/incident/due to/why" appears in same file
- [ ] **Bash 3.2 compatible**: empty array length-checked before iteration; `BASH_REMATCH` saved to local var before next regex; `wc -l` output normalized
- [ ] `--all <dir>` batch mode produces summary: `Summary: N pass, N warn, N fail`
- [ ] `--all` exit code: 0 if all pass, 1 if any fail, 3 if no fail but any warn
- [ ] Single-file mode prints per-file verdict + per-violation lines prefixed with `[E]` or `[W]`
- [ ] **Against the 17 baseline files** at `/tmp/claude/memory-validation/sample-memories/`: 1 PASS (MEMORY.md), 17 WARN-SEMANTIC, 0 FAIL — must match REPORT exactly
- [ ] **Against synthetic fixtures from `tests/fixtures/`**: each fail-fixture detected, each pass-fixture passes
- [ ] Help text on `--help` or `-h`
- [ ] Script has `+x` permission and shebang `#!/bin/bash`

### Test Plan

- Run on the 17 baseline files → match REPORT verdict counts exactly
- Run on synthetic fixture set (created in #A5)
- Run on macOS bash 3.2.57 (default) and Linux bash 5.x — both must succeed
- Run with `set -u` enabled in script — must not crash on edge cases
- Performance: 17 files in < 1 second (target; not strict)
- Re-run twice — output byte-identical (deterministic)

### Implementation Notes

- macOS `wc -l` output has leading whitespace → use `wc -l | tr -d ' '` then `${var:-0}` default
- `set -u` + empty array reference (`${arr[@]}` when arr is empty) crashes on bash 3.2 → guard with `(( ${#arr[@]} > 0 ))` before iteration
- `BASH_REMATCH[1]` is overwritten on next regex match → save to local var (`local m="${BASH_REMATCH[1]}"`) immediately
- `awk 'NR>1 && /^---$/ {print NR; exit}'` finds closing delimiter — but `awk` triggers `bash-write-guard` if it writes via redirection. This validator does not redirect, only prints; verify the exact awk invocation does not match the guard's heuristic before adopting
- `MEMORY.md` is the auto-generated index, not a memory — short-circuit to PASS without checks
- Frontmatter quote stripping: simple `${value//\"/}` for double quotes; YAML allows single quotes too — handle in v1.1 if needed (defer)
- Help text format follows existing `claude-config/scripts/` convention (terse, examples first)

### Deliverable

- `scripts/validate.sh` (executable, +x, ~200 lines)
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — net-new tool.

### Rollback Plan

Revert PR. No system consumes validate.sh until #C3 (pre-commit hook).

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #A1
- Blocks: #A5
- Related: #B2 (shares frontmatter parser), #C2 (shares frontmatter parser), #C3 (consumer), #D1 (consumer), #D2 (consumer), #F1 (consumer)

**Docs**:
- Spec: `docs/MEMORY_VALIDATION_SPEC.md` (created in #A1)
- Baseline report: `/tmp/claude/memory-validation/baseline/REPORT.md`

**Commits/PRs**: (filled at PR time)

**Reference implementation**: `/tmp/claude/memory-validation/scripts/validate.sh`
