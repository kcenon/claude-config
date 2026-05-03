# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- `bootstrap.sh` pins the install source to a release tag instead of the floating
  `main` branch (SLSA-aligned supply-chain hardening). The default `GITHUB_REF`
  is `v1.10.0`, and `git clone` now uses `--branch "$GITHUB_REF" --depth 1`,
  which both anchors integrity to a tagged release and reduces clone size on
  bandwidth-constrained networks.
- `GITHUB_BRANCH` is preserved as a one-release deprecation alias for the new
  `GITHUB_REF` variable; setting it emits a stderr warning. Migrate any
  automation that overrides `GITHUB_BRANCH` to `GITHUB_REF` before the next
  major release.

[Unreleased]: https://github.com/kcenon/claude-config/compare/v1.10.0...HEAD
