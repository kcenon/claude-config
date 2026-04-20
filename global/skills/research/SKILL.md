---
name: research
description: "Conduct structured research on any topic: web search, codebase analysis, and document synthesis into organized reports. Use when investigating technologies, analyzing alternatives, gathering reference materials, fact-checking claims, or producing technical documentation from research. Use this skill whenever the user asks to research, investigate, compare, or survey a topic."
user-invocable: true
disable-model-invocation: true
argument-hint: "<topic> [--depth shallow|standard|deep] [--output file.md] [--sources web|code|both] [--lang en|ko|ja|...] [--template auto|plain] [--integrate] [--reanchor-interval N]"
allowed-tools:
  - WebSearch
  - WebFetch
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
  - Agent
max_iterations: 5
halt_condition: "Depth target reached (shallow=1 round, standard=3, deep=5), OR user confirms sufficient findings, OR no new sources surface for 2 consecutive rounds"
on_halt: "Write report with partial findings and explicit coverage-gap section"
---

# Research Command

Conduct structured research on any topic and produce organized reference documents.

## Usage

```
/research "WebSocket vs SSE for real-time updates"
/research "OAuth 2.0 PKCE flow" --depth deep --output docs/reference/oauth-pkce.md
/research "error handling patterns" --sources code
/research "DICOM SR TID 1500" --output docs/reference/dicom-sr-tid-1500.md --integrate
/research "React Server Components" --lang ko
/research "gRPC vs REST performance" --template plain
```

## Arguments

- `<topic>` (required): Research topic. Accepts any natural language query.

- `[--depth <level>]` (default: `standard`):
  - `shallow` — Quick overview. 1-2 web searches, scan codebase. 3-5 sources. Short report.
  - `standard` — Balanced investigation. 3-5 web searches, pattern analysis. 5-10 sources.
  - `deep` — Thorough investigation. 8-12 web searches, full codebase analysis. 10-20 sources.

- `[--output <path>]` (default: none — output to conversation):
  - File path for saving the report as `.md` file.
  - Triggers context detection (Phase 0-B) to adapt output format.

- `[--sources <type>]` (default: `both`):
  - `web` — Web search and external documentation only.
  - `code` — Codebase analysis only (grep, glob, read).
  - `both` — Combine web and codebase sources.

- `[--lang <code>]` (default: auto-detect, fallback `en`):
  - Override output language. Examples: `en`, `ko`, `ja`, `zh`.
  - If omitted: detect from existing docs in `--output` directory.

- `[--template <mode>]` (default: `auto`):
  - `auto` — Detect conventions from existing docs in output directory.
  - `plain` — Force generic English markdown (no frontmatter adaptation).

- `[--integrate]`:
  - Register the output document in project's document index system.
  - Requires `docs/.index/` or `.index/` to exist.
  - Updates manifest, bundles, and router files.

## Instructions

### Phase 0: Context Analysis

#### 0-A. Topic Analysis

1. Parse the topic into 3-5 core research questions.
2. Determine investigation strategy based on `--depth`:

| Depth | Web Searches | Codebase Scope | Target Sources | Report Sections |
|-------|-------------|----------------|----------------|-----------------|
| `shallow` | 1-2 queries | Related files scan | 3-5 | 4-5 sections |
| `standard` | 3-5 queries | Pattern/usage analysis | 5-10 | 6-8 sections |
| `deep` | 8-12 queries | Full architecture analysis | 10-20 | 8+ sections |

3. If the topic implies comparison (e.g., "A vs B", "comparison", "alternatives"):
   - Plan a comparison matrix in the output.
4. If the topic implies investigation (e.g., "how does X work", "why"):
   - Plan a deep-dive explanation structure.

#### 0-B. Output Context Detection (when `--output` is specified)

Sample up to 3 existing `.md` files in the output directory:

```bash
# Find existing markdown files in the output directory
OUTDIR=$(dirname "$OUTPUT_PATH")
SAMPLES=$(find "$OUTDIR" -maxdepth 1 -name "*.md" -type f | head -3)
```

Detect from samples:

| Item | Detection Method | Fallback |
|------|-----------------|----------|
| **Language** | Character ratio analysis (Korean > 30% → `ko`, etc.) | `en` (or `--lang`) |
| **Frontmatter** | Check first lines for `---` YAML block | No frontmatter |
| **Frontmatter schema** | Extract YAML keys (e.g., `doc_id`, `doc_version`, `approval`) | Skip |
| **Section pattern** | Check heading style (`## 1. Title` vs `## Title`) | Numbered sections |
| **Markers** | Scan for `> **SSOT**:`, `> **Cross-reference**:` patterns | Skip |
| **File naming** | Check sibling files (kebab-case, snake_case, etc.) | kebab-case |
| **Citation style** | Check last section for reference format | Numbered list |

Store detected conventions as the **output profile** for Phase 3.

**Override rules**:
- `--lang` always overrides detected language.
- `--template plain` skips all context detection.

#### 0-C. Index System Detection (when `--integrate` is specified)

```bash
# Search for document index system
INDEX_DIR=""
if [ -d "docs/.index" ]; then INDEX_DIR="docs/.index"
elif [ -d ".index" ]; then INDEX_DIR=".index"
fi
```

If found:
1. Read `manifest.yaml` to understand existing document registry.
2. Read `bundles.yaml` to identify related bundles.
3. Read `router.yaml` to check existing keyword routes.
4. Determine next available document ID (if ID pattern exists).

If not found and `--integrate` was specified:
- Warn: "No index system detected. Skipping integration. Run `/doc-index` to create one."

#### 0-D. Existing Document Check

Before creating a new document:
1. Search the output directory for documents on the same topic.
2. If found, ask whether to **update** existing or **create new**.

### Phase 1: Discovery (Information Gathering)

Execute in parallel where possible using the Agent tool for independent searches.

#### 1-A. Web Sources (when `--sources` includes `web`)

1. Formulate search queries based on core research questions.
   - Include the current year for time-sensitive topics.
   - Use domain-specific terminology for technical topics.

2. Execute `WebSearch` for each query.

3. For promising results, use `WebFetch` to extract detailed content.
   - Prioritize: official documentation, peer-reviewed sources, authoritative blogs.
   - Skip: forums with unverified answers, outdated content (> 2 years for fast-moving tech).

4. Record for each source:
   - URL, title, access date
   - Key findings extracted
   - Confidence level (High / Medium / Low)

#### 1-B. Codebase Sources (when `--sources` includes `code`)

1. Use `Grep` and `Glob` to find topic-related code, configuration, and documentation.

2. Use `Read` to examine relevant files.

3. Record:
   - File path and line ranges
   - Patterns, implementations, or configurations found
   - How the codebase relates to the research topic

#### 1-C. Existing Documentation Sources

1. If an index system was detected (Phase 0-C):
   - Use manifest/router to find related existing documents.
   - Read relevant sections for cross-reference material.

2. If no index system:
   - Scan `docs/`, `reference/`, `README.md` for related content.

### Phase 2: Analysis

#### 2-A. Cross-Validation

- Every factual claim must have at least 2 independent sources.
- Mark single-source claims with confidence indicator.
- Flag contradictory information between sources explicitly.

See `reference/source-evaluation.md` for confidence scoring criteria.

#### 2-B. Synthesis

1. Group findings by research question.
2. Identify key themes and patterns across sources.
3. For comparison topics: build evaluation matrix.
   - Use symbols: `✅` (supported), `⚠️` (partial/conditional), `❌` (not supported).
   - Include numeric scores (1-5) where applicable.
4. For investigation topics: build explanation chain.

#### 2-C. Codebase Relevance (when `--sources` includes `code`)

- Map findings to specific project files, patterns, or decisions.
- Note how research results apply to or conflict with current codebase.

### Phase 3: Synthesis (Document Generation)

#### 3-A. Template Selection

| Condition | Template |
|-----------|----------|
| `--template plain` | Generic English markdown (Template A) |
| `--template auto` + context detected | Adapted template matching existing docs (Template B) |
| `--template auto` + no context | Generic English markdown (Template A) |
| No `--output` (conversation) | Generic English markdown (Template A) |

See `reference/output-templates.md` for complete template definitions.

#### 3-B. Document Assembly

1. Apply the selected template.
2. Write sections in order, populating with Phase 2 analysis results.
3. For context-adapted output (Template B):
   - Replicate detected frontmatter schema with appropriate values.
   - Match section numbering pattern.
   - Include detected markers (SSOT, cross-reference) where applicable.
   - Match citation/reference style.
4. **Language application**:
   - Body text: determined language (`--lang` or detected).
   - Technical terms, acronyms, code identifiers, URLs: always English.
   - Source titles and authors in citations: original language preserved.

#### 3-C. Output

- If `--output` specified: write file using `Write` tool.
  - Verify parent directory exists.
  - If file already exists: confirm overwrite with user.
- If no `--output`: output the full report in the conversation.

### Phase 4: Integration (when `--integrate` is specified)

Requires index system detected in Phase 0-C.

1. **manifest**: Add entry with document metadata (id, file, title, keywords, sections).
2. **bundles**: Add document to relevant existing bundles or suggest new bundle.
3. **router**: Add keyword routes for the new document's topics.
4. Validate all index files after modification.

If integration fails, warn the user and suggest running `/doc-index` for full regeneration.

## Post-Research Workflow

After research output is saved with `--output`:

```
/research "<topic>" --output docs/reference/topic.md    # Generate
/doc-review docs/reference/topic.md                     # Validate
/doc-index                                              # Re-index (alternative to --integrate)
```

### Skill Ecosystem Integration

| Workflow | Usage |
|----------|-------|
| Pre-implementation | `/research` → `/issue-create` → `/issue-work` |
| Documentation | `/research` → `/doc-update` → `/doc-review` → `/doc-index` |
| Security investigation | `/research` → `/security-audit` |
| Performance investigation | `/research` → `/performance-review` |
| Architecture design | `/research` → `/harness` |
| API design | `/research` → `/api-design` guidance |

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| **Default language** | English. Auto-detect from output directory. `--lang` overrides. |
| **Source attribution** | Every factual claim must cite at least one source. |
| **Cross-validation** | Claims must have 2+ independent sources. Single-source claims marked. |
| **Date awareness** | Web searches include current year for time-sensitive topics. |
| **Bias prevention** | Never rely on a single source. Present multiple perspectives. |
| **Existing doc preservation** | Confirm before overwriting existing files. |
| **Technical terms** | Keep in English regardless of output language. |
| **Frontmatter keys** | Keep in English regardless of output language. |
| **Citation originals** | Preserve original language of source titles and authors. |

## Output

### Conversation Output (no `--output`)

A complete research report rendered in the conversation using the generic template.

### File Output (`--output` specified)

A `.md` file matching the detected document conventions of the output directory.

### Summary (always shown)

```markdown
## Research Summary

| Item | Value |
|------|-------|
| Topic | <topic> |
| Depth | shallow / standard / deep |
| Sources | N web, M codebase |
| Output | conversation / <file-path> |
| Language | en / ko / ... |
| Template | plain / adapted |
| Integrated | yes / no / skipped |
```

## Error Handling

### Prerequisite Errors

| Condition | Action |
|-----------|--------|
| Empty topic | Error: "Topic is required" |
| `--output` directory does not exist | Error: "Output directory not found: `<path>`" |
| `--integrate` without index system | Warn and skip integration |
| `--sources web` but WebSearch unavailable | Warn, fall back to `--sources code` |

### Runtime Errors

| Condition | Action |
|-----------|--------|
| WebSearch returns no results | Try alternative queries. If all fail, report and continue with available sources. |
| WebFetch fails for a URL | Skip URL, note in report as "[Inaccessible]". Continue with other sources. |
| Insufficient sources found | Warn in report summary. Lower confidence ratings. |
| Output file already exists | Ask user: overwrite / rename / cancel |
| Index integration fails | Warn and suggest `/doc-index` |

### Quality Gates

Before finalizing the report, verify:

- [ ] All research questions addressed (or explicitly noted as unresolved)
- [ ] Source count meets depth requirement minimum
- [ ] No unsupported claims (every finding has at least one citation)
- [ ] Comparison matrix complete (if applicable)
- [ ] Cross-references to existing project docs included (if `--sources code`)
- [ ] Output language consistent throughout

## Reanchoring Loop Invariants

`--reanchor-interval N` (default 5, `0` disables) controls how often the Core invariants block from `global/skills/_shared/invariants.md` is emitted between research rounds.

Loop bind point: between `shallow`/`standard`/`deep` round iterations. For deep-depth runs (5+ rounds with many WebFetch outputs), this keeps the English-only and citation-required rules adjacent to the latest round's findings instead of buried behind accumulated source content.
