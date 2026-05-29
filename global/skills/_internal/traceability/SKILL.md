---
name: traceability
description: "Generate and validate the bidirectional traceability matrix linking requirements, design, code, tests, risk records, and standard clauses. Consumes docs/.index/{manifest,bundles,graph,router}.yaml plus an optional compliance/ directory and produces docs/.index/traceability.yaml (machine-readable) and docs/.index/traceability.md (human-readable). Read-mostly: writes only the two trace artifacts and never mutates source documents. Opt-in — no-op when docs/.index/graph.yaml is absent so non-regulated repos are unaffected."
argument-hint: "[--ci] [--check-only] [--verbose]"
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
  - { type: success, expr: "traceability.yaml and traceability.md written and validation reports zero broken links" }
  - { type: success, expr: "no-op exit when docs/.index/graph.yaml is absent" }
  - { type: failure, expr: "validation reports any broken link in --ci or --check-only mode" }
  - { type: failure, expr: "manifest/graph/router parse error or write step errors out" }
on_halt: "Print broken-link report (or no-op message) and exit non-zero on failure, zero on success or no-op"
tiers:
  light:
    ref_docs: []
    deep_checks: false
  standard:
    ref_docs: [schema, validation]
    deep_checks: true
  deep:
    ref_docs: [schema, validation]
    deep_checks: true
default_tier: standard
iso_class: A
applies_at_or_above: A
# ref_docs keys:
#   schema     -> reference/matrix-schema.md
#   validation -> reference/validation-rules.md
---

# traceability Skill

Generate and validate the requirements-to-evidence traceability matrix for projects that
have adopted the regulated-industry track. The skill is the read-mostly counterpart to
`doc-index`: where `doc-index` builds the catalogue, `traceability` stitches the catalogue
into the audit-facing matrix.

## Usage

```
/traceability                  # Generate matrix and report broken links (warnings only)
/traceability --ci             # Validate-only mode for CI; exits non-zero on broken links
/traceability --check-only     # Validate the existing matrix without regenerating it
/traceability --verbose        # Print per-row resolution detail
```

No positional arguments. Operates on the current project directory.

## Arguments

| Flag | Behavior |
|------|----------|
| `--ci` | Generate matrix, then validate. Exit non-zero if any broken link is reported. Intended for the `validate` job in GitHub Actions. |
| `--check-only` | Skip generation; validate the existing `docs/.index/traceability.yaml` against the current `docs/.index/` and `compliance/` state. Use to detect drift without rewriting the artifact. |
| `--verbose` | Print one line per matrix row showing how each cell was resolved (which manifest entry, which graph cascade, which compliance clause). |

`--ci` and `--check-only` are mutually exclusive. If both are supplied, `--ci` wins and a
warning is printed.

## Inputs

| Path | Required | Purpose |
|------|----------|---------|
| `docs/.index/graph.yaml` | Yes (gate) | Source of cascade chains and `req_chains`. Skill is a no-op when this file is absent. |
| `docs/.index/manifest.yaml` | Yes | Document registry with doc_ids, sections, and tags. |
| `docs/.index/bundles.yaml` | Yes | Feature bundles used to detect orphan code paths. |
| `docs/.index/router.yaml` | Yes | ID routes for resolving `requirement_id` and other entity references. |
| `compliance/` | Optional | Per-standard rule files (e.g. `iec-62304.md`, `iso-13485.md`). When present, each clause referenced in the matrix is verified to exist. |

## Outputs

| Path | Format | Audience |
|------|--------|----------|
| `docs/.index/traceability.yaml` | YAML | Machine-readable matrix consumed by hooks, CI, and other skills. |
| `docs/.index/traceability.md` | Markdown | Human-readable matrix reviewable in PR diffs. |

Both files are regenerated atomically: the skill writes to a sibling `*.tmp` file and renames
on success. A failed generation never produces a half-written artifact.

## Opt-in Gate

The skill is purely additive and must not break repos that have not adopted the regulated track.

```bash
if [[ ! -f docs/.index/graph.yaml ]]; then
    echo "traceability: docs/.index/graph.yaml absent — skill is a no-op for this repo"
    exit 0
fi
```

This check runs before any other phase. The exit code is `0` so CI invocations on
non-regulated repos do not fail.

## Instructions

### Phase 0: Validate Environment

1. Confirm `docs/.index/graph.yaml` exists; if not, print the no-op message and exit 0.
2. Confirm the remaining three index files (`manifest.yaml`, `bundles.yaml`, `router.yaml`)
   are present. Missing any of these is a hard failure — the matrix cannot be built.
3. Detect optional `compliance/` directory at the repo root. Record whether it exists; the
   `clause_refs` validation in Phase 3 depends on this.
4. If `--check-only` is set, skip Phase 1 and 2. Read the existing
   `docs/.index/traceability.yaml` directly and proceed to Phase 3.

### Phase 1: Resolve Entities

Build in-memory lookup tables from the index files. Reference: `reference/matrix-schema.md`
defines the row shape these tables feed.

1. **Requirements**: from `router.yaml` `id_routes.SRS`, walk each section in `section_map`
   and emit one entry per `SRS-{CAT}-{NNN}` identifier discovered. Record source file and
   line range for each.
2. **Design items**: from `router.yaml` `id_routes.SI` (and `IF` if present). Each becomes
   a candidate `design_id` for matching requirements.
3. **Code paths**: from `bundles.yaml`, collect every `files[].file` value plus any
   `code_paths` field present at the bundle level. The skill does not crawl source-code
   directories directly — it relies on the bundle catalogue to bound the search.
4. **Tests**: from `router.yaml` `id_routes.TC`. Each `TC-{CAT}-{NNN}` is a candidate
   `test_id`. Section line ranges identify the source SVP document.
5. **Risk records**: from `router.yaml` `id_routes.H` and any `id_routes.HUS`. Hazards
   become `risk_ids`; HUS scenarios are recorded as additional risk evidence.
6. **Clauses**: if `compliance/` exists, scan `compliance/*.md` for clause anchors. The
   accepted format is `> **Clause**: <STANDARD>-<NUMBER>` or a heading
   `## Clause <STANDARD>-<NUMBER>`. Record each clause as `{standard, number, file, line}`.

### Phase 2: Stitch the Matrix

For each `requirement_id` discovered in Phase 1, build one matrix row by following the
cascade graph:

1. Start with the row keyed by `requirement_id`.
2. **Design link**: read `graph.yaml` `req_chains.<requirement_category>.design_items` and
   record the matching `SI-` ids. If the row's `requirement_id` is `SRS-CALC-001`, the
   relevant chain is `req_chains.SRS-CALC` (or whatever key `doc-index` produced).
3. **Code paths**: collect every bundle `files[].file` whose bundle includes the design id
   from step 2, or whose bundle name matches the requirement category.
4. **Tests**: read `req_chains.<category>.tests` and record matching `TC-` ids.
5. **Risk**: read `req_chains.<category>.hazards` and record matching `H-` ids.
6. **Clause refs**: any clauses in `compliance/` whose body cites the requirement id (via
   `requirement_id:` frontmatter or inline `> SRS-<CAT>-<NNN>` reference) are added.
7. **Status**: derive from cell completeness. See `reference/matrix-schema.md` for the
   full status table.

### Phase 3: Validate

Reference: `reference/validation-rules.md` defines the broken-link taxonomy and exit codes.

Validation runs whether or not the matrix was just regenerated. Each finding is one of:

| Finding | Trigger |
|---------|---------|
| `requirement_without_test` | Row has `test_ids: []` and status is not `deferred`. |
| `code_without_trace` | A file appears in `bundles.yaml` but no matrix row references it. |
| `dangling_clause_ref` | A `clause_refs` entry names a clause not present in `compliance/`. |
| `dangling_design_ref` | A `design_id` that does not appear in `router.yaml` `id_routes.SI`. |
| `dangling_risk_ref` | A `risk_ids` entry not present in `router.yaml` `id_routes.H`. |
| `dangling_test_ref` | A `test_ids` entry not present in `router.yaml` `id_routes.TC`. |
| `orphan_requirement` | A `requirement_id` discovered in Phase 1 has no row in the matrix. |

Findings are written to the report regardless of mode. The exit-code policy is:

- Default mode: warnings only, exit 0 even when findings exist.
- `--ci` and `--check-only`: any finding causes a non-zero exit (see
  `reference/validation-rules.md` for the exit-code map).

### Phase 4: Write Artifacts

Skip when `--check-only` is set.

1. Write `docs/.index/traceability.yaml.tmp` with the row schema from
   `reference/matrix-schema.md`.
2. Write `docs/.index/traceability.md.tmp` from the same row data, formatted as a Markdown
   table grouped by requirement category.
3. On success, rename both `*.tmp` files to their final names. On any error, delete the
   `*.tmp` files and exit non-zero.

### Phase 5: Report

Emit a summary block on stdout:

```markdown
## Traceability Matrix Generated

| Metric | Value |
|--------|-------|
| Requirements | N |
| Rows complete | N |
| Rows incomplete | N |
| Findings | N (M errors / K warnings) |
| traceability.yaml | X bytes |
| traceability.md | Y bytes |
```

Append a per-finding table when `--verbose` is set or when running under `--ci`.

## Output

The skill produces the two artifacts above plus the on-stdout summary. No other files are
modified — in particular, the skill never edits `manifest.yaml`, `bundles.yaml`, `graph.yaml`,
or `router.yaml`. Those remain `doc-index`'s responsibility.

## Error Handling

| Condition | Action |
|-----------|--------|
| `docs/.index/graph.yaml` absent | No-op exit 0 (opt-in gate, see Phase 0). |
| `docs/.index/{manifest,bundles,router}.yaml` absent | Exit non-zero with the missing file name. |
| YAML parse error in any input | Exit non-zero with file path and line number. |
| Write step fails (permission, disk) | Delete any `*.tmp` files, report the path, exit non-zero. |
| Validation finding in `--ci` or `--check-only` mode | Print the finding table, exit non-zero (see exit-code map in `reference/validation-rules.md`). |
| Validation finding in default mode | Print the finding table, exit 0. |
| `compliance/` referenced but absent | Skip clause validation; print one informational line; do not fail. |

## Policies

### Command-Specific Rules

| Item | Rule |
|------|------|
| Inputs | Only `docs/.index/*.yaml` and `compliance/*.md` are read. The skill never crawls source-code directories directly. |
| Outputs | Only `docs/.index/traceability.yaml` and `docs/.index/traceability.md`. No other files are touched. |
| Opt-in | Absent `docs/.index/graph.yaml` is a no-op exit 0, never a failure. |
| Atomicity | Writes go to `*.tmp` first, then rename on success. Failure deletes the temp files. |
| Existing skills | This skill is purely additive; existing skill behavior is unchanged. |

## How Other Components Use the Matrix

| Consumer | Use |
|----------|-----|
| `traceability-guard` PreToolUse hook (sibling issue #590) | Reads `traceability.yaml` to detect when a PR touches a `code_paths` entry without updating its row. |
| `compliance/<standard>.md` rules (sibling issue #591) | Reference clauses validated by this skill's `dangling_clause_ref` finding. |
| `pr-work` skill (future P2) | Auto-injects impacted matrix rows into the PR body. |
| External auditor | Reads `traceability.md` directly from the repo at any tagged release. |

## References

- Schema for `traceability.yaml`: `reference/matrix-schema.md`
- Validation rules and exit codes: `reference/validation-rules.md`
- Catalogue producer: `global/skills/_internal/doc-index/SKILL.md`
- Parent epic: `kcenon/claude-config#588`

## Side Effects and Loop-Safety

This skill is `loop_safe: true`. It is a single-pass (`max_iterations: 1`) read-mostly operation: it consumes `docs/.index/{manifest,bundles,graph,router}.yaml` and writes only `docs/.index/traceability.{yaml,md}`, never mutating source documents. Re-running is idempotent — it regenerates the same two artifacts from current inputs, so wrapping it in a `/loop` is safe (and a no-op when `graph.yaml` is absent). The `max_iterations: 1` / `halt_conditions` metadata expresses single-pass exit semantics, not a polling loop.
