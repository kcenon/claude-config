# Traceability Impact Template

Markdown template for the `## Traceability Impact` section that the `pr-work`
skill's Phase 5b injects into a PR body when `$REGULATED_TRACK=true`. The
template is the single source of truth for the section's wording, the
sentinel-comment placement, and the per-row format. The skill body must
preserve the structure documented here verbatim so downstream auditors and
reviewers always see the same shape.

> **Loading**: Loaded only when Phase 5b runs (which requires Phase 0a's
> `$REGULATED_TRACK=true`). Skip when the consumer project has no
> `compliance/` directory.

## Section Skeleton

The injected block is bracketed by two HTML-comment sentinels and is placed
at the very top of the PR body, before any user-supplied content. The
sentinels are matched literally; the skill never parses the markdown between
them and replaces the entire region on every re-run.

```markdown
<!-- traceability-impact:start -->
## Traceability Impact

This PR touches the following traceability cascade. Source of truth:
`docs/.index/graph.yaml` resolved by `hooks/lib/validate-traceability.sh`.

| Touched doc_id | Cascade targets | Coverage in diff |
|----------------|-----------------|------------------|
| `<doc_id_1>`   | `<target_1>, <target_2>, ...` | <covered \| missing> |
| `<doc_id_2>`   | `<target_3>` | <covered \| missing> |

Generated at: `<UTC ISO 8601 timestamp>`
Diff range: `origin/<base>..<head_branch>` (<N> commits)
<!-- traceability-impact:end -->
```

## Per-Row Format

Each row of the table corresponds to one doc_id discovered in the diff (via
`extract_doc_ids_from_path` in the shared library) whose
`graph_cascade_targets` returned a non-empty list. The cells are filled as
follows.

| Column | Source | Format |
|--------|--------|--------|
| `Touched doc_id` | The doc_id key from `graph.yaml`. | Backtick-wrapped uppercase identifier (e.g. `` `SRS-CALC-001` ``). |
| `Cascade targets` | Output of `graph_cascade_targets <graph_yaml> <doc_id>`. | Backtick-wrapped, comma-separated. Repo-relative paths and downstream doc_ids both render verbatim. |
| `Coverage in diff` | Per-target check: `covered` when the target appears in the diff (either as a path or as a touched doc_id), `missing` otherwise. | Lowercase literal. The whole-row value is `covered` only when every target is covered; otherwise `missing`. |

Rows are sorted by `Touched doc_id` ASCII-ascending so a re-run on the same
diff produces a byte-identical block. Idempotency is the contract.

## Empty-Diff Case

When the diff touches no doc_id with a non-empty cascade (the common case
for a docs-only or test-only commit), the section still appears -- with the
literal placeholder line shown below. Empty-with-rationale is auditable;
silent omission is not.

```markdown
<!-- traceability-impact:start -->
## Traceability Impact

No traceability cascade impact detected for this diff.

Generated at: `<UTC ISO 8601 timestamp>`
Diff range: `origin/<base>..<head_branch>` (<N> commits)
<!-- traceability-impact:end -->
```

The skill MUST NOT skip injecting the section just because the table is
empty. A reviewer reading the PR who sees no section cannot tell whether
the regulated track is off, the cascade is empty, or the skill failed --
all three are different states with different remediations.

## Failure-Mode Message

When the impact computation itself fails (e.g.
`hooks/lib/validate-traceability.sh` exits non-zero, the graph file is
malformed, or `git diff` cannot be resolved), Phase 5b prints a one-line
warning on stderr and continues. It does NOT block the PR. The next push
re-runs Phase 5b.

The injected section in the failure case carries an explicit notice so
reviewers know the table is stale rather than empty:

```markdown
<!-- traceability-impact:start -->
## Traceability Impact

Cascade computation failed during this push. Re-run will retry on the next
commit. See the previous Phase 5b log for the underlying cause.

Generated at: `<UTC ISO 8601 timestamp>`
Diff range: `origin/<base>..<head_branch>` (<N> commits)
<!-- traceability-impact:end -->
```

The failure-message variant is always recoverable -- the next successful
Phase 5b run replaces it with the regular table or the empty-diff
placeholder.

## Idempotency Contract

The skill body locates the existing block by searching for the literal
`<!-- traceability-impact:start -->` and `<!-- traceability-impact:end -->`
sentinels in the current PR body, then replaces the entire region between
(and including) them with the freshly rendered block. Implementation
sketch (the SKILL.md body invokes the equivalent):

```bash
# In Phase 5b, after IMPACT_TABLE is built.
PR_BODY=$(gh pr view "$PR_NUMBER" --repo "$ORG/$PROJECT" --json body -q .body)
NEW_BLOCK=$(render_traceability_impact_block "$IMPACT_TABLE")

if printf '%s' "$PR_BODY" | grep -qF '<!-- traceability-impact:start -->'; then
    # Replace the existing block in place.
    UPDATED=$(printf '%s' "$PR_BODY" | awk -v new="$NEW_BLOCK" '
        /<!-- traceability-impact:start -->/ { in_block=1; print new; next }
        /<!-- traceability-impact:end -->/   { in_block=0; next }
        !in_block { print }
    ')
else
    # First run on this PR: prepend the block.
    UPDATED=$(printf '%s\n\n%s' "$NEW_BLOCK" "$PR_BODY")
fi

printf '%s' "$UPDATED" > /tmp/pr-body.tmp
gh pr edit "$PR_NUMBER" --repo "$ORG/$PROJECT" --body-file /tmp/pr-body.tmp
rm -f /tmp/pr-body.tmp
```

A reviewer who manually edits the table is overwritten on the next push.
That is the correct behavior -- the table is computed from the diff, not
asserted by hand. Reviewer prose belongs outside the sentinel comments.

## Whitespace and Encoding

| Property | Rule |
|----------|------|
| Newline at the end of each line | LF (`\n`); never CRLF. |
| Leading whitespace on a row | None. The pipe character starts the line. |
| Trailing whitespace | None. Trim before writing. |
| Encoding | UTF-8 without BOM. |
| Non-ASCII glyphs | Avoid in the injected block to keep the `pr-language-guard` hook happy. ASCII `->` for arrows, ASCII hyphen-minus for dashes. |

The encoding rules are the same `pr-work` already enforces on commit
messages and PR comments; the injected block respects them so the
language-guard hook never trips on the skill's own output.

## Cross-references

- Shared library invoked to compute the cascade:
  `../../../../hooks/lib/validate-traceability.sh`
- Graph file consumed by the library: `docs/.index/graph.yaml` (in the
  consumer project; produced by `doc-index`).
- Sister gate that consumes the same impact data:
  `evidence-attachment-policy.md` (Phase 9b).
- Skill body that calls into this template: `../SKILL.md` Phase 5b.
- Sibling extension that produces the upstream YAML block consumed by
  Phase 9b: `../../issue-create/reference/regulated-fields.md` "Embedded
  YAML block format".
