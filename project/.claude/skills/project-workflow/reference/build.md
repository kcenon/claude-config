---
alwaysApply: false
paths:
  - "**/CMakeLists.txt"
  - "**/*.cmake"
  - "**/Makefile"
  - "**/makefile"
  - "**/*.mk"
  - "**/BUILD"
  - "**/BUILD.bazel"
  - "**/WORKSPACE"
  - "**/WORKSPACE.bazel"
  - "**/build.gradle"
  - "**/build.gradle.kts"
  - "**/settings.gradle"
  - "**/settings.gradle.kts"
  - "**/gradle.properties"
  - "**/pom.xml"
  - "**/package.json"
  - "**/package-lock.json"
  - "**/npm-shrinkwrap.json"
  - "**/yarn.lock"
  - "**/pnpm-lock.yaml"
  - "**/go.mod"
  - "**/go.sum"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
  - "**/pyproject.toml"
  - "**/requirements*.txt"
  - "**/Pipfile"
  - "**/Pipfile.lock"
  - "**/poetry.lock"
  - "**/Gemfile"
  - "**/Gemfile.lock"
  - "**/composer.json"
  - "**/composer.lock"
  - "**/Dockerfile"
  - "**/docker-compose*.yml"
  - "**/docker-compose*.yaml"
  - "**/*.csproj"
  - "**/*.fsproj"
  - "**/*.vbproj"
  - "**/*.sln"
---

# Build and Dependency Management

## Use Appropriate Tools

Select build and dependency management tools based on your language:

- **C/C++**: CMake (cross-platform builds, `cmake_minimum_required(VERSION 3.20)`, explicit `CMAKE_CXX_STANDARD`) with vcpkg or Conan for packages
- **Kotlin/Java**: Gradle (Kotlin DSL) or Maven
- **TypeScript/JavaScript**: npm or yarn, with `build` / `test` / `lint` scripts in `package.json`
- **Python**: Poetry (recommended) or pip with pinned `requirements.txt` / `requirements-dev.txt`

## Separate Environments

### Development vs Production

**Key differences**:

| Aspect | Development | Production |
|--------|-------------|------------|
| Debug symbols | Included | Stripped |
| Optimizations | Minimal (-O0/-O1) | Maximum (-O3) |
| Assertions | Enabled | Disabled |
| Logging | Verbose | Essential only |
| Dependencies | Include dev tools | Runtime only |

Select the profile explicitly (`CMAKE_BUILD_TYPE`, `NODE_ENV`, one Python virtual
environment per project) rather than relying on defaults.

## Pin Dependency Versions

### Why Pin Versions?

- **Reproducibility**: Same build results across machines and time
- **Stability**: Avoid breaking changes from automatic updates
- **Security**: Control when to adopt updates with known vulnerabilities

### Version Pinning Strategies

- **Exact version** (most strict): `"express": "4.18.2"`
- **Minor version range** (recommended): `"express": "~4.18.2"`
- **Major version range**: `"express": "^4.18.2"`

Use exact versions for production-critical dependencies.

### Lock Files

Always commit lock files to version control:

- **npm**: `package-lock.json`
- **yarn**: `yarn.lock`
- **pip**: `requirements.txt` (with exact versions) or `poetry.lock`
- **Gradle**: `gradle.lockfile`
- **Go**: `go.sum`

## Build Reproducibility

- Pin base image versions in Dockerfiles and install dependencies from the lock file before copying application code
- Pin runner OS and toolchain versions in CI (e.g. `ubuntu-22.04`, an exact Python version)

## Dependency Updates

### Regular Update Strategy

1. **Monitor for updates**: Use tools like Dependabot, Renovate
2. **Review changelogs**: Understand what changed
3. **Test thoroughly**: Run full test suite after updates
4. **Update incrementally**: One or few dependencies at a time
5. **Document breaking changes**: Note required code changes

## Build Optimization

- **Incremental builds**: `ccache` for CMake; `org.gradle.caching=true` and `org.gradle.parallel=true` for Gradle
- **Dependency caching in CI**: cache package-manager directories keyed on the lock file hash

> Examples: see `.claude/reference/project-management/build-examples.md`
