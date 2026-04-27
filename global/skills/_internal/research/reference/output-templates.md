# Output Templates

Templates for research report generation. Template A is the generic default;
Template B adapts to detected document conventions.

## Template A: Generic (Plain)

Used when `--template plain`, no `--output`, or no existing docs detected.

```markdown
# Research Report: {Topic}

**Date**: YYYY-MM-DD
**Depth**: shallow | standard | deep
**Sources**: N web, M codebase

---

## 1. Overview

### 1.1 Research Objective

[What questions this research aims to answer]

### 1.2 Scope and Methodology

| Item | Value |
|------|-------|
| **Depth** | shallow / standard / deep |
| **Web searches** | N queries |
| **Pages analyzed** | M pages |
| **Codebase files** | K files |

## 2. Background

[Technical context and foundational concepts]

## 3. Findings

### 3.1 [Finding Title]

[Detailed finding with evidence]

> Source: [Title](URL) | Accessed: YYYY-MM-DD | Confidence: High

### 3.2 [Finding Title]

[Detailed finding with evidence]

## 4. Comparative Analysis

| Criteria | Option A | Option B | Option C |
|----------|:--------:|:--------:|:--------:|
| **Criterion 1** | ✅ | ⚠️ | ❌ |
| **Criterion 2** | 4/5 | 3/5 | 5/5 |
| **Criterion 3** | ✅ | ✅ | ⚠️ |

## 5. Codebase Relevance

[How findings relate to the current project — included when --sources includes code]

- `path/to/file.ext:line` — [Observation]
- `path/to/other.ext` — [Pattern found]

## 6. Recommendations

1. **[Recommendation 1]**: [Rationale with source reference]
2. **[Recommendation 2]**: [Rationale with source reference]

## 7. Open Questions

- [ ] [Unresolved question requiring further investigation]
- [ ] [Area needing additional data]

## 8. References

1. Author (Year), *Title*, Publisher/URL
2. Author (Year), *Title*, Publisher/URL
3. [Web Source Title](https://url), accessed YYYY-MM-DD
```

### Section Inclusion Rules

| Section | Shallow | Standard | Deep |
|---------|:-------:|:--------:|:----:|
| 1. Overview | ✅ | ✅ | ✅ |
| 2. Background | Optional | ✅ | ✅ |
| 3. Findings | ✅ | ✅ | ✅ |
| 4. Comparative Analysis | If comparison topic | ✅ | ✅ |
| 5. Codebase Relevance | If `--sources code/both` | If `--sources code/both` | ✅ |
| 6. Recommendations | ✅ | ✅ | ✅ |
| 7. Open Questions | Optional | ✅ | ✅ |
| 8. References | ✅ | ✅ | ✅ |

## Template B: Context-Adapted

Used when `--template auto` and existing document conventions are detected.

Template B is not a fixed template — it is dynamically constructed by replicating
the patterns detected during Phase 0-B. The following describes what to replicate.

### Frontmatter Replication

If existing documents use YAML frontmatter, construct matching frontmatter:

```yaml
---
# Replicate all keys found in existing docs.
# Example detected schema:
doc_id: "[pattern]-NNN"          # Use detected ID pattern, assign next number
doc_title: "[Topic title]"       # In detected language
doc_version: "0.1.0"             # Always start at 0.1.0 for new docs
doc_date: "YYYY-MM-DD"           # Current date
doc_status: "Draft"              # Always "Draft" for new research docs
# ... replicate any additional keys found (classification, product, approval, etc.)
---
```

**Rules**:
- Replicate the exact key structure (including nesting depth).
- For ID fields: detect the pattern (e.g., `STM-REF-NNN`) and assign next sequential number.
- For approval/author blocks: leave date fields empty (pending review).
- For fixed fields (classification, product): copy verbatim from existing docs.

### Context Block Replication

If existing documents have post-title context blockquotes, replicate the pattern:

```markdown
# [Title in detected language]

> **[Key 1]**: [Value matching detected pattern]
> **[Key 2]**: [Related document links using detected separator]
> **[Key 3]**: 0.1.0
> **[Key 4]**: YYYY-MM-DD
```

### Section Structure Replication

Match the detected heading and numbering style:

| Detected Pattern | Replicate |
|-----------------|-----------|
| `## 1. Title` | Numbered H2 sections |
| `## Title` | Unnumbered H2 sections |
| `### 1.1 Title` | Numbered H3 subsections |
| Horizontal rules between sections | Include `***` separators |
| Table of contents section | Include linked TOC |

### Marker Replication

If existing documents use special markers, include them where appropriate:

| Detected Marker | When to Include |
|----------------|-----------------|
| `> **SSOT**: ...` | When the research section is the authoritative source for a topic |
| `> **Cross-reference**: ...` | When referencing other existing documents |
| `> **Note**: ...` | For advisory asides |

### Citation Style Replication

Match the reference/bibliography format of existing documents:

| Detected Style | Format |
|---------------|--------|
| Numbered list | `1. Author (Year), *Title*, URL` |
| Linked references | `- [Title](URL)` |
| Academic style | `Author et al. (Year), *Title*, Journal, DOI` |
| Table format | `\| # \| Title \| URL \| Type \| Date \|` |

### Symbol Convention

If existing documents use evaluation symbols, match them:

- `✅` / `⚠️` / `❌` — Binary/ternary evaluation
- `●` / `○` — Required/optional
- Numeric scores (1-5) — Quantitative rating
- Custom symbols — Replicate as found

## Comparison Matrix Formats

### Technology Comparison (Feature-Based)

```markdown
| Feature | Tech A | Tech B | Tech C |
|---------|:------:|:------:|:------:|
| **Feature 1** | ✅ | ⚠️ | ❌ |
| **Feature 2** | ❌ | ✅ | ✅ |
| **Maturity** | High | Medium | Low |
| **Community** | Large | Medium | Small |
```

### Scored Evaluation

```markdown
| Criteria | Weight | Tech A | Tech B | Tech C |
|----------|:------:|:------:|:------:|:------:|
| **Performance** | 30% | 4.5 | 3.0 | 5.0 |
| **Ecosystem** | 25% | 5.0 | 4.0 | 2.0 |
| **Learning curve** | 20% | 3.0 | 4.5 | 2.5 |
| **Maintenance** | 15% | 4.0 | 4.0 | 3.0 |
| **Cost** | 10% | 5.0 | 3.0 | 4.0 |
| **Weighted Total** | | **4.25** | **3.70** | **3.55** |
```

### Pros/Cons Format

```markdown
### Option A: [Name]

**Advantages**:
- [Advantage 1] — [Source]
- [Advantage 2] — [Source]

**Disadvantages**:
- [Disadvantage 1] — [Source]
- [Disadvantage 2] — [Source]

**Best for**: [Use case description]
```
