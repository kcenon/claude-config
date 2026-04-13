# Source Evaluation Guide

Criteria for evaluating source reliability, assigning confidence levels,
and handling conflicting information.

## Confidence Levels

### High Confidence

The claim is well-supported and can be stated as fact.

**Criteria** (at least 2 must be met):
- Official documentation from the technology vendor/maintainer
- Peer-reviewed paper or RFC/specification
- 2+ independent authoritative sources agree
- Verified by codebase evidence (implementation matches claim)
- Published by recognized domain expert with verifiable credentials

**Markers in report**: No special marker needed. State directly.

### Medium Confidence

The claim is supported but has limited verification.

**Criteria**:
- Single authoritative source without independent confirmation
- Multiple non-authoritative sources agree (blogs, tutorials)
- Source is recent but from a less established author
- Codebase evidence is partial or indirect

**Markers in report**: Append `[Medium confidence — single source]` or similar qualifier.

### Low Confidence

The claim has weak support and should be treated as preliminary.

**Criteria**:
- Single non-authoritative source
- Information is outdated (> 2 years for fast-moving tech)
- Source has known bias or commercial interest
- Contradicted by other sources without clear resolution

**Markers in report**: Append `[Low confidence — unverified]` and note the limitation.

## Source Type Hierarchy

Sources are ranked by general reliability (higher = more reliable):

| Rank | Source Type | Examples | Typical Confidence |
|------|-----------|----------|-------------------|
| 1 | Standards/Specifications | RFC, ISO, IEC, W3C specs | High |
| 2 | Official documentation | Language docs, framework docs, API refs | High |
| 3 | Academic papers | Peer-reviewed journals, conference papers | High |
| 4 | Vendor technical blogs | Engineering blogs from major tech companies | High-Medium |
| 5 | Recognized expert content | Known practitioners, core contributors | Medium-High |
| 6 | Community documentation | Wiki, community guides, curated lists | Medium |
| 7 | Tutorial/blog posts | Individual developer blogs, tutorials | Medium-Low |
| 8 | Forum answers | Stack Overflow, GitHub discussions | Low-Medium |
| 9 | AI-generated content | LLM outputs, AI summaries | Low |
| 10 | Unverified claims | Social media, comments, anonymous posts | Very Low |

**Note**: Rank is a starting point. A well-researched blog post may be more reliable
than a poorly maintained official doc. Use judgment.

## Cross-Validation Rules

### Mandatory Cross-Validation

The following claim types **must** be verified by 2+ independent sources:

- Performance benchmarks or metrics
- Security vulnerability assessments
- Compatibility or support claims (e.g., "supports X")
- Cost or pricing information
- Licensing terms

### Single-Source Acceptable

These can be cited from a single authoritative source:

- API signatures and syntax (from official docs)
- Version numbers and release dates
- Specification requirements (from the spec itself)
- Mathematical formulas or algorithms (from academic papers)

### Handling Contradictions

When sources disagree:

1. **Identify the conflict clearly** in the report.
2. **Present both perspectives** with their sources.
3. **Assess which is more likely correct** based on:
   - Source authority (higher-ranked source preferred)
   - Recency (newer information preferred for tech topics)
   - Specificity (more specific claim preferred over general)
   - Codebase evidence (if available, strongly preferred)
4. **State your assessment** but mark it as such:

```markdown
> **Note**: Sources disagree on this point. [Source A](url) claims X,
> while [Source B](url) claims Y. Based on [reasoning], X appears more
> likely, but independent verification is recommended.
```

## Citation Format

### In-Text Citation

For inline references within findings:

```markdown
According to [the official documentation](https://url), the maximum
connection limit is 1000 concurrent WebSocket connections per server instance.
```

### Source Block

For detailed source attribution after a finding:

```markdown
> Source: [Title](URL) | Accessed: YYYY-MM-DD | Confidence: High
```

### References Section

Numbered list at the end of the report:

```markdown
## References

1. Mozilla Developer Network (2026), *WebSocket API*, https://developer.mozilla.org/en-US/docs/Web/API/WebSocket, accessed 2026-04-13
2. Grigorik, I. (2013), *High Performance Browser Networking*, O'Reilly Media
3. IETF (2011), RFC 6455: *The WebSocket Protocol*, https://tools.ietf.org/html/rfc6455
```

**Rules**:
- Number sequentially (do not skip numbers).
- Include access date for web sources.
- Preserve original language of titles.
- Include DOI for academic papers when available.

## Freshness Assessment

| Topic Domain | Freshness Threshold | Action if Stale |
|-------------|--------------------|--------------------|
| Web frameworks/libraries | 1 year | Search for newer sources |
| Programming languages | 2 years | Acceptable if stable feature |
| Security vulnerabilities | 6 months | Must find current assessment |
| Cloud services/pricing | 3 months | Warn about potential changes |
| Standards/specifications | 5 years | Usually stable, check for amendments |
| Academic research | 5 years | Acceptable, note newer developments |
| Hardware/performance | 2 years | Benchmarks may be outdated |

## Bias Detection

Flag potential bias when:

- Source is a vendor comparing their product to competitors
- Source has commercial interest in the conclusion
- Source is affiliated with one side of a technical debate
- Source presents only positive or only negative aspects
- Multiple sources share the same original source (echo chamber)

When bias is detected, note it:

```markdown
> **Note**: This comparison is from [Vendor]'s blog and may favor their product.
> Cross-referenced with independent benchmarks where available.
```
