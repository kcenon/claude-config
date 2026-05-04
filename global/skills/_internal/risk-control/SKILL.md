---
name: risk-control
description: "Manage Hazard and Risk records for projects on the regulated-industry track. Maintains a single normalized risk file (docs/.index/risk-file.yaml) holding hazard identification, initial and residual risk estimates, control measures with verification links, and bidirectional Risk<->Requirement linking via the requirements[] field. Subcommands: add | edit | evaluate | validate | list. Output is consumed by the traceability skill (matrix risk_ids[] field) and the evidence-pack skill (risk_file kind). Opt-in: no-op when docs/.index/manifest.yaml is absent so non-regulated repos are unaffected. Atomic writes via *.tmp + rename; idempotent for diffability. Implements ISO 14971 sections 5-9 operationally."
argument-hint: "<add|edit|evaluate|validate|list> [args] [--ci] [--verbose]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
loop_safe: true
max_iterations: 1
halt_conditions:
  - { type: success, expr: "subcommand completed successfully and risk-file.yaml is well-formed (atomic rename succeeded)" }
  - { type: success, expr: "no-op exit when docs/.index/manifest.yaml is absent" }
  - { type: failure, expr: "validate or evaluate --ci reports an unacceptable residual risk or schema violation" }
  - { type: failure, expr: "manifest/risk-file parse error or write step errors out" }
on_halt: "Print per-record findings table (or no-op message) and exit non-zero on failure, zero on success or no-op"
tiers:
  light:
    ref_docs: []
    deep_checks: false
  standard:
    ref_docs: [schema, matrix]
    deep_checks: true
  deep:
    ref_docs: [schema, matrix]
    deep_checks: true
default_tier: standard
# ref_docs keys:
#   schema -> reference/risk-record-schema.md
#   matrix -> reference/risk-matrix.md
---

# risk-control Skill

Manage Hazard and Risk records for projects that have adopted the regulated-industry track.
The skill is the operational implementation of ISO 14971 sections 5 through 9 (already
documented as clauses by the sibling `compliance/iso-14971.md` rule file): it produces and
maintains the per-project risk file that the `traceability` matrix references via its
`risk_ids[]` field and that the `evidence-pack` skill collects under the `risk_file` kind.

The skill does not invent regulatory content; it provides a structured, validatable home
for the records that ISO 14971 already requires.

## Usage

```
/risk-control add <id>                       # Create a new risk record interactively
/risk-control edit <id>                      # Modify an existing record
/risk-control evaluate                       # Recompute residual risk for every record
/risk-control evaluate --ci                  # Same; exit non-zero on any unacceptable residual
/risk-control validate                       # Schema and cross-reference check (warnings only)
/risk-control validate --ci                  # Same; exit non-zero on any finding
/risk-control list                           # Print a table of all records and their status
/risk-control list --verbose                 # Same with control_measures and verification expanded
```

Exactly one subcommand is required as the first positional argument. The `add` and `edit`
subcommands take a record id (`R-NN` or `H-NN`) as the second positional argument; the others
take none.

## Arguments

| Position / Flag | Behavior |
|-----------------|----------|
| `<subcommand>` (positional, required) | One of `add`, `edit`, `evaluate`, `validate`, `list`. Any other value exits non-zero with a usage hint. |
| `<id>` (positional, required for `add`/`edit`) | Record identifier. Format: `R-NN` (risk) or `H-NN` (hazard); see `reference/risk-record-schema.md`. `add` refuses an id already present; `edit` refuses one absent. |
| `--ci` | Applies to `evaluate` and `validate`. Exit non-zero on any unacceptable residual risk (`evaluate`) or any schema/cross-reference finding (`validate`). Intended for the GitHub Actions validate job. |
| `--verbose` | Applies to `list`. Expand `control_measures` and `verification` columns. Otherwise prints only the headline status per record. |

`--ci` is ignored (with a warning) on `add`, `edit`, and `list`.

## Inputs

| Path | Required | Purpose |
|------|----------|---------|
| `docs/.index/manifest.yaml` | Yes (gate) | Document registry. Skill is a no-op when this file is absent. Used by `validate` to confirm every requirement listed under `requirements[]` resolves to a real document. |
| `docs/.index/risk-file.yaml` | Optional on `add` (created); required on `edit`/`evaluate`/`validate`/`list` | The risk file the skill maintains. See `reference/risk-record-schema.md` for the exact YAML shape. |
| `risk-matrix.yaml` (repo root) | Optional | Per-project override of the default 5x5 acceptability matrix. Defaults documented in `reference/risk-matrix.md`. When absent, the default matrix is used. |
| `compliance/iso-14971.md` | Optional | Source of truth for clause IDs referenced in `clause_refs[]`. When present, `validate` confirms every cited clause exists. Skipped (with one info line) when absent. |

The skill never reads source code, never runs builds, and never calls out to external systems.

## Outputs

| Path | Format | Audience |
|------|--------|----------|
| `docs/.index/risk-file.yaml` | YAML | Single normalized risk file. Consumed by `traceability` (via `risk_ids[]`) and `evidence-pack` (via the `risk_file` kind). Schema: `reference/risk-record-schema.md`. |

The file is written atomically: the skill writes to a sibling `*.tmp` file and renames on
success. A failed run never produces a half-written artifact. Records are sorted by `id`
on every write to guarantee byte-identical output for unchanged input (idempotency contract,
matches `traceability` and `evidence-pack`).

## Opt-in Gate

The skill is purely additive and must not break repos that have not adopted the regulated track.

```bash
if [[ ! -f docs/.index/manifest.yaml ]]; then
    echo "risk-control: docs/.index/manifest.yaml absent -- skill is a no-op for this repo"
    exit 0
fi
```

This check runs before any other phase. The exit code is `0` so CI invocations on
non-regulated repos do not fail. To opt in, a consumer project runs the `doc-index` skill
(which produces `manifest.yaml`); the first `/risk-control add ...` invocation then creates
`docs/.index/risk-file.yaml` from scratch.

## Instructions

### Phase 0: Validate Environment

1. Confirm `docs/.index/manifest.yaml` exists; if not, print the no-op message and exit 0.
2. Validate the subcommand is one of `add`, `edit`, `evaluate`, `validate`, `list`. Otherwise
   exit non-zero with a usage hint.
3. For `add` and `edit`, validate the second positional argument matches the id formats
   declared in `reference/risk-record-schema.md`. Exit non-zero on malformed ids.
4. Detect optional inputs: `risk-matrix.yaml` at repo root, `compliance/iso-14971.md`. Record
   their presence; later phases gate on them.
5. If `docs/.index/risk-file.yaml` exists, parse it and verify `_meta.schema` major matches
   the schema this skill writes. On a major mismatch, exit non-zero with the mismatch
   detail. (Minor mismatches are tolerated; the writer upgrades on next save.)

### Phase 1: Dispatch by Subcommand

Each subcommand runs an independent code path. The phases below describe the per-subcommand
behavior. All paths share the Phase 0 gate and the Phase 4 atomic-write step.

#### Subcommand: add

1. Refuse if `<id>` is already present in `docs/.index/risk-file.yaml`.
2. Prompt the operator for each required field listed in `reference/risk-record-schema.md`
   (or accept them from a heredoc on stdin when running non-interactively).
3. Compute `initial_risk` from the supplied `severity` and `probability` using the matrix
   (default or project override; see `reference/risk-matrix.md`).
4. Default `residual_severity` and `residual_probability` to the initial values; the operator
   updates them later via `edit` after control measures are added.
5. Insert the new record into the in-memory record list; proceed to Phase 4.

#### Subcommand: edit

1. Refuse if `<id>` is absent from `docs/.index/risk-file.yaml`.
2. Load the existing record into memory.
3. Prompt the operator for each field, prefilling current values (or accept full replacement
   from stdin in non-interactive mode).
4. Recompute `initial_risk` and `residual_risk` from the (possibly updated) severity and
   probability values via the matrix.
5. Replace the in-memory record; proceed to Phase 4.

#### Subcommand: evaluate

1. Load every record from `docs/.index/risk-file.yaml`.
2. For each record, recompute `residual_risk` from `residual_severity` and
   `residual_probability` against the current matrix. (The stored value is updated on write
   so that downstream consumers see the current matrix's verdict.)
3. Build the findings list: every record whose `residual_risk` is `unacceptable` per the
   matrix is one finding. Records in the `ALARP` band emit a warning rather than an error,
   per the standard's "as low as reasonably practicable" doctrine -- see
   `reference/risk-matrix.md` for the exact band definitions.
4. Print the findings table to stdout. Format documented in the `reference/risk-record-schema.md`
   "Evaluation Output" section.
5. In `--ci` mode, exit non-zero when any finding is `unacceptable`. ALARP-band warnings do
   not fail CI by default; the project can tighten this by setting
   `risk_acceptance.alarp_fails_ci: true` in `risk-matrix.yaml`.
6. On success (no findings, or warnings only outside `--ci`), proceed to Phase 4 to persist
   any recomputed `residual_risk` values back to disk. (No-op if values match what is on
   disk -- the idempotency contract makes this safe to run on every commit.)

#### Subcommand: validate

1. Load every record from `docs/.index/risk-file.yaml`.
2. For each record, run the validation checks documented in `reference/risk-record-schema.md`
   "Validation Rules", which cover at minimum:
   - Every record has at least one `control_measures[]` entry.
   - Every `control_measures[]` entry has at least one `verification[]` entry.
   - Every requirement listed under `requirements[]` resolves to a `doc_id` in
     `docs/.index/manifest.yaml`. (Skipped with a warning when `manifest.yaml` declares no
     requirement entries -- the project has not yet started cataloguing requirements.)
   - Every `clause_refs[]` value resolves to a clause id present in `compliance/iso-14971.md`.
     (Skipped when the file is absent.)
   - Every `severity` and `probability` value is in the enum declared in the schema.
3. Print the findings table.
4. In `--ci` mode, exit non-zero on any finding. Default mode emits warnings and exits 0.
5. `validate` does not write to disk; skip Phase 4.

#### Subcommand: list

1. Load every record from `docs/.index/risk-file.yaml`.
2. Print a Markdown table sorted by `id`. Default columns: `id`, `hazard`, `initial_risk`,
   `residual_risk`, `status`. With `--verbose`, additionally expand `control_measures` and
   `verification` as nested rows under each record.
3. `list` does not write to disk; skip Phase 4.

### Phase 4: Atomic Write

Skip when subcommand is `validate` or `list`, or when no record changed.

1. Sort the in-memory record list by `id` (stable, ASCII order). Recompute `_meta.generated`
   timestamp.
2. Render the YAML using the canonical layout in `reference/risk-record-schema.md`. Empty
   list fields are emitted as `[]`, never as `~` or as an omitted key, so consumers never
   need to distinguish "absent" from "empty".
3. Write to `docs/.index/risk-file.yaml.tmp`.
4. On success, rename to `docs/.index/risk-file.yaml`. On any error, delete the `*.tmp`
   file and exit non-zero.

### Phase 5: Report

Emit a one-line summary on stdout per subcommand:

| Subcommand | Summary line |
|------------|--------------|
| `add` | `risk-control: added <id> (initial=<level>, residual=<level>); records=<N>` |
| `edit` | `risk-control: updated <id> (initial=<level>, residual=<level>); records=<N>` |
| `evaluate` | `risk-control: evaluated <N> records; unacceptable=<U> ALARP=<A>` |
| `validate` | `risk-control: validated <N> records; findings=<F> (errors=<E>, warnings=<W>)` |
| `list` | `risk-control: listed <N> records` |

Append the per-finding or per-record table required by the subcommand to stdout above the
summary.

## Bidirectional Risk-Requirement Linking

Each risk record carries a `requirements[]` list naming the SRS ids the risk is mitigated
by (or, equivalently, that the risk depends on for control). The link is one-directional in
the risk file (risk -> requirements), but the next `traceability` skill run picks it up in
the other direction without any new wiring: the matrix already reserves `risk_ids[]` on
every requirement row (see `traceability/reference/matrix-schema.md`), and the skill's
Phase 1 step 5 already collects hazards from `router.yaml` `id_routes.H`. When `risk-file.yaml`
is present, the matrix's risk-side data source is this skill rather than ad-hoc registries.

The integration contract is: `risk-control` owns the risk records; `traceability` reads
them and stitches them into the matrix. No bidirectional write coordination is required
because the risk file is the single source of truth.

## Output

The skill produces only `docs/.index/risk-file.yaml` plus the on-stdout summary. No other
files in the consumer project are modified -- in particular, the skill never edits
`manifest.yaml`, `bundles.yaml`, `graph.yaml`, `router.yaml`, or `traceability.yaml`. Those
remain `doc-index`'s and `traceability`'s responsibility.

## Error Handling

| Condition | Action |
|-----------|--------|
| `docs/.index/manifest.yaml` absent | No-op exit 0 (opt-in gate, see Phase 0). |
| Subcommand argument missing or invalid | Exit non-zero with usage hint. |
| `<id>` malformed for `add`/`edit` | Exit non-zero with the expected format from the schema. |
| `add` invoked with an existing id | Exit non-zero with the suggestion to use `edit`. |
| `edit` invoked with an absent id | Exit non-zero with the suggestion to use `add`. |
| `_meta.schema` major mismatch on existing risk file | Exit non-zero with the detected vs. expected schema versions. |
| `risk-matrix.yaml` malformed | Exit non-zero with the YAML parse error and the offending line. |
| Validation finding in `--ci` mode | Print the finding table, exit non-zero. (Per ISO-14971-7.3, an unacceptable residual risk that has not been addressed must not pass review; CI mirrors that policy.) |
| Validation finding in default mode | Print the finding table, exit 0. |
| Write step fails (permission, disk) | Delete the `*.tmp` file, report the path, exit non-zero. |
| `compliance/iso-14971.md` referenced but absent | Skip clause validation; print one informational line; do not fail. |

## Policies

### Side Effects and Loop-Safety

This skill is `loop_safe: true`. The `evaluate`, `validate`, and `list` subcommands are pure
reads (with `evaluate` also writing back recomputed `residual_risk` values when they change,
which the idempotency contract makes safe). The `add` and `edit` subcommands are gated by
operator input, so wrapping in `/loop` would no-op after the first prompt -- safe but
pointless. The skill writes byte-identical output for byte-identical input (records sorted by
id, fields in canonical order); diffs in version control are minimal and reviewable.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Inputs | Only `docs/.index/{manifest,risk-file}.yaml`, optional `risk-matrix.yaml`, and optional `compliance/iso-14971.md` are read. The skill never crawls source-code directories. |
| Outputs | Only `docs/.index/risk-file.yaml`. No other file is touched. |
| Opt-in | Absent `docs/.index/manifest.yaml` is a no-op exit 0, never a failure. |
| Atomicity | Writes go to `*.tmp` first, then rename on success. Failure deletes the temp file. |
| Idempotency | Same input always produces byte-identical output. Re-running `evaluate` on an unchanged risk file is a no-op. |
| Bidirectional linking | One-directional in the risk file (risk -> requirements). `traceability` reads it and produces the inverse view in the matrix. |
| External submission | Never. Submission to eQMS / regulator portals is out of scope. |

### Validation Message Style

When `validate` or `evaluate --ci` reports a finding, the message must include the relevant
ISO 14971 clause id (e.g. `ISO-14971-7.3`) so an auditor reading the CI log can pivot
directly to the standard. The clause-to-finding mapping is documented in
`reference/risk-record-schema.md` "Validation Rules" -- the skill body must use that table
verbatim rather than inventing new mappings.

## How Other Components Use the Risk File

| Consumer | Use |
|----------|-----|
| `traceability` skill (P0-1) | Reads `risk-file.yaml` to populate `risk_ids[]` on requirement matrix rows. Bidirectional linking comes for free. |
| `evidence-pack` skill (P1-1) | Mirrors `risk-file.yaml` (and the `risk-file/` directory if it exists) under the `risk_file` kind in the per-release evidence pack. |
| `traceability-guard` PreToolUse hook (P0-2) | Reads `risk-file.yaml` (when present) to detect when a PR touches a `code_paths` entry that traces to a risk without updating the risk record. |
| External auditor | Reads `risk-file.yaml` directly from the repo at any tagged release; consumes it alongside the matrix as the operational risk-management record. |

## References

- Risk record schema: `reference/risk-record-schema.md`
- Default risk matrix and per-project override format: `reference/risk-matrix.md`
- ISO 14971 clause source: `compliance/iso-14971.md` (project root, when present)
- Sibling matrix consumer: `global/skills/_internal/traceability/SKILL.md`
- Sibling release-time consumer: `global/skills/_internal/evidence-pack/SKILL.md`
- Parent epic: `kcenon/claude-config#588`
- Originating issue: `kcenon/claude-config#596`
