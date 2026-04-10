---
name: doc-index
description: "Generate document index files (manifest, bundles, graph, router) for project documentation. Creates docs/.index/ with searchable registry, feature-grouped bundles, cross-reference dependency graph, and query routing. Supports flat mode (generic projects) and grouped mode (projects with doc_id frontmatter for streamliner-level output)."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
---

# Document Index Generator

Generate structured YAML index files for project documentation.

## Usage

```
/doc-index
```

No arguments. Operates on the current project directory.

## Output Files

| File | Purpose | Flat Mode | Grouped Mode |
|------|---------|-----------|--------------|
| `docs/.index/manifest.yaml` | Document registry with metadata, sections, and tags | `documents:` array | Categorized groups (core, screens, flows, reference) |
| `docs/.index/bundles.yaml` | Feature-grouped document sets | Path-based bundles with token estimates | SI/workflow/cross-cutting bundles with line ranges |
| `docs/.index/graph.yaml` | Cross-reference dependency graph | `nodes:` outgoing references | `cascade:` + `req_chains:` + `hazard_map:` |
| `docs/.index/router.yaml` | Query-to-bundle routing | `routes:` keyword mapping | `id_routes:` + `intent_routes:` |

## Mode Detection

The script auto-detects the output mode:

- **Flat mode**: Default for generic projects. When <50% of files have `doc_id` in YAML frontmatter.
- **Grouped mode**: When >50% of files have `doc_id` frontmatter. Produces streamliner-quality output with categorized manifest, line-ranged bundles, cascade graphs, and ID routing.

## Instructions

### Phase 0: Validate Environment

1. Verify current directory contains `.md` files
2. Create `docs/.index/` directory if it does not exist
3. If `bundles.yaml` already exists, its `custom:` section will be preserved automatically

### Phase 1: Generate Index Files

Run the bundled generation script:

```bash
bash "${SKILL_DIR}/scripts/generate-index.sh" "$(pwd)"
```

Where `${SKILL_DIR}` is the directory containing this SKILL.md file. Locate it with:

```bash
SCRIPT=$(find ~/.claude -path "*/doc-index/scripts/generate-index.sh" -type f 2>/dev/null | head -1)
bash "$SCRIPT" "$(pwd)"
```

The script:
1. Discovers all `.md` files recursively (excluding `.git/`)
2. Pre-processes: caches frontmatter, sections (## headings with line ranges), doc_ids, titles
3. Detects mode (flat vs grouped) based on `doc_id` prevalence
4. Classifies documents by category, scope, and manifest group
5. Generates four YAML files with `_meta` headers
6. Preserves `custom:` section in `bundles.yaml` and `id_patterns:` in `router.yaml`

### Phase 2: Report Results

After the script completes, read the summary output and present it to the user.

## Grouped Mode Features

When `doc_id` frontmatter is detected, the script produces:

### manifest.yaml — Categorized Registry
- `core:` — Main regulatory/design documents with full metadata (sections, req_count, tc_count, si, hazards)
- `screens:` — UI screen specs in compact format with hazard mapping
- `flows:` — User flow specs with screen references
- `reference:` — Subcategorized (regulatory, rendering, infrastructure, security, clinical, business, standards)
- `placeholders:` — Stub documents
- `reports:` — Progress reports

### bundles.yaml — Line-Ranged Bundles
- `si-xx:` — Software Item bundles with SDS section line ranges
- `workflow-*:` — Clinical workflow bundles with screen references
- Cross-cutting: `security:`, `safety:`, `database:`, `api:`, `testing:`, `regulatory-submission:`
- File entries: `{file: path.md, lines: "start-end", note: "context"}`

### graph.yaml — Impact Analysis
- `cascade:` — Document-level impact chains (when X changes, review Y)
- `screen_cascade:` — Screen → flow mappings with hub detection
- `req_chains:` — Requirement category → SI, screen, hazard, test case mapping
- `hazard_map:` — Hazard → affected screens

### router.yaml — Query Routing
- `id_routes:` — Pattern-based routing with section_map (from `id_patterns:`)
- `intent_routes:` — Keyword → bundle mapping (Korean + English)

## How Claude Uses the Index Files

| Scenario | Claude Action |
|----------|---------------|
| "What docs exist about X?" | `Read router.yaml` → match keyword → `Read bundles.yaml` for that bundle |
| "I'm working on feature X" | `Read bundles.yaml` → find matching bundle → `Read` each doc with line ranges |
| "I changed file X" | `Read graph.yaml` → find cascade targets → generate impact checklist |
| "What does SRS-CALC-001 say?" | `Read router.yaml` → id_routes.SRS → section_map.CALC → read exact lines |
| "Which screens has H-07?" | `Read graph.yaml` → hazard_map.H-07 → list affected screens |

## ID Pattern Support

For projects with formal identifiers (e.g., `SRS-DATA-001`, `H-01`, `SCR-003`), add declarations to the bottom of `router.yaml`:

```yaml
id_patterns:
  - prefix: SRS
    source: docs/software-requirements-specification.md
  - prefix: H
    source: docs/reference/iso-14971-risk-management.md
  - prefix: SCR
    source: docs/ui/screens/    # directory source: file-per-ID
```

Then re-run `/doc-index`. In grouped mode, the script generates full `id_routes:` with `section_map` entries mapping categories to line ranges. In flat mode, it generates `identifiers:` with format detection and cross-references.

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Scope | Only `.md` files, excluding `.git/` |
| Idempotent | Running twice produces identical output (except date in `_meta`) |
| Custom bundles | `custom:` section in `bundles.yaml` is never overwritten |
| ID patterns | `id_patterns:` section in `router.yaml` is never overwritten |
| No dependencies | Pure bash — no yq, jq, python, or node required |
| Line endings | Handles both LF and CRLF input; outputs LF |
| Code blocks | References inside fenced code blocks are excluded from graph |

## Output

After completion, provides summary:

```markdown
## Document Index Generated

| Metric | Value |
|--------|-------|
| Mode | flat/grouped |
| Total documents | N |
| Documents with sections | N |
| manifest.yaml | X bytes |
| bundles.yaml | Y bytes |
| graph.yaml | Z bytes |
| router.yaml | W bytes |
| **Total index** | **T bytes** |
| Cross-references | N |
| Generation time | Ts |
```

## Error Handling

| Error Condition | Behavior |
|-----------------|----------|
| No .md files found | Exit with error message |
| Unresolvable reference | Skip silently (reference target may not exist) |
| Missing docs/.index/ | Created automatically |
| Existing index files | Overwritten (except custom/id_patterns sections) |
| ID pattern source not found | Warning, skip that pattern |
| No doc_id in frontmatter | Falls back to flat mode |
