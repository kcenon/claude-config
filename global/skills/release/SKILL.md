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

### 5. Create Git Tag

```bash
# Create annotated tag
git tag -a "v$VERSION" -m "Release v$VERSION"

# Push tag to remote
git push origin "v$VERSION"
```

### 6. Create GitHub Release

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

Three-team workflow for release creation. Dev team handles git operations, Review team validates changelog accuracy, Doc team formats release notes and documentation.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Version check │
         │ Final publish │
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│ Dev  │   │Review│   │ Doc  │
│ Team │◄──│ Team │   │ Team │
└──────┘   └──────┘   └──────┘
  dev     reviewer    doc-writer

  Dev: creates tag, manages git operations
  Reviewer: validates changelog accuracy and version correctness
  Doc-writer: formats release notes and updates CHANGELOG.md
```

### T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (Validate Version, Get Previous Tag).
Verify version format and collect commit range.

### T-2. Create Team and Tasks

```
TeamCreate(team_name="release-v$VERSION", description="Release v$VERSION for $ORG/$PROJECT")
```

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Generate raw changelog from commits | dev | — | A |
| 2 | Validate changelog accuracy and completeness | reviewer | 1 | B |
| 3 | Format release notes and update CHANGELOG.md | doc-writer | 1 | B |
| 4 | Apply changelog corrections (if reviewer has findings) | dev | 2 | C |
| 5 | Review formatted release notes | reviewer | 3 | C |
| 6 | Apply release notes corrections (if any) | doc-writer | 5 | D |
| 7 | Create git tag and push | dev | 2 or 4, 5 or 6 | E |
| 8 | Create GitHub release with final notes | lead | 7 | E |

### T-3. Spawn Teammates

**Dev Team** (git operations + changelog generation):

```
Agent(
  name="dev",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the dev team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 1: Generate raw changelog by categorizing commits since $PREVIOUS_TAG:
       - feat → Added, fix → Fixed, refactor/perf/style → Changed
       - docs → Documentation, test/chore/build/ci → Other
       Format: '- commit_message (short_hash)'
    2. Task 4: If reviewer reports inaccuracies in the changelog,
       correct the categorization or descriptions.
    3. Task 7: Create annotated git tag and push:
       git tag -a 'v$VERSION' -m 'Release v$VERSION'
       git push origin 'v$VERSION'

    Rules:
    - Commit format: chore(release): prepare v$VERSION (English only, no emojis)
    - Do NOT create tag until reviewer approves changelog

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (changelog validation):

```
Agent(
  name="reviewer",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the review team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 2: Validate the raw changelog:
       - Are commits categorized correctly? (feat vs fix vs refactor)
       - Are breaking changes identified and highlighted?
       - Are all commits since $PREVIOUS_TAG included?
       - Is the version bump appropriate? (major for breaking, minor for feat, patch for fix)
       Report any inaccuracies to dev.
    2. Task 5: Review the formatted release notes from doc-writer:
       - Professional formatting?
       - Accurate content matching the validated changelog?
       - Breaking changes section if applicable?

    Feedback: Send corrections to dev (Task 4) or doc-writer (Task 6) as needed.
    Max 1 review round for changelog, 1 for release notes.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (release notes formatting):

```
Agent(
  name="doc-writer",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the documentation team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 3: Format the raw changelog into professional release notes:
       - Add version header with date: ## [VERSION] - YYYY-MM-DD
       - Group by category: Added, Fixed, Changed, Documentation, Other
       - Remove empty categories
       - Add migration notes if breaking changes exist
    2. Update CHANGELOG.md file with the new release section
    3. Task 6: If reviewer suggests corrections, apply them

    Rules:
    - Follow existing CHANGELOG.md format if present
    - Commit format: docs(release): update CHANGELOG for v$VERSION

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

### T-4. Workflow Phases (Lead coordinates)

**Phase A — Changelog Generation:**
1. Dev generates raw changelog from git commits (Task 1)

**Phase B — Parallel Review + Formatting:**
1. Reviewer validates changelog accuracy (Task 2) ∥ Doc-writer formats release notes (Task 3)
2. These run in parallel — both depend on Task 1

**Phase C — Corrections (if needed):**
1. Dev applies changelog corrections from reviewer (Task 4)
2. Reviewer validates doc-writer's formatted notes (Task 5)

**Phase D — Final Adjustments:**
1. Doc-writer applies any corrections to release notes (Task 6)

**Phase E — Publish:**
1. Dev creates and pushes git tag (Task 7)
2. Lead creates GitHub release with final notes (Task 8):
   ```bash
   gh release create v$VERSION --repo $ORG/$PROJECT \
     --title "v$VERSION" --notes "$RELEASE_NOTES"
   ```

### T-5. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

### T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. If changelog was generated: offer to continue in Solo Mode from Step 5 (tag)
3. If nothing completed: offer full Solo restart

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

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Inside git repo | "Not a git repository" | Navigate to a git repository |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Invalid version format | Report "Invalid version format" with example | Use semver format (1.2.0) |
| Tag already exists | Report "Tag vX.X.X already exists" | Choose different version |
| No commits since last release | Report "No new commits since PREVIOUS_TAG" | Verify commit history |
| Tag push failed | Report "Failed to push tag" | Check repository permissions |
| Release creation failed | Report GitHub API error with details | Check repository permissions |
| Network error | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Team mode: teammate failure | Fallback to Solo Mode from last completed step | Automatic recovery |
| Team mode: reviewer disagrees on version | Report version concern to user for decision | User decides final version |
| Agent Teams not enabled | Fall back to Solo Mode with warning | Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
