# Compliance Rules — Per-Standard Index

Path-triggered rule files mapping safety-standard clauses to project evidence. Each file is a YAML-frontmatter rule loaded only when matching paths are touched (see `paths:` in each file). Clause IDs follow the format `<STANDARD>-<NUMBER>` (e.g. `IEC-62304-5.1.7`) and are consumed by the `traceability` skill's matrix `clause_refs[]` field — once published, treat IDs as permanent.

> **Distinction from `enterprise/rules/compliance.md`**: that file remains the authority for organization-wide controls (SOC 2, GDPR, ISO 27001). This directory is the authority for product-safety standards a regulated-industry medical / automotive / functional-safety project must demonstrate against.

## Populated Standards

| File | Standard | Scope |
|------|----------|-------|
| `iec-62304.md` | IEC 62304:2006 + Amd 1:2015 | Medical-device software lifecycle (planning, requirements, architecture, unit verification, integration, system testing, release, maintenance, risk management within software, configuration management, problem resolution) |
| `iso-13485.md` | ISO 13485:2016 | QMS clauses that intersect with software change control (computer-software validation, document and record control, design and development cycle, process validation for software builds, monitoring, improvement) |
| `iso-14971.md` | ISO 14971:2019 | Risk-management process for medical devices (analysis, evaluation, control with the priority hierarchy, residual risk, post-production information) |

## Future-Work Standards (Out of Scope for This Iteration)

The following standards are queued for a follow-up issue once the three populated files are stable. Contributions welcome on the same template.

| Standard | Domain | Notes |
|----------|--------|-------|
| ISO 26262 | Automotive functional safety | Multi-part (parts 2–9 software-relevant). ASIL classification adds an axis comparable to IEC 62304's Class A/B/C. |
| IEC 61508 | General functional safety | The parent standard from which ISO 26262 was derived. Covers SIL classification and proven-in-use arguments. |
| DO-178C | Airborne software | Aviation; assurance levels A–E. Heavy emphasis on structural coverage that the matrix would need to track. |

## How to Extend

To add a new standard rule file:

1. Pick a filename matching the existing kebab-case pattern (`iso-26262.md`, `iec-61508.md`, `do-178c.md`).
2. Start with the YAML frontmatter contract:
   ```yaml
   ---
   name: compliance-<standard-id>
   description: <one-line scope>
   alwaysApply: false
   paths:
     - <glob1>
     - <glob2>
   ---
   ```
   The `paths:` list is the on-demand loader's trigger — list the consumer-project glob patterns whose changes invoke clauses from this standard.
3. Mint stable clause IDs as `<STANDARD>-<NUMBER>` where `<STANDARD>` is the uppercase abbreviated name with hyphens preserved (`IEC-62304`, `ISO-26262`) and `<NUMBER>` is the dotted clause path verbatim from the standard. Multi-part standards include the part number, e.g. `ISO-26262-6-7.4.13`.
4. For each clause entry, use the anchor format on its own line so the `traceability` skill can discover it:
   ```markdown
   > **Clause**: <STANDARD>-<NUMBER>
   - **Subject**: short title
   - **Paraphrase**: ≤2 sentences in your own words
   - **Evidence required**: artifacts a reviewer can point at
   - **Triggers**: project-path conditions that invoke the clause
   ```
5. Never quote standard text verbatim. ISO and IEC hold copyright on the normative text; paraphrase or omit and note the omission here.
6. Update the "Populated Standards" table above with the new entry.

## Conventions

- **Stable IDs are a hard contract**: existing `clause_refs[]` rows in downstream `traceability.yaml` artifacts will break if an ID is renamed. If a clause must be split or deprecated, retire the old ID with a note rather than reusing it.
- **Paraphrase, do not quote**: see point 5 above. If you cannot paraphrase a clause without losing its meaning, omit it and add a one-line note to this README explaining the omission so the gap is visible.
- **Class / ASIL / SIL applicability**: when a standard scales obligations by class (IEC 62304 A/B/C, ISO 26262 ASIL A-D, IEC 61508 SIL 1-4), record the applicable class on each clause entry. Consumers filter clauses by class at policy-load time.
- **Scope discipline**: include only clauses a single PR or change can violate. QMS-level process clauses (annual reviews, training programs at the organization level) belong to the QMS owner, not the per-change author. Document scope decisions in each file's "Scope" section.

## Cross-references

- Traceability matrix schema (`clause_refs[]` definition): `global/skills/_internal/traceability/reference/matrix-schema.md`
- Validation finding `dangling_clause_ref` definition: `global/skills/_internal/traceability/reference/validation-rules.md`
- Sibling enforcement layer (PreToolUse hook): `global/hooks/traceability-guard.sh`
- Organization-wide compliance (SOC 2 / GDPR / ISO 27001): `enterprise/rules/compliance.md`
