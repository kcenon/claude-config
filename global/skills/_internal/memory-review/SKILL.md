---
name: memory-review
description: Interactive review of stale, flagged, and duplicate memories from the latest audit report. Walks entries one at a time with verify / quarantine / edit / skip choices.
argument-hint: "[--category stale|flagged|duplicate|broken-ref|all] [--limit N] [--report <path>]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Read Edit Grep Glob Bash"
loop_safe: false
---

# /memory-review — Interactive Memory Triage

This skill walks the user through entries flagged by the most recent audit
report (produced by `~/.claude/memory-shared/scripts/audit.sh`, #528). For
each entry the user picks an action; the skill applies it immediately and
moves to the next entry.

The skill is `disable-model-invocation: true` because every action is
mutating (update `last-verified`, move to quarantine, open editor) and Claude
must not unilaterally promote or demote a memory. The user must explicitly
type `/memory-review` (or `memory-review` per the alias rule in
`global/CLAUDE.md`) to start.

## Usage

```
/memory-review                                    # Review all categories
/memory-review --category stale                   # Stale entries only
/memory-review --category duplicate --limit 10    # First 10 duplicate suspects
/memory-review --report path/to/report.md         # Use a specific report
```

## Arguments

| Argument | Values | Default | Description |
|----------|--------|---------|-------------|
| `--category` | `stale`, `flagged`, `duplicate`, `broken-ref`, `all` | `all` | Filter findings by audit section |
| `--limit` | integer | unlimited | Cap reviewed entries |
| `--report` | path | latest in `~/.claude/memory-shared/audit/` | Override report path (testing) |

`--category` mapping to audit sections (per #528 report format):

| Value | Audit section |
|-------|---------------|
| `flagged` | `## 1. Validator Findings` |
| `stale` | `## 2. Stale` |
| `duplicate` | `## 3. Duplicate Suspects` |
| `broken-ref` | `## 4. Broken References` |
| `all` | All four sections, in order above |

## Procedure

Execute the workflow step by step. Each step that mutates a file commits
immediately so a mid-review interruption leaves the file system in a
consistent state.

### 1. Locate the audit report

If `--report <path>` was provided, use that path. Otherwise pick the latest
report by mtime:

```bash
if [ -n "$REPORT_PATH" ]; then
  REPORT="$REPORT_PATH"
else
  REPORT=$(ls -t ~/.claude/memory-shared/audit/*.md 2>/dev/null | head -1)
fi
```

If `REPORT` is empty or the file does not exist:

```
No audit report found at ~/.claude/memory-shared/audit/.
Run ~/.claude/memory-shared/scripts/audit.sh first, or wait for the
weekly job.
```

Stop and exit. Do not invent entries.

Otherwise announce:

```
Found audit report: <REPORT>
```

### 2. Parse sections

Read the report with `Read`. Split the body into the four sections by H2
heading prefix. Use these exact patterns (per #528):

| Section | H2 Prefix |
|---------|-----------|
| Validator Findings | `## 1. Validator Findings` |
| Stale | `## 2. Stale` |
| Duplicate Suspects | `## 3. Duplicate Suspects` |
| Broken References | `## 4. Broken References` |

For each section, parse list entries. The audit emits one bullet per
finding; each bullet contains a path and a short reason. Quote-block excerpts
(if any) follow the bullet.

If `--category` is set, drop sections that do not match. If `--limit N` is
set, truncate the merged entry list to `N` items (preserving section order).

Announce the planned scope:

```
Categories: <X> stale, <Y> duplicate-suspect, <Z> broken-ref, <W> flagged
Reviewing <N> entries.
```

### 3. Walk entries

For each entry, in section order, present a concise summary and ask the
user. Quote the original memory's `description` (or the first non-frontmatter
line) so the user remembers why the memory exists. Show key audit metadata
(reason, age, severity).

Format:

```
[<category> <i>/<total>] <relative-path>
> "<one-line description from the file>"
> last-verified: <date> (<age> days ago)
> reason: <audit reason>

Action: (y) verify  (n) quarantine  (e) edit  (s) skip  (q) quit
```

Wait for the user's keystroke.

#### Pagination

Per epic R4 mitigation: only flagged items surface here. Clean items are not
shown — the audit report already excluded them. After every 5 entries, pause
and ask:

```
Reviewed 5 entries. (c) continue  (q) quit
```

### 4. Apply the user's choice

Each action is committed to disk before advancing. Failures are reported and
the entry is treated as `s` (skipped) so the loop continues.

#### `y` — verify

Update the `last-verified` field in the file's YAML frontmatter to today's
date (KST):

```bash
TODAY=$(TZ=Asia/Seoul date +%Y-%m-%d)
```

Use `Read` then `Edit` (read-before-edit invariant). Replace the existing
`last-verified: <old>` line with `last-verified: <TODAY>`. If the field is
absent, insert it after `description:` in the frontmatter block.

After save, run the validator:

```bash
~/.claude/memory-shared/scripts/validate.sh "<file>" 2>&1
```

If `PASS`, print `[OK] last-verified -> <TODAY>`. If `FAIL`, revert the
change (re-Edit back to old value) and print `[WARN] validation failed,
reverted`. Treat the entry as skipped.

#### `n` — quarantine

Run the quarantine script:

```bash
~/.claude/memory-shared/scripts/quarantine-move.sh "<file>" \
    --reason "/memory-review demoted on $(TZ=Asia/Seoul date -Iseconds)"
```

Print the script's stdout. On non-zero exit, print `[WARN] quarantine
failed: <stderr>` and continue.

#### `e` — edit

Open `$EDITOR` on the file:

```bash
EDITOR_BIN="${EDITOR:-${VISUAL:-nano}}"
if ! command -v "$EDITOR_BIN" >/dev/null 2>&1; then
  echo "[WARN] \$EDITOR='$EDITOR_BIN' not found; cannot edit"
  # Treat as skipped
fi
"$EDITOR_BIN" "<file>"
```

After the editor exits, re-validate:

```bash
~/.claude/memory-shared/scripts/validate.sh "<file>"
```

| Validator result | Action |
|------------------|--------|
| `PASS` | Update `last-verified` to today; print `[OK] edited and verified` |
| `FAIL` | Print `[WARN] edit produced invalid file: <reason>`; ask: `(r) retry edit  (s) skip` |

If the editor exits without saving (mtime unchanged), treat as `s` (skip).

#### `s` — skip

No mutation. Print `[skip] <file>` and advance.

#### `q` — quit

Stop the loop, jump straight to the summary in step 5.

### 5. Summary

At the end of the loop (or on `q`), emit a per-action count:

```
Reviewed <N> entries:
  verified:    <V>
  quarantined: <Q>
  edited:      <E>
  skipped:     <S>
```

Then prompt:

```
Run memory-sync.sh to push these changes? (y/n)
```

If `y`, run:

```bash
~/.claude/scripts/memory-sync.sh --lock-timeout 30
```

Print the script's exit code. If `n` or absent, print `Skipping sync. Run
manually when ready.`

## Output formatting

- Each entry: filename, description quote, key audit metadata, then choices
- Pagination: every 5 entries pause and ask "continue / quit"
- Quote-block memory excerpts with `>` so the user sees the original intent
- Use relative paths under `~/.claude/memory-shared/` for readability

## Edge cases

| Case | Handling |
|------|----------|
| No audit report exists | Print friendly message and exit. Do not invent entries. |
| `--category` matches zero entries | Print `No entries in category <X> for review.` and exit. |
| `$EDITOR` not set and `nano` absent | Warn, treat the `e` choice as skip for that entry. |
| Edit produces a `validate.sh FAIL` | Offer retry or skip; never silently leave an invalid file. |
| Quarantine script not executable / file already quarantined | Warn, continue with next entry. |
| Two reports from same day | Pick latest mtime (already handled by `ls -t`). |
| Weekly + monthly reports both present | Use weekly only (matches `audit/<YYYY-WW>/REPORT.md` cadence). |
| User closes session mid-review | Each action is committed immediately; resume by re-invoking. No automatic resume file. |
| Concurrent invocation in two sessions | Both modify; later overwrites earlier. Document warning, do not lock. |
| Memory file already in `quarantine/` appearing in audit | `n` is a no-op via the quarantine script's idempotent guard; warn and continue. |

## Halt conditions

The skill stops and emits the summary when:

1. The entry list is exhausted (success).
2. The user types `q` at any prompt (user halt).
3. The same file fails three actions in a row (3-fail rule).
4. `~/.claude/memory-shared/scripts/quarantine-move.sh` or `validate.sh`
   is missing or non-executable (fallback: skip the action and warn).

## State and side effects

- Modifies frontmatter `last-verified` on memory files (in-place edit).
- Moves memory files between `memories/` and `quarantine/` via
  `quarantine-move.sh`.
- May launch `$EDITOR` for the `e` action.
- Does not auto-commit; the user runs `memory-sync.sh` (or accepts the prompt
  in step 5) to push.

## External dependencies

| Script | Purpose | Source issue |
|--------|---------|--------------|
| `~/.claude/memory-shared/scripts/validate.sh` | Re-validate after verify or edit | #511 |
| `~/.claude/memory-shared/scripts/quarantine-move.sh` | Demote a memory | #514 |
| `~/.claude/scripts/memory-sync.sh` | Push changes after review | #520 |
| `~/.claude/memory-shared/scripts/audit.sh` | Source of the report this skill consumes | #528 |

If a dependency is missing, surface a clear error citing the responsible
issue rather than silently skipping.

## Frontmatter rationale

| Field | Value | Why |
|-------|-------|-----|
| `disable-model-invocation` | `true` | Mutating actions; user must initiate |
| `user-invocable` | `true` | Appears in `/` autocomplete |
| `allowed-tools` | `Read Edit Grep Glob Bash` | Read frontmatter, edit `last-verified`, glob audit dir, shell out to scripts |
| `loop_safe` | `false` | Each invocation mutates files; not idempotent under `/loop` |

## Future work (not in this skill)

- `quarantine-restore.sh` flow for restoring a quarantined memory after
  review (separate skill).
- Multi-machine coordination — each machine reviews its local view; merge is
  via `memory-sync.sh`.
- AI-assisted semantic review (#530) layered on top of this interactive flow.

## Cross-references

- `docs/MEMORY_TRUST_MODEL.md` — promotion / demotion rules (#511)
- `docs/MEMORY_SYNC.md` — operational reference for `memory-sync.sh` (#520)
- `docs/MEMORY_VALIDATION_SPEC.md` — validator rules consumed by this skill
- Existing skill patterns: `global/skills/_internal/issue-work/SKILL.md`,
  `global/skills/_internal/branch-cleanup/SKILL.md`
