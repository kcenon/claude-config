# Regulated-Issue Fields

Per-issue-type matrix for the additional metadata fields required when the
`issue-create` skill detects a `compliance/` directory in the consumer project root
(`$REGULATED_TRACK=true` in Phase 0a of the SKILL body). Validation rules and the
embedded YAML block format are normative for the skill, the templates under
`templates/`, and the downstream consumers (`traceability` skill, the `pr-work`
regulated extension landing in #603).

> **Loading**: Loaded only when Phase 0a sets `$REGULATED_TRACK=true`. Skip when the
> consumer project has no `compliance/` directory.

## Per-Issue-Type Field Matrix

The matrix below defines, for each GitHub issue `type/*` label, which of the three
regulated fields are required, optional, or conditionally required. A value of
`required` means the skill MUST halt with a clear message when the field is missing.
`required-if-safety` means required when the issue's "Where" section names code under a
safety-relevant path (any path matched by a `paths:` glob in
`compliance/<standard>.md`). `optional` means the field may be left blank.

| Issue type        | `requirement_id`         | `risk_level`         | `clause_refs`           |
|-------------------|--------------------------|----------------------|-------------------------|
| `type/feature`    | required                 | required-if-safety   | >=1 required            |
| `type/bug`        | required-if-safety       | required-if-safety   | >=1 if safety           |
| `type/security`   | required                 | required             | >=1 required            |
| `type/chore`      | optional                 | optional             | optional                |
| `type/docs`       | optional                 | optional             | optional                |
| `type/test`       | linked-to-test-target    | optional             | optional                |
| `type/refactor`   | required-if-safety       | required-if-safety   | >=1 if safety           |

**`linked-to-test-target` (test issues only):** the prompt asks for the
`requirement_id` that the new or modified test verifies. The id is recorded so the
matrix can derive the `test_ids[]` -> `requirement_id` link without re-scanning.

**Safety-relevant detection.** The skill considers the issue safety-relevant when
the user's "Where" entry names any path matched by a `paths:` glob in
`compliance/iec-62304.md`, `compliance/iso-13485.md`, or `compliance/iso-14971.md`
(e.g. `risk-file/**`, `docs/risk-management/**`, `tests/safety/**`,
`src/medical/**`). When the consumer project ships additional standards files
(`compliance/iso-26262.md`, `compliance/do-178c.md`, etc.) those `paths:` are
unioned in.

## Allowed Values

### `requirement_id`

| Property | Rule |
|----------|------|
| Format   | `^SRS-[A-Z0-9]+-[0-9]+$` (e.g. `SRS-CALC-001`, `SRS-AUTH-014`). Matches the `id_routes.SRS` regex from `traceability/reference/matrix-schema.md`. |
| Validation | When `docs/.index/manifest.yaml` is present in the project, the value must resolve via that manifest's `id_routes.SRS` entry; unknown IDs are rejected with a list of close matches (Levenshtein distance <= 2). |
| Cardinality | Single value (one issue traces to one requirement). |
| Empty case | Permitted only when the matrix row above marks the field `optional`. |

### `risk_level`

| Property | Rule |
|----------|------|
| Allowed values | `acceptable`, `ALARP`, `unacceptable`. Case-sensitive. |
| Source | ISO 14971 risk acceptability scale, mirrored in the `risk-control` skill's record schema (`risk-control/reference/risk-record-schema.md` "Risk Level" enumeration). |
| Validation | Reject any value not in the three-element enum above. |
| Empty case | Permitted only when the matrix row above marks the field `optional` or the issue is not safety-relevant (per the safety-relevant detection rule). |

### `clause_refs[]`

| Property | Rule |
|----------|------|
| Format   | `<STANDARD>-<NUMBER>` per `traceability/reference/matrix-schema.md` "Clause Reference Format" (e.g. `IEC-62304-5.3.3`, `ISO-13485-7.3.3`, `ISO-14971-7.3`). Hyphens between standard and number; dotted clause path verbatim from the standard. |
| Cardinality | List of one or more values. The skill prompt asks for a comma-separated string and parses on `,`. |
| Validation | Each value's `<STANDARD>` prefix must match an existing `compliance/<standard>.md` file (e.g. `IEC-62304` -> `compliance/iec-62304.md`); each `<NUMBER>` must resolve to an `> **Clause**: <id>` anchor in that file. Unknown IDs are rejected. |
| Empty case | Permitted only when the matrix row above marks the field `optional` or `>=1 if safety` and the issue is not safety-relevant. |

## Embedded YAML Block Format

When `$REGULATED_TRACK=true`, the regulated-issue templates open with a fenced
YAML code block at the very top of the issue body. The block is the canonical
serialization that downstream skills parse. The format is fixed; do not vary it.

```yaml
regulated:
  requirement_id: SRS-CALC-001
  risk_level: ALARP
  clause_refs:
    - IEC-62304-5.3.3
    - ISO-14971-7.3
```

**Format rules** (the same rules the templates and the future `pr-work` extension
must honor):

1. The block MUST be the first non-blank content of the issue body, fenced by
   ```` ```yaml ```` and ```` ``` ````. Nothing precedes it -- not the title, not
   a heading, not a comment.
2. The top-level key is `regulated:`. No alternative key (no `meta:`, no `iso:`).
3. Field order inside the block is fixed: `requirement_id` -> `risk_level` ->
   `clause_refs`. Downstream parsers MAY rely on this order for diff stability.
4. Omitted optional fields are written as the literal value `null` (so the field
   is still present and a parser can distinguish "not asked" from "asked but
   empty"). Required fields that the user supplied are written as scalar strings.
5. `clause_refs:` is always a YAML list (block style with `- ` markers), even
   when only one entry is present. Single-line flow style is not used so a `git
   diff` of an added clause is one inserted line, not a rewritten line.
6. The block is followed by exactly one blank line, then the standard 5W1H
   sections (`## What`, `## Why`, ...).

**Worked example -- a feature issue.**

````markdown
```yaml
regulated:
  requirement_id: SRS-CALC-014
  risk_level: ALARP
  clause_refs:
    - IEC-62304-5.3.3
    - ISO-14971-7.3
```

## What

Add range-validation guard to the dosing calculator so out-of-range
parameters are rejected before therapy delivery.

...
````

**Worked example -- a chore issue (all regulated fields omitted).**

````markdown
```yaml
regulated:
  requirement_id: null
  risk_level: null
  clause_refs: null
```

## What

Bump CI image to ubuntu-24.04 LTS.

...
````

The `null` placeholders are intentional. Downstream parsers MAY treat an entirely
absent block as "this issue predates the regulated extension" (a legitimate
distinction), but a present block with `null` fields means "the skill ran on the
regulated track and the per-type matrix permitted omission". Both states matter to
the audit trail.

## Halt Behavior

When a required field is missing or invalid, the skill MUST halt before calling
`gh issue create`. The halt message is structured so the operator can recover
without re-running the entire interaction:

```
issue-create halted: regulated-track field violation

  field      : <name>
  rule       : <one-line rule from the matrix or validation table above>
  user input : <verbatim>
  hint       : <suggestion if available; e.g. "Did you mean SRS-CALC-014?">

No issue was created. Re-run /issue-create with a corrected value.
```

The skill MUST NOT silently fall back to creating a bare (non-regulated) issue --
that would defeat the purpose of the gate.

## Cross-references

- Matrix schema that consumes `requirement_id` and `clause_refs`:
  `../../traceability/reference/matrix-schema.md`
- Risk record schema that defines `risk_level` enumeration:
  `../../risk-control/reference/risk-record-schema.md`
- Per-standard clause IDs:
  `compliance/iec-62304.md`, `compliance/iso-13485.md`, `compliance/iso-14971.md`
- Issue templates that embed the YAML block:
  `templates/regulated-feature.md`, `templates/regulated-bug.md`
- Skill body that calls into this reference:
  `../SKILL.md` Phase 0a / 0b
