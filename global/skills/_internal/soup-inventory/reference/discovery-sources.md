# SOUP Discovery Sources

Per-language lockfile parsers used by the `soup-inventory` skill's `discover` subcommand.
For each ecosystem this file documents the lockfile path glob, the parser strategy, and
which fields the parser auto-populates on a candidate SOUP record.

> **Loading**: Loaded under `tier: standard` and `tier: deep` via the skill's `ref_docs.sources`
> entry. Skip when invoking under `tier: light`.

The skill body must not invent discovery strategies -- it implements exactly the contracts
documented here. Adding a new ecosystem requires updating this file and adding a parser
implementation note.

## Discovery Contract Template

Each section below follows this structure:

| Field | Meaning |
|-------|---------|
| **Lockfile glob** | Path glob the discoverer scans for. Project-relative. |
| **Lockfile authority** | Whether the file is the canonical pin (always YES for discovery; the manifest file like `package.json` is not used). |
| **Auto-populated fields** | Fields the parser fills on a candidate record. Other fields are left to `enrich`. |
| **Field-extraction rules** | Per-field rules for where in the lockfile each value comes from. |
| **Skip rules** | Lockfile entry types that are intentionally not added to the SOUP register (e.g. dev-only test fixtures, the project's own packages). |

The discoverer always treats the lockfile as the source of truth for `(name, version)`
pairs. Manifest files (`package.json`, `pyproject.toml` `[project]` table, `Cargo.toml`,
`go.mod`) are not used because they often carry version ranges rather than exact pins, and
the SOUP register requires exact pins per IEC 62304 §8.1.1.

## ecosystem: npm (Node.js)

| Field | Value |
|-------|-------|
| **Lockfile glob** | `package-lock.json` (root or any sub-directory checked into the repo) |
| **Lockfile authority** | YES -- `lockfileVersion >= 2` carries flat `packages{}` with exact versions and license metadata. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` from the `packages.<path>.name` (or the path key when name is absent). `version` from `packages.<path>.version`. `license_spdx` from `packages.<path>.license` (string form) or the `licenses[].type` array fallback. `supplier` from `packages.<path>._npmUser.name` when present, else from the `homepage` URL host, else `"unknown"`. `source_url` from `packages.<path>.repository.url` (stripped of `git+` prefix), else from `homepage`, else from `https://www.npmjs.com/package/<name>`. |
| **Skip rules** | Skip the root entry (the project itself). Skip entries with `dev: true` whose path matches the configured dev-only allow-list (default: empty -- the operator opts in by setting `soup-license-policy.yaml` `npm.skip_dev: true`). |

The npm v2/v3 lockfile schema is the only supported form. Older `package-lock.json` v1 files
are detected and emit a parse error directing the operator to upgrade with
`npm install --package-lock-only`.

## ecosystem: PyPI (Python)

| Field | Value |
|-------|-------|
| **Lockfile glob** | `requirements.txt`, `requirements-*.txt`, `pyproject.toml` (when `[tool.poetry.lock]` or `[tool.uv.lock]` is present), `poetry.lock`, `uv.lock`, `Pipfile.lock` |
| **Lockfile authority** | YES when the file pins exact versions (`==X.Y.Z`). `requirements.txt` files using `~=` or `>=` are not authoritative and emit a parse error directing the operator to use `pip-compile` or a true lockfile. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` from the requirement specifier or the lockfile's `package.name`. `version` from `==X.Y.Z` or `package.version`. `license_spdx` from PyPI metadata cached in the lockfile (`poetry.lock` `package.metadata.license`, `uv.lock` `[[package]] license`); falls back to `UNKNOWN` for `requirements.txt` since it carries no license metadata. `supplier` from `package.metadata.author` when present, else `"unknown"`. `source_url` from `package.metadata.home-page` or `package.source.url` for git/path sources, else `https://pypi.org/project/<name>/<version>/`. |
| **Skip rules** | Skip `python` itself when the lockfile lists it as a dependency. Skip editable installs (`-e .` or `develop = true`) since they refer to the project's own source. |

Plain `requirements.txt` files without exact pins are common but unsuitable for SOUP
discovery. The skill emits a parse error rather than guess versions; the operator is
expected to materialize a true lockfile via `pip-compile` (pip-tools), `poetry lock`, or
`uv lock`.

## ecosystem: Go modules

| Field | Value |
|-------|-------|
| **Lockfile glob** | `go.sum` (alongside `go.mod` for module path resolution) |
| **Lockfile authority** | YES -- `go.sum` carries exact module versions and content hashes. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` from the module path (e.g. `github.com/gin-gonic/gin`). `version` from the version column (`v1.9.1`); the `/go.mod` rows are skipped (they are duplicate hashes). `supplier` from the module path's host + first path segment (e.g. `github.com/gin-gonic` -> `gin-gonic`); falls back to `"unknown"` for non-VCS hosts. `source_url` constructed as `https://<module-path>` (Go's import-path convention). `license_spdx` is `UNKNOWN` (Go modules carry no in-lockfile license metadata; the operator resolves via `go-licenses` or manual inspection during `enrich`). |
| **Skip rules** | Skip the project's own module (matched against the `module` directive in `go.mod`). Skip `+incompatible` versions only when `soup-license-policy.yaml` `go.skip_incompatible: true` (off by default). |

Go's lockfile-as-content-addressable-store design means license metadata is intentionally
out-of-band. The `UNKNOWN` license forces operator review on `validate --ci`, which is the
correct conservative default for an audit-facing register.

## ecosystem: Cargo (Rust)

| Field | Value |
|-------|-------|
| **Lockfile glob** | `Cargo.lock` |
| **Lockfile authority** | YES -- `Cargo.lock` pins exact crate versions and source URLs. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` from each `[[package]] name`. `version` from `[[package]] version`. `source_url` from `[[package]] source` (stripped of the `registry+` or `git+` prefix); falls back to `https://crates.io/crates/<name>` for crates.io packages. `supplier` from the source URL's host + author (e.g. `crates.io/<name>` -> `crates.io`); refined by the operator. `license_spdx` is `UNKNOWN` (Cargo lockfile does not carry license metadata; `cargo metadata --format-version 1` does, but invoking it requires an active toolchain so the discoverer keeps the parser pure-text). |
| **Skip rules** | Skip the workspace root and any `[[package]]` entry whose `source` field is absent (those are local path dependencies, i.e. the project itself). |

Rust's situation mirrors Go: license metadata is not in the lockfile. The operator resolves
via `cargo-license` or manual inspection during `enrich`.

## ecosystem: Maven (Java)

| Field | Value |
|-------|-------|
| **Lockfile glob** | `pom.xml` (when used with the Maven Resolver locking plugin or `mvn dependency:resolve` output checked in), or `dependency-tree.txt` produced by `mvn dependency:tree -DoutputFile=...` |
| **Lockfile authority** | YES when using the Maven Resolver locking plugin (`.mvn/dependency-locks/*.xml`); otherwise the discoverer falls back to parsing the explicit `<version>` pins in `pom.xml` and refuses to discover from version ranges. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` constructed as `<groupId>:<artifactId>`. `version` from the locked `<version>` (or the pinned `<version>` in `pom.xml`). `supplier` from `<organization><name>` when present, else from the `<groupId>` (e.g. `org.apache.commons` -> `Apache Commons`). `source_url` from `<scm><url>` or `<url>`, else `https://search.maven.org/artifact/<groupId>/<artifactId>/<version>/jar`. `license_spdx` from `<licenses><license><name>` mapped to the closest SPDX id; emits `UNKNOWN` when the mapping is ambiguous. |
| **Skip rules** | Skip the parent POM and the project's own artifact (matched against the top-level `<groupId>:<artifactId>`). Skip `<scope>test</scope>` dependencies when `soup-license-policy.yaml` `maven.skip_test: true` (off by default). |

The Maven ecosystem's SPDX mapping is imperfect; the parser uses a conservative subset
(MIT, Apache-2.0, BSD-2/3-Clause, EPL-1.0/2.0, GPL-2.0/3.0, LGPL-2.1/3.0, MPL-2.0) and falls
back to `UNKNOWN` for everything else. The operator refines via `enrich`.

## ecosystem: NuGet (.NET)

| Field | Value |
|-------|-------|
| **Lockfile glob** | `packages.lock.json` (per-project, requires `<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>` in the `.csproj`) |
| **Lockfile authority** | YES -- `packages.lock.json` pins exact NuGet package versions per target framework. |
| **Auto-populated fields** | `name`, `version`, `supplier`, `source_url`, `license_spdx` |
| **Field-extraction rules** | `name` from each `dependencies.<framework>.<name>` key. `version` from the `resolved` field (not `requested`, which may be a range). `supplier` from `https://api.nuget.org/v3/registration5-semver1/<name>/index.json` cached in `packages.lock.json` `contentHash`-adjacent metadata when present; falls back to `"unknown"`. `source_url` is `https://www.nuget.org/packages/<name>/<version>`. `license_spdx` is `UNKNOWN` (NuGet's per-package license metadata is fetched on restore but not persisted to the lockfile; the operator resolves via `dotnet list package --vulnerable --include-transitive` or the NuGet web UI). |
| **Skip rules** | Skip entries marked `type: Project` (those are project-references). Skip the framework reference packages (`Microsoft.NETCore.App.Ref`, `Microsoft.AspNetCore.App.Ref`, etc.) that ship with the .NET SDK rather than as third-party SOUP. |

NuGet projects without `packages.lock.json` cannot be discovered automatically -- the
operator must enable `<RestorePackagesWithLockFile>` first. The skill emits an informational
message rather than a parse error in this case (the project may not have opted into lockfiles
yet).

## Multi-ecosystem Projects

A consumer project may have multiple lockfiles (e.g. a Node.js frontend plus a Python
backend). The discoverer scans for all supported lockfile globs in parallel and merges
candidates into a single register. Id collisions (same `(name, version)` pair from two
ecosystems) are impossible by construction because npm and PyPI do not share package names
across registries -- the namespace is scoped per ecosystem. When a true name collision
occurs (rare), the discoverer prefixes the id label with the ecosystem (`npm:express` vs
`maven:io.express:express`) and the operator can rename via `enrich`.

## Skip-List Mechanism

The `soup-license-policy.yaml` per-project override file (see `license-policy.md`) carries
an optional `skip:` section listing `(name, version)` pairs to exclude from the register.
This is the escape hatch for documented exemptions (e.g. internal mirror packages that are
audited via a separate process). Format:

```yaml
skip:
  - name: "internal-mirror-pkg"
    version: "*"           # "*" means all versions
    reason: "Audited via internal-quality-system; tracked outside SOUP register"
  - name: "lodash"
    version: "4.17.21"
    reason: "Audited under SOUP-002 in v1.0.0; pre-existing register entry"
```

The discoverer logs each skip on stdout for the audit trail. Skipped entries do not appear
in `soup.yaml`.

## Adding a New Ecosystem

When a new lockfile-bearing ecosystem must be supported (e.g. `composer.lock` for PHP,
`mix.lock` for Elixir, `Gemfile.lock` for Ruby):

1. Pick a snake_case ecosystem id matching the existing pattern.
2. Add a section to this file with all five contract fields populated.
3. Document the field-extraction rules in enough detail that a second implementer would
   produce byte-identical candidate records on the same input.
4. Update the skill body's Phase 1 step 1 candidate-lockfile list (the `discover` subcommand
   description in `../SKILL.md`).
5. Bump `_meta.schema` minor in `soup-record-schema.md` only if the new ecosystem requires
   a new optional field on the record schema (e.g. `framework_target` for NuGet).

## Cross-references

- Record shape: `soup-record-schema.md`
- License allow-list and override format: `license-policy.md`
- Skill body that runs these parsers: `../SKILL.md`
- Source of truth for SOUP-relevant clauses: `compliance/iec-62304.md` (project root)
