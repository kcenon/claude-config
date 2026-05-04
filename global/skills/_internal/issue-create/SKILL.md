---
name: issue-create
description: Create well-structured GitHub issues using the 5W1H framework with proper labels and acceptance criteria.
argument-hint: "<project-name> [--type bug|feature] [--priority high|medium]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Bash(gh issue *)"
loop_safe: false
iso_class: A
applies_at_or_above: A
---

# Issue Create Command

Create well-structured GitHub issues using the 5W1H framework.

## Usage

```
/issue-create <project-name> [--type <type>] [--priority <priority>] [--org <organization>]
/issue-create <organization>/<project-name> [--type <type>] [--priority <priority>]
```

**Example**:
```
/issue-create hospital_erp_system                              # Interactive mode
/issue-create hospital_erp_system --type bug --priority high   # With options
/issue-create mycompany/hospital_erp_system --type feature     # Full repo path
```

## Arguments

`$ARGUMENTS` format: `<project-name> [options]` or `<organization>/<project-name> [options]`

- **Project name**: Repository name (or full path with organization)
- **--type**: Issue type (bug, feature, refactor, docs) - default: feature
- **--priority**: Priority level (critical, high, medium, low) - default: medium
- **--org**: GitHub organization or user (optional, auto-detected if not provided)

## Organization Detection

Parse `$ARGUMENTS` and determine organization:

```bash
# Check if --org flag is provided
if [[ "$ARGUMENTS" == *"--org"* ]]; then
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$ARGUMENTS" | sed -n 's/.*--org[[:space:]]*\([^[:space:]]*\).*/\1/p')
# Check if first argument contains / (full path format)
elif [[ "$(echo "$ARGUMENTS" | awk '{print $1}')" == *"/"* ]]; then
    REPO_PATH=$(echo "$ARGUMENTS" | awk '{print $1}')
    ORG=$(echo "$REPO_PATH" | cut -d'/' -f1)
    PROJECT=$(echo "$REPO_PATH" | cut -d'/' -f2)
# Auto-detect from git remote
else
    PROJECT=$(echo "$ARGUMENTS" | awk '{print $1}')
    cd "$PROJECT" 2>/dev/null || { echo "Error: Project directory not found: $PROJECT"; exit 1; }
    ORG=$(git remote get-url origin 2>/dev/null | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|' | sed -E 's|.*[:/]([^/]+)/[^/]+$|\1|')
    if [[ -z "$ORG" ]]; then
        echo "Error: Cannot detect organization. Use --org flag or full path format."
        exit 1
    fi
fi
```

## Phase 0a -- Regulated-track detection

After organization detection, before any prompts, detect whether the consumer project
is on the regulated-industry track. Set `$REGULATED_TRACK=true` when the project root
contains a `compliance/` directory (typically `compliance/iec-62304.md`, `iso-13485.md`,
`iso-14971.md`); set `$REGULATED_TRACK=false` otherwise.

```bash
# Resolve the consumer-project root from the parsed PROJECT name (or current cwd
# when invoked via the skill alias from inside a project).
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
if [ -d "$PROJECT_ROOT/$PROJECT" ]; then
    PROJECT_ROOT="$PROJECT_ROOT/$PROJECT"
fi

if [ -d "$PROJECT_ROOT/compliance" ]; then
    REGULATED_TRACK=true
else
    REGULATED_TRACK=false
fi
```

**Behavior matrix:**

| `$REGULATED_TRACK` | Effect on the rest of the skill |
|--------------------|---------------------------------|
| `false` (default) | Skill proceeds exactly as documented in sections 1-5 below. No regulated-field prompts. No template change. No behavior change relative to pre-#602 invocations. |
| `true` | After the standard prompts in section 1, the skill enters Phase 0b (regulated-fields prompts) before proceeding to section 2. The created issue body is built from the regulated-issue templates under `reference/templates/`, with the regulated metadata embedded in a YAML code block at the top so the `traceability` skill's next run picks it up. |

The detection is a single test on directory presence -- no parsing, no glob. When
`compliance/` is absent the skill is functionally identical to its pre-#602 form;
this is the most important functional invariant of this extension.

## Phase 0b -- Regulated-fields prompts (only when `$REGULATED_TRACK=true`)

Skipped entirely when `$REGULATED_TRACK=false`.

When the regulated track is active, after gathering the standard fields in section 1
the skill prompts for the additional metadata defined by the per-issue-type matrix in
`reference/regulated-fields.md`:

| Field | Prompt (asked when required by the type matrix) |
|-------|--------------------------------------------------|
| `requirement_id` | "Which requirement does this issue trace to (e.g. SRS-CALC-001)?" |
| `risk_level` | "What is the ISO 14971 risk level after controls (acceptable / ALARP / unacceptable)?" |
| `clause_refs` | "Which standard clauses justify this change? Comma-separated, e.g. IEC-62304-5.3.3, ISO-14971-7.3" |

**Field requirement enforcement:** see the matrix in `reference/regulated-fields.md`.
The skill MUST halt with a clear message when a required field is missing -- it MUST
NOT silently create a bare issue. Optional fields may be left blank.

**Field validation rules** (also in `reference/regulated-fields.md`):

1. `requirement_id` matches `^SRS-[A-Z0-9]+-[0-9]+$`. When `docs/.index/manifest.yaml`
   is present in the project, the value must resolve via the manifest's
   `id_routes.SRS` entry; unknown IDs are rejected with a list of close matches.
2. `risk_level` is one of the three ISO 14971 acceptability levels: `acceptable`,
   `ALARP`, `unacceptable`. Case-sensitive (matches the `risk-control` skill's
   record schema).
3. `clause_refs[]` entries match the format `<STANDARD>-<NUMBER>` per
   `traceability/reference/matrix-schema.md` (e.g. `IEC-62304-5.3.3`,
   `ISO-13485-7.3.3`, `ISO-14971-7.3`). When the matching `compliance/<standard>.md`
   file is present, each ID must resolve to an `> **Clause**: <id>` anchor in that
   file; unknown IDs are rejected.

The exact embedded YAML block format is documented in
`reference/regulated-fields.md` "Embedded YAML block format". Both regulated
templates under `reference/templates/` open with that block so the traceability
skill (and the future `pr-work` regulated extension landing in #603) can parse the
regulated metadata from the issue body without rerunning this skill.

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--type` | bug, feature, refactor, docs | feature | Issue type for labeling |
| `--priority` | critical, high, medium, low | medium | Priority level |
| `--org` | string | auto-detect | GitHub organization or user |

## Instructions

### 1. Gather Issue Details

Collect information through conversation:

| Field | Required | Prompt |
|-------|----------|--------|
| Title | Yes | "What is a brief title for this issue?" |
| Type | Yes | "Is this a bug, feature, refactor, or docs?" |
| Priority | Yes | "What priority: critical, high, medium, or low?" |
| Description | Yes | "Describe the issue in detail (What needs to be done?)" |
| Motivation | Yes | "Why is this needed? What problem does it solve?" |
| Acceptance Criteria | Yes | "What are the acceptance criteria?" |

### 2. Apply 5W1H Framework

Structure the issue using the 5W1H template:

```markdown
## What
<!-- Clear description of the task or problem -->

## Why
<!-- Motivation, impact, and business value -->

## Where
- Files/Components:
- Environment:
- Related Issues:

## How

### Technical Approach
<!-- High-level implementation plan if known -->

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

### 3. Determine Labels

Based on gathered information, select appropriate labels:

#### Type Labels

| Type | Label | Use When |
|------|-------|----------|
| Bug | `type/bug` | Something is broken |
| Feature | `type/feature` | New functionality |
| Refactor | `type/refactor` | Code improvement without behavior change |
| Docs | `type/docs` | Documentation changes |

#### Priority Labels

| Priority | Label | Use When |
|----------|-------|----------|
| Critical | `priority/critical` | Blocking production, security issue |
| High | `priority/high` | Important, needed soon |
| Medium | `priority/medium` | Standard priority |
| Low | `priority/low` | Nice to have |

#### Size Estimation (Optional)

| Size | Label | Expected LOC |
|------|-------|--------------|
| XS | `size/XS` | < 50 lines |
| S | `size/S` | 50-200 lines |
| M | `size/M` | 200-500 lines |
| L | `size/L` | 500-1000 lines |
| XL | `size/XL` | > 1000 lines (should be split) |

### 4. Create Issue

```bash
gh issue create --repo $ORG/$PROJECT \
  --title "[Type]: Title" \
  --label "type/<type>" \
  --label "priority/<priority>" \
  --body "$(cat <<'EOF'
## What
<description>

## Why
<motivation>

## Where
- Files/Components: <if known>
- Related Issues: <if any>

## How

### Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
EOF
)"
```

### 5. Confirm Creation

After creating the issue:
- Report the issue URL
- Summarize the created issue

## Title Conventions

| Type | Format | Example |
|------|--------|---------|
| Bug | `[Bug]: Brief description` | `[Bug]: Login fails with special characters` |
| Feature | `[Feature]: Brief description` | `[Feature]: Add dark mode toggle` |
| Refactor | `[Refactor]: Brief description` | `[Refactor]: Extract auth middleware` |
| Docs | `[Docs]: Brief description` | `[Docs]: Update API documentation` |

## Policies

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Title length | 50 characters or less (ideal) |
| Acceptance criteria | At least 2 testable items |

## Output

After completion, provide summary:

```markdown
## Issue Created

| Item | Value |
|------|-------|
| Repository | $ORG/$PROJECT |
| Issue | #NUMBER |
| URL | https://github.com/$ORG/$PROJECT/issues/NUMBER |
| Type | type |
| Priority | priority |

### Summary
- Title: <title>
- Description: <brief summary>
- Acceptance Criteria: N items
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| gh CLI installed | "GitHub CLI is not installed" | Install from https://cli.github.com |
| gh authenticated | "Not authenticated with GitHub" | Run `gh auth login` |
| Repository access | "Cannot access repository" | Verify repository permissions |
| Organization detected | "Cannot detect organization" | Use `--org` flag or full path format |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| Invalid type | Report valid options: bug, feature, refactor, docs | Choose from valid types |
| Invalid priority | Report valid options: critical, high, medium, low | Choose from valid priorities |
| Empty title | Prompt for title again | Provide a non-empty title |
| Issue creation failed | Report GitHub API error with details | Check repository permissions |
| Network timeout | Report "Cannot reach GitHub - check connection" | Verify internet connection |
| Label not found | Create issue without label, warn user | Labels may need to be created in repository |
