# memory-sync-issues

Issue staging directory for the Cross-machine Memory Sync EPIC.

This directory holds the 30 GitHub issue source files (1 EPIC + 29 children) plus the
automation tooling that registers them. The structure exists so the registration is
reproducible if the issues are ever lost or need to be re-created in another repo.

## Layout

```
scripts/memory-sync-issues/
├── README.md                          # This file
├── issues/                            # 30 markdown files (frontmatter + body)
│   ├── EPIC.md
│   ├── A1-spec-correction.md
│   ├── ...
│   └── G3-operational-docs.md
└── tooling/
    ├── validate-issues.sh             # Sanity-check frontmatter and graph
    ├── setup-labels-milestones.sh     # Create labels and milestones in repo
    └── create-issues.sh               # Two-pass issue registration
```

## Issue file frontmatter schema

Each `issues/*.md` file starts with YAML frontmatter:

```yaml
---
title: "<conventional-commit-prefix>: <description>"
labels:
  - type/<feature|chore|docs|test|ci|epic>
  - priority/<high|medium|low>
  - area/memory
  - size/<XS|S|M|L>
  - phase/<A-G>
milestone: memory-sync-v1-<phase>
blocked_by: [A1, A2, ...]              # placeholder IDs
blocks: [A5, ...]
parent_epic: EPIC                      # children only
---
```

Body uses 5W1H + Detailed Design + Acceptance Criteria + Cross-references sections.
Body may reference other issues via `#A1`, `#B2`, etc. — `create-issues.sh` substitutes
these to real GitHub numbers in PASS 2.

## Workflow

### One-time setup (per repo)

```bash
# Create labels and milestones in kcenon/claude-config
./tooling/setup-labels-milestones.sh --dry-run     # preview
./tooling/setup-labels-milestones.sh               # apply
```

### Validate issue graph before registration

```bash
./tooling/validate-issues.sh ./issues
# Expected: Errors: 0, Warnings: 0
```

### Register all 30 issues

```bash
# Dry-run first (no GitHub mutations):
./tooling/create-issues.sh --dry-run

# Actual registration (creates EPIC + 29 children):
./tooling/create-issues.sh --execute

# If pass 2 (placeholder substitution) failed mid-way:
./tooling/create-issues.sh --execute --resume
```

The `id-map.json` file is written in `tooling/` after PASS 1 succeeds. It maps
placeholder IDs (`EPIC`, `A1` ... `G3`) to real GitHub issue numbers. `--resume`
uses this map to retry PASS 2 without re-creating issues.

### Verify registration

```bash
gh issue list --repo kcenon/claude-config --label area/memory --limit 50
# Expected: 30 open issues with the area/memory label
```

## Resilience and reproducibility

- All three tooling scripts are bash 3.2+ compatible (macOS default and Linux 5.x)
- `setup-labels-milestones.sh` is idempotent (re-running is safe)
- `create-issues.sh` PASS 1 is idempotent given an `id-map.json`: it skips any
  ID already mapped
- Source markdown files are committed to git, so the issue content can be reviewed,
  amended, and re-registered if needed

## Troubleshooting

### "labels not found" during create-issues.sh

Run `setup-labels-milestones.sh` first.

### "milestone not found"

Same — `setup-labels-milestones.sh` creates 7 milestones.

### `validate-issues.sh` reports asymmetry warnings

`blocked_by` on one issue must have a corresponding `blocks` on the dependency.
Edit the relevant frontmatter and re-validate.

### `gh issue create` fails with rate limit

Run with `--resume` after a delay; the `id-map.json` preserves progress.

## Reference

- EPIC: see `issues/EPIC.md`
- Validation spec: `docs/MEMORY_VALIDATION_SPEC.md` (created in #A1)
- Trust model: `docs/MEMORY_TRUST_MODEL.md` (created in #B1)
- Operations runbook: `docs/MEMORY_SYNC.md` (consolidated in #G3)
- Threat model: `docs/THREAT_MODEL.md` (created in #G3)
