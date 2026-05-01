# Memory Validation Specification

**Version**: 1.0.1
**Last updated**: 2026-05-01
**Status**: Active

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [File Location and Naming](#2-file-location-and-naming)
3. [Frontmatter Schema](#3-frontmatter-schema)
4. [Field Semantics](#4-field-semantics)
5. [Body Content Rules](#5-body-content-rules)
6. [Owner Identity Allowlist](#6-owner-identity-allowlist)
7. [Validator Exit-Code Contract](#7-validator-exit-code-contract)
8. [Bash Compatibility Constraints](#8-bash-compatibility-constraints)
9. [Baseline Behavior Expectation](#9-baseline-behavior-expectation)
10. [Versioning](#10-versioning)

---

## 1. Purpose and Scope

This document is the authoritative specification governing the three memory validation
tools: `validate.sh`, `secret-check.sh`, and `injection-check.sh`. Implementers of
those tools must satisfy every rule stated here.

### In scope

- Frontmatter field semantics and required/recommended field distinction
- Filename pattern as the canonical memory identifier
- Owner identity allowlist (email patterns recognized as non-secret)
- Bash compatibility constraints for the validator implementations
- Exit-code contract for all three validators
- Acceptance behavior for the 17 existing baseline memory files

### Out of scope

- Implementing the validators (those are separate deliverables)
- Trust-tier promotion/demotion mechanics
- Quarantine enforcement workflows
- Memory sync transport between machines

### Corrections from earlier design

Four errors were discovered during the 2026-05-01 baseline session when prototype
validators were first applied to real memory files. This spec incorporates all four
corrections. See Section 9 for the resulting baseline verdicts.

---

## 2. File Location and Naming

Memory files live in the agent memory directory:

```
~/.claude/agent-memory/<agent-name>/
```

For the cross-machine sync system the canonical source is:

```
claude-memory/memories/
```

### Filename pattern (REQUIRED)

```
^(user|feedback|project|reference)_[a-z0-9_]+\.md$
```

The portion before `.md` is the **canonical identifier** for the memory entry. The
filename, not any frontmatter field, is the stable key used for deduplication and
indexing.

**Valid examples:**

```
user_github.md
feedback_ci_merge_policy.md
project_kcenon_label_namespaces.md
reference_grafana_oncall_board.md
```

**Invalid examples:**

```
GitHub-Account.md             # uppercase, dash separator
misc_random_thoughts.md       # type prefix not in enum
feedback_CI_Policy.md         # uppercase in topic
my_notes.md                   # missing type prefix
```

### Correction note (§3.1)

The original design treated the frontmatter `name` field as a kebab-case identifier.
Real auto-memory writes `name` as a human-readable display label
(e.g., `"CI merge policy enforcement"`). The filename carries the identifier; `name`
is display text only. Validators must not enforce kebab-case on `name`.

---

## 3. Frontmatter Schema

Every memory file must open with a YAML frontmatter block delimited by `---`.

### Required fields

| Field | Type | Constraint |
|---|---|---|
| `name` | string | 2–100 chars, no newlines, free-form display text |
| `description` | string | 1–256 chars, no newlines, single-line summary |
| `type` | enum | one of: `user`, `feedback`, `project`, `reference` |

### Recommended fields (Phase 2 backfill)

| Field | Type | Constraint |
|---|---|---|
| `source-machine` | string | hostname of the machine that wrote the entry |
| `created-at` | string | ISO 8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`) |
| `trust-level` | enum | one of: `verified`, `inferred`, `quarantined` |
| `last-verified` | string | ISO 8601 date (`YYYY-MM-DD`) |

Absence of recommended fields produces a `WARN-SEMANTIC` result, not a failure.
This is intentional: the 17 existing baseline memories pre-date the sync system and
lack these fields. They will be backfilled as part of migration.

### Minimal valid example

```markdown
---
name: CI merge policy enforcement
description: Never merge when any CI check is incomplete or failing.
type: feedback
---

Lead with the rule. **Why:** prior incident where merged broken CI caused prod outage.
**How to apply:** check `gh pr checks` before any merge action.
```

### Full example with recommended fields

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

Lead with the rule. **Why:** prior incident where merged broken CI caused prod outage.
**How to apply:** check `gh pr checks` before any merge action.
```

---

## 4. Field Semantics

### `name`

- **Purpose**: Human-readable display label shown in indexes and logs.
- **Format**: Free-form text, 2–100 characters, no newlines.
- **Not an identifier**: Do not enforce kebab-case or snake_case. The filename is the
  identifier.
- **Quoting**: YAML quoting (single or double) is permitted; validators strip quotes
  before measuring length.

### `description`

- **Purpose**: One-line summary used to judge relevance when selecting memories for
  a conversation.
- **Format**: Single line, 1–256 characters, no newlines.
- **Quality expectation**: Should be specific enough to distinguish this memory from
  others of the same type. Vague descriptions like "notes" are technically valid but
  semantically poor.

### `type`

- **Purpose**: Classifies the memory's role. Drives which structural checks apply.
- **Allowed values**:
  - `user` — information about the user's role, expertise, or preferences
  - `feedback` — guidance given by the user about how to approach work
  - `project` — facts about ongoing work, decisions, goals, or incidents
  - `reference` — pointers to external systems and their purpose
- **Additional values**: This enum may be extended in a future spec revision.
  Validators must reject values not listed above unless the spec version is higher
  than 1.0.0.

### `source-machine`

- **Purpose**: Records which machine wrote the entry. Required for sync conflict
  resolution.
- **Format**: Hostname as returned by `hostname -s`.
- **Default on backfill**: Current machine at backfill time.

### `created-at`

- **Purpose**: Approximate creation timestamp. Used for audit ordering and TTL checks.
- **Format**: ISO 8601 UTC, e.g., `2026-05-01T14:00:00Z`.
- **Precision**: Second-level precision is sufficient. Milliseconds are not required.
- **Default on backfill**: File modification time (`mtime`) as a reasonable
  approximation.

### `trust-level`

- **Purpose**: Indicates how confident the system is that this memory is accurate
  and was written intentionally by the owner.
- **Allowed values**:
  - `verified` — user explicitly confirmed or directly wrote the content
  - `inferred` — written by the agent based on conversation context; not yet
    confirmed by the user
  - `quarantined` — flagged for review; must not be loaded into active context
- **Default on backfill**:
  - `user`, `feedback` types → `verified` (direct user input)
  - `project`, `reference` types → `inferred` by default; promoted to `verified`
    only when an explicit user-approval signal exists (e.g., the user added the
    memory via direct dictation, or a reviewer manually approves during backfill)
  - The default is intentionally conservative: `inferred` is the safe choice when
    the origin is ambiguous, since the trust model gates auto-application on
    `verified`. A reviewer can promote later; the reverse direction (silently
    auto-applied wrong content) is harder to recover from.

### `last-verified`

- **Purpose**: Date the memory was last reviewed as still accurate.
- **Format**: ISO 8601 date, e.g., `2026-05-01`.
- **Use**: Entries where `last-verified` is more than 90 days ago are candidates for
  re-review.

---

## 5. Body Content Rules

The body is the content after the closing `---` frontmatter delimiter.

### Length bounds

| Bound | Value | Consequence of violation |
|---|---|---|
| Minimum | 30 characters | FAIL (structural) |
| Maximum | 5000 characters | WARN-SEMANTIC (consider splitting) |

### Structural markers for `feedback` and `project` types

Memories of type `feedback` and `project` **recommend** (not require) two structural
markers in the body:

- `**Why:**` or `Why:` — the reason the rule or fact is significant
- `**How to apply:**` or `How to apply:` — when and where this guidance applies

Absence of these markers produces a `WARN-SEMANTIC` result, not a failure. The intent
is to encourage self-documenting memories that provide context for future reasoning,
not to block memories that lack the markers.

Example of well-structured `feedback` body:

```
Never merge when any CI check is incomplete.

**Why:** Prior incident (2026-Q1) where a skipped check masked a broken migration.
**How to apply:** Run `gh pr checks` before triggering any merge tool call.
```

### Frontmatter-only files

A file with valid frontmatter but an empty or near-empty body (fewer than 30 chars)
fails validation. Every memory must have substantive content.

### Secret-shaped strings in body

If a memory legitimately needs to reference what a secret looks like (e.g., describing
a past leak), use the redaction token convention:

```
<redacted>ghp_...example...</redacted>
```

This prevents `secret-check.sh` from flagging the entry as containing a live token.

---

## 6. Owner Identity Allowlist

`secret-check.sh` scans for email addresses, tokens, and paths that may represent
leaked credentials or foreign identities. To avoid false positives, the tool
recognizes a set of owner-controlled identifiers as safe.

### Recognized owner email patterns

The following patterns are recognized as owner emails and do not trigger a finding:

1. **Primary email**: Any address listed in the `OWNER_EMAILS` array in the tool
   configuration (e.g., `kcenon@gmail.com`).

2. **GitHub no-reply (numeric prefix)**:
   ```
   <numeric-id>+<github-handle>@users.noreply.github.com
   ```
   Example: `4158198+kcenon@users.noreply.github.com`

3. **GitHub no-reply (bare)**:
   ```
   <github-handle>@users.noreply.github.com
   ```
   Example: `kcenon@users.noreply.github.com`

### Correction note (§3.2)

The original design only compared email addresses against a single configured address.
`user_github.md` contains `4158198+kcenon@users.noreply.github.com`, which is the
owner's GitHub no-reply address. Without the numeric-prefix pattern, all 18 files
would produce false-positive findings. Both GitHub no-reply formats must be recognized.

### Recognized owner paths

Home directory paths containing the configured `OWNER_HOME_USER` value are not flagged.
Paths under `/Users/<other-user>/` or `/home/<other-user>/` are flagged.

### Token patterns that always trigger findings

Regardless of context, the following patterns always produce a finding:

- `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` (GitHub tokens)
- `sk-` followed by 20+ alphanumeric characters (OpenAI-style keys). The 20-character
  minimum is **load-bearing**: implementations must enforce length, not merely match
  the `sk-` prefix, otherwise package names like `sk-learn` would over-match.
- `AKIA` followed by 16 uppercase alphanumeric characters (AWS access key IDs)
- `-----BEGIN <TYPE> KEY-----` (PEM-encoded private keys)
- SSH key fingerprints matching `SHA256:` followed by 43 base64 characters

To include token-shaped strings in documentation, use the redaction convention from
Section 5.

---

## 7. Validator Exit-Code Contract

All three validators share a consistent exit-code semantics. Exit codes are designed
to be composable: a CI step can use `exit_code <= 2` to gate on hard failures
(structural OR format errors) while treating code 3 as advisory. Use `exit_code != 0`
to gate on any non-clean state including warnings.

### Full exit-code table

| Tool | Exit code | Label | Meaning | Blocks merge? |
|---|---|---|---|---|
| `validate.sh` | 0 | PASS | File is fully valid | No |
| `validate.sh` | 1 | FAIL-STRUCT | Structural error (missing delimiter, missing required field, body too short) | Yes |
| `validate.sh` | 2 | FAIL-FORMAT | Format error (field value violates type/length constraint) | Yes |
| `validate.sh` | 3 | WARN-SEMANTIC | Semantic warning (missing recommended field or structural marker) | No |
| `secret-check.sh` | 0 | CLEAN | No findings | No |
| `secret-check.sh` | 1 | SECRET-DETECTED | PII or token pattern found | Yes |
| `injection-check.sh` | 0 | CLEAN | No suspicious patterns | No |
| `injection-check.sh` | 3 | FLAGGED | Suspicious natural-language pattern (warning only) | No |

### Usage code

All three tools also exit with code `64` when called with no arguments (usage error).
This is not a memory validation result.

### `--all` mode

When called with `--all <dir>`, each tool scans all `*.md` files in the directory,
prints per-file results, then exits with the worst code seen across all files.
`MEMORY.md` (the index file) is always skipped.

### Distinction between exit 1 and exit 2 in `validate.sh`

- **Exit 1 (FAIL-STRUCT)**: The file cannot be parsed as a valid memory file at all.
  Examples: missing frontmatter delimiters, missing required fields, body shorter than
  30 characters.
- **Exit 2 (FAIL-FORMAT)**: The file parses correctly but a field value violates its
  format constraint. Examples: `type` set to an unknown value, `description` exceeding
  256 characters.

In practice, the prototype implementation maps most violations to exit 1 unless a
specific format check is triggered. Future implementations may produce exit 2 more
granularly.

### `injection-check.sh` never blocks

Injection patterns are inherently ambiguous: a legitimate CI policy memory that says
"never merge with failing checks" will trigger the absolute-command density check.
Exit code 3 is therefore advisory only. Human review is required to determine whether
a flagged entry is a real injection attempt or a legitimate policy statement. See
Section 9 for the three files that produce FLAGGED verdicts in the baseline.

---

## 8. Bash Compatibility Constraints

Validators must run correctly on both:

- **Bash 3.2** — the default on macOS (including current macOS releases as of 2026)
- **Bash 5.x** — common on Linux CI environments

The following patterns are required to ensure Bash 3.2 compatibility.

### Empty-array guards

Bash 3.2 with `set -u` raises `unbound variable` when expanding an empty array with
`${array[@]}`. Always check array length before iterating:

```bash
# Required pattern
if (( ${#errors[@]} > 0 )); then
  for e in "${errors[@]}"; do
    printf "    [E] %s\n" "$e"
  done
fi

# Also required when appending is conditional
errors=()
# ... populate errors ...
(( ${#errors[@]} > 0 )) && code=1
```

Never write `for e in "${errors[@]}"` unconditionally in a `set -u` script on
Bash 3.2.

### BASH_REMATCH save-then-use pattern

In Bash 3.2, `BASH_REMATCH` may be unset if no `=~` match has occurred in the current
scope. Additionally, subsequent `=~` expressions overwrite `BASH_REMATCH`. Always save
the match result to a named variable immediately after the `=~` test:

```bash
# Required pattern
if [[ "$line" =~ ([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}) ]]; then
  local email="${BASH_REMATCH[1]}"   # save before any other =~ or function call
  # use $email from here on
fi

# Unsafe pattern (do not use)
if [[ "$line" =~ ([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}) ]]; then
  some_function "$line"              # may run =~ internally, clobbering BASH_REMATCH
  echo "${BASH_REMATCH[1]}"         # unreliable
fi
```

### `wc -l` output normalization

On macOS, `wc -l` pads its output with leading whitespace (e.g., `"   3"`). Using
this directly in arithmetic context `(( count >= 3 ))` is safe because bash strips
the whitespace in arithmetic. However, when storing the value in a variable and later
using it in a conditional string context, normalization is required:

```bash
# Required pattern
absolute_count="$(grep -i -o -E '\b(always|never)\b' "$f" 2>/dev/null | wc -l | tr -d ' ')"
absolute_count="${absolute_count:-0}"
if (( absolute_count >= 3 )); then
  ...
fi
```

The two-step normalization — `tr -d ' '` to strip whitespace, `${var:-0}` to default
empty output to zero — ensures the value is safe for `(( ))` arithmetic on both
macOS and Linux.

### Correction note (§3.3 and §3.4)

Two Bash 3.2 bugs were found during baseline:

- **§3.3**: `set -u` with empty `errors` array caused `unbound variable` on macOS.
  Fix: guard all array expansions with `(( ${#arr[@]} > 0 ))` checks.
- **§3.4**: `grep -c | wc -l` produced arithmetic failures on macOS because `grep -c`
  outputs a single count (not lines of output), and that count had leading whitespace.
  Fix: use `grep -o ... | wc -l | tr -d ' '` with `${var:-0}` default.

---

## 9. Baseline Behavior Expectation

The 17 memory files at:

```
~/.claude/projects/-Users-raphaelshin-Sources/memory/
```

plus the `MEMORY.md` index file (18 total) must produce exactly the following verdicts
when the validators are run against them.

### validate.sh --all

| Metric | Expected value |
|---|---|
| PASS | 0 |
| WARN-SEMANTIC | 17 |
| FAIL | 0 |
| Skipped | 1 (`MEMORY.md`) |

`MEMORY.md` is skipped per Section 2 (it is not a memory file). Skipped files are
**not** included in any of the PASS / WARN / FAIL counts; the summary line therefore
reads `Summary: 0 pass, 17 warn, 0 fail` against the 18-file directory.

All 17 WARN-SEMANTIC results are caused by absence of the four Phase 2 recommended
fields (`source-machine`, `created-at`, `trust-level`, `last-verified`). No file has
a structural or format error. This is the expected state before migration backfill.

### secret-check.sh --all

| Metric | Expected value |
|---|---|
| CLEAN | 18 |
| SECRET-DETECTED | 0 |

`user_github.md` contains `4158198+kcenon@users.noreply.github.com`. This is the
owner's GitHub no-reply address (see Section 6) and must be recognized as CLEAN.
Any implementation that produces a finding on this file is incorrectly applying the
allowlist.

### injection-check.sh --all

| Metric | Expected value |
|---|---|
| CLEAN | 14 |
| FLAGGED | 3 |

The three FLAGGED files are:

| File | Reason |
|---|---|
| `feedback_ci_merge_policy.md` | High density of absolute commands (`never`, `always`) in a legitimate CI policy |
| `feedback_ci_never_ignore_failures.md` | Same pattern |
| `feedback_never_merge_with_ci_failure.md` | Same pattern |

These are **false positives** — the files contain legitimate policy statements, not
injection attempts. The `Why:` and `How to apply:` structure in each file confirms the
statements are intentional. Because `injection-check.sh` exits 3 (FLAGGED, not
blocked), these files do not block any workflow. They are listed here so implementers
can verify their tool produces the expected output without under-counting or
over-counting.

### How to verify

```bash
cd /path/to/memory-directory
validate.sh    --all .
secret-check.sh  --all .
injection-check.sh --all .
```

An implementation is compliant if the summary lines match the expected values above.
Per-file output order may vary.

---

## 10. Versioning

### Spec version

This document is **v1.0.0**. The version follows Semantic Versioning:

- **MAJOR**: Breaking change to the spec (e.g., removing a required field, changing
  exit codes in an incompatible way).
- **MINOR**: Backward-compatible addition (e.g., new recommended field, new injection
  pattern recognized, new recognized owner email format).
- **PATCH**: Clarification or typo fix with no behavioral change.

Validator implementations must declare which spec version they target. A validator
targeting v1.0.0 must satisfy every rule in this document.

### Change log

#### v1.0.1 — 2026-05-01

PATCH release applying review feedback from PR #536:

1. **§7 exit-code composability example corrected** — gate expression `exit_code <= 1`
   would let format errors (exit 2) through. Updated to `exit_code <= 2` for hard
   failures, with `exit_code != 0` documented for any non-clean state.
2. **§9 baseline summary clarified** — PASS count is 0 (not 1). `MEMORY.md` is
   skipped per §2 and not counted in any of PASS/WARN/FAIL.
3. **§9 WARN-SEMANTIC explanation now includes `last-verified`** (was missing) as
   the fourth Phase 2 recommended field.
4. **§4 `trust-level` default for `project`/`reference` types** is now explicitly
   `inferred` by default (conservative), with promotion to `verified` requiring
   explicit user-approval signal. Removes prior "with clear factual content"
   subjectivity.
5. **§6 `sk-` pattern note** — clarified that the 20-character minimum is
   load-bearing and must be enforced (prevents `sk-learn`-style false positives).

#### v1.0.0 — 2026-05-01

Initial release. Incorporates four corrections from the 2026-05-01 baseline session:

1. **`name` field is display text, not kebab-case identifier** (§2, §4): Validators
   must not reject `name` values that are not kebab-case. The filename is the
   identifier.

2. **GitHub no-reply email patterns added to owner allowlist** (§6): Both
   `<id>+<handle>@users.noreply.github.com` and `<handle>@users.noreply.github.com`
   are recognized as owner emails.

3. **Bash 3.2 empty-array and BASH_REMATCH guards required** (§8): Validators must
   guard all array expansions with length checks and save `BASH_REMATCH` captures to
   named variables immediately after matching.

4. **`wc -l` output must be normalized** (§8): Use `tr -d ' '` and `${var:-0}`
   default when storing `wc -l` results in variables used for arithmetic.
