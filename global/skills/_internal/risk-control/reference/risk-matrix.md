# Risk Acceptability Matrix

Default 5x5 risk-acceptability matrix used by the `risk-control` skill to derive
`initial_risk` and `residual_risk` from `severity` and `probability`. Per-project overrides
are supported via a `risk-matrix.yaml` file at the consumer project's repo root; when
absent, the defaults below apply.

> **Loading**: Loaded under `tier: standard` and `tier: deep` via the skill's `ref_docs.matrix`
> entry. Skip when invoking under `tier: light`.

## Default 5x5 Matrix

Rows are severity (worst at the bottom); columns are probability of harm (highest on the
right). Each cell is the resulting risk level.

|                  | improbable    | remote        | occasional    | probable        | frequent        |
|------------------|---------------|---------------|---------------|-----------------|-----------------|
| **negligible**   | acceptable    | acceptable    | acceptable    | acceptable      | ALARP           |
| **minor**        | acceptable    | acceptable    | acceptable    | ALARP           | ALARP           |
| **serious**      | acceptable    | ALARP         | ALARP         | ALARP           | unacceptable    |
| **critical**     | ALARP         | ALARP         | unacceptable  | unacceptable    | unacceptable    |
| **catastrophic** | ALARP         | unacceptable  | unacceptable  | unacceptable    | unacceptable    |

The shape follows ISO 14971 Annex C example matrices: severity dominates probability, and
the diagonal of `unacceptable` cells climbs from the bottom-left corner. The matrix is
deliberately conservative: no `catastrophic` outcome is `acceptable` regardless of
probability, and no `frequent` event is `acceptable` regardless of severity.

## Acceptability Bands

| Band            | Meaning |
|-----------------|---------|
| `acceptable`    | No further risk reduction required. ISO-14971-6 acceptance criteria are met as-is. |
| `ALARP`         | Acceptable provided the risk has been reduced as low as reasonably practicable (further reduction would be grossly disproportionate to the benefit). The record SHOULD carry a justification in `notes`. |
| `unacceptable`  | Further risk-control measures required, or the design must be reconsidered. The `evaluate --ci` subcommand exits non-zero on any record in this band that is not in status `accepted` (benefit-risk override per ISO-14971-7.4) or status `deferred` (with justification). |

The three-band model is a project-policy convention; it maps onto ISO 14971's two-state
"acceptable / not acceptable" decision via the `accepted` status (benefit-risk override) and
the `deferred` status (mitigation queued for a later release). Some projects collapse ALARP
into either acceptable or unacceptable; see "Per-Project Overrides" below.

## Numeric Weights (Internal)

The skill's matrix derivation uses these integer weights:

| Severity        | Weight |
|-----------------|--------|
| negligible      | 1      |
| minor           | 2      |
| serious         | 3      |
| critical        | 4      |
| catastrophic    | 5      |

| Probability     | Weight |
|-----------------|--------|
| improbable      | 1      |
| remote          | 2      |
| occasional      | 3      |
| probable        | 4      |
| frequent        | 5      |

The product (severity_weight x probability_weight) is the risk priority number (RPN). The
default-matrix bands map RPN to acceptability:

| RPN range | Band            |
|-----------|-----------------|
| 1 - 4     | acceptable      |
| 5 - 12    | ALARP           |
| 13 - 25   | unacceptable    |

A per-project override (see below) can adjust the band thresholds, swap the weights, or
replace the matrix wholesale. The skill always uses RPN as the internal scalar so that
overrides keep the same derivation interface.

## Per-Project Overrides

A consumer project that needs different acceptability criteria places a `risk-matrix.yaml`
file at the repo root. The skill loads this file in Phase 0 and uses it instead of the
defaults above.

### Override File Schema

```yaml
# risk-matrix.yaml -- project-specific risk acceptability matrix
_meta:
  schema: "1.0.0"           # Same schema major as risk-file.yaml
  source: "<project-name>"  # Free-form; appears in risk-file.yaml _meta.matrix_source

severity_weights:
  negligible:    1
  minor:         2
  serious:       3
  critical:      4
  catastrophic:  5

probability_weights:
  improbable:    1
  remote:        2
  occasional:    3
  probable:      4
  frequent:      5

bands:
  acceptable:   { max_rpn: 4 }      # RPN <= max_rpn -> acceptable
  alarp:        { max_rpn: 12 }     # acceptable.max_rpn < RPN <= alarp.max_rpn -> ALARP
  unacceptable: { max_rpn: 25 }     # alarp.max_rpn < RPN -> unacceptable

risk_acceptance:
  alarp_fails_ci: false             # When true, evaluate --ci fails on ALARP findings
                                    # Default false -- matches ISO-14971 ALARP doctrine
```

### Override Examples

#### More-conservative project (e.g. surgical robotics)

Tighten the bands so any RPN above 6 is `unacceptable`:

```yaml
_meta:
  schema: "1.0.0"
  source: "surgical-robotics-2026"
bands:
  acceptable:   { max_rpn: 2 }
  alarp:        { max_rpn: 6 }
  unacceptable: { max_rpn: 25 }
risk_acceptance:
  alarp_fails_ci: true              # No ALARP records pass CI without explicit acceptance
```

#### Two-band model (collapse ALARP into ALARP-as-unacceptable)

Some quality-management systems do not use ALARP and require everything be either
acceptable or unacceptable. Set both `bands.alarp.max_rpn` equal to
`bands.acceptable.max_rpn` so the ALARP band is empty:

```yaml
bands:
  acceptable:   { max_rpn: 4 }
  alarp:        { max_rpn: 4 }      # Empty ALARP band
  unacceptable: { max_rpn: 25 }
```

The skill still emits the `ALARP` enum value in records where `residual_risk` falls into
the (empty) ALARP band -- which is impossible by construction here -- so the file shape is
unchanged. Operators see only `acceptable` and `unacceptable` in practice.

### Override Validation

The override file is parsed in Phase 0. The skill exits non-zero (with the YAML parse error
and the offending line) on:

- Missing or non-integer weight for any severity / probability enum value.
- `bands.alarp.max_rpn < bands.acceptable.max_rpn` (out-of-order bands).
- `bands.unacceptable.max_rpn < bands.alarp.max_rpn` (out-of-order bands).
- Any unknown top-level key (forward-compatibility guard -- update this file when new keys
  are introduced).

The override is otherwise opt-in: a project that ships only the defaults sees no behavior
change.

## Computing initial_risk and residual_risk

For `initial_risk`:

```
weight_s = severity_weights[record.severity]
weight_p = probability_weights[record.probability]
rpn      = weight_s * weight_p
band     = first(b in [acceptable, alarp, unacceptable]
                where rpn <= bands[b].max_rpn)
record.initial_risk = band  # 'acceptable' | 'ALARP' | 'unacceptable'
```

`residual_risk` follows the identical formula with `residual_severity` and
`residual_probability` substituted in. The `evaluate` subcommand recomputes both fields on
every run so a matrix override propagates without rewriting records by hand.

The derivation is deterministic: the same inputs always produce the same band, which is the
property that makes the risk file diff cleanly in version control (idempotency contract).

## Cross-references

- Record schema that consumes this matrix: `risk-record-schema.md`
- Skill body: `../SKILL.md`
- ISO 14971 clause source: `compliance/iso-14971.md`
- Annex C of ISO 14971:2019 contains illustrative example matrices; this file paraphrases
  the qualitative bands rather than copying the standard's text.
