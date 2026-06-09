---
title: "feat(memory): deterministic MEMORY.md index generator"
labels:
  - type/feature
  - priority/medium
  - area/memory
  - size/M
  - phase/C-bootstrap
milestone: memory-sync-v1-bootstrap
blocked_by: [A5, B4, C1]
blocks: [C3]
parent_epic: EPIC
---

## What

Implement `scripts/regen-index.sh` that generates the `MEMORY.md` index by reading frontmatter from `memories/*.md` and `quarantine/*.md`. Output is deterministic (sorted, no timestamps in marker comments) so two runs produce byte-identical files. Includes `--check` mode for CI drift detection.

### Scope (in)

- Single bash script, executable
- Reads frontmatter (`name`, `description`, `type`) from each `*.md`
- Generates output between fixed AUTO-GENERATED markers
- Groups by type in fixed order: User, Feedback, Project, Reference
- Within group, sorted alphabetically by filename
- Separate "Quarantine" section (lists quarantined entries with reason)
- `--check` mode: regenerates and diffs against current `MEMORY.md`, exits non-zero on drift

### Scope (out)

- Editing memory bodies
- Adding new sections beyond the fixed type list
- HTML/JSON output formats

## Why

`MEMORY.md` is loaded by Claude on every session start as the index of what memories exist. Without an authoritative generator, the index drifts: hand-edits leak in, new files don't get indexed, quarantine state is invisible. Drift means users (and Claude) act on wrong information about what memory is available.

### What this unblocks

- #C3 — pre-commit hook calls `--check` to refuse commits with drift
- #D1 — sync engine calls regen after pull/merge to keep index aligned with content
- #F1 — audit can compare current index to expected
- #G3 — operational docs reference this generator as the single source of `MEMORY.md` truth

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 1 day
- **Target close**: within 1 week of #C1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-memory/scripts/regen-index.sh`
- **Output target**: `kcenon/claude-memory/MEMORY.md`

## How

### Approach

Reuse #A2's frontmatter parser (extracted as a sourceable function or shared lib). For each memory file, emit one bullet of the form `- [<name>](<path>) — <description>`. Group by type with fixed-order H2 headers. Wrap output in marker comments. `--check` does the same generation to a temp buffer and `diff`s against the existing `MEMORY.md`.

### Detailed Design

**Script signature**:
```
regen-index.sh                       # in-place regenerate MEMORY.md
regen-index.sh --check               # exit 0 if no drift, 1 if drift, prints diff
regen-index.sh --output <path>       # write to alternate path
regen-index.sh --memories-dir <dir>  # use alternate source dir
```

**Exit codes**:
- `0` — success (or no drift in `--check`)
- `1` — drift detected (`--check` only) OR write failure
- `64` — usage error

**Internal flow**:
1. Read existing `MEMORY.md` if exists; extract content **outside** AUTO-GENERATED markers (preserved verbatim)
2. Scan `memories/*.md`:
   a. Skip `MEMORY.md` itself
   b. Parse frontmatter for `name`, `description`, `type`, `trust-level`
   c. Reject if frontmatter parse fails (validate.sh would have caught this earlier)
3. Group by type
4. Emit AUTO-GENERATED block
5. Scan `quarantine/*.md` similarly; emit Quarantine section (only if non-empty)
6. Concatenate: pre-marker content + new generated block + post-marker content
7. If `--check`: diff against existing; exit 0 or 1
8. Else: write atomically (temp file + mv)

**Output format** (full example, deterministic):

```markdown
# Claude Memory Index

<!-- BEGIN AUTO-GENERATED — do not edit -->
<!-- generator: regen-index.sh v1 -->

## User

- [GitHub account](memories/user_github.md) — GitHub handle: @kcenon

## Feedback

- [CI failure merge policy](memories/feedback_ci_never_ignore_failures.md) — Never merge PR when any CI check has failure
- [CI merge policy enforcement](memories/feedback_ci_merge_policy.md) — Never merge PRs while any CI check is queued or in_progress
- [Explicit numbered options for HIGH RISK work](memories/feedback_explicit_option_choices.md) — Stop at blockers and present 2-4 concrete options
- [Governance gates handoff in /issue-work](memories/feedback_governance_gates_handoff.md) — When EPIC sub-issues list manual gates, hand off
- [Never merge with any CI failure](memories/feedback_never_merge_with_ci_failure.md) — Never rationalize 'unrelated' failures as merge justification

## Project

- [claude-config repo guard quirks](memories/project_claude_config_guards.md) — pr-language-guard rejects non-ASCII; attribution-guard substring matches
- [claude-docker PSScriptAnalyzer warning scope](memories/project_claude_docker_psanalyzer.md) — Warning severity surfaces ~40 findings
- [claude_code_agent CI lint workflow scope](memories/project_claude_code_agent_lint.md) — Local npm run lint is ESLint-only
- [claude_code_agent local secrets dirs break husky hooks](memories/project_claude_code_agent_secrets_perms.md) — macOS perms pollute git stderr
- [kcenon ecosystem layout standardization EPIC](memories/project_kcenon_layout_standardization_epic.md) — Master EPIC common_system#657 + 8 sub-EPICs
- [kcenon EPIC checklists are commonly stale](memories/project_kcenon_stale_epic_checklists.md) — Open EPICs routinely list sub-issues as unchecked
- [kcenon issue titles understate scope](memories/project_kcenon_issue_scope.md) — Small-sounding titles often wrap EPIC-sized work
- [kcenon label namespace inconsistency](memories/project_kcenon_label_namespaces.md) — Repos mix priority/, priority:, and bare labels
- [osx_cleaner branching setup](memories/project_osx_cleaner_branching.md) — develop branch created 2026-04-21 to satisfy pr-target-guard
- [pacs_system develop-PR CI trigger correction](memories/project_pacs_system_ci_triggers.md) — pacs_system workflows DO trigger CI on develop-targeted PRs
- [Steamliner document approval process](memories/project_steamliner_doc_approval.md) — Wet signatures on printed paper copies, not electronic

## Quarantine (review required)

> ⚠ The following entries are not auto-applied. See `docs/MEMORY_TRUST_MODEL.md`.

(none)

<!-- END AUTO-GENERATED -->
```

**Sort key**: filename ascending (case-sensitive). Filename is the canonical identifier per #A1.

**Description trimming**: descriptions can be 256 chars; trim to ~100 chars in index for readability, with `…` ellipsis if trimmed.

**Pre/post-marker preservation**: any user-written content above the BEGIN marker or below the END marker is preserved verbatim. If markers are missing entirely, generator inserts them at the end of the file.

**State and side effects**:
- Reads `memories/`, `quarantine/`, current `MEMORY.md`
- Writes `MEMORY.md` (or temp + mv for atomicity)
- No network

**External dependencies**: bash 3.2+, `validate.sh` for parser (or duplicated parser fn), `diff` (POSIX).

### Inputs and Outputs

**Input** (regen):
```
$ ./regen-index.sh
```

**Output**:
```
[OK] regenerated MEMORY.md (17 entries, 0 quarantined)
```
Exit: `0`

**Input** (check, no drift):
```
$ ./regen-index.sh --check
```

**Output**:
```
[OK] MEMORY.md is up to date
```
Exit: `0`

**Input** (check, drift):
```
$ ./regen-index.sh --check
```

**Output**:
```
[DRIFT] MEMORY.md is out of date
--- a/MEMORY.md
+++ b/MEMORY.md
@@ -10,6 +10,7 @@
 ## Feedback

 - [CI merge policy enforcement](memories/feedback_ci_merge_policy.md) — ...
+- [New rule](memories/feedback_new_rule.md) — recently added

Run regen-index.sh (without --check) to update.
```
Exit: `1`

**Input** (custom dirs, used by #G2 multi-machine tests):
```
$ ./regen-index.sh --memories-dir ./fixtures/memories --output /tmp/test-index.md
```

### Edge Cases

- **Frontmatter missing required fields** in a file → validate.sh would have rejected; this script also rejects with diagnostic and exits 1
- **Two files with the same `name`** → both listed (filename disambiguates); names are display labels, not unique
- **Quarantine empty** → "Quarantine" section emitted with `(none)` placeholder
- **Pre-marker content contains the BEGIN marker as a literal string** (e.g., in a code block) → false positive risk; mitigation: only treat first occurrence as marker
- **Existing `MEMORY.md` has no markers** → generator inserts markers at end of file, preserves all existing content above
- **`memories/` empty** → generator emits empty type sections with `(none)` placeholders; valid
- **Description contains markdown special chars** (`[`, `]`, `(`, `)`) → escape minimally for link safety
- **Filename contains spaces** → not allowed per filename pattern; rejected upstream
- **`MEMORY.md` is read-only** → write fails; exit 1 with diagnostic

### Acceptance Criteria

- [ ] Script `scripts/regen-index.sh` (executable)
- [ ] Generates output between `<!-- BEGIN AUTO-GENERATED ... -->` and `<!-- END AUTO-GENERATED -->` markers
- [ ] Groups by type in fixed order: User → Feedback → Project → Reference → Quarantine
- [ ] Within each group, sorted by filename ascending
- [ ] **Two consecutive runs produce byte-identical output** (deterministic)
- [ ] No timestamps or other variable values in marker comments
- [ ] Pre-marker and post-marker user content preserved verbatim
- [ ] `--check` mode: exits 0 with "up to date" message if no drift; exits 1 with diff if drift
- [ ] `--output <path>` writes to alternate location
- [ ] `--memories-dir <dir>` uses alternate source
- [ ] Quarantine section lists entries from `quarantine/` separately, with "review required" note
- [ ] Description trimming at ~100 chars with `…` ellipsis
- [ ] **Against the 17-memory baseline** (after #C1 seed): produces a `MEMORY.md` that matches a hand-crafted reference (committed in this PR for regression)
- [ ] Bash 3.2 + bash 5.x both pass
- [ ] Help text on `--help`

### Test Plan

- Run twice → diff is empty (deterministic)
- Add a new memory; `--check` reports drift; regen updates index
- Move a memory to quarantine via #B4 tool; regen places it in Quarantine section
- Edit pre-marker content; regen preserves it
- Run on empty `memories/` → graceful empty sections
- macOS + Linux both pass
- Reference index file checked into repo so future regressions are detected

### Implementation Notes

- Use the same frontmatter parser as #A2 — copy or source; do not re-implement
- Sort: bash `sort` with `LC_ALL=C` for byte-stable ordering across locales
- Atomic write: build full string in a variable, then `printf "%s" "$content" > "$out.tmp" && mv "$out.tmp" "$out"`
- Avoid `awk` write-redirection (bash-write-guard) — bash + temp file pattern
- Description trimming: `${desc:0:97}…` if `${#desc} > 100`
- Markdown link escape: `${desc//]/\\]}` (only `]` matters in description text inside link's text segment)
- Reference index file location: `tests/fixtures/expected-MEMORY.md` regenerated and committed any time canonical 17-memory baseline changes

### Deliverable

- `scripts/regen-index.sh` (executable, ~200 lines)
- `tests/fixtures/expected-MEMORY.md` for regression
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — `MEMORY.md` becomes auto-generated where previously it was hand-written, but the file's structural meaning is preserved.

### Rollback Plan

Revert PR. Manually maintain `MEMORY.md` until next attempt.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #A5, #B4, #C1
- Blocks: #C3
- Related: #D1 (consumer), #F1 (consumer)

**Docs**:
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1)
- `docs/MEMORY_TRUST_MODEL.md` (#B1)

**Commits/PRs**: (filled at PR time)
