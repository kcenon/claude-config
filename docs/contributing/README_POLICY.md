# README Evidence Policy

The root [README](../../README.md) and its Korean copy
[README.ko.md](../../README.ko.md) are entry pages: status, quick start, what
you get, installation, a documentation index, versioning, contributing, and
license. The detail lives in [`docs/guides/`](../guides/). Each README must be
nonempty and at most 300 physical lines, including code, comments, and blank
lines. When a README section grows past one screen (about 50 lines), move it to
a `docs/` page and link it. Do not compress unrelated paragraphs or add filler
to meet the limit. The two copies keep the same heading structure and inline
paths; `scripts/diff-readme.sh` checks that.

## Local Check

Run from the repository root:

```sh
python3 tests/scripts/test_readme_lint.py
python3 scripts/readme_lint.py
```

The [standard-library linter](../../scripts/readme_lint.py) checks `README.md`
and, when it exists, `README.ko.md` by default. It resolves paths from its own
checkout and accepts explicit file paths and `--root` for other checkouts or
fixtures. Findings use `path:line: rule: message`. Violations and unreadable
files return a nonzero status. It never uses the network.
[Documentation Audit](../../.github/workflows/doc-audit.yml) runs the tests and
the linter on pull requests that change a README, `VERSION_MAP.yml`, `docs/`,
the linter or its test, or a workflow file.

## Status and Release

After the title, and within the first 20 lines, show `Status: active`,
`Status: maintenance`, or `Status: experimental`, and link the release tag. The
status describes project activity, not quality. The linked tag must match the
`suite` field of `VERSION_MAP.yml`; `scripts/sync_versions.sh` updates the link
when a release bumps `suite`, and `scripts/check_versions.sh` fails when they
differ. The linter checks the format and the `suite` match offline; a reviewer
checks that the tag exists.

## Badges

Use badges only for workflows in this repository. The image URL and the click
URL must name the same `.yml` or `.yaml` file in `.github/workflows/`, and that
file must exist. Keep the license, the version, and service links as prose.

## Claims and Density

Remove promotional qualifiers, including production-ready, enterprise-grade,
battle-tested, blazing, world-class, comprehensive, robust, seamless, 100%,
guaranteed, and zero-overhead, zero-warning, zero-leak, or zero-race wording. A
citation does not exempt a banned qualifier. Describe a capability by what the
repository shows, such as the file a hook blocks or the command a skill runs.

The linter recognizes speedup multipliers, latency and throughput units,
percentages, test pass counts, and allocation counts in visible prose.
Measurements belong in a `docs/` page that names how they were taken, such as
[docs/TOKEN_OPTIMIZATION.md](../TOKEN_OPTIMIZATION.md) and
[docs/tier2-benchmark-results.md](../tier2-benchmark-results.md). Versions,
dates, list numbers, link destinations, and fenced or indented code are not
measurements.

Density is `100 * distinct prose lines containing a qualifier or measurement /
total physical lines`. The maximum is 1.0 per 100 lines.

A headline figure may stay in a README only with an adjacent marker. The marker
links a `docs/` section that names the environment, date, command, and raw
result:

```markdown
Measured claim. <!-- source: docs/<page>.md#<anchor> (YYYY-MM-DD, <environment>) -->
```

The parser checks marker structure and local links, not whether the measurement
supports the claim. Reviewers check that.

## Provenance

`scripts/readme_lint.py` is a port of the kcenon/dcmtk-docker README lint,
itself a port of the kcenon/common_system lint at commit `c2f4037`, with the
same rules. This port also checks `README.ko.md` and reads the release version
from `VERSION_MAP.yml`. It keeps the upstream Korean patterns, so later
upstream fixes stay easy to carry over.
