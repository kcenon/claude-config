# Document Review Command

> **Deprecated**: This command has been migrated to Skills format. Use `global/skills/doc-review/SKILL.md` instead. This file is kept for backward compatibility and will be removed in a future version. The Skills version includes parallel agent analysis, SSOT detection, and automatic fix mode.

Comprehensive markdown document review with anchor validation, accuracy checking, and SSOT analysis.

## Usage

```
/doc-review                                    # Review all docs (auto-detect directory)
/doc-review docs/reference                     # Specify docs directory
/doc-review --scope anchors                    # Anchor validation only
/doc-review --scope all --fix                  # Full review with auto-fix
```

## Arguments

- `[docs-directory]`: Path to documentation directory (optional, auto-detected)
- `[--scope <phase>]`: `anchors`, `accuracy`, `ssot`, or `all` (default: `all`)
- `[--fix]`: Automatically apply fixes and commit

## Instructions

Execute a 4-phase document review:

### Phase 1: Anchor/Link Validation
- Build anchor registry from all headings (GitHub-style slug algorithm)
- Validate intra-file `](#anchor)` and inter-file `](file.md#anchor)` references
- Skip code blocks

### Phase 2: Accuracy/Consistency
- Terminology consistency across documents
- Version number and fact checking

### Phase 3: SSOT/Redundancy
- Detect SSOT declarations and verify non-SSOT documents defer properly
- Find redundant content and missing cross-references

### Phase 4: Fix and Verify (--fix only)
- Apply fixes in priority order (Must-Fix → Should-Fix → Nice-to-Have)
- Re-run anchor validation for regression check
- Commit changes

## Policies

See [_policy.md](./_policy.md) for common rules.

## Output

Structured report with findings classified as Must-Fix / Should-Fix / Nice-to-Have, overall score, and list of modified files (in --fix mode).
