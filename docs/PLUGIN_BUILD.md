# Plugin Build Policy

This document describes how the `plugin/` and `plugin-lite/` trees are packaged
for marketplace publication and kept consistent with the rest of the repo.

## Self-Contained Principle (#568)

The marketplace tarballs published from `plugin/` and `plugin-lite/` must be
self-contained: at runtime the plugin is unpacked on the user's machine and
loaded without re-fetching files from the original repository. Anything a
shipped hook needs at runtime therefore has to live inside the plugin tree
itself — a plugin must never depend on a sibling path that only exists in the
development checkout.

## Bundled Runtime Assets

A plugin tree bundles a runtime asset only when a component it actually ships
sources that asset at load time. When a bundled copy is required, the canonical
source lives under `hooks/lib/` and the copy must match it verbatim; add the
copy to a `diff -q` gate in `.github/workflows/validate-hooks.yml` so the trees
never drift in `main`.

> History: `plugin/hooks/lib/validate-commit-message.sh` and
> `plugin-lite/hooks/lib/validate-commit-message.sh` were previously bundled on
> the assumption that each plugin shipped `commit-message-guard.sh` and resolved
> the sibling lib at runtime. Neither plugin ships that guard, so the bundled
> libs had no runtime consumer and were removed (deep-audit
> `plugin-bundled-lib-no-consumer`). Re-introduce a bundled lib only together
> with the component that sources it, and restore the `diff -q` gate at the same
> time.

## CI Enforcement (smoke test)

`.github/workflows/validate-hooks.yml` runs `tests/plugin/smoke-test.sh` (#622)
on every PR that touches `plugin/`, `plugin-lite/`, or `tests/plugin/`. The
smoke test catches packaging regressions — manifest schema mismatches, missing
or renamed skills, broken hook references — before they ship in a release.
Sh/PowerShell parity: the matching `tests/plugin/smoke-test.ps1` is held for the
future Windows runner job (out of scope for #622).

## Why Copy Instead of Symlink

When a runtime asset must be bundled, use a real file copy rather than a
symlink: symlinks are not portable across the install paths the plugin supports
(Linux, macOS, Windows tarballs, git-subdir installs). A real file copy is the
only representation that survives every install transport, and a CI `diff -q` is
the integrity check that compensates for the lack of a single filesystem inode.

## Cross-Layer SKILL.md Drift Contract (#822)

`skill-drift-contract.yml` declares the `SKILL.md` copies that must stay aligned
across distribution layers. Today it covers the skills duplicated between
`plugin/skills/` and `project/.claude/skills/`. CI runs
`scripts/check_skill_drift.sh` and `scripts/check_skill_drift.ps1` from the
`Validate Skills` workflow so unapproved drift fails before merge.

The contract watches high-risk frontmatter fields that affect invocation,
permissions, routing, and finding severity: tool grants, disallowed tools,
model-invocation disablement, path routing, fork/agent routing, halt behavior,
and severity/finding-level declarations. Most pairs also require exact body
parity after frontmatter is stripped, because output contracts and reference
imports are load-bearing behavior.

When updating a duplicated skill:

1. Edit both layer copies when the behavior is meant to stay aligned.
2. If a layer difference is intentional, add or update an exception in
   `skill-drift-contract.yml` with a specific reason and pinned `source` and
   `target` values.
3. Use `body.mode: ignore` only when the body intentionally routes to different
   layer-local references, and include a reason.
4. Run `bash scripts/check_skill_drift.sh` and
   `pwsh -NoProfile -File scripts/check_skill_drift.ps1`.
5. Run the matching test suites under `tests/scripts/` when changing the
   checker or contract format.

Exceptions are not blanket waivers. The checker verifies pinned exception
values, so a later edit to either side must either restore parity or update the
reviewed exception.

## Future Work

A dedicated build script (`scripts/build-plugin.sh`) could automate copying any
bundled assets and stage tarballs for marketplace publication. Until that
exists, the manual copy + `diff -q` workflow above is the policy for any asset
that genuinely needs bundling.
