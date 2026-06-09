# Traceability Validation Rules

What counts as a broken link, when each finding is raised, and the exit-code policy used by
the `traceability` skill.

> **Loading**: Loaded under `tier: standard` and `tier: deep` via the skill's `ref_docs.validation`
> entry. Skip when invoking under `tier: light`.

## Finding Taxonomy

Every finding emitted by `Phase 3: Validate` is one of the seven types below. The `severity`
column controls the default exit-code path; `--ci` and `--check-only` modes promote all
warnings to failures (see "Exit-Code Policy").

| Finding | Severity | Trigger |
|---------|----------|---------|
| `requirement_without_test` | error | Row has `test_ids: []` and `status` is not `deferred`. |
| `code_without_trace` | error | A file appears in `bundles.yaml` but no matrix row references it via `code_paths`. |
| `dangling_clause_ref` | error | A `clause_refs` entry names a clause not present in `compliance/`. Suppressed when `compliance/` does not exist. |
| `dangling_design_ref` | error | A `design_id` value does not appear in `router.yaml` `id_routes.SI`. |
| `dangling_risk_ref` | error | A `risk_ids` entry does not appear in `router.yaml` `id_routes.H`. |
| `dangling_test_ref` | error | A `test_ids` entry does not appear in `router.yaml` `id_routes.TC`. |
| `orphan_requirement` | warning | A `requirement_id` discovered in Phase 1 has no row in the matrix (matrix is stale). |

### Severity Modifiers

The base severity above is adjusted by row-level signals:

- A row with `status: deferred` and a `notes:` field starting with `deferred:` downgrades
  every error on that row to a warning. Auditors rely on the explicit deferral note —
  silent suppression is forbidden.
- `status: needs_review` is itself a warning; pair it with the underlying finding rather
  than emitting it standalone.

## Concrete Examples

### Example 1: `requirement_without_test`

```yaml
- requirement_id: SRS-CALC-007
  design_id: SI-CALC
  code_paths:
    - src/calc/engine.cpp
  test_ids: []           # <-- triggers finding
  risk_ids: []
  clause_refs: []
  status: incomplete
```

Finding row:

```
ERROR  requirement_without_test  SRS-CALC-007  no entries in test_ids
```

To clear: add at least one `TC-CALC-NNN` to `test_ids`, or switch the row to `status: deferred`
with a `deferred: ...` note explaining the timeline.

### Example 2: `code_without_trace`

`bundles.yaml` lists `src/render/pipeline.cpp` under the `si-rg` bundle. No row in
`traceability.yaml` references that file in any `code_paths` entry.

```
ERROR  code_without_trace  src/render/pipeline.cpp  bundle si-rg has no matrix row referencing this file
```

To clear: regenerate the matrix (the file usually appears once `req_chains` are wired in
`graph.yaml`), or remove the file from `bundles.yaml` if it is genuinely orphaned.

### Example 3: `dangling_clause_ref`

```yaml
- requirement_id: SRS-DATA-002
  clause_refs:
    - IEC-62304-9.99.99      # <-- not present in compliance/iec-62304.md
```

Finding row:

```
ERROR  dangling_clause_ref  SRS-DATA-002  clause IEC-62304-9.99.99 not found in compliance/iec-62304.md
```

To clear: fix the typo in the `clause_refs` entry, or add the clause anchor to the
`compliance/` rule file using the format `> **Clause**: IEC-62304-9.99.99`.

### Example 4: Suppressed When `compliance/` Is Absent

If the project has not adopted compliance rules yet, `dangling_clause_ref` is not raised
even when `clause_refs` contains values. The skill prints one informational line:

```
INFO   compliance/ directory absent — clause_refs validation skipped (3 clauses unchecked)
```

This keeps the skill usable for projects that adopt the matrix before they adopt the
clause-mapping layer (e.g. early P0 cuts of the regulated track epic).

### Example 5: `orphan_requirement` (Stale Matrix)

The catalogue lists `SRS-SEC-014` in `router.yaml` `id_routes.SRS.section_map.SEC`, but the
matrix has no row for it.

```
WARNING  orphan_requirement  SRS-SEC-014  not present in traceability.yaml; regenerate the matrix
```

Default mode prints this as a warning and continues. `--ci` and `--check-only` promote it
to a failure: a stale matrix is exactly what those modes are designed to catch.

## Exit-Code Policy

The skill exits with one of three codes.

| Exit code | Meaning | When |
|-----------|---------|------|
| `0` | Success | No findings, OR default mode with only warning-severity findings, OR no-op when `docs/.index/graph.yaml` is absent. |
| `1` | Validation failure | At least one finding remains after severity modifiers were applied, AND the mode is `--ci` or `--check-only`. |
| `2` | Skill-internal failure | Missing required input, YAML parse error, write failure, or any other condition unrelated to the matrix content itself. |

Default mode never returns `1` — it surfaces findings on stdout and exits `0` so contributors
can iterate locally without each invocation feeling like a CI bounce. `--ci` exists to make
the same skill usable as a merge gate.

### Mode Matrix

| Mode | Generates artifacts? | Validates? | Errors → exit | Warnings → exit |
|------|----------------------|------------|---------------|-----------------|
| Default | Yes | Yes | 0 | 0 |
| `--ci` | Yes | Yes | 1 | 1 |
| `--check-only` | No | Yes | 1 | 1 |

`--verbose` is orthogonal to mode and only changes report formatting.

## Report Format

Each finding is one line on stdout in the format:

```
<SEVERITY>  <finding_id>  <subject>  <message>
```

Where `<SEVERITY>` is `ERROR`, `WARNING`, or `INFO`, padded to 7 characters, and `<subject>`
identifies the offending entity (a `requirement_id`, a file path, or a clause reference).

The summary block printed at the end of every run shows the counts:

```
Findings: 3 (2 errors / 1 warning / 0 info)
```

In `--verbose` mode, a per-row table is appended showing how each row resolved each cell.

## Adding a New Finding Type

When the schema or workflow grows new failure modes, add them here first:

1. Pick a snake_case finding id following the existing prefixes (`requirement_*`,
   `dangling_*`, `code_*`, `orphan_*`).
2. Add a row to "Finding Taxonomy" with the trigger and base severity.
3. Add a concrete example in "Concrete Examples" showing the YAML that triggers it and
   the on-stdout finding row.
4. Update the skill body's Phase 3 table to include the new finding.
5. Bump `_meta.schema` minor in `matrix-schema.md` only if the finding is paired with a
   new schema field. Validation-only additions do not require a schema bump.

## Cross-references

- Row schema referenced by these rules: `matrix-schema.md`
- Skill that emits the findings: `../SKILL.md`
- Catalogue producer that builds the inputs: `../../doc-index/SKILL.md`
- Sibling enforcement layer (PreToolUse): `kcenon/claude-config#590` (`traceability-guard`)
- Sibling clause-mapping layer: `kcenon/claude-config#591` (`compliance/<standard>.md` rules)
