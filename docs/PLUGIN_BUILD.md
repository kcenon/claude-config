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

## Future Work

A dedicated build script (`scripts/build-plugin.sh`) could automate copying any
bundled assets and stage tarballs for marketplace publication. Until that
exists, the manual copy + `diff -q` workflow above is the policy for any asset
that genuinely needs bundling.
