---
name: release
description: Create a release with automated changelog generation from commits since last release using semantic versioning.
argument-hint: "<version> [--draft] [--prerelease] [--solo|--team]"
user-invocable: true
context: fork
allowed-tools:
  - Bash
---

# Release Command

Create a release with automated changelog generation from commits since last release.

## Usage

```
/release <version> [--draft] [--prerelease] [--org <organization>]
/release <organization>/<project-name> <version> [--draft] [--prerelease]
```

**Example**:
```
/release 1.2.0                           # Create release v1.2.0
/release 2.0.0 --draft                   # Create as draft release
/release 1.0.0-beta.1 --prerelease       # Create pre-release
/release mycompany/myrepo 1.5.0          # Specify repository explicitly
/release 1.2.0 --solo                           # Force solo mode
/release 1.2.0 --team                           # Force team mode (parallel)
```

## Arguments

`$ARGUMENTS` format: `<version> [options]` or `<organization>/<project-name> <version> [options]`

- **version**: Semantic version (e.g., 1.2.0, 2.0.0-beta.1)
- **--draft**: Create as draft release (not published)
- **--prerelease**: Mark as pre-release
- **--solo**: Force solo mode — single agent handles all steps sequentially
- **--team**: Force team mode — dev + reviewer + doc-writer in parallel
- If neither provided: auto-recommend based on commit count since last release
- **--org**: GitHub organization or user (optional, auto-detected if not provided)

## Organization Detection

Parse `$ARGUMENTS` and determine organization:

```bash
# Check if --org flag is provided
if [[ "$ARGUMENTS" == *"--org"* ]]; then
    VERSION=$(echo "$ARGUMENTS" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?')
    ORG=$(echo "$ARGUMENTS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
    PROJECT=$(basename "$(pwd)")
# Check if first argument contains / (full path format)
elif [[ "$(echo "$ARGUMENTS" | awk '{print $1}')" == *"/"* ]]; then
    REPO_PATH=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
    PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
    VERSION=$(echo "$ARGUMENTS" | awk '{print $2}')
# Auto-detect from git remote
else
    VERSION=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    PROJECT=$(git remote get-url origin 2>/dev/null | sed -E 's|.*/([^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--draft` | flag | false | Create release as draft (not published) |
| `--prerelease` | flag | false | Mark release as pre-release |
| `--org` | string | auto-detect | GitHub organization or user |

## Instructions

### Phase 0: Execution Mode Selection

#### 0-1. If `--solo` or `--team` flag was provided

Extract the flag from `$ARGUMENTS`. Use `$EXEC_MODE` directly.

#### 0-2. If no flag was provided (interactive selection)

Count commits since last release to estimate complexity:

```bash
PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [[ -n "$PREVIOUS_TAG" ]]; then
    COMMIT_COUNT=$(git rev-list --count $PREVIOUS_TAG..HEAD)
else
    COMMIT_COUNT=$(git rev-list --count HEAD)
fi
```

| Signal | Solo (Recommended) | Team (Recommended) |
|--------|-------------------|-------------------|
| Commits since last release | < 20 | 20+ |
| Release type | Patch (x.x.X) | Major/Minor (X.x.x, x.X.x) |
| Has breaking changes | No | Yes |

Use `AskUserQuestion` to present the choice:

- **Question**: "Release v$VERSION with $COMMIT_COUNT commits. Which execution mode?"
- **Header**: "Mode"
- **Options**:
  1. Recommended mode with "(Recommended)" suffix
  2. The other mode
- **Description for Solo**: "Sequential release process. Lower token cost. Best for small patch releases."
- **Description for Team**: "3-team parallel: dev handles git ops + reviewer validates changelog + doc-writer formats release notes. Best for major releases."

Store the result in `$EXEC_MODE` (solo | team).

#### 0-3. Mode Routing

- If `$EXEC_MODE == "solo"` → Execute **Solo Mode** (Steps 1-6 below, unchanged)
- If `$EXEC_MODE == "team"` → Execute **Team Mode Instructions**

---

## Solo Mode

### 1. Validate Version Format

Ensure version follows semantic versioning:

```bash
# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    echo "Error: Invalid version format. Use semantic versioning (e.g., 1.2.0, 2.0.0-beta.1)"
    exit 1
fi

# Check if tag already exists
if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Error: Tag v$VERSION already exists"
    exit 1
fi
```

### 2. Get Previous Release Tag

```bash
# Get the most recent tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$PREVIOUS_TAG" ]]; then
    echo "No previous release found. Generating changelog from all commits."
    COMMIT_RANGE="HEAD"
else
    echo "Previous release: $PREVIOUS_TAG"
    COMMIT_RANGE="$PREVIOUS_TAG..HEAD"
fi
```

### 3. Generate Changelog

Collect and categorize commits since last release:

```bash
# Get commits since last release
COMMITS=$(git log $COMMIT_RANGE --pretty=format:"%s|%h|%an" --no-merges)

# Initialize category arrays
ADDED=""
FIXED=""
CHANGED=""
DOCS=""
OTHER=""

# Categorize commits by type prefix
while IFS='|' read -r message hash author; do
    # Extract type from conventional commit format
    TYPE=$(echo "$message" | grep -oE '^(feat|fix|docs|refactor|perf|test|chore|style|build|ci)' || echo "other")

    case "$TYPE" in
        feat)
            ADDED="$ADDED\n- $message ($hash)"
            ;;
        fix)
            FIXED="$FIXED\n- $message ($hash)"
            ;;
        refactor|perf|style)
            CHANGED="$CHANGED\n- $message ($hash)"
            ;;
        docs)
            DOCS="$DOCS\n- $message ($hash)"
            ;;
        *)
            OTHER="$OTHER\n- $message ($hash)"
            ;;
    esac
done <<< "$COMMITS"
```

### 4. Format Changelog

Structure the changelog with categories:

```markdown
## [VERSION] - YYYY-MM-DD

### Added
- feat(scope): description (abc1234)
- feat: another feature (def5678)

### Fixed
- fix(scope): bug description (ghi9012)

### Changed
- refactor(scope): improvement (jkl3456)
- perf: optimization (mno7890)

### Documentation
- docs: update readme (pqr1234)

### Other
- chore: maintenance task (stu5678)
```

### 5. Create Release PR (develop -> main)

Create a pull request from `develop` to `main` with the changelog as the PR body:

```bash
# Ensure we are on the develop branch with latest changes
git checkout develop
git pull origin develop

# Create release PR targeting main
PR_URL=$(gh pr create --repo $ORG/$PROJECT \
  --base main --head develop \
  --title "release: v$VERSION" \
  --body "$CHANGELOG")

PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "Created release PR #$PR_NUMBER: $PR_URL"
```

### 6. Monitor CI and Merge

Wait for CI to pass on the release PR, then squash merge:

```bash
# Wait briefly for workflows to register
sleep 8

# Poll CI checks (30s intervals, 10min max)
# See issue-work reference for full CI monitoring protocol
gh pr checks $PR_NUMBER --repo $ORG/$PROJECT

# ALL checks must pass before proceeding
gh pr merge $PR_NUMBER --repo $ORG/$PROJECT --squash
```

**IMPORTANT**: Do NOT use `--delete-branch` — the `develop` branch must be retained.

If CI fails, diagnose and fix on `develop`, push, and re-poll. Max 3 attempts.

### 7. Create Git Tag on main

```bash
# Switch to main and pull the merged commit
git checkout main
git pull origin main

# Create annotated tag on main
git tag -a "v$VERSION" -m "Release v$VERSION"

# Push tag to remote
git push origin "v$VERSION"

# Return to develop branch
git checkout develop
```

### 8. Create GitHub Release

```bash
# Build release command
RELEASE_CMD="gh release create v$VERSION --repo $ORG/$PROJECT --title \"v$VERSION\""

# Add draft flag if specified
if [[ "$ARGUMENTS" == *"--draft"* ]]; then
    RELEASE_CMD="$RELEASE_CMD --draft"
fi

# Add prerelease flag if specified
if [[ "$ARGUMENTS" == *"--prerelease"* ]]; then
    RELEASE_CMD="$RELEASE_CMD --prerelease"
fi

# Add changelog as release notes
RELEASE_CMD="$RELEASE_CMD --notes \"\$CHANGELOG\""

# Execute release creation
eval $RELEASE_CMD
```

## Changelog Categories

Commits are categorized based on conventional commit prefixes:

| Prefix | Category | Description |
|--------|----------|-------------|
| `feat` | Added | New features |
| `fix` | Fixed | Bug fixes |
| `refactor` | Changed | Code refactoring |
| `perf` | Changed | Performance improvements |
| `style` | Changed | Code style changes |
| `docs` | Documentation | Documentation updates |
| `test` | Other | Test additions/changes |
| `chore` | Other | Maintenance tasks |
| `build` | Other | Build system changes |
| `ci` | Other | CI configuration changes |

---

## Team Mode Instructions

See `reference/team-mode.md` for the complete team mode workflow with changelog and release coordination.

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Version format | Semantic versioning required (MAJOR.MINOR.PATCH) |
| Tag prefix | Always use `v` prefix (e.g., v1.2.0) |
| Duplicate tags | Prevent creation if tag exists |

## Output

After completion, provide summary:

```markdown
## Release Created

| Item | Value |
|------|-------|
| Repository | ORG/PROJECT |
| Version | vVERSION |
| Type | Release / Draft / Pre-release |
| Execution mode | Solo / Team |
| Tag | vVERSION |
| URL | https://github.com/ORG/PROJECT/releases/tag/vVERSION |

### Changelog Summary
| Category | Count |
|----------|-------|
| Added | N |
| Fixed | N |
| Changed | N |
| Documentation | N |
| Other | N |

### Commits Included
- Total: N commits since PREVIOUS_TAG
```

## Error Handling

See `reference/error-handling.md` for prerequisite checks and runtime error handling.
