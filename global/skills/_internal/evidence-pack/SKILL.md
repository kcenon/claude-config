---
name: evidence-pack
description: "Assemble per-release evidence packages from artifacts already produced elsewhere in the project (traceability matrix, CI logs, PR review records, signed-commit lists, external research citations, risk file). Output is a self-contained directory under evidence/<version>/ containing a manifest.yaml, per-artifact subdirectories, and an INTEGRITY checksum. Read-mostly with respect to source code: writes only under evidence/. Opt-in gate: no-op when the consumer project has no evidence/ parent directory, so non-regulated repos are unaffected. Idempotent: refuses to overwrite an existing pack unless --force is passed."
argument-hint: "<version> [--include <pattern>] [--exclude <pattern>] [--dry-run] [--force]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
loop_safe: false
max_iterations: 1
halt_conditions:
  - { type: success, expr: "evidence/<version>/manifest.yaml and INTEGRITY written; per-artifact subdirectories populated" }
  - { type: success, expr: "no-op exit when evidence/ parent directory is absent" }
  - { type: success, expr: "dry-run exit after printing the manifest plan without writing" }
  - { type: failure, expr: "evidence/<version>/ already exists and --force is not set" }
  - { type: failure, expr: "any required collector errors out (matrix copy, gh, git) and --include did not exclude that kind" }
  - { type: failure, expr: "version argument missing or not a valid semantic version / tag" }
on_halt: "Print collected/skipped artifact summary and exit non-zero on failure, zero on success or no-op"
tiers:
  light:
    ref_docs: []
    deep_checks: false
  standard:
    ref_docs: [manifest, sources]
    deep_checks: true
  deep:
    ref_docs: [manifest, sources]
    deep_checks: true
default_tier: standard
# ref_docs keys:
#   manifest -> reference/manifest-schema.md
#   sources  -> reference/source-mapping.md
---

# evidence-pack Skill

Assemble per-release evidence packages for projects that have adopted the regulated-industry
track. The skill is the release-time partner of the `traceability` skill: where `traceability`
maintains the per-commit matrix, `evidence-pack` packages that matrix together with surrounding
artifacts (CI logs, PR reviews, signed commits, research citations, risk file) into a single
directory an external auditor can consume without further stitching.

The skill is a Design History File (DHF) generator in spirit. It does not invent evidence; it
collects what already exists.

## Usage

```
/evidence-pack v1.2.0                             # Build full pack for tag v1.2.0
/evidence-pack v1.2.0 --include matrix,ci_run_log # Only collect specific kinds
/evidence-pack v1.2.0 --exclude pr_review         # Collect everything except PR review records
/evidence-pack v1.2.0 --dry-run                   # Plan only; print what would be collected and exit
/evidence-pack v1.2.0 --force                     # Overwrite an existing evidence/v1.2.0 pack
```

Exactly one positional argument is required: the release version or git tag. Flags are optional.

## Arguments

| Position / Flag | Behavior |
|-----------------|----------|
| `<version>` (positional, required) | Release identifier used as the output subdirectory name. Accepts semantic versions (`v1.2.0`), date-tagged releases (`2026-05-04`), or any other ASCII slug matching `[A-Za-z0-9._-]+`. Refuses values containing path separators or whitespace. |
| `--include <pattern>` | Comma-separated allowlist of artifact `kind` values to collect. When set, all kinds not in the list are skipped. See `reference/manifest-schema.md` for valid kinds. |
| `--exclude <pattern>` | Comma-separated denylist of artifact `kind` values to skip. Mutually independent from `--include`; if both are set, the include list is applied first, then the exclude list removes from it. |
| `--dry-run` | Run the planning phase only. Print the manifest plan (kinds, sources, collection commands) to stdout and exit zero. No files are written. Useful for previewing in CI before allowing real collection. |
| `--force` | Overwrite an existing `evidence/<version>/` directory. Without `--force`, the skill refuses to clobber a previously generated pack and exits non-zero (idempotency contract). |

## Inputs

| Path | Required | Purpose |
|------|----------|---------|
| `evidence/` (parent dir at repo root) | Yes (gate) | Opt-in marker. Skill is a no-op when this directory is absent. |
| `docs/.index/traceability.yaml` | Optional | Verbatim copy collected as the `matrix` artifact. Skipped when absent. |
| `risk-file/` | Optional | Recursively collected as the `risk_file` artifact. Skipped when absent. |
| `docs/research/` | Optional | Citation files collected as `research_artifact` entries. Skipped when absent. |
| `gh` CLI authenticated to the current repo | Yes for `ci_run_log` and `pr_review` kinds | Used to query workflow runs and PR review history. Skipped (with one info line per kind) if `gh` is not on `PATH`. |
| `git` history with the release tag reachable | Yes for `signed_commits` kind | Used to enumerate commits between the previous tag and `<version>`. |

The detailed source-to-artifact mapping is documented in `reference/source-mapping.md`.

## Outputs

All outputs live under `evidence/<version>/` (relative to the consumer project root):

| Path | Format | Purpose |
|------|--------|---------|
| `evidence/<version>/manifest.yaml` | YAML | Top-level manifest. One entry per collected artifact. Schema: `reference/manifest-schema.md`. |
| `evidence/<version>/INTEGRITY` | Plain text | Single-line `sha256:<hex>` over the sorted manifest entries. Detect tampering of the manifest itself. |
| `evidence/<version>/<kind>/...` | Varies by kind | Per-artifact subdirectory. One subdirectory per `kind` value in the manifest. Layout per kind: see `reference/source-mapping.md`. |

The skill writes `manifest.yaml` and `INTEGRITY` atomically: each goes to a sibling `*.tmp`
file and is renamed on success. A failed run never leaves a half-written manifest.

## Opt-in Gate

The skill is purely additive and must not break repos that have not adopted the regulated track.

```bash
if [[ ! -d evidence ]]; then
    echo "evidence-pack: ./evidence directory absent -- skill is a no-op for this repo"
    exit 0
fi
```

This check runs before any other phase. The exit code is `0` so CI invocations on
non-regulated repos do not fail. To opt in, a consumer project creates an empty `evidence/`
directory at the repo root (a `.gitkeep` is sufficient) and tracks the per-release subdirectories
that the skill produces.

## Instructions

### Phase 0: Validate Environment

1. Confirm `evidence/` exists at the repo root; if not, print the no-op message and exit 0.
2. Validate `<version>` matches `^[A-Za-z0-9._-]+$`. If it contains a path separator,
   whitespace, or is empty, exit non-zero with a clear message.
3. If `evidence/<version>/` already exists and `--force` is not set, exit non-zero with the
   path and the suggestion to pass `--force`.
4. Resolve git HEAD (`git rev-parse HEAD`) and the current tag (`git describe --tags --exact-match`
   or `git rev-parse --short HEAD` as fallback). Record both for the manifest header.
5. Detect optional collectors:
   - `gh` on `PATH` and authenticated (probe with `gh auth status`).
   - `git` available and the current directory is a git work tree.
   - `sha256sum` (Linux) or `shasum -a 256` (macOS) for checksumming.
   Missing optional collectors do not fail the skill; they downgrade the affected kinds to
   skipped-with-reason in the manifest.

### Phase 1: Plan the Manifest

Reference: `reference/manifest-schema.md` defines the row shape of each manifest entry, and
`reference/source-mapping.md` defines per-kind collection commands and target subdirectories.

1. Build the candidate kind list from the schema (`matrix`, `ci_run_log`, `pr_review`,
   `signed_commits`, `research_artifact`, `risk_file`).
2. Apply `--include` if set: keep only kinds in the include list.
3. Apply `--exclude` if set: remove kinds in the exclude list.
4. For each remaining kind, run the source mapping's "presence check" (e.g.
   `[[ -f docs/.index/traceability.yaml ]]` for `matrix`). Kinds whose source is absent are
   recorded as `skipped: source_absent` in the manifest plan rather than triggering an error.
5. Emit the planned manifest (header + per-kind plan rows) to stdout.

### Phase 2: Dry-run Exit Point

If `--dry-run` is set, exit zero immediately after Phase 1. Print the planned manifest as
YAML to stdout but do not create `evidence/<version>/`.

### Phase 3: Collect Artifacts

For each kind that survived Phase 1 with a present source, run the collector defined in
`reference/source-mapping.md` and write the output under `evidence/<version>/<kind>/`. The
collector for each kind is documented there; the skill body must not invent new collection
strategies.

For each artifact written:

1. Compute `sha256` of the file (or, for directory-shaped kinds like `risk_file` or
   `research_artifact`, the sha256 of a deterministic listing produced by
   `find <dir> -type f | sort | xargs sha256sum`).
2. Record `collected_at` as the UTC ISO 8601 timestamp at which the collector finished.
3. Record `source` as the original repo-relative path or the `gh` / `git` command that
   produced the artifact (verbatim, including arguments). This is the audit trail.
4. Record `related_clauses` as the list of clause IDs the artifact bears on (e.g. the
   matrix maps to `IEC-62304-5.2.6` and `ISO-13485-7.3.6`; CI run logs map to
   `IEC-62304-5.5.5` and `ISO-13485-7.3.6`). The mapping table lives in
   `reference/source-mapping.md`.

If a collector errors out (non-zero exit, network failure, permission denied), the entry is
recorded as `failed: <message>` rather than silently dropped. The overall skill exits
non-zero only when a collector fails for a kind that was explicitly requested via `--include`;
failures for default-collected kinds emit a warning but allow the pack to be produced
(the manifest will mark the kind as failed so an auditor can see the gap).

### Phase 4: Write Manifest and Integrity File

Skip if `--dry-run` was already handled in Phase 2.

1. Write `evidence/<version>/manifest.yaml.tmp` with the schema documented in
   `reference/manifest-schema.md`. Sort entries by `kind` then `source` for stable diffs.
2. Compute `sha256` over the canonical (sorted, no extra whitespace) manifest content.
   Write the result to `evidence/<version>/INTEGRITY.tmp` as a single line:
   `sha256:<hex>\n`.
3. On success, rename both `*.tmp` files to their final names. On any error, delete the
   `*.tmp` files plus any partial per-artifact subdirectories that this invocation created
   and exit non-zero. (Existing artifacts under `evidence/<version>/` from a prior `--force`
   overwrite are left alone unless this invocation produced them.)

### Phase 5: Report

Emit a summary block on stdout:

```markdown
## Evidence Pack Generated

| Metric | Value |
|--------|-------|
| Version | <version> |
| Kinds collected | N |
| Kinds skipped | N (source_absent) |
| Kinds failed | N |
| manifest.yaml | X bytes |
| INTEGRITY sha256 | <16-char-prefix>... |
| Output | evidence/<version>/ |
```

Append a per-kind table when `--dry-run` was passed or when at least one kind failed.

## Output

The skill produces the per-version evidence directory plus the on-stdout summary. No other
files in the consumer project are modified -- in particular, the skill never edits source
code, never runs builds, and never publishes to external systems. Submission to an external
eQMS is explicitly out of scope (see issue #595 "Out of Scope").

## Error Handling

| Condition | Action |
|-----------|--------|
| `evidence/` parent absent | No-op exit 0 (opt-in gate, see Phase 0). |
| `<version>` argument missing or invalid | Exit non-zero with usage hint. |
| `evidence/<version>/` exists and `--force` not set | Exit non-zero with the existing path and `--force` suggestion. |
| `gh` not authenticated (kinds `ci_run_log`, `pr_review`) | Mark affected kinds as `skipped: tool_unavailable`; do not fail the skill. |
| Collector for an `--include`-requested kind fails | Exit non-zero after writing a partial manifest that records the failure. |
| Collector for a default-collected kind fails | Mark the kind as `failed: <message>` in the manifest; continue. |
| Write step fails (permission, disk) | Delete `*.tmp` files and any subdirectories this invocation created; report the path; exit non-zero. |
| `<version>` already collected (without `--force`) | See above; refusal is the correct behavior to preserve audit history. |

## Policies

### Side Effects and Loop-Safety

This skill is `loop_safe: false`. Each invocation produces an immutable per-release artifact
directory, and re-running for the same `<version>` either refuses (default) or destructively
overwrites (`--force`). Wrapping in `/loop` would either no-op after the first iteration or
churn the same directory; both outcomes are wrong.

The idempotency contract is "one pack per version" rather than "no-side-effect retry":
existing packs are evidence in their own right and must not be silently replaced.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Inputs | Only existing artifacts produced by other tools (matrix from `traceability`, CI logs from `gh`, etc.). The skill never invents data. |
| Outputs | Only files under `evidence/<version>/`. No other directory is touched. |
| Opt-in | Absent `evidence/` parent is a no-op exit 0, never a failure. |
| Atomicity | Manifest and integrity file go to `*.tmp` first, then rename on success. Failure deletes them. |
| Idempotency | Re-running for an existing `<version>` is refused unless `--force` is passed. |
| External submission | Never. Submission to eQMS / regulator portals is out of scope. |
| Cryptographic signing | Out of scope. The `INTEGRITY` checksum protects against accidental tampering only; it is not a signed attestation. |

## How Other Components Use the Pack

| Consumer | Use |
|----------|-----|
| External auditor | Reads `evidence/<version>/manifest.yaml` and walks per-kind subdirectories. The `INTEGRITY` file lets them detect post-hoc edits to the manifest. |
| `release` skill (future P2) | Could invoke `evidence-pack <version>` automatically after a release tag is created. |
| `pr-work` skill (future P2) | Could surface "evidence pack updated" as part of release-candidate PR descriptions. |
| `traceability` skill (sibling P0-1) | Produces `docs/.index/traceability.yaml` which becomes the `matrix` artifact in this pack. |

## References

- Manifest schema: `reference/manifest-schema.md`
- Per-kind source mapping: `reference/source-mapping.md`
- Sibling matrix producer: `global/skills/_internal/traceability/SKILL.md`
- Compliance clause source files: `compliance/iec-62304.md`, `compliance/iso-13485.md`
- Parent epic: `kcenon/claude-config#588`
- Originating issue: `kcenon/claude-config#595`
