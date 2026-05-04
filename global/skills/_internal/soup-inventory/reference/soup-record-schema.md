# SOUP Record Schema

YAML schema for `docs/.index/soup.yaml` records produced and maintained by the
`soup-inventory` skill. This file is the single source of truth for record shape and field
semantics.

> **Loading**: Loaded under `tier: standard` and `tier: deep` via the skill's `ref_docs.schema`
> entry. Skip when invoking under `tier: light`.

## Top-Level Document Layout

```yaml
# docs/.index/soup.yaml
# Generated and maintained by /soup-inventory -- do not edit by hand
_meta:
  schema: "1.0.0"           # Schema version of this document
  generated: "YYYY-MM-DDTHH:MM:SSZ"  # ISO 8601 UTC timestamp of last write
  generator: "soup-inventory"        # Skill name that produced this artifact
  source_index_version: ""  # docs/.index/manifest.yaml _meta.schema, copied verbatim when manifest is present
  records: N                # Total record count
  needs_review: N           # Subset with status: needs_review
  ready: N                  # Subset with status: ready

records:
  - <record>                # See "Record Schema" below
  - <record>
  - ...
```

`_meta.schema` follows semantic versioning. Consumers must check `_meta.schema` before
parsing records; mismatched majors mean the schema has changed in a backward-incompatible way.

Records are sorted by `id` (stable, ASCII order) on every write to guarantee byte-identical
output for unchanged input (idempotency contract, matches the sibling skills).

## Record Schema

Every record is one third-party software item the project depends on.

```yaml
- id: SOUP-001                          # MANDATORY -- primary key, format SOUP-NNN
  name: "express"                       # MANDATORY -- package name as it appears in the lockfile
  version: "4.18.2"                     # MANDATORY -- exact pinned version
  supplier: "OpenJS Foundation"         # MANDATORY -- upstream maintainer or organization
  source_url: "https://github.com/expressjs/express"  # MANDATORY -- canonical upstream URL
  license_spdx: "MIT"                   # MANDATORY -- SPDX identifier (or "UNKNOWN" when the lockfile carries no license metadata)
  purpose: "HTTP request routing for the device-facing REST API"  # MANDATORY for status: ready
  risk_class: B                         # MANDATORY -- one of A, B, C, or unset (sentinel for status: needs_review)
  dependent_requirements:               # MANDATORY (may be empty list)
    - SRS-API-001
    - SRS-API-014
  dependent_si_ids:                     # MANDATORY (may be empty list)
    - SI-IL
  verification_refs:                    # MANDATORY (may be empty list)
    - IEC-62304-5.3.3
    - tests/integration/test_express_routing.py
  status: ready                         # MANDATORY -- one of needs_review, ready
  notes: ""                             # OPTIONAL -- free-form, single line for human reviewers
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Format `SOUP-NNN` (three zero-padded digits). Primary key for the record. Assigned by the skill on `discover`; never reused after retirement. |
| `name` | string | Yes | Package name as it appears in the lockfile. Auto-populated by `discover`; not editable by `enrich`. |
| `version` | string | Yes | Exact pinned version. Auto-populated by `discover`; refreshed on re-discovery when the lockfile entry's version changes. |
| `supplier` | string | Yes | Upstream maintainer name or organization. Auto-populated where the lockfile carries it (npm `_npmUser`, PyPI `Author`, etc.); falls back to the value `"unknown"` otherwise. Operator can refine via `enrich`. |
| `source_url` | string | Yes | Canonical upstream URL (homepage, repository, or registry page). Auto-populated where available. |
| `license_spdx` | string | Yes | SPDX license identifier (e.g. `MIT`, `Apache-2.0`, `BSD-3-Clause`). Set to `UNKNOWN` when the lockfile carries no license metadata; the operator must resolve this before `validate --ci` will pass. |
| `purpose` | string | Conditional | One-line description of why the project uses this SOUP. Required when `status: ready`. Empty string is permitted only when `status: needs_review`. |
| `risk_class` | enum | Yes | One of `A`, `B`, `C` (matches IEC 62304 software item classification), or `unset` (sentinel for newly discovered records). `validate --ci` rejects `unset`. |
| `dependent_requirements` | list[string] | Yes (may be empty) | Format `SRS-{CAT}-{NNN}`. Empty list is permitted for SOUP items that support infrastructure rather than a specific requirement (e.g. test runners). |
| `dependent_si_ids` | list[string] | Yes (may be empty) | Format `SI-{CODE}`. Empty list is permitted for cross-cutting SOUP items that no single design item owns. |
| `verification_refs` | list[string] | Yes (may be empty) | Each entry must resolve to one of: a clause id present in `compliance/iec-62304.md`, a `SRS-*` id present in `manifest.yaml`, a `H-*` id present in `risk-file.yaml`, or a repo-relative file path that exists on disk. Empty list is permitted only when `status: needs_review`. |
| `status` | enum | Yes | One of `needs_review` (newly discovered, awaiting enrichment) or `ready` (fully enriched and ready for the matrix). |
| `notes` | string | No | Free-form, single line. Auditors read this; keep it factual. |

### Enrichment Fields

The `enrich` subcommand prompts for these fields only:

| Field | Purpose |
|-------|---------|
| `purpose` | Why the project uses this SOUP. |
| `risk_class` | A / B / C per IEC 62304 software item classification, derived from the failure-mode impact this SOUP can have on the device. |
| `dependent_requirements[]` | Which `SRS-*` ids depend on this SOUP. |
| `dependent_si_ids[]` | Which `SI-*` design items allocate this SOUP. |
| `verification_refs[]` | What evidence (clause / requirement / file path) demonstrates this SOUP has been verified for the project's intended use. |

Auto-populated fields (`name`, `version`, `supplier`, `source_url`, `license_spdx`) are not
editable through `enrich`; they are refreshed only by `discover`.

### Status Field

The `status` value tracks the record's enrichment progress. The skill writes one of the two
values; consumers must not invent new ones.

| Status | Derivation rule |
|--------|-----------------|
| `needs_review` | Record was just created by `discover`. `purpose` is empty, `risk_class` is `unset`, `verification_refs[]` is empty. The matrix should not consume this record's `dependent_requirements[]` until enrichment completes. |
| `ready` | `purpose` is non-empty, `risk_class` is one of `A`/`B`/`C`, `verification_refs[]` is non-empty. The matrix consumes this record. |

`enrich` flips a record from `needs_review` to `ready` on successful submission. There is no
explicit "retire" state; instead, retired SOUPs are removed from the lockfile (which `discover`
detects via the lockfile cross-check) and the operator deletes the orphaned record from the
register manually.

## Identifier Format Conventions

Identifiers in SOUP records must match the formats produced by the sibling skills:

| Entity | Format | Example | Source |
|--------|--------|---------|--------|
| SOUP record | `SOUP-{NNN}` | `SOUP-001` | This file |
| Requirement | `SRS-{CAT}-{NNN}` | `SRS-API-001` | `traceability/reference/matrix-schema.md` |
| Design item | `SI-{CODE}` | `SI-IL` | `traceability/reference/matrix-schema.md` |
| Hazard | `H-{NN}` | `H-03` | `risk-control/reference/risk-record-schema.md` |
| Clause | `<STANDARD>-<NUMBER>` | `IEC-62304-5.3.3` | `traceability/reference/matrix-schema.md` |

### File Path Format

`verification_refs[]` entries that point to evidence files use repo-relative paths with
forward slashes (`tests/integration/test_x.py`), no leading `./`, no leading `/`. The skill
resolves them against the repo root at validation time.

## Validation Rules

The `validate` subcommand runs the following checks. The IEC 62304 clause column is the
clause id the message must cite when the finding triggers in `--ci` mode.

| Finding | Trigger | IEC 62304 clause | Severity |
|---------|---------|------------------|----------|
| `lockfile_entry_without_record` | A lockfile entry has no matching SOUP record. | `IEC-62304-8.1.1` | error |
| `record_without_lockfile_entry` | A SOUP record has no matching lockfile entry. | `IEC-62304-8.1.1` | warning |
| `risk_class_unset` | `risk_class` is the `unset` sentinel. | `IEC-62304-5.3.3` | error |
| `license_unknown` | `license_spdx` is `UNKNOWN`. | `IEC-62304-5.3.3` | error |
| `license_outside_allow_list` | `license_spdx` is not in the active allow-list (see `license-policy.md`). | `IEC-62304-5.3.3` | error |
| `license_in_forbid_list` | `license_spdx` is in the active forbid-list. | `IEC-62304-5.3.3` | error |
| `dangling_requirement_ref` | A `dependent_requirements[]` entry does not resolve to a `SRS-*` id in `manifest.yaml`. | `IEC-62304-5.3.3` | error |
| `dangling_si_ref` | A `dependent_si_ids[]` entry does not resolve to a `SI-*` id in `manifest.yaml`. | `IEC-62304-5.3.3` | error |
| `dangling_verification_ref` | A `verification_refs[]` entry does not resolve to a clause / requirement / file path. | `IEC-62304-5.3.3` | error |
| `purpose_empty_when_ready` | `purpose` is empty but `status` is `ready`. | `IEC-62304-5.3.3` | error |
| `verification_refs_empty_when_ready` | `verification_refs[]` is empty but `status` is `ready`. | `IEC-62304-5.3.3` | error |

In default mode, every finding emits a warning and the skill exits 0. In `--ci` mode, every
`error`-severity finding causes a non-zero exit; warnings remain non-fatal.

### Validation Output

Findings are printed as a Markdown table:

```markdown
## SOUP Inventory Validation Findings

| ID | Finding | Detail | Clause |
|----|---------|--------|--------|
| SOUP-005 | risk_class_unset | risk_class is "unset"; run `enrich SOUP-005` | IEC-62304-5.3.3 |
| SOUP-012 | license_in_forbid_list | license_spdx "GPL-3.0" is in the project forbid-list | IEC-62304-5.3.3 |
| -        | lockfile_entry_without_record | lockfile entry "vue@3.4.0" has no SOUP record; run `discover` | IEC-62304-8.1.1 |

Summary: 2 errors, 0 warnings across 14 records.
```

## Example: Minimal Register

A small but complete `soup.yaml` for a project with two SOUP records, one fully enriched
and one freshly discovered:

```yaml
_meta:
  schema: "1.0.0"
  generated: "2026-05-04T12:34:56Z"
  generator: "soup-inventory"
  source_index_version: "1.0.0"
  records: 2
  needs_review: 1
  ready: 1

records:
  - id: SOUP-001
    name: "express"
    version: "4.18.2"
    supplier: "OpenJS Foundation"
    source_url: "https://github.com/expressjs/express"
    license_spdx: "MIT"
    purpose: "HTTP request routing for the device-facing REST API"
    risk_class: B
    dependent_requirements:
      - SRS-API-001
      - SRS-API-014
    dependent_si_ids:
      - SI-IL
    verification_refs:
      - IEC-62304-5.3.3
      - tests/integration/test_express_routing.py
    status: ready
    notes: ""

  - id: SOUP-002
    name: "lodash"
    version: "4.17.21"
    supplier: "unknown"
    source_url: "https://github.com/lodash/lodash"
    license_spdx: "MIT"
    purpose: ""
    risk_class: unset
    dependent_requirements: []
    dependent_si_ids: []
    verification_refs: []
    status: needs_review
    notes: ""
```

## Example: Record Cross-Referencing a Hazard

```yaml
- id: SOUP-007
  name: "openssl"
  version: "3.2.1"
  supplier: "OpenSSL Software Foundation"
  source_url: "https://www.openssl.org"
  license_spdx: "Apache-2.0"
  purpose: "TLS termination for the cloud sync channel"
  risk_class: A
  dependent_requirements:
    - SRS-SEC-001
    - SRS-SEC-004
  dependent_si_ids:
    - SI-WA
  verification_refs:
    - IEC-62304-5.3.3
    - IEC-62304-7.1.1
    - H-08
    - tests/security/test_tls_handshake.py
  status: ready
  notes: "Hazard H-08 covers the failure mode where openssl returns an unverified peer cert"
```

The `verification_refs[]` list mixes a clause id, a hazard id, and a test file path -- the
schema permits all three forms because each one is a valid pivot point for an auditor.

## Schema Evolution

Schema changes are versioned via `_meta.schema`. The current major is `1`. Bump rules:

| Change | Bump |
|--------|------|
| Add a new optional field | Minor -- `1.0.0` -> `1.1.0`. Older consumers ignore the field. |
| Add a new allowed `status` value | Minor -- existing entries unchanged; older consumers should warn rather than fail on unknown statuses. |
| Add a new allowed `risk_class` value | Major -- existing classification logic depends on the closed enum. |
| Rename or remove a field | Major -- `1.x.x` -> `2.0.0`. Consumers must guard on the major. |
| Change the meaning of an existing field | Major. |

The `soup-inventory` skill writes the matching schema version into `_meta.schema` on every
write. External tooling that consumes `soup.yaml` should refuse to parse when the major does
not match the schema this file documents.

## Cross-references

- Per-language lockfile parsing: `discovery-sources.md`
- Default license allow-list / forbid-list: `license-policy.md`
- Skill body that produces records: `../SKILL.md`
- Sibling matrix consumer: `../../traceability/reference/matrix-schema.md` (see `soup_ids[]` row field)
- Sibling risk-side consumer: `../../risk-control/reference/risk-record-schema.md`
- Parent epic: `kcenon/claude-config#588`
