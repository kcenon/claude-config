# Plugin Build Policy

This document describes how the `plugin/` and `plugin-lite/` trees are kept in
sync with the canonical hook lib at `hooks/lib/`.

## Background (#568)

The marketplace tarballs published from `plugin/` and `plugin-lite/` must be
self-contained: at runtime the plugin is unpacked at the user's machine and
sourced without re-fetching files from the original repository. Anything the
hooks need at runtime therefore has to live inside the plugin tree.

`global/hooks/commit-message-guard.sh` sources its rules from
`hooks/lib/validate-commit-message.sh` (the single source of truth used by
both the PreToolUse hook and the git `commit-msg` terminal hook). When a
plugin marketplace user installs `claude-config`, the runtime resolves the
sibling `lib/` directory next to `commit-message-guard.sh` -- so each plugin
tree must ship its own copy of the canonical lib.

The hook is **fail-closed**: if the canonical lib cannot be sourced, the
hook refuses rather than silently falling back to a drifted inline copy.
Bundling the lib correctly is therefore a release-blocking invariant.

## Canonical Source

`hooks/lib/validate-commit-message.sh` is the single source of truth.

Bundled copies that must match it verbatim:

- `plugin/hooks/lib/validate-commit-message.sh`
- `plugin-lite/hooks/lib/validate-commit-message.sh`

## Update Procedure

When `hooks/lib/validate-commit-message.sh` changes:

```bash
cp hooks/lib/validate-commit-message.sh plugin/hooks/lib/validate-commit-message.sh
cp hooks/lib/validate-commit-message.sh plugin-lite/hooks/lib/validate-commit-message.sh

# Verify the copies are byte-identical to the canonical source.
diff -q hooks/lib/validate-commit-message.sh plugin/hooks/lib/validate-commit-message.sh
diff -q hooks/lib/validate-commit-message.sh plugin-lite/hooks/lib/validate-commit-message.sh
# Both diffs MUST produce no output.
```

Both copies and the canonical source should land in the same commit so the
trees never appear drifted in history.

## CI Enforcement

`.github/workflows/validate-hooks.yml` runs the same `diff -q` checks on
every PR. If either bundled copy drifts from the canonical lib, the
workflow fails and the PR cannot merge. This guarantees the invariant
holds in `main` regardless of how the copies were produced (manual,
script, or future build tooling).

## Why Copy Instead of Symlink

Symlinks are not portable across the install paths the plugin supports
(Linux, macOS, Windows tarballs, git-subdir installs). A real file copy
is the only representation that survives every install transport. CI
diff is the integrity check that compensates for the lack of a single
filesystem inode.

## Future Work

A dedicated build script (`scripts/build-plugin.sh`) could automate the
copy step and stage tarballs for marketplace publication. Until that
exists, the manual copy + `diff -q` workflow above is the policy.
