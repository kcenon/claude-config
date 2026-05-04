# SOUP License Policy

Default license allow-list and forbid-list applied by the `soup-inventory` skill's
`validate` subcommand, and the per-project override mechanism for both lists.

> **Loading**: Loaded under `tier: deep` only via the skill's `ref_docs.license` entry. The
> default lists below are small enough that `tier: standard` operates from the SKILL.md
> body's reference. Load this file when authoring a project-specific override or when
> investigating an unexpected `license_outside_allow_list` finding.

## Default Allow-List

The default allow-list covers the licenses that are unambiguously safe for proprietary
medical / regulated-industry products to consume without distribution-level obligations:

| SPDX ID | License Name | Notes |
|---------|--------------|-------|
| `MIT` | MIT License | Permissive; no source disclosure on distribution. |
| `Apache-2.0` | Apache License 2.0 | Permissive; explicit patent grant. |
| `BSD-2-Clause` | BSD 2-Clause "Simplified" License | Permissive. |
| `BSD-3-Clause` | BSD 3-Clause "New" or "Revised" License | Permissive. |
| `BSD-0-Clause` | BSD Zero Clause License | Public-domain equivalent. |
| `ISC` | ISC License | Functionally equivalent to BSD-2-Clause. |
| `Unlicense` | The Unlicense | Public-domain dedication. |
| `CC0-1.0` | Creative Commons Zero v1.0 Universal | Public-domain dedication. |
| `Zlib` | zlib License | Permissive. |
| `BlueOak-1.0.0` | Blue Oak Model License 1.0.0 | Modern permissive license. |
| `Python-2.0` | Python Software Foundation License 2.0 | Permissive; CPython interpreter. |
| `PostgreSQL` | PostgreSQL License | Permissive; substantially MIT. |

The default list is intentionally narrow. Anything outside this set requires an explicit
project override (see "Per-Project Override" below) accompanied by a documented rationale
that an auditor can review.

## Default Forbid-List

The default forbid-list covers licenses whose obligations are typically incompatible with
proprietary distribution of medical / regulated-industry software:

| SPDX ID | License Name | Reason |
|---------|--------------|--------|
| `GPL-1.0` | GNU General Public License v1.0 only | Strong copyleft. |
| `GPL-1.0-only` | GNU General Public License v1.0 only | Strong copyleft. |
| `GPL-2.0` | GNU General Public License v2.0 only | Strong copyleft. |
| `GPL-2.0-only` | GNU General Public License v2.0 only | Strong copyleft. |
| `GPL-3.0` | GNU General Public License v3.0 only | Strong copyleft + patent retaliation. |
| `GPL-3.0-only` | GNU General Public License v3.0 only | Strong copyleft + patent retaliation. |
| `GPL-3.0-or-later` | GNU General Public License v3.0 or later | Strong copyleft + patent retaliation. |
| `AGPL-3.0` | GNU Affero General Public License v3.0 | Network-use disclosure obligation. |
| `AGPL-3.0-only` | GNU Affero General Public License v3.0 only | Network-use disclosure obligation. |
| `AGPL-3.0-or-later` | GNU Affero General Public License v3.0 or later | Network-use disclosure obligation. |
| `SSPL-1.0` | Server Side Public License 1.0 | Source-available, not OSI-approved. |
| `BUSL-1.1` | Business Source License 1.1 | Source-available with use restrictions. |
| `Commons-Clause` | Commons Clause | Restricts commercial use. |

The default forbid-list is conservative: a project may legitimately use a copyleft license
in a way that does not violate its terms (e.g. an internal-only tool that is never
distributed). In that case, the project explicitly removes the entry from the forbid-list
in its override file with a documented rationale.

## Licenses That Require Per-Project Decision

These licenses are neither in the default allow-list nor the default forbid-list -- the
project must declare a stance for each one it consumes. The skill emits
`license_outside_allow_list` for each occurrence until a project-specific override either
allows or forbids the license:

| SPDX ID | License Name | Typical Concern |
|---------|--------------|-----------------|
| `LGPL-2.0` / `LGPL-2.1` / `LGPL-3.0` | GNU Lesser GPL | Weak copyleft; static linking implications must be reviewed. |
| `MPL-1.1` / `MPL-2.0` | Mozilla Public License | File-level copyleft; review whether modified files are distributed. |
| `EPL-1.0` / `EPL-2.0` | Eclipse Public License | File-level copyleft + patent retaliation. |
| `CDDL-1.0` / `CDDL-1.1` | Common Development and Distribution License | File-level copyleft. |
| `CC-BY-*` / `CC-BY-SA-*` | Creative Commons (attribution / share-alike) | Mostly used for documentation; copyleft variants need review. |
| `OFL-1.1` | SIL Open Font License | Permissive but with naming restrictions. |
| `OpenSSL` | OpenSSL License | Pre-3.0 OpenSSL; 3.0 onwards is Apache-2.0. |
| `Artistic-1.0` / `Artistic-2.0` | Artistic License | Perl ecosystem; review distribution clauses. |
| `WTFPL` | Do What The F*ck You Want To Public License | OSI-controversial; some projects forbid its use. |

`UNKNOWN` is also treated as outside the allow-list -- the skill always emits
`license_unknown` for records whose `license_spdx` is `UNKNOWN`, regardless of the override
file.

## Per-Project Override

A consumer project overrides the default lists by checking in
`soup-license-policy.yaml` at the repo root. Format:

```yaml
# soup-license-policy.yaml
# Per-project license policy for the soup-inventory skill
# Schema version
schema: "1.0.0"

allow:
  - SPDX_ID         # Adds to the default allow-list
  - SPDX_ID

forbid:
  - SPDX_ID         # Adds to the default forbid-list
  - SPDX_ID

allow_remove:
  - SPDX_ID         # Removes from the default allow-list (rare; usually only after a project decision to ban a previously allowed license)

forbid_remove:
  - SPDX_ID         # Removes from the default forbid-list (e.g. an internal-only tool that does not distribute and so can use GPL-2.0)

# Per-record exemptions for one-off cases
exemptions:
  - id: SOUP-007
    license_spdx: "LGPL-2.1"
    rationale: "Dynamic linking only; LGPL terms satisfied per legal review 2025-12-01"
    approved_by: "compliance-officer"
    approved_at: "2025-12-01"

# Per-ecosystem skip flags (consumed by discovery-sources.md parsers)
npm:
  skip_dev: false
maven:
  skip_test: false
go:
  skip_incompatible: false

# Optional skip-list (see discovery-sources.md "Skip-List Mechanism")
skip:
  - name: "internal-mirror-pkg"
    version: "*"
    reason: "Audited via internal-quality-system"
```

### Override Resolution Order

The `validate` subcommand resolves the active allow-list and forbid-list as follows:

1. Start with the default allow-list.
2. Add every entry in the override's `allow:` list.
3. Remove every entry in the override's `allow_remove:` list.
4. Start with the default forbid-list.
5. Add every entry in the override's `forbid:` list.
6. Remove every entry in the override's `forbid_remove:` list.
7. For each record being validated, check the override's `exemptions:` list first; an
   exemption with matching `id` and `license_spdx` skips both the allow-list and
   forbid-list checks for that record (the rationale is logged on stdout for the audit
   trail).

A license appearing in both the allow-list and the forbid-list after merging is a hard
configuration error (`policy_conflict`); the skill exits non-zero with the conflicting SPDX
id and the relevant override stanzas.

## Exemption Discipline

Exemptions are first-class records in the audit trail. Each exemption must carry:

| Field | Required | Purpose |
|-------|----------|---------|
| `id` | Yes | The `SOUP-NNN` id this exemption applies to. |
| `license_spdx` | Yes | The exact SPDX id being exempted. The exemption does not extend to a different version of the same license. |
| `rationale` | Yes | One-line explanation. Auditors read this; keep it factual and citable. |
| `approved_by` | Yes | Role name (not a person; roles outlive employees). |
| `approved_at` | Yes | ISO 8601 date the approval was recorded. |

Exemptions without a `rationale` field are rejected at policy-load time. Rationales such as
`"approved"` or `"OK"` are technically permitted but should be flagged in PR review --
auditors will challenge them.

## SPDX Identifier Style

The skill compares `license_spdx` values using exact string match against the SPDX License
List (https://spdx.org/licenses/). Common normalization rules:

- Use `Apache-2.0`, not `Apache 2.0` or `ASL-2.0`.
- Use `BSD-3-Clause`, not `New BSD` or `BSD3`.
- Use `MIT`, not `Expat` (Expat is the SPDX deprecated alias).
- For dual-licensed packages, use the SPDX expression form: `(MIT OR Apache-2.0)`. The
  skill treats expressions as satisfying the allow-list when at least one operand is in the
  allow-list and none of the operands are in the forbid-list.

The skill does not maintain a synonym table -- licenses that lockfiles report under
non-SPDX names (e.g. `BSD` for an unspecified BSD variant) are resolved to `UNKNOWN` and
the operator must specify the exact SPDX id during `enrich`.

## Cross-references

- Where license values come from: `discovery-sources.md`
- Record field that carries the SPDX id: `soup-record-schema.md`
- Skill body that applies these rules: `../SKILL.md`
- SPDX License List authority: https://spdx.org/licenses/
