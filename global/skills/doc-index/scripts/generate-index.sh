#!/usr/bin/env bash
# generate-index.sh — Generate document index files for project documentation
# Part of the /doc-index skill
# Usage: bash generate-index.sh [project-directory]
#
# Generates four YAML index files in docs/.index/:
#   manifest.yaml — Document registry with metadata, sections, and tags
#   bundles.yaml  — Feature-grouped document sets with token estimates
#   graph.yaml    — Cross-reference dependency graph with cascade analysis
#   router.yaml   — Keyword-to-bundle query routing with ID routes

set -uo pipefail

# ============================================================
# Configuration
# ============================================================

SCHEMA_VERSION="1.0.0"
PROJECT_DIR="${1:-.}"
INDEX_DIR=""
CUSTOM_SECTION=""

# Global arrays
declare -a ALL_FILES=()
TOTAL_FILES=0
TOTAL_REFS=0
TOTAL_SIZE=0
START_TIME=$(date +%s)

# Temp file for graph references
REF_TMPFILE=""

# Caches (populated in pre-processing loop)
declare -A FM_CACHE=()
declare -A SECTION_CACHE=()
declare -A DOC_ID_CACHE=()
declare -A TITLE_CACHE=()
declare -A SIZE_CACHE=()

# Mode: "flat" (no doc_id) or "grouped" (has doc_id)
MANIFEST_MODE="flat"

# ============================================================
# Logging
# ============================================================

info()    { printf '\033[0;34m[INFO]\033[0m %s\n' "$1" >&2; }
warn()    { printf '\033[1;33m[WARN]\033[0m %s\n' "$1" >&2; }
error()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2; }
success() { printf '\033[0;32m[OK]\033[0m %s\n' "$1" >&2; }

# ============================================================
# Cleanup
# ============================================================

cleanup() {
  [[ -n "${REF_TMPFILE:-}" && -f "${REF_TMPFILE:-}" ]] && rm -f "$REF_TMPFILE"
}
trap cleanup EXIT

# ============================================================
# YAML Helpers
# ============================================================

# Safely escape a string for YAML double-quoted output
emit_yaml_string() {
  local val="$1"
  val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$val"
}

get_timestamp() {
  if command -v gdate &>/dev/null; then
    gdate --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
  else
    date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%d'
  fi
}

# Emit _meta header (replaces old version/generated/total_files)
emit_meta() {
  local file_type="$1"
  printf '_meta: {schema: "%s", generated: "%s"' "$SCHEMA_VERSION" "$(date +%Y-%m-%d)"
  if [[ "$file_type" == "manifest" ]]; then
    local total_mb
    total_mb=$(awk "BEGIN{printf \"%.2f\", $TOTAL_SIZE/1048576}" 2>/dev/null || echo "0.00")
    printf ', docs: %d, size_mb: %s' "$TOTAL_FILES" "$total_mb"
  fi
  printf '}\n'
}

# ============================================================
# Frontmatter Extraction
# ============================================================

# Extract raw YAML frontmatter text (between --- delimiters)
extract_frontmatter() {
  local file="$1"
  local in_fm=false
  local result=""
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    if [[ "$line" == "---" ]]; then
      if $in_fm; then break; fi
      in_fm=true
      continue
    fi
    if $in_fm; then result+="${line}"$'\n'; fi
  done < "$file"
  printf '%s' "$result"
}

# Get a top-level scalar field from frontmatter
get_fm_field() {
  local fm="$1" field="$2"
  local val
  val=$(printf '%s' "$fm" | grep -E "^${field}:" 2>/dev/null | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" | tr -d '\r' || true)
  printf '%s' "$val"
}

# Get an array field from frontmatter (handles [a, b] and - a\n- b)
get_fm_array_field() {
  local fm="$1" field="$2"
  local line
  line=$(printf '%s' "$fm" | grep -E "^${field}:" 2>/dev/null | head -1 || true)
  [[ -z "$line" ]] && return

  local val
  val=$(printf '%s' "$line" | sed "s/^${field}:[[:space:]]*//" | tr -d '\r')

  if [[ "$val" == "["* ]]; then
    # Inline array: [a, b, c]
    printf '%s' "$val" | sed 's/^\[//;s/\]$//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
  else
    # Block array: read subsequent - lines
    local found=false
    printf '%s\n' "$fm" | while IFS= read -r l; do
      l=$(printf '%s' "$l" | tr -d '\r')
      if [[ "$l" == "${field}:"* ]]; then
        found=true
        continue
      fi
      if $found; then
        if [[ "$l" == "  -"* || "$l" == "- "* ]]; then
          printf '%s\n' "$(printf '%s' "$l" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/')"
        elif [[ "$l" == "  "* || "$l" == "" ]]; then
          continue
        else
          break
        fi
      fi
    done
  fi
}

# Get a nested field from frontmatter (e.g., "regulatory.hazard_ids")
get_fm_nested_field() {
  local fm="$1" dotpath="$2"
  local parent="${dotpath%%.*}"
  local child="${dotpath#*.}"

  # Find parent section and extract child
  local in_parent=false
  local indent=""
  printf '%s\n' "$fm" | while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    if [[ "$line" == "${parent}:"* ]] && ! $in_parent; then
      in_parent=true
      continue
    fi
    if $in_parent; then
      if [[ "$line" == "  ${child}:"* ]]; then
        printf '%s' "$line" | sed "s/^[[:space:]]*${child}:[[:space:]]*//"
        return
      elif [[ "$line" != "  "* && "$line" != "" ]]; then
        break
      fi
    fi
  done
}

# ============================================================
# Title & Description Extraction
# ============================================================

extract_title() {
  local file="$1" fm="$2"

  # Priority: frontmatter name > first # heading > filename stem
  local name
  name=$(get_fm_field "$fm" "name")
  [[ -n "$name" ]] && { printf '%s' "$name"; return; }

  name=$(get_fm_field "$fm" "doc_title")
  [[ -n "$name" ]] && { printf '%s' "$name"; return; }

  local heading
  heading=$(tr -d '\r' < "$file" | grep -m1 '^# ' 2>/dev/null | sed 's/^# //' || true)
  [[ -n "$heading" ]] && { printf '%s' "$heading"; return; }

  # Filename stem with title case
  local stem
  stem=$(basename "$file" .md | tr '-' ' ' | tr '_' ' ')
  printf '%s' "$stem"
}

extract_description() {
  local file="$1" fm="$2"

  local desc
  desc=$(get_fm_field "$fm" "description")
  if [[ -n "$desc" ]]; then
    printf '%s' "${desc:0:80}"
    return
  fi

  # First non-empty, non-heading, non-frontmatter line
  local in_fm=false past_fm=false
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '\r')
    [[ "$line" == "---" ]] && { if ! $past_fm; then if $in_fm; then past_fm=true; in_fm=false; else in_fm=true; fi; fi; continue; }
    $in_fm && continue
    [[ -z "$line" ]] && continue
    [[ "$line" == "#"* ]] && continue
    [[ "$line" == ">"* ]] && continue
    printf '%s' "${line:0:80}"
    return
  done < "$file"
}

# ============================================================
# Classification (for flat mode)
# ============================================================

classify_category() {
  local rel="$1"
  case "$rel" in
    */skills/*/SKILL.md) echo "skill" ;;
    */agents/*.md)       echo "agent" ;;
    */_policy.md)        echo "policy" ;;
    */rules/*.md|*/coding/*.md|*/workflow/*.md|*/api/*.md|*/security*.md|*/operations/*.md|*/project-management/*.md|*/core/*.md)
                         echo "rule" ;;
    */reference/*.md)    echo "reference" ;;
    */design/*.md)       echo "design" ;;
    *settings*|*config*|*CLAUDE.md|*HOOKS*|*hooks*) echo "config" ;;
    *)                   echo "root" ;;
  esac
}

classify_scope() {
  local rel="$1"
  case "$rel" in
    global/*)       echo "global" ;;
    plugin-lite/*)  echo "plugin-lite" ;;
    plugin/*)       echo "plugin" ;;
    project/*)      echo "project" ;;
    enterprise/*)   echo "enterprise" ;;
    docs/*)         echo "docs" ;;
    *)              echo "root" ;;
  esac
}

# ============================================================
# Tag Generation
# ============================================================

generate_tags() {
  local rel="$1" fm="$2" file="$3"

  local -a tags=()

  # Stem tag
  local stem
  stem=$(basename "$rel" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  [[ "$stem" != "readme" && "$stem" != "index" ]] && tags+=("$stem")

  # Directory tag
  local dirn
  dirn=$(basename "$(dirname "$rel")" | tr '[:upper:]' '[:lower:]')
  [[ "$dirn" != "." && "$dirn" != "$stem" ]] && tags+=("$dirn")

  # alwaysApply tag
  local always
  always=$(get_fm_field "$fm" "alwaysApply")
  [[ "$always" == "true" ]] && tags+=("always-loaded")

  # Keyword scan
  local content
  content=$(head -60 "$file" 2>/dev/null | tr -d '\r' || true)
  [[ "$content" == *security* || "$content" == *auth* ]]    && tags+=("security")
  [[ "$content" == *test* || "$content" == *verification* ]] && tags+=("testing")
  [[ "$content" == *performance* || "$content" == *optim* ]] && tags+=("performance")
  [[ "$content" == *api* || "$content" == *endpoint* ]]      && tags+=("api")
  [[ "$content" == *workflow* || "$content" == *git* ]]      && tags+=("workflow")
  [[ "$content" == *ci* || "$content" == *pipeline* ]]       && tags+=("ci")
  [[ "$content" == *document* || "$content" == *README* ]]   && tags+=("documentation")

  # Deduplicate
  local unique
  unique=$(printf '%s\n' "${tags[@]}" | sort -u | head -10 | tr '\n' ', ' | sed 's/,$//')
  printf '[%s]' "$unique"
}

# ============================================================
# Sections Extraction & Cache
# ============================================================

# Extract ## headings with line ranges (pipe-delimited output)
extract_sections_raw() {
  local file="$1"
  local -a h_names=() h_lines=()

  while IFS=: read -r lnum rest; do
    [[ -z "$lnum" ]] && continue
    local h
    h=$(printf '%s' "$rest" | tr -d '\r' | sed 's/^## //')
    h_names+=("$h")
    h_lines+=("$lnum")
  done < <(tr -d '\r' < "$file" | grep -n '^## ' 2>/dev/null || true)

  local count=${#h_names[@]}
  [[ $count -eq 0 ]] && return

  local total
  total=$(wc -l < "$file" | tr -d ' ')

  local i
  for ((i = 0; i < count; i++)); do
    local s=${h_lines[$i]}
    local e
    if [[ $((i + 1)) -lt $count ]]; then
      e=$(( ${h_lines[$((i + 1))]} - 1 ))
    else
      e=$total
    fi
    printf '%s|%d|%d\n' "${h_names[$i]}" "$s" "$e"
  done
}

# Cache sections for a file
cache_sections() {
  local file="$1" rel="$2"
  local data
  data=$(extract_sections_raw "$file")
  [[ -n "$data" ]] && SECTION_CACHE["$rel"]="$data"
}

# Find which section heading contains a given line number
find_section_for_line() {
  local rel="$1" line_num="$2"
  local sections="${SECTION_CACHE[$rel]:-}"
  [[ -z "$sections" ]] && return
  while IFS='|' read -r heading start end; do
    [[ -z "$heading" ]] && continue
    if [[ $line_num -ge $start && $line_num -le $end ]]; then
      printf '%s' "$heading"
      return
    fi
  done <<< "$sections"
}

# Emit sections as YAML flow entries: {h: "heading", l: start, e: end}
emit_sections_yaml() {
  local rel="$1" indent="$2"
  local sections="${SECTION_CACHE[$rel]:-}"
  [[ -z "$sections" ]] && return 1

  local file_abs="${PROJECT_DIR}/${rel}"
  printf '%ssections:\n' "$indent"
  while IFS='|' read -r heading start end; do
    [[ -z "$heading" ]] && continue
    # Check if section contains SRS-xxx requirement categories
    local req_cats=""
    if [[ -f "$file_abs" ]]; then
      req_cats=$(sed -n "${start},${end}p" "$file_abs" 2>/dev/null \
        | grep -oE 'SRS-[A-Z]+' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)
    fi
    local escaped_h
    escaped_h=$(printf '%s' "$heading" | sed 's/"/\\"/g')
    if [[ -n "$req_cats" ]]; then
      printf '%s  - {h: "%s", l: %d, e: %d, req: [%s]}\n' "$indent" "$escaped_h" "$start" "$end" "$req_cats"
    else
      printf '%s  - {h: "%s", l: %d, e: %d}\n' "$indent" "$escaped_h" "$start" "$end"
    fi
  done <<< "$sections"
  return 0
}

# ============================================================
# Domain Metadata Extraction (for grouped mode)
# ============================================================

# Count unique ID patterns in file content
count_ids_in_file() {
  local file="$1" pattern="$2"
  tr -d '\r' < "$file" | grep -oE "$pattern" 2>/dev/null | sort -u | wc -l | tr -d ' '
}

# Extract hazard IDs from frontmatter (supports multiple locations)
extract_hazards_from_fm() {
  local fm="$1"
  # Try direct hazard_ids field
  local hazards
  hazards=$(get_fm_array_field "$fm" "hazard_ids" 2>/dev/null || true)
  if [[ -z "$hazards" ]]; then
    # Try regulatory.hazard_ids nested field
    local nested
    nested=$(get_fm_nested_field "$fm" "regulatory.hazard_ids" 2>/dev/null || true)
    if [[ -n "$nested" && "$nested" == "["* ]]; then
      hazards=$(printf '%s' "$nested" | sed 's/^\[//;s/\]$//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
  fi
  printf '%s' "$hazards"
}

# Extract screen references from flow documents
extract_screens_from_content() {
  local file="$1"
  tr -d '\r' < "$file" | grep -oE 'SCR-[0-9]+' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//'
}

# ============================================================
# Bundle Classification (for flat mode)
# ============================================================

classify_bundle() {
  local rel="$1"
  case "$rel" in
    */core/*)                   echo "core" ;;
    */coding/*.md)              echo "coding" ;;
    */api/*.md)                 echo "api" ;;
    */workflow/*.md)            echo "workflow" ;;
    */security*.md)             echo "security" ;;
    */project-management/*.md|*/operations/*.md) echo "project-mgmt" ;;
    global/skills/*/SKILL.md)   echo "skills-global" ;;
    plugin/skills/*/SKILL.md|project/skills/*/SKILL.md) echo "skills-plugin" ;;
    */agents/*.md)              echo "agents" ;;
    */commands/*.md)            echo "commands" ;;
    */design/*.md)              echo "design" ;;
    docs/*.md)                  echo "docs-misc" ;;
    *settings*|*config*|*hooks*|plugin-lite/*) echo "config" ;;
    plugin-lite/*)              echo "plugin-lite" ;;
    *)                          echo "root" ;;
  esac
}

bundle_description() {
  case "$1" in
    core)           echo "Core principles, communication, and environment rules" ;;
    coding)         echo "Coding standards, error handling, performance, and safety rules" ;;
    api)            echo "API design, architecture, observability, and REST API conventions" ;;
    workflow)       echo "Git workflow, CI resilience, GitHub issues and PRs" ;;
    security)       echo "Security rules, compliance, authentication, and input validation" ;;
    project-mgmt)   echo "Build management, testing, documentation, and operations" ;;
    skills-global)  echo "Global skills: harness, issue-work, pr-work, release, doc-index" ;;
    skills-plugin)  echo "Plugin/project skills: api-design, coding-guidelines, security-audit" ;;
    agents)         echo "Agent definitions and configurations" ;;
    commands)       echo "Slash command implementations" ;;
    design)         echo "Architecture and optimization design documents" ;;
    docs-misc)      echo "Project documentation, token reports, extensions" ;;
    config)         echo "Configuration files, CLAUDE.md, hooks, version history" ;;
    plugin-lite)    echo "Lightweight plugin, behavioral guardrails" ;;
    root)           echo "Project overview: README, HOOKS, QUICKSTART" ;;
    *)              echo "$1" ;;
  esac
}

# ============================================================
# Reference Scanning
# ============================================================

scan_references() {
  local file="$1"
  local base_dir
  base_dir=$(dirname "$file")

  # Strip code blocks before scanning
  local content
  content=$(tr -d '\r' < "$file" | sed '/^```/,/^```/d')

  # 1. Markdown links: [text](path.md)
  printf '%s' "$content" | grep -oE '\[.*\]\([^)]+\.md[^)]*\)' 2>/dev/null | while IFS= read -r match; do
    local target
    target=$(printf '%s' "$match" | sed 's/.*](//' | sed 's/)$//' | sed 's/#.*//' | sed 's/?.*//')
    [[ -z "$target" ]] && continue
    local resolved
    resolved=$(resolve_ref "$base_dir" "$target")
    [[ -n "$resolved" ]] && printf '%s|link|0\n' "$resolved"
  done || true

  # 2. See references: see `path.md`
  printf '%s' "$content" | grep -oE 'see `[^`]+\.md`' 2>/dev/null | while IFS= read -r match; do
    local target
    target=$(printf '%s' "$match" | sed "s/see \`//" | sed "s/\`$//")
    local resolved
    resolved=$(resolve_ref "$base_dir" "$target")
    [[ -n "$resolved" ]] && printf '%s|see|0\n' "$resolved"
  done || true

  # 3. @load directives: @load: reference/name
  printf '%s' "$content" | grep -oE '@load:[[:space:]]+[^[:space:]]+' 2>/dev/null | while IFS= read -r match; do
    local target
    target=$(printf '%s' "$match" | sed 's/@load:[[:space:]]*//')
    # Try with .md extension
    local resolved=""
    resolved=$(resolve_ref "$base_dir" "${target}.md")
    [[ -z "$resolved" ]] && resolved=$(resolve_ref "$base_dir" "reference/${target}.md")
    [[ -n "$resolved" ]] && printf '%s|load|0\n' "$resolved"
  done || true

  # 4. Direct imports: @./reference/file.md
  printf '%s' "$content" | grep -oE '^@\./[^[:space:]]+' 2>/dev/null | while IFS= read -r match; do
    local target
    target=$(printf '%s' "$match" | sed 's/^@\.\///')
    local resolved
    resolved=$(resolve_ref "$base_dir" "$target")
    [[ -n "$resolved" ]] && printf '%s|import|0\n' "$resolved"
  done || true
}

resolve_ref() {
  local base_dir="$1" target="$2"
  local resolved=""

  if [[ "$target" == /* ]]; then
    resolved="${PROJECT_DIR}${target}"
  else
    resolved="${base_dir}/${target}"
  fi

  resolved=$(realpath -q "$resolved" 2>/dev/null || true)
  [[ -z "$resolved" || ! -f "$resolved" ]] && return

  # Return project-relative path
  printf '%s' "${resolved#${PROJECT_DIR}/}"
}

# ============================================================
# Mode Detection
# ============================================================

detect_manifest_mode() {
  local count=0
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    [[ -n "${DOC_ID_CACHE[$rel]}" ]] && count=$((count + 1))
  done
  if [[ $count -gt $((TOTAL_FILES / 2)) ]]; then
    MANIFEST_MODE="grouped"
  else
    MANIFEST_MODE="flat"
  fi
  info "Manifest mode: ${MANIFEST_MODE} (${count}/${TOTAL_FILES} files have doc_id)"
}

# Classify a document into manifest group (for grouped mode)
classify_manifest_group() {
  local rel="$1" doc_id="$2"

  # By directory path first
  case "$rel" in
    ui/screens/*)      echo "screens" ; return ;;
    ui/flows/*)        echo "flows" ; return ;;
    ui/*)              echo "ui_support" ; return ;;
    placeholders/*)    echo "placeholders" ; return ;;
    reports/*)         echo "reports" ; return ;;
    reference/*)       echo "reference" ; return ;;
  esac

  # By doc_id prefix
  case "$doc_id" in
    *-UIS-*)  echo "screens" ;;
    *-UIF-*)  echo "flows" ;;
    *-UID-*)  echo "ui_support" ;;
    *-REF-*)  echo "reference" ;;
    *)        echo "core" ;;
  esac
}

# Classify reference document into subcategory
classify_ref_subcategory() {
  local file="$1"
  local content
  content=$(head -50 "$file" 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]' || true)

  case "$content" in
    *iec*|*iso*|*fda*|*mfds*|*regulatory*|*compliance*|*samd*|*pmcf*|*psur*)  echo "regulatory" ;;
    *render*|*ssr*|*webgpu*|*vtk*|*viewer*|*video*|*streaming*)               echo "rendering" ;;
    *deploy*|*docker*|*aws*|*dicom*|*s3*|*auth*|*logging*|*monitor*|*server*|*websocket*|*interface*) echo "infrastructure" ;;
    *security*|*encrypt*|*penetrat*|*protect*|*vulnerab*|*phi*)               echo "security" ;;
    *hemodynamic*|*physics*|*clinical*|*ifu*|*competitive*|*gap*analysis*)     echo "clinical" ;;
    *cost*|*pricing*|*license*|*business*)                                     echo "business" ;;
    *sbom*|*coding*standard*|*migration*|*container*|*base*image*)            echo "standards" ;;
    *)                                                                         echo "general" ;;
  esac
}

# ============================================================
# Generator: manifest.yaml
# ============================================================

generate_manifest() {
  local output="${INDEX_DIR}/manifest.yaml"
  info "Generating manifest.yaml..."

  if [[ "$MANIFEST_MODE" == "grouped" ]]; then
    generate_manifest_grouped "$output"
  else
    generate_manifest_flat "$output"
  fi

  local msize
  msize=$(wc -c < "$output" | tr -d ' ')
  success "manifest.yaml generated ($((msize / 1024))KB, ${TOTAL_FILES} documents, mode=${MANIFEST_MODE})"
}

generate_manifest_flat() {
  local output="$1"
  {
    printf '# docs/.index/manifest.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    printf '# Regenerate with: /doc-index\n\n'
    emit_meta "manifest"
    printf '\n'
    printf 'documents:\n'

    local i
    for ((i = 0; i < TOTAL_FILES; i++)); do
      local file="${ALL_FILES[$i]}"
      local rel="${file#${PROJECT_DIR}/}"
      local fm="${FM_CACHE[$rel]:-}"

      local title desc category scope fsize tags
      title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"
      desc=$(extract_description "$file" "$fm")
      category=$(classify_category "$rel")
      scope=$(classify_scope "$rel")
      fsize="${SIZE_CACHE[$rel]:-0}"
      tags=$(generate_tags "$rel" "$fm" "$file")

      printf '  - path: %s\n' "$(emit_yaml_string "$rel")"

      local doc_id="${DOC_ID_CACHE[$rel]:-}"
      [[ -n "$doc_id" ]] && printf '    id: %s\n' "$doc_id"

      printf '    title: %s\n' "$(emit_yaml_string "$title")"
      printf '    description: %s\n' "$(emit_yaml_string "$desc")"
      printf '    category: %s\n' "$category"
      printf '    scope: %s\n' "$scope"
      printf '    size: %d\n' "$fsize"
      printf '    tags: %s\n' "$tags"

      # Emit sections if available
      emit_sections_yaml "$rel" "    " 2>/dev/null || true

    done
  } > "$output"
}

generate_manifest_grouped() {
  local output="$1"

  # Categorize all files into groups
  declare -A GROUP_FILES=()
  declare -A REF_SUBCATS=()  # reference subcategory for ref docs

  local i
  for ((i = 0; i < TOTAL_FILES; i++)); do
    local file="${ALL_FILES[$i]}"
    local rel="${file#${PROJECT_DIR}/}"
    local doc_id="${DOC_ID_CACHE[$rel]:-}"
    local group
    group=$(classify_manifest_group "$rel" "$doc_id")
    GROUP_FILES["$group"]+="${rel}"$'\n'

    # Subcategorize reference docs
    if [[ "$group" == "reference" ]]; then
      local subcat
      subcat=$(classify_ref_subcategory "$file")
      REF_SUBCATS["$rel"]="$subcat"
    fi
  done

  {
    printf '# docs/.index/manifest.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    printf '# Read this FIRST, then load only needed sections.\n'
    emit_meta "manifest"
    printf '\n'

    # Core documents (detailed format)
    if [[ -n "${GROUP_FILES[core]:-}" ]]; then
      printf 'core:\n'
      printf '%s' "${GROUP_FILES[core]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local file="${PROJECT_DIR}/${rel}"
        local fm="${FM_CACHE[$rel]:-}"
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        local title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"

        printf '  - id: %s\n' "$doc_id"
        printf '    file: %s\n' "$rel"
        printf '    title: %s\n' "$(emit_yaml_string "$title")"

        # Keywords from frontmatter
        local kw
        kw=$(get_fm_array_field "$fm" "keywords" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
        if [[ -z "$kw" ]]; then
          # Generate from tags
          local tags
          tags=$(generate_tags "$rel" "$fm" "$file" | sed 's/^\[//;s/\]$//')
          kw="$tags"
        fi
        [[ -n "$kw" ]] && printf '    keywords: [%s]\n' "$kw"

        # Domain metadata
        local req_count tc_count
        req_count=$(count_ids_in_file "$file" 'SRS-[A-Z]+-[0-9]+')
        tc_count=$(count_ids_in_file "$file" 'TC-[A-Z]+-[0-9]+')
        [[ "$req_count" -gt 0 ]] && printf '    req_count: %d\n' "$req_count"
        [[ "$tc_count" -gt 0 ]] && printf '    tc_count: %d\n' "$tc_count"

        # SI identifiers
        local si_list
        si_list=$(tr -d '\r' < "$file" | grep -oE 'SI-[A-Z]+' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)
        if [[ -n "$si_list" ]]; then
          # Only include if this doc defines SI items (SDS), not just references them
          local si_count
          si_count=$(printf '%s' "$si_list" | tr ',' '\n' | wc -l | tr -d ' ')
          [[ "$si_count" -ge 3 ]] && printf '    si: [%s]\n' "$si_list"
        fi

        # Sections
        emit_sections_yaml "$rel" "    " 2>/dev/null || true

        printf '\n'
      done
    fi

    # Screens (compact format)
    if [[ -n "${GROUP_FILES[screens]:-}" ]]; then
      printf '# UI Screens\nscreens:\n'
      printf '%s' "${GROUP_FILES[screens]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local file="${PROJECT_DIR}/${rel}"
        local fm="${FM_CACHE[$rel]:-}"
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        local title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"
        local scr_id
        scr_id=$(get_fm_field "$fm" "screen_id")
        [[ -z "$scr_id" ]] && scr_id=$(basename "$rel" .md | grep -oE 'SCR-[0-9]+' 2>/dev/null || true)

        local hazards
        hazards=$(extract_hazards_from_fm "$fm" | tr '\n' ',' | sed 's/,$//' | sed 's/[[:space:]]//g')

        printf '  - {id: %s, file: %s, scr: %s, title: %s' "$doc_id" "$rel" "$scr_id" "$(emit_yaml_string "$title")"
        [[ -n "$hazards" ]] && printf ', hazards: [%s]' "$hazards"
        printf '}\n'
      done
    fi

    # Flows (compact format)
    if [[ -n "${GROUP_FILES[flows]:-}" ]]; then
      printf '\n# UI Flows\nflows:\n'
      printf '%s' "${GROUP_FILES[flows]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local file="${PROJECT_DIR}/${rel}"
        local fm="${FM_CACHE[$rel]:-}"
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        local flw_id
        flw_id=$(get_fm_field "$fm" "flow_id")
        [[ -z "$flw_id" ]] && flw_id=$(basename "$rel" .md | grep -oE 'FLW-[0-9]+' 2>/dev/null || true)

        local screens
        screens=$(extract_screens_from_content "$file")

        printf '  - {id: %s, file: %s, flw: %s' "$doc_id" "$rel" "$flw_id"
        [[ -n "$screens" ]] && printf ', screens: [%s]' "$screens"
        printf '}\n'
      done
    fi

    # UI Support (compact format)
    if [[ -n "${GROUP_FILES[ui_support]:-}" ]]; then
      printf '\n# UI Support\nui_support:\n'
      printf '%s' "${GROUP_FILES[ui_support]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        local title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"
        printf '  - {id: %s, file: %s, title: %s}\n' "$doc_id" "$rel" "$(emit_yaml_string "$title")"
      done
    fi

    # Reference documents (subcategorized, compact format)
    if [[ -n "${GROUP_FILES[reference]:-}" ]]; then
      printf '\n# Reference Documents\nreference:\n'

      # Group by subcategory
      declare -A SUBCAT_FILES=()
      printf '%s' "${GROUP_FILES[reference]}" | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local subcat="${REF_SUBCATS[$rel]:-general}"
        printf '%s|%s\n' "$subcat" "$rel"
      done | sort -t'|' -k1,1 -k2,2 | while IFS='|' read -r subcat rel; do
        [[ -z "$rel" ]] && continue
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        local title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"

        # Track subcategory changes for headers
        if [[ "${_prev_subcat:-}" != "$subcat" ]]; then
          printf '  %s:\n' "$subcat"
          _prev_subcat="$subcat"
        fi
        printf '    - {id: %s, file: %s, title: %s}\n' "$doc_id" "$rel" "$(emit_yaml_string "$title")"
      done
    fi

    # Placeholders (compact format)
    if [[ -n "${GROUP_FILES[placeholders]:-}" ]]; then
      printf '\n# Placeholders — stubs, skip reading\nplaceholders:\n'
      printf '%s' "${GROUP_FILES[placeholders]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        local doc_id="${DOC_ID_CACHE[$rel]:-}"
        printf '  - {id: %s, file: %s}\n' "$doc_id" "$rel"
      done
    fi

    # Reports (compact pattern format)
    if [[ -n "${GROUP_FILES[reports]:-}" ]]; then
      printf '\n# Reports — skip unless reviewing history\nreports:\n'
      printf '%s' "${GROUP_FILES[reports]}" | sort | while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        printf '  - %s\n' "$rel"
      done
    fi
  } > "$output"
}

# ============================================================
# Generator: bundles.yaml
# ============================================================

generate_bundles() {
  local output="${INDEX_DIR}/bundles.yaml"
  info "Generating bundles.yaml..."

  if [[ "$MANIFEST_MODE" == "grouped" ]]; then
    generate_bundles_grouped "$output"
  else
    generate_bundles_flat "$output"
  fi

  local bsize
  bsize=$(wc -c < "$output" | tr -d ' ')
  success "bundles.yaml generated ($((bsize / 1024))KB)"
}

generate_bundles_flat() {
  local output="$1"

  declare -A B_FILES=()
  declare -A B_SIZES=()

  local i
  for ((i = 0; i < TOTAL_FILES; i++)); do
    local file="${ALL_FILES[$i]}"
    local rel="${file#${PROJECT_DIR}/}"
    local bundle
    bundle=$(classify_bundle "$rel")
    B_FILES["$bundle"]+="${rel}"$'\n'
    local sz="${SIZE_CACHE[$rel]:-0}"
    B_SIZES["$bundle"]=$(( ${B_SIZES["$bundle"]:-0} + sz ))
  done

  {
    printf '# docs/.index/bundles.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT (auto section)\n'
    printf '# Custom section (below) is preserved across regeneration\n\n'
    emit_meta "bundles"
    printf '\nauto:\n'

    local sorted_keys
    sorted_keys=$(printf '%s\n' "${!B_FILES[@]}" | sort)

    while IFS= read -r bundle; do
      [[ -z "$bundle" ]] && continue
      local desc tokens
      desc=$(bundle_description "$bundle")
      tokens=$(( ${B_SIZES["$bundle"]} / 4 ))

      printf '  %s:\n' "$bundle"
      printf '    description: %s\n' "$(emit_yaml_string "$desc")"
      printf '    estimated_tokens: %d\n' "$tokens"
      printf '    docs:\n'

      printf '%s' "${B_FILES["$bundle"]}" | sort | while IFS= read -r doc; do
        [[ -z "$doc" ]] && continue
        printf '      - %s\n' "$(emit_yaml_string "$doc")"
      done
    done <<< "$sorted_keys"

    printf '\n'
    if [[ -n "$CUSTOM_SECTION" ]]; then
      printf '%s\n' "$CUSTOM_SECTION"
    else
      printf 'custom: {}\n'
    fi
  } > "$output"
}

# Emit a single bundle file entry
emit_bundle_entry() {
  local file="$1" lines="$2" note="$3" indent="$4"
  printf '%s- {file: %s' "$indent" "$file"
  [[ -n "$lines" ]] && printf ', lines: "%s"' "$lines"
  if [[ -n "$note" ]]; then
    local escaped_note
    escaped_note=$(printf '%s' "$note" | sed 's/"/\\"/g')
    printf ', note: "%s"' "$escaped_note"
  fi
  printf '}\n'
}

generate_bundles_grouped() {
  local output="$1"

  {
    printf '# docs/.index/bundles.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    printf '# Load a bundle to get all context for a feature.\n'
    printf '# All file paths relative to docs/. Use line ranges to avoid loading full documents.\n'
    emit_meta "bundles"
    printf '\n'

    # Auto-generate SI bundles from SDS sections
    generate_si_bundles

    # Auto-generate workflow bundles from FLW documents
    generate_workflow_bundles

    # Auto-generate cross-cutting bundles
    generate_crosscutting_bundles

    printf '\n'
    if [[ -n "$CUSTOM_SECTION" ]]; then
      printf '%s\n' "$CUSTOM_SECTION"
    else
      printf 'custom: {}\n'
    fi
  } > "$output"
}

# Generate SI-xx bundles from SDS sections
generate_si_bundles() {
  # Find the SDS document
  local sds_rel=""
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    if [[ "$did" == *-SAD-* || "$did" == *-SDS-* ]]; then
      sds_rel="$rel"
      break
    fi
  done
  [[ -z "$sds_rel" ]] && return

  local sds_file="${PROJECT_DIR}/${sds_rel}"
  [[ ! -f "$sds_file" ]] && return

  # Find SI-xx identifiers and their sections
  local si_ids
  si_ids=$(tr -d '\r' < "$sds_file" | grep -oE 'SI-[A-Z]+' 2>/dev/null | sort -u || true)
  [[ -z "$si_ids" ]] && return

  printf '# Software Item bundles (from SDS)\n'

  local sds_sections="${SECTION_CACHE[$sds_rel]:-}"

  while IFS= read -r si_id; do
    [[ -z "$si_id" ]] && continue
    local si_lower
    si_lower=$(printf '%s' "$si_id" | tr '[:upper:]' '[:lower:]' | tr '-' '-')
    local bundle_name="si-${si_lower#si-}"

    # Find the SDS section containing this SI definition
    local si_lines=""
    if [[ -n "$sds_sections" ]]; then
      while IFS='|' read -r heading start end; do
        [[ -z "$heading" ]] && continue
        # Check if this section contains the SI identifier
        local match
        match=$(sed -n "${start},${end}p" "$sds_file" 2>/dev/null | grep -c "$si_id" 2>/dev/null || true)
        if [[ "$match" -gt 0 ]]; then
          si_lines="${start}-${end}"
          break
        fi
      done <<< "$sds_sections"
    fi

    # Find SI full name from SDS content
    local si_full_name
    si_full_name=$(tr -d '\r' < "$sds_file" | grep -m1 "${si_id}.*(" 2>/dev/null | grep -oE '\(.*\)' | tr -d '()' | head -1 || true)
    [[ -z "$si_full_name" ]] && si_full_name="$si_id"

    printf '%s:\n' "$bundle_name"
    printf '  name: "%s (%s)"\n' "$si_full_name" "$si_id"
    printf '  files:\n'

    # SDS section
    if [[ -n "$si_lines" ]]; then
      emit_bundle_entry "$sds_rel" "$si_lines" "${si_id} def" "    "
    else
      emit_bundle_entry "$sds_rel" "" "" "    "
    fi

    # Find related SRS sections
    local srs_rel=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      [[ "${DOC_ID_CACHE[$rel]}" == *-SRS-* ]] && { srs_rel="$rel"; break; }
    done
    if [[ -n "$srs_rel" ]]; then
      local srs_file="${PROJECT_DIR}/${srs_rel}"
      # Find SRS sections that reference this SI
      local srs_sections="${SECTION_CACHE[$srs_rel]:-}"
      if [[ -n "$srs_sections" ]]; then
        while IFS='|' read -r heading start end; do
          [[ -z "$heading" ]] && continue
          local has_ref
          has_ref=$(sed -n "${start},${end}p" "$srs_file" 2>/dev/null | grep -c "$si_id" 2>/dev/null || true)
          if [[ "$has_ref" -gt 0 ]]; then
            local note_text
            note_text=$(printf '%s' "$heading" | head -c 40)
            emit_bundle_entry "$srs_rel" "${start}-${end}" "$note_text" "    "
            break  # Only first matching section
          fi
        done <<< "$srs_sections"
      fi
    fi

    # Find screen documents referencing this SI
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" != *-UIS-* ]] && continue
      local scr_file="${PROJECT_DIR}/${rel}"
      local has_ref
      has_ref=$(tr -d '\r' < "$scr_file" 2>/dev/null | grep -c "$si_id" 2>/dev/null || true)
      [[ "$has_ref" -gt 0 ]] && emit_bundle_entry "$rel" "" "" "    "
    done

    # Find reference documents relevant to this SI
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" != *-REF-* ]] && continue
      local ref_file="${PROJECT_DIR}/${rel}"
      local has_ref
      has_ref=$(head -30 "$ref_file" 2>/dev/null | tr -d '\r' | grep -c "$si_id" 2>/dev/null || true)
      [[ "$has_ref" -gt 0 ]] && emit_bundle_entry "$rel" "" "" "    "
    done

    printf '\n'
  done <<< "$si_ids"
}

# Generate workflow bundles from FLW documents
generate_workflow_bundles() {
  local has_flows=false
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    [[ "${DOC_ID_CACHE[$rel]}" == *-UIF-* ]] && { has_flows=true; break; }
  done
  $has_flows || return

  printf '# Clinical workflow bundles\n'

  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    [[ "$did" != *-UIF-* ]] && continue
    local file="${PROJECT_DIR}/${rel}"
    local title="${TITLE_CACHE[$rel]:-$(basename "$rel" .md)}"
    local flw_id
    flw_id=$(basename "$rel" .md | grep -oE 'FLW-[0-9]+' 2>/dev/null || true)
    [[ -z "$flw_id" ]] && continue

    # Generate bundle name from filename
    local bundle_name
    bundle_name=$(basename "$rel" .md | sed "s/^${flw_id}-//" | tr '_' '-')
    bundle_name="workflow-${bundle_name}"

    printf '%s:\n' "$bundle_name"
    printf '  name: %s\n' "$(emit_yaml_string "$title")"
    printf '  files:\n'

    # The flow document itself
    emit_bundle_entry "$rel" "" "" "    "

    # Screen documents referenced in the flow
    local screens
    screens=$(extract_screens_from_content "$file")
    if [[ -n "$screens" ]]; then
      local scr
      for scr in $(printf '%s' "$screens" | tr ',' ' '); do
        # Find screen file
        local scr_rel
        for scr_rel in "${!DOC_ID_CACHE[@]}"; do
          if [[ "$scr_rel" == *"${scr}"* ]]; then
            emit_bundle_entry "$scr_rel" "" "" "    "
            break
          fi
        done
      done
    fi

    printf '\n'
  done
}

# Generate cross-cutting bundles (security, safety, database, api, testing, regulatory)
generate_crosscutting_bundles() {
  printf '# Cross-cutting bundles\n'

  # Security bundle
  local srs_rel=""
  for rel in "${!DOC_ID_CACHE[@]}"; do
    [[ "${DOC_ID_CACHE[$rel]}" == *-SRS-* ]] && { srs_rel="$rel"; break; }
  done

  generate_crosscutting_bundle_by_keyword "security" "Security" \
    "SRS-SEC|security|threat|auth|encrypt|protect" "$srs_rel"

  generate_crosscutting_bundle_by_keyword "safety" "Safety & Risk" \
    "SRS-SAFE|safety|risk|hazard|H-[0-9]" "$srs_rel"

  generate_crosscutting_bundle_by_keyword "database" "Database" \
    "database|schema|SQL|table|migration" "$srs_rel"

  generate_crosscutting_bundle_by_keyword "api" "API" \
    "API|REST|endpoint|interface|gRPC|WebSocket" "$srs_rel"

  generate_crosscutting_bundle_by_keyword "testing" "Testing" \
    "test|verification|validation|TC-" "$srs_rel"

  # Regulatory submission bundle (full docs)
  local has_reg=false
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    local group
    group=$(classify_manifest_group "$rel" "$did")
    [[ "$group" == "core" ]] && { has_reg=true; break; }
  done
  if $has_reg; then
    printf 'regulatory-submission:\n'
    printf '  name: "Regulatory Package"\n'
    printf '  note: "Full docs — no line filtering"\n'
    printf '  files:\n'
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      local group
      group=$(classify_manifest_group "$rel" "$did")
      [[ "$group" == "core" ]] && emit_bundle_entry "$rel" "" "" "    "
    done
    # Add compliance status report if exists
    for rel in "${!DOC_ID_CACHE[@]}"; do
      [[ "$rel" == *compliance* ]] && emit_bundle_entry "$rel" "" "" "    "
    done
    printf '\n'
  fi
}

generate_crosscutting_bundle_by_keyword() {
  local bundle_name="$1" bundle_title="$2" pattern="$3" srs_rel="$4"

  local -a matched_files=()

  # Find SRS section matching keyword
  local srs_section_lines=""
  if [[ -n "$srs_rel" ]]; then
    local srs_file="${PROJECT_DIR}/${srs_rel}"
    local srs_sections="${SECTION_CACHE[$srs_rel]:-}"
    if [[ -n "$srs_sections" ]]; then
      while IFS='|' read -r heading start end; do
        [[ -z "$heading" ]] && continue
        local match
        match=$(sed -n "${start},${end}p" "$srs_file" 2>/dev/null | grep -cE "$pattern" 2>/dev/null || true)
        if [[ "$match" -gt 2 ]]; then
          srs_section_lines="${start}-${end}"
          break
        fi
      done <<< "$srs_sections"
    fi
  fi

  # Find all docs matching the keyword pattern
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    local group
    group=$(classify_manifest_group "$rel" "$did")
    [[ "$group" == "placeholders" || "$group" == "reports" ]] && continue
    [[ "$rel" == "$srs_rel" ]] && continue  # SRS handled separately with section

    local file="${PROJECT_DIR}/${rel}"
    local match
    match=$(head -50 "$file" 2>/dev/null | tr -d '\r' | grep -cE "$pattern" 2>/dev/null || true)
    [[ "$match" -gt 0 ]] && matched_files+=("$rel")
  done

  # Only emit if we have files
  [[ ${#matched_files[@]} -eq 0 && -z "$srs_section_lines" ]] && return

  printf '%s:\n' "$bundle_name"
  printf '  name: %s\n' "$(emit_yaml_string "$bundle_title")"
  printf '  files:\n'

  if [[ -n "$srs_section_lines" && -n "$srs_rel" ]]; then
    local note=""
    [[ "$bundle_name" == "security" ]] && note="SRS-SEC"
    [[ "$bundle_name" == "safety" ]] && note="SRS-SAFE"
    emit_bundle_entry "$srs_rel" "$srs_section_lines" "$note" "    "
  fi

  local f
  for f in "${matched_files[@]}"; do
    emit_bundle_entry "$f" "" "" "    "
  done

  printf '\n'
}

# ============================================================
# Generator: graph.yaml
# ============================================================

generate_graph() {
  local output="${INDEX_DIR}/graph.yaml"
  info "Generating graph.yaml..."

  REF_TMPFILE=$(mktemp)

  # Scan all files for references
  local i
  for ((i = 0; i < TOTAL_FILES; i++)); do
    local file="${ALL_FILES[$i]}"
    local rel="${file#${PROJECT_DIR}/}"

    local refs
    refs=$(scan_references "$file")
    [[ -z "$refs" ]] && continue

    while IFS='|' read -r target rtype lnum; do
      [[ -z "$target" ]] && continue
      printf '%s|%s|%s|%s\n' "$rel" "$target" "$rtype" "$lnum" >> "$REF_TMPFILE"
      TOTAL_REFS=$((TOTAL_REFS + 1))
    done <<< "$refs"
  done

  {
    printf '# docs/.index/graph.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    if [[ "$MANIFEST_MODE" == "grouped" ]]; then
      printf '# When X changes, review Y.\n'
    else
      printf '# Cross-reference dependency graph\n'
    fi
    printf '\n'
    emit_meta "graph"
    printf '\n'

    if [[ "$MANIFEST_MODE" == "grouped" ]]; then
      # Grouped mode: cascade + req_chains + hazard_map + screen_cascade
      generate_cascade
      generate_screen_cascade
      generate_req_chains
      generate_hazard_map
    else
      # Flat mode: just nodes
      generate_graph_nodes
    fi
  } > "$output"

  local gsize
  gsize=$(wc -c < "$output" | tr -d ' ')
  success "graph.yaml generated ($((gsize / 1024))KB, ${TOTAL_REFS} references)"
}

generate_graph_nodes() {
  if [[ ! -s "$REF_TMPFILE" ]]; then
    printf 'nodes: {}\n'
    return
  fi

  printf 'nodes:\n'

  local source_nodes
  source_nodes=$(awk -F'|' '{print $1}' "$REF_TMPFILE" | sort -u)

  while IFS= read -r node; do
    [[ -z "$node" ]] && continue

    local outgoing
    outgoing=$(grep "^${node}|" "$REF_TMPFILE" 2>/dev/null | sort -t'|' -k1,3 -u || true)
    [[ -z "$outgoing" ]] && continue

    printf '  %s:\n' "$(emit_yaml_string "$node")"
    while IFS='|' read -r _src tgt typ ln; do
      printf '    - target: %s\n' "$(emit_yaml_string "$tgt")"
      printf '      type: %s\n' "$typ"
    done <<< "$outgoing"
  done <<< "$source_nodes"
}

# Generate cascade section (document-level impact chains)
generate_cascade() {
  [[ ! -s "$REF_TMPFILE" ]] && return

  # Build doc_id → rel mapping
  declare -A ID_TO_REL=()
  declare -A REL_TO_ID=()
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    [[ -n "$did" ]] && { ID_TO_REL["$did"]="$rel"; REL_TO_ID["$rel"]="$did"; }
  done

  printf '# Document-level cascade (source → targets to review)\ncascade:\n'

  # For each doc with doc_id, find outgoing references to other doc_id docs
  local source_id
  for source_id in $(printf '%s\n' "${!ID_TO_REL[@]}" | sort); do
    local source_rel="${ID_TO_REL[$source_id]}"

    # Find outgoing references from this doc to other doc_id docs
    local targets=""
    local outgoing
    outgoing=$(grep "^${source_rel}|" "$REF_TMPFILE" 2>/dev/null | sort -t'|' -k2 -u || true)
    [[ -z "$outgoing" ]] && continue

    local -a target_entries=()
    while IFS='|' read -r _src tgt typ ln; do
      [[ -z "$tgt" ]] && continue
      local target_id="${REL_TO_ID[$tgt]:-}"
      [[ -z "$target_id" ]] && continue
      [[ "$target_id" == "$source_id" ]] && continue

      # Generate why text from reference context
      local why="Referenced"
      local section_heading
      section_heading=$(find_section_for_line "$source_rel" "${ln:-1}" 2>/dev/null || true)
      if [[ -n "$section_heading" ]]; then
        why="Referenced in ${section_heading}"
      fi

      target_entries+=("{doc: ${target_id}, why: \"${why}\"}")
    done <<< "$outgoing"

    [[ ${#target_entries[@]} -eq 0 ]] && continue

    printf '  %s:\n' "$source_id"
    printf '    targets:\n'
    # Deduplicate by target doc_id
    printf '%s\n' "${target_entries[@]}" | sort -u | while IFS= read -r entry; do
      printf '      - %s\n' "$entry"
    done
  done
  printf '\n'
}

# Generate screen cascade (screen → flows mapping)
generate_screen_cascade() {
  # Collect screen → flows data
  declare -A SCR_FLOWS=()
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    [[ "$did" != *-UIF-* ]] && continue

    local file="${PROJECT_DIR}/${rel}"
    local flw_id
    flw_id=$(basename "$rel" .md | grep -oE 'FLW-[0-9]+' 2>/dev/null || true)
    [[ -z "$flw_id" ]] && continue

    local screens
    screens=$(extract_screens_from_content "$file")
    if [[ -n "$screens" ]]; then
      local scr
      for scr in $(printf '%s' "$screens" | tr ',' ' '); do
        SCR_FLOWS["$scr"]+="${flw_id},"
      done
    fi
  done

  [[ ${#SCR_FLOWS[@]} -eq 0 ]] && return

  printf '# Screen impacts\nscreen_cascade:\n'

  # Find docs that should be updated for any screen change
  local ui_trace_rel=""
  local val_rel=""
  for rel in "${!DOC_ID_CACHE[@]}"; do
    [[ "${DOC_ID_CACHE[$rel]}" == *-UID-003* ]] && ui_trace_rel="$rel"
    [[ "${DOC_ID_CACHE[$rel]}" == *-VAL-* ]] && val_rel="$rel"
  done
  if [[ -n "$ui_trace_rel" || -n "$val_rel" ]]; then
    printf '  any_screen: ['
    local first=true
    [[ -n "$ui_trace_rel" ]] && { printf '{doc: %s, why: "Traceability matrix"}' "${DOC_ID_CACHE[$ui_trace_rel]}"; first=false; }
    [[ -n "$val_rel" ]] && { $first || printf ', '; printf '{doc: %s, why: "Usability validation"}' "${DOC_ID_CACHE[$val_rel]}"; }
    printf ']\n'
  fi

  # Emit per-screen cascades (only for screens with 2+ flows)
  local scr
  for scr in $(printf '%s\n' "${!SCR_FLOWS[@]}" | sort); do
    local flows="${SCR_FLOWS[$scr]}"
    flows=$(printf '%s' "$flows" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    local flow_count
    flow_count=$(printf '%s' "$flows" | tr ',' '\n' | wc -l | tr -d ' ')
    [[ "$flow_count" -lt 2 ]] && continue

    local note=""
    [[ "$flow_count" -ge 3 ]] && note=', note: "Hub screen"'
    printf '  %s: {flows: [%s]%s}\n' "$scr" "$flows" "$note"
  done
  printf '\n'
}

# Generate requirement chains (SRS-CAT → affected entities)
generate_req_chains() {
  # Find SRS document
  local srs_rel=""
  for rel in "${!DOC_ID_CACHE[@]}"; do
    [[ "${DOC_ID_CACHE[$rel]}" == *-SRS-* ]] && { srs_rel="$rel"; break; }
  done
  [[ -z "$srs_rel" ]] && return

  local srs_file="${PROJECT_DIR}/${srs_rel}"
  [[ ! -f "$srs_file" ]] && return

  # Find all SRS categories
  local categories
  categories=$(tr -d '\r' < "$srs_file" | grep -oE 'SRS-[A-Z]+' 2>/dev/null | sort -u || true)
  [[ -z "$categories" ]] && return

  printf '# Requirement category → affected entities\nreq_chains:\n'

  while IFS= read -r cat; do
    [[ -z "$cat" ]] && continue

    local cat_code="${cat#SRS-}"

    # Find SI items for this category
    local si_list=""
    local sds_rel=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" == *-SAD-* || "$did" == *-SDS-* ]] && { sds_rel="$rel"; break; }
    done
    if [[ -n "$sds_rel" ]]; then
      local sds_file="${PROJECT_DIR}/${sds_rel}"
      si_list=$(tr -d '\r' < "$sds_file" 2>/dev/null \
        | grep -B5 -A5 "$cat" 2>/dev/null \
        | grep -oE 'SI-[A-Z]+' 2>/dev/null \
        | sort -u | tr '\n' ',' | sed 's/,$//' || true)
    fi

    # Find screens referencing this category
    local scr_list=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" != *-UIS-* ]] && continue
      local scr_file="${PROJECT_DIR}/${rel}"
      local has_ref
      has_ref=$(tr -d '\r' < "$scr_file" 2>/dev/null | grep -c "$cat" 2>/dev/null || true)
      if [[ "$has_ref" -gt 0 ]]; then
        local scr_id
        scr_id=$(basename "$rel" .md | grep -oE 'SCR-[0-9]+' 2>/dev/null || true)
        [[ -n "$scr_id" ]] && scr_list+="${scr_id},"
      fi
    done
    scr_list=$(printf '%s' "$scr_list" | sed 's/,$//' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    # Find hazards linked to this category
    local hazard_list=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" != *-UIS-* ]] && continue
      local fm="${FM_CACHE[$rel]:-}"
      local file_hazards
      file_hazards=$(extract_hazards_from_fm "$fm" | tr '\n' ',' | sed 's/,$//' || true)
      if [[ -n "$file_hazards" ]]; then
        local scr_file="${PROJECT_DIR}/${rel}"
        local has_ref
        has_ref=$(tr -d '\r' < "$scr_file" 2>/dev/null | grep -c "$cat" 2>/dev/null || true)
        [[ "$has_ref" -gt 0 ]] && hazard_list+="${file_hazards},"
      fi
    done
    hazard_list=$(printf '%s' "$hazard_list" | tr ',' '\n' | sed 's/[[:space:]]//g' | sort -t'-' -k2 -n -u | tr '\n' ',' | sed 's/,$//')

    # TC category (by convention)
    local tc_cat="TC-${cat_code}"

    # Find reference docs
    local ref_list=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" != *-REF-* ]] && continue
      local ref_file="${PROJECT_DIR}/${rel}"
      local has_ref
      has_ref=$(tr -d '\r' < "$ref_file" 2>/dev/null | grep -c "$cat" 2>/dev/null || true)
      if [[ "$has_ref" -gt 0 ]]; then
        ref_list+="${did},"
      fi
    done
    ref_list=$(printf '%s' "$ref_list" | sed 's/,$//')

    # Emit chain entry
    printf '  %s: {' "$cat"
    local first=true
    [[ -n "$si_list" ]] && { printf 'si: [%s]' "$si_list"; first=false; }
    [[ -n "$scr_list" ]] && { $first || printf ', '; printf 'scr: [%s]' "$scr_list"; first=false; }
    [[ -n "$hazard_list" ]] && { $first || printf ', '; printf 'hazards: [%s]' "$hazard_list"; first=false; }
    { $first || printf ', '; printf 'tc: %s' "$tc_cat"; first=false; }
    [[ -n "$ref_list" ]] && { printf ', refs: [%s]' "$ref_list"; }
    printf '}\n'
  done <<< "$categories"
  printf '\n'
}

# Generate hazard map (H-xx → affected screens)
generate_hazard_map() {
  # Collect all hazards from screen frontmatter
  declare -A HAZARD_SCREENS=()
  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    [[ "$did" != *-UIS-* ]] && continue

    local fm="${FM_CACHE[$rel]:-}"
    local hazards
    hazards=$(extract_hazards_from_fm "$fm")
    [[ -z "$hazards" ]] && continue

    local scr_id
    scr_id=$(basename "$rel" .md | grep -oE 'SCR-[0-9]+' 2>/dev/null || true)
    [[ -z "$scr_id" ]] && continue

    while IFS= read -r h; do
      h=$(printf '%s' "$h" | sed 's/[[:space:]]//g')
      [[ -z "$h" ]] && continue
      HAZARD_SCREENS["$h"]+="${scr_id},"
    done <<< "$hazards"
  done

  [[ ${#HAZARD_SCREENS[@]} -eq 0 ]] && return

  # Try to find hazard titles from risk management document
  local risk_rel=""
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    [[ "$did" == *-REF-006* || "$rel" == *risk*management* || "$rel" == *iso*14971* ]] && { risk_rel="$rel"; break; }
  done

  printf '# Hazard → affected screens\nhazard_map:\n'

  local h
  for h in $(printf '%s\n' "${!HAZARD_SCREENS[@]}" | sort -t'-' -k2 -n); do
    local screens="${HAZARD_SCREENS[$h]}"
    screens=$(printf '%s' "$screens" | tr ',' '\n' | sed 's/[[:space:]]//g' | sort -t'-' -k2 -n -u | tr '\n' ',' | sed 's/,$//')

    # Try to find hazard title
    local title=""
    if [[ -n "$risk_rel" ]]; then
      local risk_file="${PROJECT_DIR}/${risk_rel}"
      title=$(tr -d '\r' < "$risk_file" 2>/dev/null | grep -m1 "$h" 2>/dev/null | sed "s/.*${h}[^a-zA-Z]*//" | sed 's/|.*//' | head -c 30 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)
    fi

    local note=""
    [[ -z "$screens" ]] && note=', note: "Server-side only"'

    if [[ -n "$title" ]]; then
      printf '  %s: {title: "%s", scr: [%s]%s}\n' "$h" "$title" "$screens" "$note"
    else
      printf '  %s: {scr: [%s]%s}\n' "$h" "$screens" "$note"
    fi
  done
}

# ============================================================
# Generator: router.yaml
# ============================================================

# Preserve user-defined id_patterns from existing router.yaml
ID_PATTERNS_SECTION=""

preserve_id_patterns() {
  local router_file="${INDEX_DIR}/router.yaml"
  if [[ -f "$router_file" ]]; then
    ID_PATTERNS_SECTION=$(sed -n '/^id_patterns:/,$p' "$router_file" | tr -d '\r')
    if [[ -n "$ID_PATTERNS_SECTION" ]]; then
      info "Preserved existing id_patterns section"
    fi
  fi
}

# Parse id_patterns section and return prefix|source pairs
parse_id_patterns() {
  [[ -z "$ID_PATTERNS_SECTION" ]] && return
  local current_prefix="" current_source=""
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
    case "$line" in
      "- prefix:"*)
        if [[ -n "$current_prefix" && -n "$current_source" ]]; then
          printf '%s|%s\n' "$current_prefix" "$current_source"
        fi
        current_prefix=$(printf '%s' "$line" | sed 's/- prefix:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/')
        current_source=""
        ;;
      "source:"*)
        current_source=$(printf '%s' "$line" | sed 's/source:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/')
        ;;
    esac
  done <<< "$ID_PATTERNS_SECTION"
  if [[ -n "$current_prefix" && -n "$current_source" ]]; then
    printf '%s|%s\n' "$current_prefix" "$current_source"
  fi
}

# Find files that reference this prefix (excluding source)
emit_cross_refs() {
  local prefix="$1"
  local source="$2"

  local ref_files
  ref_files=$(grep -rl "${prefix}-" "$PROJECT_DIR" --include="*.md" 2>/dev/null \
    | sort | while IFS= read -r f; do
        local rel="${f#${PROJECT_DIR}/}"
        [[ "$rel" == "$source" ]] && continue
        [[ "$rel" == docs/.index/* ]] && continue
        printf '%s\n' "$rel"
      done | head -20)

  if [[ -n "$ref_files" ]]; then
    printf '    referenced_by:\n'
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      printf '      - %s\n' "$(emit_yaml_string "$ref")"
    done <<< "$ref_files"
  fi
}

generate_router() {
  local output="${INDEX_DIR}/router.yaml"
  info "Generating router.yaml..."

  preserve_id_patterns

  if [[ "$MANIFEST_MODE" == "grouped" ]]; then
    generate_router_grouped "$output"
  else
    generate_router_flat "$output"
  fi

  local rsize
  rsize=$(wc -c < "$output" | tr -d ' ')
  success "router.yaml generated ($((rsize / 1024))KB)"
}

generate_router_flat() {
  local output="$1"
  {
    printf '# docs/.index/router.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT (auto sections)\n'
    printf '# id_patterns section (bottom) is preserved across regeneration\n\n'
    emit_meta "router"
    printf '\n'

    printf '# Keyword routes: map user queries to the right bundle\n'
    printf 'routes:\n'
    printf '  - keywords: [hook, hooks, PreToolUse, PostToolUse, settings.json, permission]\n'
    printf '    bundle: config\n'
    printf '    primary: "HOOKS.md"\n'
    printf '  - keywords: [commit, git, branch, merge, rebase, conflict, stash]\n'
    printf '    bundle: workflow\n'
    printf '  - keywords: [issue, PR, pull request, 5W1H, review]\n'
    printf '    bundle: workflow\n'
    printf '  - keywords: [CI, GitHub Actions, pipeline, workflow.yml]\n'
    printf '    bundle: workflow\n'
    printf '  - keywords: [api, REST, endpoint, route, controller, handler]\n'
    printf '    bundle: api\n'
    printf '  - keywords: [security, auth, OWASP, injection, XSS, encryption, secret]\n'
    printf '    bundle: security\n'
    printf '  - keywords: [test, testing, verification, coverage, assertion, TDD]\n'
    printf '    bundle: project-mgmt\n'
    printf '  - keywords: [build, CMake, Makefile, compile, link, dependency]\n'
    printf '    bundle: project-mgmt\n'
    printf '  - keywords: [performance, optimization, cache, latency, throughput, profiling]\n'
    printf '    bundle: coding\n'
    printf '  - keywords: [error, exception, handling, recovery, fallback]\n'
    printf '    bundle: coding\n'
    printf '  - keywords: [skill, SKILL.md, slash command, /command]\n'
    printf '    bundle: skills-global\n'
    printf '  - keywords: [agent, subagent, team, orchestrator, harness]\n'
    printf '    bundle: agents\n'
    printf '  - keywords: [plugin, extension, install, bootstrap, deploy, setup]\n'
    printf '    bundle: config\n'
    printf '  - keywords: [documentation, README, changelog, comment, docstring]\n'
    printf '    bundle: project-mgmt\n'
    printf '  - keywords: [design, prefetch, caching, module, optimization phase]\n'
    printf '    bundle: design\n'
    printf '  - keywords: [coding, standard, convention, naming, style, format]\n'
    printf '    bundle: coding\n'
    printf '  - keywords: [architecture, microservice, DDD, layer, component]\n'
    printf '    bundle: api\n\n'

    printf '# Skip rules: files that rarely need direct access\n'
    printf 'skip:\n'
    printf '  - "plugin-lite/*"\n'
    printf '  - "*/reference/*"\n'
    printf '  - "*/_policy.md"\n'

    # Resolve id_patterns into identifiers section (legacy flat format)
    local patterns
    patterns=$(parse_id_patterns)
    if [[ -n "$patterns" ]]; then
      printf '\n# Auto-resolved from id_patterns declarations below\n'
      printf 'identifiers:\n'
      while IFS='|' read -r prefix source; do
        [[ -z "$prefix" ]] && continue
        resolve_one_pattern_flat "$prefix" "$source"
      done <<< "$patterns"
    fi

    printf '\n'
    if [[ -n "$ID_PATTERNS_SECTION" ]]; then
      printf '%s\n' "$ID_PATTERNS_SECTION"
    else
      printf '# User-defined ID pattern declarations (preserved on regeneration)\n'
      printf '# Add patterns here, then re-run /doc-index to auto-resolve\n'
      printf '#\n'
      printf '# id_patterns:\n'
      printf '#   - prefix: SRS\n'
      printf '#     source: docs/requirements/SRS.md\n'
      printf '#   - prefix: H\n'
      printf '#     source: docs/safety/threat-model.md\n'
    fi
  } > "$output"
}

# Flat mode: resolve ID pattern (legacy format)
resolve_one_pattern_flat() {
  local prefix="$1" source="$2"
  local source_abs="${PROJECT_DIR}/${source}"
  local is_dir=false
  [[ -d "$source_abs" ]] && is_dir=true

  if $is_dir; then
    local instance_count=0
    printf '  %s:\n' "$prefix"
    printf '    format: "%s-{NNN}"\n' "$prefix"
    printf '    source: %s\n' "$(emit_yaml_string "$source")"
    printf '    instances:\n'
    while IFS= read -r f; do
      local bn
      bn=$(basename "$f" .md)
      local id_part
      id_part=$(printf '%s' "$bn" | grep -oE "^${prefix}-[0-9]+" 2>/dev/null || true)
      if [[ -n "$id_part" ]]; then
        local num="${id_part#${prefix}-}"
        printf '      "%s": %s\n' "$num" "$(emit_yaml_string "${f#${PROJECT_DIR}/}")"
        instance_count=$((instance_count + 1))
      fi
    done < <(find "$source_abs" -name "*.md" -type f 2>/dev/null | sort)
    emit_cross_refs "$prefix" "$source"
    return
  fi

  [[ ! -f "$source_abs" ]] && { warn "ID pattern source not found: $source"; return; }

  local all_ids
  all_ids=$(tr -d '\r' < "$source_abs" | grep -oE "${prefix}-[A-Z]+-[0-9]+" 2>/dev/null | head -500 || true)

  if [[ -n "$all_ids" ]]; then
    printf '  %s:\n' "$prefix"
    printf '    format: "%s-{CAT}-{NNN}"\n' "$prefix"
    printf '    source: %s\n' "$(emit_yaml_string "$source")"
    printf '    categories:\n'
    local cats
    cats=$(printf '%s\n' "$all_ids" | sed "s/^${prefix}-//" | sed 's/-[0-9]*$//' | sort -u)
    while IFS= read -r cat; do
      [[ -z "$cat" ]] && continue
      local first_line count
      first_line=$(tr -d '\r' < "$source_abs" | grep -n "${prefix}-${cat}-" -m1 2>/dev/null | cut -d: -f1 || true)
      count=$(tr -d '\r' < "$source_abs" | grep -c "${prefix}-${cat}-" 2>/dev/null || true)
      [[ -z "$first_line" ]] && first_line=0
      printf '      %s: {line: %s, count: %s}\n' "$cat" "$first_line" "$count"
    done <<< "$cats"
  else
    all_ids=$(tr -d '\r' < "$source_abs" | grep -oE "${prefix}-[0-9]+" 2>/dev/null | head -500 || true)
    if [[ -n "$all_ids" ]]; then
      local id_count
      id_count=$(printf '%s\n' "$all_ids" | sort -u | wc -l | tr -d ' ')
      printf '  %s:\n' "$prefix"
      printf '    format: "%s-{NNN}"\n' "$prefix"
      printf '    source: %s\n' "$(emit_yaml_string "$source")"
      printf '    count: %s\n' "$id_count"
    else
      warn "No IDs matching prefix '${prefix}' found in ${source}"
      return
    fi
  fi
  emit_cross_refs "$prefix" "$source"
}

generate_router_grouped() {
  local output="$1"
  {
    printf '# docs/.index/router.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    printf '# Match query to minimum document set.\n\n'
    emit_meta "router"
    printf '\n'

    # Generate id_routes from id_patterns
    local patterns
    patterns=$(parse_id_patterns)
    if [[ -n "$patterns" ]]; then
      printf '# Identifier routes (exact pattern → document + section)\n'
      printf 'id_routes:\n'
      while IFS='|' read -r prefix source; do
        [[ -z "$prefix" ]] && continue
        generate_id_route "$prefix" "$source"
      done <<< "$patterns"
      printf '\n'
    fi

    # Intent routes
    printf '# Intent routes (keyword → bundle)\n'
    printf 'intent_routes:\n'
    generate_intent_routes_grouped
    printf '\n'

    # Skip rules
    printf '# Always skip — no useful content\n'
    printf 'skip: ['
    local skip_patterns=("placeholders/*" "reports/weekly_report/*" "reports/monthly_report/*")
    local first=true
    local p
    for p in "${skip_patterns[@]}"; do
      $first || printf ', '
      printf '%s' "$p"
      first=false
    done
    printf ']\n'

    # Preserve id_patterns section
    printf '\n'
    if [[ -n "$ID_PATTERNS_SECTION" ]]; then
      printf '%s\n' "$ID_PATTERNS_SECTION"
    fi
  } > "$output"
}

# Generate a single id_route entry with section_map
generate_id_route() {
  local prefix="$1" source="$2"
  local source_abs="${PROJECT_DIR}/${source}"

  # Directory source (e.g., SCR, FLW)
  if [[ -d "$source_abs" ]]; then
    printf '  %s:\n' "$prefix"
    printf '    pattern: "%s-{NNN}"\n' "$prefix"
    printf '    file: "%s/%s-{NNN}-*.md"\n' "$source" "$prefix"

    # Find also-references
    local also_files=""
    for rel in "${!DOC_ID_CACHE[@]}"; do
      local did="${DOC_ID_CACHE[$rel]}"
      [[ "$did" == *-UID-* ]] && also_files+="$rel, "
    done
    also_files=$(printf '%s' "$also_files" | sed 's/, $//')
    [[ -n "$also_files" ]] && printf '    also: [%s]\n' "$also_files"
    return
  fi

  [[ ! -f "$source_abs" ]] && { warn "ID pattern source not found: $source"; return; }

  # Detect format: compound (PREFIX-CAT-NNN) or simple (PREFIX-NNN)
  local compound_ids
  compound_ids=$(tr -d '\r' < "$source_abs" | grep -oE "${prefix}-[A-Z]+-[0-9]+" 2>/dev/null | head -500 || true)

  printf '  %s:\n' "$prefix"

  if [[ -n "$compound_ids" ]]; then
    printf '    pattern: "%s-{CAT}-{NNN}"\n' "$prefix"
    printf '    file: %s\n' "$source"

    # Build section_map from SECTION_CACHE
    local sections="${SECTION_CACHE[$source]:-}"
    if [[ -n "$sections" ]]; then
      printf '    section_map:\n'
      local cats
      cats=$(printf '%s\n' "$compound_ids" | sed "s/^${prefix}-//" | sed 's/-[0-9]*$//' | sort -u)
      while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        # Find which section contains this category's IDs
        while IFS='|' read -r heading start end; do
          [[ -z "$heading" ]] && continue
          local has_cat
          has_cat=$(sed -n "${start},${end}p" "$source_abs" 2>/dev/null | grep -c "${prefix}-${cat}-" 2>/dev/null || true)
          if [[ "$has_cat" -gt 0 ]]; then
            printf '      %s: {l: %d, e: %d}\n' "$cat" "$start" "$end"
            break
          fi
        done <<< "$sections"
      done <<< "$cats"
    fi

    # Also field
    printf '    also: "graph.yaml → req_chains.%s-{CAT}"\n' "$prefix"
  else
    # Simple format (PREFIX-NNN)
    local simple_ids
    simple_ids=$(tr -d '\r' < "$source_abs" | grep -oE "${prefix}-[0-9]+" 2>/dev/null | head -500 || true)
    if [[ -n "$simple_ids" ]]; then
      printf '    pattern: "%s-{NN}"\n' "$prefix"
      printf '    file: %s\n' "$source"

      # Find relevant sections
      local sections="${SECTION_CACHE[$source]:-}"
      if [[ -n "$sections" ]]; then
        local section_count=0
        local section_yaml=""
        while IFS='|' read -r heading start end; do
          [[ -z "$heading" ]] && continue
          local has_id
          has_id=$(sed -n "${start},${end}p" "$source_abs" 2>/dev/null | grep -c "${prefix}-[0-9]" 2>/dev/null || true)
          if [[ "$has_id" -gt 2 ]]; then
            local escaped_h
            escaped_h=$(printf '%s' "$heading" | sed 's/"/\\"/g')
            section_yaml+="      - {name: \"${escaped_h}\", l: ${start}, e: ${end}}"$'\n'
            section_count=$((section_count + 1))
          fi
        done <<< "$sections"
        if [[ $section_count -gt 0 ]]; then
          printf '    sections:\n%s' "$section_yaml"
        fi
      fi

      # Also/lookup fields
      local also_files=""
      for rel in "${!DOC_ID_CACHE[@]}"; do
        [[ "$rel" == "$source" ]] && continue
        local ref_file="${PROJECT_DIR}/${rel}"
        local has_ref
        has_ref=$(head -30 "$ref_file" 2>/dev/null | tr -d '\r' | grep -c "${prefix}-" 2>/dev/null || true)
        [[ "$has_ref" -gt 0 ]] && also_files+="$rel, "
      done
      also_files=$(printf '%s' "$also_files" | sed 's/, $//')
      [[ -n "$also_files" ]] && printf '    also: [%s]\n' "$also_files"

      printf '    lookup: "graph.yaml → hazard_map.%s-{NN}"\n' "$prefix"
    fi
  fi
}

# Generate intent routes for grouped mode
generate_intent_routes_grouped() {
  # Auto-generate from available bundles
  # Check what bundles exist in the grouped output
  local has_si_wa=false has_api=false has_db=false has_security=false has_safety=false
  local has_si_am=false has_si_dg=false has_si_re=false has_si_rg=false has_si_il=false
  local has_testing=false has_regulatory=false

  local rel
  for rel in "${!DOC_ID_CACHE[@]}"; do
    local did="${DOC_ID_CACHE[$rel]}"
    case "$did" in
      *-SAD-*|*-SDS-*) has_si_wa=true; has_si_am=true; has_si_dg=true; has_si_re=true; has_si_rg=true; has_si_il=true ;;
      *-SRS-*) has_security=true; has_safety=true ;;
      *-SVP-*) has_testing=true ;;
      *-REF-*) has_regulatory=true ;;
    esac
  done

  # Emit routes based on what bundles were generated
  $has_si_wa && printf '  - {keywords: [화면, screen, UI, vue, frontend, component], bundle: si-wa}\n'
  $has_api && printf '  - {keywords: [API, REST, endpoint, fastify, backend], bundle: api}\n'
  $has_db && printf '  - {keywords: [database, schema, 테이블, SQL, migration], bundle: database}\n'
  $has_si_am && printf '  - {keywords: [hemodynamic, flow, WSS, pressure, 혈역학, 계산], bundle: si-am}\n'
  $has_si_dg && printf '  - {keywords: [DICOM, C-STORE, VENC, PACS, 의료영상], bundle: si-dg}\n'
  $has_si_re && printf '  - {keywords: [rendering, 렌더링, WebGPU, SSR, VTK, viewport], bundle: si-re}\n'
  $has_si_rg && printf '  - {keywords: [report, 리포트, export, PDF, DICOM-SR], bundle: si-rg}\n'
  $has_testing && printf '  - {keywords: [test, 테스트, verification, TC-], bundle: testing}\n'
  $has_security && printf '  - {keywords: [security, 보안, auth, encryption, threat], bundle: security}\n'
  $has_safety && printf '  - {keywords: [risk, hazard, safety, 안전, 위험], bundle: safety}\n'
  $has_regulatory && printf '  - {keywords: [regulatory, 규제, MFDS, FDA, IEC, ISO], bundle: regulatory-submission}\n'
  $has_si_il && printf '  - {keywords: [deploy, 배포, AWS, Docker, infrastructure], bundle: si-il}\n'
}

# ============================================================
# Summary
# ============================================================

print_summary() {
  local end_time duration
  end_time=$(date +%s)
  duration=$((end_time - START_TIME))

  local m_size b_size g_size r_size total
  m_size=$(wc -c < "${INDEX_DIR}/manifest.yaml" | tr -d ' ')
  b_size=$(wc -c < "${INDEX_DIR}/bundles.yaml" | tr -d ' ')
  g_size=$(wc -c < "${INDEX_DIR}/graph.yaml" | tr -d ' ')
  r_size=$(wc -c < "${INDEX_DIR}/router.yaml" | tr -d ' ')
  total=$((m_size + b_size + g_size + r_size))

  local sections_count=0
  local rel
  for rel in "${!SECTION_CACHE[@]}"; do
    [[ -n "${SECTION_CACHE[$rel]}" ]] && sections_count=$((sections_count + 1))
  done

  printf '\n## Document Index Generated\n\n'
  printf '| Metric | Value |\n'
  printf '|--------|-------|\n'
  printf '| Mode | %s |\n' "$MANIFEST_MODE"
  printf '| Total documents | %d |\n' "$TOTAL_FILES"
  printf '| Documents with sections | %d |\n' "$sections_count"
  printf '| manifest.yaml | %d bytes |\n' "$m_size"
  printf '| bundles.yaml | %d bytes |\n' "$b_size"
  printf '| graph.yaml | %d bytes |\n' "$g_size"
  printf '| router.yaml | %d bytes |\n' "$r_size"
  printf '| **Total index** | **%d bytes** |\n' "$total"
  printf '| Cross-references | %d |\n' "$TOTAL_REFS"
  printf '| Generation time | %ds |\n' "$duration"
}

# ============================================================
# Main
# ============================================================

main() {
  PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
  INDEX_DIR="${PROJECT_DIR}/docs/.index"

  info "Project: ${PROJECT_DIR}"

  mkdir -p "$INDEX_DIR"

  # Discover markdown files
  while IFS= read -r f; do
    ALL_FILES+=("$f")
  done < <(find "$PROJECT_DIR" -name "*.md" -not -path "*/.git/*" -type f | sort)

  TOTAL_FILES=${#ALL_FILES[@]}
  if [[ $TOTAL_FILES -eq 0 ]]; then
    error "No .md files found in ${PROJECT_DIR}"
    exit 1
  fi
  info "Found ${TOTAL_FILES} markdown files"

  # Pre-processing: cache frontmatter, sections, doc_ids, titles, sizes
  info "Pre-processing: extracting metadata and sections..."
  local i
  for ((i = 0; i < TOTAL_FILES; i++)); do
    local file="${ALL_FILES[$i]}"
    local rel="${file#${PROJECT_DIR}/}"

    FM_CACHE["$rel"]=$(extract_frontmatter "$file")
    TITLE_CACHE["$rel"]=$(extract_title "$file" "${FM_CACHE[$rel]}")

    local did
    did=$(get_fm_field "${FM_CACHE[$rel]}" "doc_id")
    DOC_ID_CACHE["$rel"]="$did"

    local sz
    sz=$(wc -c < "$file" | tr -d ' ')
    SIZE_CACHE["$rel"]="$sz"
    TOTAL_SIZE=$((TOTAL_SIZE + sz))

    cache_sections "$file" "$rel"
  done

  # Detect manifest mode
  detect_manifest_mode

  # Preserve custom bundles
  local bundles_file="${INDEX_DIR}/bundles.yaml"
  if [[ -f "$bundles_file" ]]; then
    CUSTOM_SECTION=$(sed -n '/^custom:/,$p' "$bundles_file" | tr -d '\r')
    [[ -n "$CUSTOM_SECTION" ]] && info "Preserved existing custom bundles section"
  fi

  generate_manifest
  generate_bundles
  generate_graph
  generate_router

  print_summary
}

main "$@"
