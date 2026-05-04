---
name: soup-inventory
description: "Maintain a SOUP (Software Of Unknown Provenance) register for every third-party software item the project depends on. Discovers candidates from lockfiles (package-lock.json, go.sum, Cargo.lock, requirements.txt, pyproject.toml, pom.xml, packages.lock.json), enriches with human-supplied risk class and verification refs, validates against a license allow-list and the requirements catalogue, and emits a per-supplier report. Outputs docs/.index/soup.yaml plus docs/.index/soup.md. Subcommands: discover | enrich | validate | list | report. Bidirectional linking with traceability via the soup_ids[] field on requirement rows. Opt-in: no-op when no lockfile is detected and docs/.index/soup.yaml is absent. Atomic writes (*.tmp + rename); idempotent (records sorted by id). Implements IEC 62304 sections 5.3.3 (SOUP requirements) and 8.1.1 (configuration items)."
argument-hint: "<discover|enrich|validate|list|report> [--ci] [--verbose]"
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
  - { type: success, expr: "subcommand completed successfully and soup.yaml is well-formed (atomic rename succeeded)" }
  - { type: success, expr: "no-op exit when no lockfile is detected and docs/.index/soup.yaml is absent" }
  - { type: failure, expr: "validate --ci reports a missing record, a forbidden license, an unset risk_class, or a dangling verification reference" }
  - { type: failure, expr: "lockfile/soup-file parse error or write step errors out" }
on_halt: "Print per-record findings table (or no-op message) and exit non-zero on failure, zero on success or no-op"
tiers:
  light:
    ref_docs: []
    deep_checks: false
  standard:
    ref_docs: [schema, sources]
    deep_checks: true
  deep:
    ref_docs: [schema, sources, license]
    deep_checks: true
default_tier: standard
iso_class: A
applies_at_or_above: A
# ref_docs keys:
#   schema  -> reference/soup-record-schema.md
#   sources -> reference/discovery-sources.md
#   license -> reference/license-policy.md
---

# soup-inventory Skill

Maintain the SOUP (Software Of Unknown Provenance) register for projects that have adopted
the regulated-industry track. The skill is the third-party-software counterpart to
`risk-control` (which owns the hazard records) and `traceability` (which owns the
requirements-to-evidence matrix): it produces and maintains the per-project SOUP file that
the traceability matrix references via a new `soup_ids[]` field on each requirement row, and
that the `evidence-pack` skill collects under a future `soup_register` kind.

The skill does not invent regulatory content; it provides a structured, validatable home
for the records that IEC 62304 sections 5.3.3 (specify functional and performance
requirements of SOUP items) and 8.1.1 (identify configuration items) already require.

## Usage

```
/soup-inventory discover                     # Scan lockfiles; produce candidate records (status: needs_review)
/soup-inventory enrich <id>                  # Open editor for human-supplied fields (purpose, risk_class, verification_refs)
/soup-inventory validate                     # Schema + cross-reference + license check (warnings only)
/soup-inventory validate --ci                # Same; exit non-zero on any finding
/soup-inventory list                         # Print a table of all records and their status
/soup-inventory list --verbose               # Same with control_measures and verification expanded
/soup-inventory report                       # Emit docs/.index/soup.md grouped by supplier
```

Exactly one subcommand is required as the first positional argument. The `enrich` subcommand
takes a record id (`SOUP-NNN`) as the second positional argument; the others take none.

## Arguments

| Position / Flag | Behavior |
|-----------------|----------|
| `<subcommand>` (positional, required) | One of `discover`, `enrich`, `validate`, `list`, `report`. Any other value exits non-zero with a usage hint. |
| `<id>` (positional, required for `enrich`) | Record identifier matching `^SOUP-[0-9]{3}$` (see `reference/soup-record-schema.md`). `enrich` refuses an id absent from the register. |
| `--ci` | Applies to `validate`. Exit non-zero on any finding. Intended for the GitHub Actions validate job. |
| `--verbose` | Applies to `list`. Expand `dependent_requirements` and `verification_refs` columns. Otherwise prints only the headline status per record. |

`--ci` is ignored (with a warning) on `discover`, `enrich`, `list`, and `report`.

## Inputs

| Path | Required | Purpose |
|------|----------|---------|
| Project lockfile (any of: `package-lock.json`, `go.sum`, `Cargo.lock`, `requirements.txt`, `pyproject.toml`, `pom.xml`, `packages.lock.json`) | Yes (gate) for `discover`; optional otherwise | Source of candidate SOUP entries. The skill is a no-op when no lockfile is present and `docs/.index/soup.yaml` does not yet exist. |
| `docs/.index/soup.yaml` | Optional on `discover` (created or merged); required on `enrich`/`validate`/`list`/`report` | The SOUP register the skill maintains. See `reference/soup-record-schema.md` for the exact YAML shape. |
| `soup-license-policy.yaml` (repo root) | Optional | Per-project override of the default license allow-list and forbid-list. Defaults documented in `reference/license-policy.md`. |
| `docs/.index/manifest.yaml` | Optional | Used by `validate` to confirm every requirement listed under `dependent_requirements[]` resolves to a real document. Skipped (with a warning) when absent. |
| `compliance/iec-62304.md` | Optional | Source of truth for clause IDs referenced in `verification_refs[]`. When present, `validate` confirms every cited clause exists. Skipped (with one info line) when absent. |

The skill never reads source code, never runs builds, and never calls out to external systems.

## Outputs

| Path | Format | Audience |
|------|--------|----------|
| `docs/.index/soup.yaml` | YAML | Single normalized SOUP register. Consumed by `traceability` (via `soup_ids[]`) and `evidence-pack` (via the future `soup_register` kind). Schema: `reference/soup-record-schema.md`. |
| `docs/.index/soup.md` | Markdown | Human-readable per-supplier report produced by `report`. Suitable for inclusion in audit-time exports. |

Both files are written atomically: the skill writes to a sibling `*.tmp` file and renames on
success. A failed run never produces a half-written artifact. Records are sorted by `id` on
every write to guarantee byte-identical output for unchanged input (idempotency contract,
matches `traceability`, `evidence-pack`, and `risk-control`).

## Opt-in Gate

The skill is purely additive and must not break repos that have not adopted the regulated track.

```bash
if ! detect_lockfile && [[ ! -f docs/.index/soup.yaml ]]; then
    echo "soup-inventory: no lockfile detected and docs/.index/soup.yaml absent -- skill is a no-op for this repo"
    exit 0
fi
```

`detect_lockfile` returns true when any of the lockfiles enumerated in
`reference/discovery-sources.md` is present at the repo root or under a documented
sub-directory. The check runs before any other phase. The exit code is `0` so CI invocations
on non-regulated repos do not fail. To opt in, a consumer project either checks a lockfile
into the repo (the common case) or hand-creates an empty `docs/.index/soup.yaml` (rare).

## Instructions

### Phase 0: Validate Environment

1. Run the opt-in gate above; on no-op, print the message and exit 0.
2. Validate the subcommand is one of `discover`, `enrich`, `validate`, `list`, `report`.
   Otherwise exit non-zero with a usage hint.
3. For `enrich`, validate the second positional argument matches `^SOUP-[0-9]{3}$`. Exit
   non-zero on malformed ids.
4. Detect optional inputs: `soup-license-policy.yaml` at repo root, `docs/.index/manifest.yaml`,
   `compliance/iec-62304.md`. Record their presence; later phases gate on them.
5. If `docs/.index/soup.yaml` exists, parse it and verify `_meta.schema` major matches the
   schema this skill writes (current major: `1`). On a major mismatch, exit non-zero with the
   mismatch detail. Minor mismatches are tolerated; the writer upgrades on next save.

### Phase 1: Dispatch by Subcommand

Each subcommand runs an independent code path. The phases below describe the per-subcommand
behavior. All paths share the Phase 0 gate and the Phase 4 atomic-write step.

#### Subcommand: discover

Reference: `reference/discovery-sources.md` defines the per-language lockfile parsers and the
auto-populated fields each one yields.

1. For each lockfile present, invoke the parser documented in `discovery-sources.md` and
   produce a candidate record per dependency. Auto-populated fields: `name`, `version`,
   `supplier`, `source_url`, and `license_spdx` where the lockfile carries it.
2. Mint a record id of the form `SOUP-NNN` where `NNN` is the next free three-digit slot
   (zero-padded, sorted ascending) not already in the existing register. Reuse the existing
   id when a candidate's `(name, version)` pair already appears in the register.
3. Set `status: needs_review` on every newly created record. Existing records are left
   untouched (the skill never overwrites enrichment data on re-discovery).
4. Set `risk_class: unset` (sentinel) and `purpose: ""` on new records. The operator fills
   these in via `enrich`.
5. Merge the new and existing record lists; proceed to Phase 4 to write the updated register.

#### Subcommand: enrich

1. Refuse if `<id>` is absent from `docs/.index/soup.yaml`.
2. Load the existing record into memory.
3. Prompt the operator for each enrichment field listed in `reference/soup-record-schema.md`
   "Enrichment Fields" section, prefilling current values:
   - `purpose` (one-line description of why this SOUP is used)
   - `risk_class` (one of `A`, `B`, `C`; matches IEC 62304 software item classification)
   - `dependent_requirements[]` (list of `SRS-{CAT}-{NNN}` ids that depend on this SOUP)
   - `dependent_si_ids[]` (list of `SI-{CODE}` design ids that allocate this SOUP)
   - `verification_refs[]` (list of clause ids, requirement ids, or evidence file paths)
4. On successful submission, set `status: ready`. Auto-populated fields (`name`, `version`,
   `supplier`, `source_url`, `license_spdx`) are not editable through `enrich`; they are
   refreshed only by `discover`.
5. Replace the in-memory record; proceed to Phase 4.

#### Subcommand: validate

Reference: `reference/license-policy.md` defines the default allow-list and the override
mechanism. `reference/soup-record-schema.md` "Validation Rules" defines the full finding set.

1. Load every record from `docs/.index/soup.yaml`.
2. Cross-check the lockfile entry list against the register: every lockfile entry must have a
   matching SOUP record (finding `lockfile_entry_without_record`). Records present in the
   register but absent from the lockfile are warned only (the dependency may have been
   removed; the operator decides whether to retire the record).
3. For each record in the register, run the validation checks documented in
   `reference/soup-record-schema.md`, which cover at minimum:
   - `risk_class` is one of `A`, `B`, `C` (finding `risk_class_unset` when value is `unset`).
   - `license_spdx` is in the active allow-list and not in the forbid-list (findings
     `license_outside_allow_list` and `license_in_forbid_list`).
   - Every `dependent_requirements[]` entry resolves to a `SRS-*` id present in
     `manifest.yaml` (when manifest is available; finding `dangling_requirement_ref`).
   - Every `verification_refs[]` entry resolves to one of: a clause id present in
     `compliance/iec-62304.md` (when present), a `SRS-*` id present in `manifest.yaml`, or
     a repo-relative file path that exists on disk (finding `dangling_verification_ref`).
   - `status` is one of `needs_review` or `ready`.
4. Print the findings table to stdout. Format documented in
   `reference/soup-record-schema.md` "Validation Output" section.
5. In `--ci` mode, exit non-zero on any finding. Default mode emits warnings and exits 0.
6. `validate` does not write to disk; skip Phase 4.

#### Subcommand: list

1. Load every record from `docs/.index/soup.yaml`.
2. Print a Markdown table sorted by `id`. Default columns: `id`, `name`, `version`,
   `license_spdx`, `risk_class`, `status`. With `--verbose`, additionally expand
   `dependent_requirements` and `verification_refs` as nested rows under each record.
3. `list` does not write to disk; skip Phase 4.

#### Subcommand: report

1. Load every record from `docs/.index/soup.yaml`.
2. Group records by `supplier`. Within each group, sort by `id`.
3. Render `docs/.index/soup.md.tmp` with one section per supplier. Each section contains a
   table of records and a list of dependent requirements / design items, suitable for
   inclusion in audit-time exports.
4. Atomically rename `docs/.index/soup.md.tmp` to `docs/.index/soup.md`. On any error,
   delete the `*.tmp` file and exit non-zero.
5. `report` does not modify `soup.yaml`; skip Phase 4 for the YAML file.

### Phase 4: Atomic Write

Skip when subcommand is `validate`, `list`, or `report` (the latter writes its own atomic
file under `report`'s Phase 1 step 4), or when no record changed.

1. Sort the in-memory record list by `id` (stable, ASCII order). Recompute `_meta.generated`
   timestamp.
2. Render the YAML using the canonical layout in `reference/soup-record-schema.md`. Empty
   list fields are emitted as `[]`, never as `~` or as an omitted key, so consumers never
   need to distinguish "absent" from "empty".
3. Write to `docs/.index/soup.yaml.tmp`.
4. On success, rename to `docs/.index/soup.yaml`. On any error, delete the `*.tmp` file and
   exit non-zero.

### Phase 5: Report

Emit a one-line summary on stdout per subcommand:

| Subcommand | Summary line |
|------------|--------------|
| `discover` | `soup-inventory: discovered <N> candidates from <M> lockfile(s); records=<R> (new=<X>, existing=<E>)` |
| `enrich` | `soup-inventory: enriched <id> (risk_class=<A|B|C>); records=<N>` |
| `validate` | `soup-inventory: validated <N> records; findings=<F> (errors=<E>, warnings=<W>)` |
| `list` | `soup-inventory: listed <N> records` |
| `report` | `soup-inventory: wrote docs/.index/soup.md with <S> supplier sections covering <N> records` |

Append the per-finding or per-record table required by the subcommand to stdout above the
summary.

## Bidirectional SOUP-Requirement Linking

Each SOUP record carries `dependent_requirements[]` and `dependent_si_ids[]` lists naming
the SRS and SI ids that depend on this third-party component. The link is one-directional in
the SOUP file (SOUP -> requirements), but the next `traceability` skill run picks it up in
the other direction without any new wiring: the matrix row schema reserves `soup_ids[]` on
every requirement row (see `traceability/reference/matrix-schema.md`), and the matrix's
Phase 1 step would collect SOUP ids from `docs/.index/soup.yaml` when it is present. When
the SOUP register is the source of truth, the matrix's SOUP-side data source is this skill
rather than ad-hoc registries.

The integration contract is: `soup-inventory` owns the SOUP records; `traceability` reads
them and stitches them into the matrix. No bidirectional write coordination is required
because the SOUP register is the single source of truth for third-party-component metadata.

## Output

The skill produces only `docs/.index/soup.yaml` (and, for `report`, `docs/.index/soup.md`)
plus the on-stdout summary. No other files in the consumer project are modified -- in
particular, the skill never edits `manifest.yaml`, `bundles.yaml`, `graph.yaml`,
`router.yaml`, `traceability.yaml`, or `risk-file.yaml`. Those remain `doc-index`'s,
`traceability`'s, and `risk-control`'s responsibilities.

## Error Handling

| Condition | Action |
|-----------|--------|
| No lockfile detected and `docs/.index/soup.yaml` absent | No-op exit 0 (opt-in gate, see Phase 0). |
| Subcommand argument missing or invalid | Exit non-zero with usage hint. |
| `<id>` malformed for `enrich` | Exit non-zero with the expected format from the schema. |
| `enrich` invoked with an absent id | Exit non-zero with the suggestion to run `discover` first. |
| `_meta.schema` major mismatch on existing SOUP file | Exit non-zero with the detected vs. expected schema versions. |
| Lockfile parse error during `discover` | Exit non-zero with the lockfile path and the parse error; do not partially update the register. |
| `soup-license-policy.yaml` malformed | Exit non-zero with the YAML parse error and the offending line. |
| Validation finding in `--ci` mode | Print the finding table, exit non-zero. (Per IEC 62304 8.1.1, an unidentified configuration item must not pass review; CI mirrors that policy.) |
| Validation finding in default mode | Print the finding table, exit 0. |
| Write step fails (permission, disk) | Delete the `*.tmp` file, report the path, exit non-zero. |
| `compliance/iec-62304.md` referenced but absent | Skip clause validation; print one informational line; do not fail. |

## Policies

### Side Effects and Loop-Safety

This skill is `loop_safe: true`. The `validate`, `list`, and `report` subcommands are pure
reads of the YAML register (with `report` writing only the regenerated Markdown view, which
the idempotency contract makes safe). The `discover` subcommand is also idempotent: re-running
on an unchanged lockfile produces a byte-identical register because (a) ids are stable for
existing `(name, version)` pairs and (b) records are sorted by id on every write. The
`enrich` subcommand is gated by operator input, so wrapping in `/loop` would no-op after the
first prompt -- safe but pointless.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Inputs | Lockfiles enumerated in `reference/discovery-sources.md`, `docs/.index/{manifest,soup}.yaml`, optional `soup-license-policy.yaml`, optional `compliance/iec-62304.md`. The skill never crawls source-code directories. |
| Outputs | Only `docs/.index/soup.yaml` and `docs/.index/soup.md`. No other file is touched. |
| Opt-in | No lockfile and no existing register is a no-op exit 0, never a failure. |
| Atomicity | Writes go to `*.tmp` first, then rename on success. Failure deletes the temp file. |
| Idempotency | Same input always produces byte-identical output. Re-running `discover` on an unchanged lockfile is a no-op; re-running `report` produces a byte-identical Markdown file. |
| Bidirectional linking | One-directional in the SOUP file (SOUP -> requirements). `traceability` reads it and produces the inverse view in the matrix. |
| External submission | Never. Submission to eQMS / regulator portals is out of scope. |
| CVE / vulnerability scanning | Out of scope. The register tracks provenance, license, and verification, not vulnerabilities. A separate skill (future) handles the CVE channel. |

### Validation Message Style

When `validate --ci` reports a finding, the message must include the relevant IEC 62304
clause id (e.g. `IEC-62304-5.3.3` for a missing SOUP requirement, `IEC-62304-8.1.1` for a
missing configuration item) so an auditor reading the CI log can pivot directly to the
standard. The clause-to-finding mapping is documented in
`reference/soup-record-schema.md` "Validation Rules" -- the skill body must use that table
verbatim rather than inventing new mappings.

## How Other Components Use the SOUP Register

| Consumer | Use |
|----------|-----|
| `traceability` skill (P0-1) | Reads `soup.yaml` to populate `soup_ids[]` on requirement matrix rows. Bidirectional linking comes for free. |
| `evidence-pack` skill (P1-1) | Will mirror `soup.yaml` (and the per-supplier `soup.md` report when present) under a future `soup_register` kind in the per-release evidence pack. The current `evidence-pack` source-mapping does not yet enumerate this kind; a follow-up issue will add it. |
| `risk-control` skill (P1-2) | Cross-references SOUP records when a hazard's failure mode involves third-party software; the link is recorded as a `verification_refs[]` entry pointing to the relevant `H-NN` id. |
| `traceability-guard` PreToolUse hook (P0-2) | Could be extended to detect when a PR adds or bumps a lockfile entry without updating the SOUP register. |
| External auditor | Reads `soup.yaml` and `soup.md` directly from the repo at any tagged release; consumes them alongside the matrix as the operational SOUP-management record. |

## References

- SOUP record schema: `reference/soup-record-schema.md`
- Per-language discovery sources: `reference/discovery-sources.md`
- Default license policy and per-project override format: `reference/license-policy.md`
- IEC 62304 clause source: `compliance/iec-62304.md` (project root, when present)
- Sibling matrix consumer: `global/skills/_internal/traceability/SKILL.md`
- Sibling release-time consumer: `global/skills/_internal/evidence-pack/SKILL.md`
- Sibling risk-side consumer: `global/skills/_internal/risk-control/SKILL.md`
- Parent epic: `kcenon/claude-config#588`
- Originating issue: `kcenon/claude-config#601`
