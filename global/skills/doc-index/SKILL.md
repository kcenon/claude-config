---
name: doc-index
description: "Generate document index files (manifest, bundles, graph) for project documentation. Creates docs/.index/ with searchable registry, feature-grouped bundles, and cross-reference dependency graph. Use when documentation structure changes, new files are added, or you need to understand document relationships."
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

| File | Purpose | Target Size |
|------|---------|-------------|
| `docs/.index/manifest.yaml` | Document registry with metadata and tags | ~50KB |
| `docs/.index/bundles.yaml` | Feature-grouped document sets with token estimates | ~13KB |
| `docs/.index/graph.yaml` | Cross-reference dependency graph (outgoing only) | ~12KB |
| `docs/.index/router.yaml` | Keyword-to-bundle query routing | ~2KB |

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
# Find the script relative to the skill location
SCRIPT=$(find ~/.claude -path "*/doc-index/scripts/generate-index.sh" -type f 2>/dev/null | head -1)
# Or if in a plugin/project layout:
SCRIPT=$(find . -path "*/doc-index/scripts/generate-index.sh" -type f 2>/dev/null | head -1)

bash "$SCRIPT" "$(pwd)"
```

The script:
1. Discovers all `.md` files recursively (excluding `.git/`)
2. Parses YAML frontmatter, headings, and cross-references
3. Classifies documents by category (rule, skill, agent, reference, design, config, root) and scope (global, plugin, project, enterprise, docs, root)
4. Groups documents into feature bundles with token estimates
5. Builds a cross-reference dependency graph from 4 reference patterns:
   - Markdown links: `[text](path.md)`
   - Load directives: `@load: reference/name`
   - See references: `` see `path.md` ``
   - Direct imports: `@./reference/file.md`
6. Generates three YAML files in `docs/.index/`
7. Preserves any existing `custom:` section in `bundles.yaml`

### Phase 2: Report Results

After the script completes, read the summary output and present it to the user.

If any warnings were generated (e.g., unresolved references), report them.

## How Claude Uses the Index Files

After generation, Claude leverages the index files with its built-in tools:

| Scenario | Claude Action |
|----------|---------------|
| "What docs exist about X?" | `Read router.yaml` → match keyword → `Read bundles.yaml` for that bundle |
| "I'm working on feature X" | `Read bundles.yaml` → find matching bundle → `Read` each doc in the bundle |
| "I changed file X" | `Read graph.yaml` → find X's outgoing targets → generate impact checklist |
| "Show me all docs about Y" | `Grep manifest.yaml` for tag/description match → load relevant files |

No additional commands are needed. The YAML files are designed for direct consumption by Claude's `Read` and `Grep` tools.

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Scope | Only `.md` files, excluding `.git/` |
| Idempotent | Running twice produces identical output (except timestamp) |
| Custom bundles | `custom:` section in `bundles.yaml` is never overwritten |
| No dependencies | Pure bash -- no yq, jq, python, or node required |
| Line endings | Handles both LF and CRLF input; outputs LF |
| Code blocks | References inside fenced code blocks are excluded from graph |

## Output

After completion, provide summary:

```markdown
## Document Index Generated

| Metric | Value |
|--------|-------|
| Total documents | N |
| manifest.yaml | X bytes |
| bundles.yaml | Y bytes |
| graph.yaml | Z bytes |
| Cross-references found | N |
| Generation time | Ts |
```

## ID Pattern Support

For projects with formal identifiers (e.g., `SRS-DATA-001`, `H-01`, `SCR-003`), add declarations to the bottom of `router.yaml`:

```yaml
id_patterns:
  - prefix: SRS
    source: docs/requirements/SRS.md
  - prefix: H
    source: docs/safety/threat-model.md
  - prefix: SCR
    source: docs/ui/screens/    # directory source: file-per-ID
```

Then re-run `/doc-index`. The script auto-resolves:
- **Format detection**: compound (`SRS-{CAT}-{NNN}`) vs simple (`H-{NN}`)
- **Category extraction**: discovers DATA, CALC, DISP, etc. with first line and count
- **Directory mapping**: maps `SCR-001` to `SCR-001-login.md`
- **Cross-references**: finds all files referencing each prefix

The `id_patterns` section is preserved across regeneration (same pattern as `bundles.yaml` custom section).

## Error Handling

| Error Condition | Behavior |
|-----------------|----------|
| No .md files found | Exit with error message |
| Unresolvable reference | Skip silently (reference target may not exist) |
| Missing docs/.index/ | Created automatically |
| Existing index files | Overwritten (except custom/id_patterns sections) |
| ID pattern source not found | Warning, skip that pattern |
