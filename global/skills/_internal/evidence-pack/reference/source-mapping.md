# Evidence-Pack Source Mapping

Per-kind collection contracts. For each manifest `kind`, this file documents the source the
collector reads from, the command(s) it runs, the output layout under
`evidence/<version>/<kind>/`, and the standard clauses the artifact bears on.

> **Loading**: Loaded under `tier: standard` and `tier: deep` via the skill's `ref_docs.sources`
> entry. Skip when invoking under `tier: light`.

The skill body must not invent collection strategies -- it implements exactly the contracts
documented here. Adding a new kind requires updating both this file and `manifest-schema.md`.

## Collector Contract Template

Each section below follows this structure:

| Field | Meaning |
|-------|---------|
| **Source presence check** | The shell test that decides whether the source exists. Used in Phase 1 to plan the manifest. |
| **Required tools** | External binaries the collector needs. Missing tools yield `status: skipped` with `reason: tool_unavailable`. |
| **Collection command(s)** | Verbatim shell command(s) the collector runs. The same string is recorded in the manifest `source` field for the audit trail. |
| **Output layout** | What lands under `evidence/<version>/<kind>/`. Files only -- no subdirectory nesting unless documented. |
| **sha256 strategy** | How the artifact's checksum is computed (single file vs. directory listing). |
| **Related clauses** | Default `related_clauses` value for entries of this kind. The collector may extend this list; it must not shorten it. |

## kind: matrix

Verbatim copy of the traceability matrix produced by the sibling `traceability` skill.

| Field | Value |
|-------|-------|
| **Source presence check** | `[[ -f docs/.index/traceability.yaml ]]` |
| **Required tools** | None (plain file copy). |
| **Collection command(s)** | `cp docs/.index/traceability.yaml evidence/<version>/matrix/traceability.yaml` |
| **Output layout** | Single file: `evidence/<version>/matrix/traceability.yaml`. |
| **sha256 strategy** | Single file: `sha256sum evidence/<version>/matrix/traceability.yaml`. |
| **Related clauses** | `IEC-62304-5.2.6`, `IEC-62304-7.3.3`, `ISO-13485-7.3.6` |

The matrix is the spine of the evidence pack: every other artifact ultimately traces back to
a row in this file. Copying it verbatim (rather than regenerating) preserves the matrix
state at release time, even if the source-of-truth indices change later.

## kind: ci_run_log

CI workflow run history for the release branch.

| Field | Value |
|-------|-------|
| **Source presence check** | `command -v gh && gh auth status >/dev/null 2>&1` |
| **Required tools** | `gh` (authenticated to the current repository). |
| **Collection command(s)** | `gh run list --branch <version> --limit 50 --json status,conclusion,name,databaseId,createdAt,headSha,event > evidence/<version>/ci_run_log/runs.json`<br><br>Then for each run id in `runs.json`: `gh run view <id> --json status,conclusion,jobs,createdAt,updatedAt,url > evidence/<version>/ci_run_log/run-<id>.json` |
| **Output layout** | `evidence/<version>/ci_run_log/runs.json` (index) plus `evidence/<version>/ci_run_log/run-<id>.json` (one per run). |
| **sha256 strategy** | Directory listing: `find evidence/<version>/ci_run_log -type f \| sort \| xargs sha256sum \| sha256sum`. |
| **Related clauses** | `IEC-62304-5.5.5`, `IEC-62304-5.6.2`, `ISO-13485-7.3.6` |

The branch name passed to `--branch` is the `<version>` argument verbatim. If the release
uses a different branch convention (e.g. `release/v1.2.0` rather than `v1.2.0`), the
operator can pass `--include ci_run_log` and follow up with manual collection until the
skill grows a `--ci-branch` override (out of scope for the initial cut).

## kind: pr_review

Pull-request review records for PRs merged into the release within the release window.

| Field | Value |
|-------|-------|
| **Source presence check** | `command -v gh && gh auth status >/dev/null 2>&1` |
| **Required tools** | `gh`. |
| **Collection command(s)** | `prev_tag=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null \|\| echo "")`<br>`prev_date=$(git log -1 --format=%cI "$prev_tag" 2>/dev/null \|\| echo "")`<br>`gh pr list --search "merged:>$prev_date base:develop" --limit 100 --json number,title,mergedAt,author,labels > evidence/<version>/pr_review/prs.json`<br><br>Then for each pr number in `prs.json`: `gh pr view <number> --json number,title,reviews,reviewDecision,mergedBy,mergeCommit > evidence/<version>/pr_review/pr-<number>.json` |
| **Output layout** | `evidence/<version>/pr_review/prs.json` (index) plus `evidence/<version>/pr_review/pr-<number>.json` (one per PR). |
| **sha256 strategy** | Directory listing (same pattern as `ci_run_log`). |
| **Related clauses** | `IEC-62304-8.2.1`, `IEC-62304-6.3`, `ISO-13485-4.2.4`, `ISO-13485-7.3.5` |

The `prev_tag` resolution uses `HEAD^` so it picks up the most recently tagged ancestor. If
no previous tag exists (first release of a project), the search degrades to "all PRs merged
to date" -- noisy but correct, and the operator can prune via `--exclude pr_review` and
collect manually once a baseline tag exists.

## kind: signed_commits

Per-commit signature status across the release window.

| Field | Value |
|-------|-------|
| **Source presence check** | `command -v git && git rev-parse --is-inside-work-tree >/dev/null 2>&1` |
| **Required tools** | `git`. |
| **Collection command(s)** | `prev_tag=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null \|\| echo "")`<br>`range="${prev_tag:+${prev_tag}..}<version>"`<br>`git log --format='%H %G? %aI %s' "$range" > evidence/<version>/signed_commits/commits.txt` |
| **Output layout** | Single file: `evidence/<version>/signed_commits/commits.txt`. One commit per line: `<sha> <gpg-status> <author-iso8601> <subject>`. |
| **sha256 strategy** | Single file. |
| **Related clauses** | `IEC-62304-8.2.1`, `IEC-62304-8.3`, `ISO-13485-7.3.5`, `ISO-13485-4.2.5` |

The `%G?` placeholder produces git's standard signature-status code: `G` (good signature),
`B` (bad), `U` (unknown validity), `N` (no signature), `X` (good signature, expired key),
`Y` (good, expiring key), `R` (good, revoked key), `E` (signature checked but cannot verify).
Auditors typically require `G` for safety-relevant commits; the file lets them grep.

When `prev_tag` is empty (first release), the range degrades to `<version>` alone, which
means "the release tag and all its history". For very long histories this can be megabytes;
the operator can pass `--exclude signed_commits` and add a project-specific collector that
limits the depth.

## kind: research_artifact

External-citation files produced by the `research` skill (or hand-curated under the same
directory).

| Field | Value |
|-------|-------|
| **Source presence check** | `[[ -d docs/research ]]` |
| **Required tools** | None. |
| **Collection command(s)** | `mkdir -p evidence/<version>/research_artifact`<br>`cp -R docs/research/. evidence/<version>/research_artifact/` |
| **Output layout** | Mirror of `docs/research/` under `evidence/<version>/research_artifact/`. Subdirectory structure preserved. |
| **sha256 strategy** | Directory listing. |
| **Related clauses** | `IEC-62304-5.3.3`, `ISO-13485-7.3.3` |

External research is the evidence trail for "where did this requirement come from?" -- the
SOUP register, regulatory citations, and academic references the SRS draws on. Mirroring
rather than referencing avoids the "the cited URL is dead at audit time" failure mode.

## kind: risk_file

Snapshot of the project's risk-management file produced by the sibling `risk-control` skill.

| Field | Value |
|-------|-------|
| **Source presence check** | `[[ -f docs/.index/risk-file.yaml ]]` |
| **Required tools** | None (plain file copy). |
| **Collection command(s)** | `mkdir -p evidence/<version>/risk_file`<br>`cp docs/.index/risk-file.yaml evidence/<version>/risk_file/risk-file.yaml` |
| **Output layout** | Single file: `evidence/<version>/risk_file/risk-file.yaml`. The `risk_file/` subdirectory is retained for symmetry with other kinds (one directory per kind), but contains exactly one file. |
| **sha256 strategy** | Single file: `sha256sum evidence/<version>/risk_file/risk-file.yaml`. |
| **Related clauses** | `IEC-62304-7.1.1`, `IEC-62304-7.2.1`, `IEC-62304-7.3.3`, `ISO-13485-7.3.3` |

The risk file is owned by the sibling `risk-control` skill (issue #596, PR #599) and is
emitted as a single normalized YAML file at `docs/.index/risk-file.yaml`. The collection
contract is **single file**: this collector copies that one file verbatim and does not
attempt to mirror a `risk-file/` directory. Future evidence-pack consumers must treat
`risk_file` as a single-file kind -- if a project ever needs additional risk artifacts,
those should be introduced under a new `kind` rather than by promoting `risk_file` to a
directory mirror (which would be a backward-incompatible schema change).

## kind: soup_register

Snapshot of the project's SOUP (Software Of Unknown Provenance) register produced by the
sibling `soup-inventory` skill.

| Field | Value |
|-------|-------|
| **Source presence check** | `[[ -f docs/.index/soup.yaml ]]` |
| **Required tools** | None (plain file copy). |
| **Collection command(s)** | `mkdir -p evidence/<version>/soup_register`<br>`cp docs/.index/soup.yaml evidence/<version>/soup_register/soup.yaml`<br>`[[ -f docs/.index/soup.md ]] && cp docs/.index/soup.md evidence/<version>/soup_register/soup.md \|\| true` |
| **Output layout** | Primary file: `evidence/<version>/soup_register/soup.yaml`. Optional companion: `evidence/<version>/soup_register/soup.md` when the source `docs/.index/soup.md` exists. |
| **sha256 strategy** | Single file: `sha256sum evidence/<version>/soup_register/soup.yaml`. The optional `soup.md` companion is documentation only and is not factored into the kind's checksum. |
| **Related clauses** | `IEC-62304-5.3.3`, `IEC-62304-8.1.1` |

The SOUP register is owned by the sibling `soup-inventory` skill (issue #601, PR #604) and
is emitted as a single normalized YAML file at `docs/.index/soup.yaml`, with an optional
human-readable per-supplier report at `docs/.index/soup.md` (produced by
`/soup-inventory report`). The collection contract is **single file**: the canonical
artifact is `soup.yaml` and the kind's `sha256` is computed over that file alone. The
`soup.md` companion is collected when present so the audit pack carries the same
human-readable view the project ships, but its absence does not affect the kind's status
(`collected` when `soup.yaml` was copied successfully) and it is not part of the checksum.
Future evidence-pack consumers must treat `soup_register` as a single-file kind -- if a
project ever needs additional SOUP artifacts beyond the YAML and its Markdown render,
those should be introduced under a new `kind` rather than by promoting `soup_register` to
a directory mirror (which would be a backward-incompatible schema change).

## Atomic Write Pattern

Every collector writes through a temp path, then renames on success:

```bash
collect_kind() {
    local kind="$1"
    local out_dir="evidence/<version>/${kind}"
    local tmp_dir="${out_dir}.tmp"

    mkdir -p "$tmp_dir"
    # ... collector body writes into $tmp_dir ...
    mv "$tmp_dir" "$out_dir"
}
```

If the collector body errors out, the orchestrator removes `$tmp_dir` (not the final
`$out_dir`, which may already exist from a `--force` overwrite of a different invocation).

The same pattern applies to single-file kinds: `cp ... <kind>/<file>.tmp && mv
<kind>/<file>.tmp <kind>/<file>`.

## Adding a New Kind

When a new evidence type becomes available (e.g. `dependency_lock` for SBOM artifacts):

1. Pick a snake_case kind id following the existing pattern.
2. Add a row to "Allowed `kind` Values" in `manifest-schema.md`.
3. Add a section to this file with all six contract fields populated.
4. Update the skill body's Phase 1 candidate kind list.
5. Bump `_meta.schema` minor in `manifest-schema.md` (new kinds are backward-compatible).

## Cross-references

- Manifest entry shape: `manifest-schema.md`
- Skill body that runs these collectors: `../SKILL.md`
- Matrix that the `matrix` kind copies: `docs/.index/traceability.yaml` (produced by `../../traceability/SKILL.md`)
- Clause source files: `compliance/iec-62304.md`, `compliance/iso-13485.md`
