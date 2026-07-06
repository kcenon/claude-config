# SKILL.md Drift Contract

`SKILL.md` files are copied across multiple distribution layers. A shared skill
name must not gain different permissions, routing, severity behavior, or
mutation authority by accident.

## Compared Layers

- Compare `project/.claude/skills/<name>/SKILL.md` with
  `plugin/skills/<name>/SKILL.md` for skill names present in both layers.
- Compare `plugin/skills/<name>/SKILL.md` with
  `plugin-lite/skills/<name>/SKILL.md` only for explicitly paired skill names.
- Treat `global/skills/_internal/**/SKILL.md` as independent keyword or slash
  skills unless `skill-drift-contract.yml` declares a paired copy.
- Project-only skills are not drift failures by themselves. Retire, migrate, or
  prune them through the installer and skill ownership policies.

## High-Risk Fields

The drift gate must review these frontmatter fields and any body text that
defines the same behavior:

- `allowed-tools` and `disallowed-tools`
- `disable-model-invocation`, `user-invocable`, and `argument-hint`
- `paths`, `model`, `context`, and `agent`
- `severity`, `finding_levels`, `iso_class`, `safety_class`, and
  `applies_at_or_above`
- output contracts, finding formats, read-only posture, and mutation authority

Formatting-only YAML differences, such as flow lists versus block lists, should
be normalized before comparison.

## Intentional Difference Workflow

When changing a shared skill:

1. Decide whether every paired layer should behave the same. Prefer identical
   behavior unless the layer has a real runtime or packaging reason to differ.
2. If behavior should match, update every paired `SKILL.md` in the same PR.
3. If behavior should differ, record the exception in
   `skill-drift-contract.yml`. The entry must name the compared paths, field or
   body section, reason, and pinned `source` and `target` values.
4. Update this document if the exception introduces a new allowed drift class.
5. Run the skill validators and the drift gate before review.

## Allowed Difference Classes

- Tool permissions may differ when project skills intentionally edit files but
  plugin skills are read-only review helpers.
- `context` or `agent` may differ only when one layer uses a forked or
  subagent posture that the paired layer does not provide.
- `paths` may differ when package scope differs, such as plugin-only runtime
  paths.
- Body text may differ only to describe real layer behavior. Severity and
  output contracts should stay aligned unless `skill-drift-contract.yml` records
  an exception.

## CI Contract

The drift gate should run from the skills validation workflow on changes to
skill layers, `skill-drift-contract.yml`, or the drift checker. Failures should
print the paired paths and the exact field or section that drifted so reviewers
can either sync the copies or approve a narrow exception.

Existing skill checks still apply:

- `scripts/validate_skills.sh`
- `scripts/spec_lint.sh --strict`
- `scripts/check_skill_drift.sh`
- `scripts/check_skill_drift.ps1`
- `tests/scripts/test-check-skill-drift.sh`
- `tests/scripts/test-check-skill-drift.ps1`
