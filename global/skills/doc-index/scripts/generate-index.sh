#!/usr/bin/env bash
# generate-index.sh — Generate document index files for project documentation
# Part of the /doc-index skill
# Usage: bash generate-index.sh [project-directory]
#
# Generates three YAML index files in docs/.index/:
#   manifest.yaml — Document registry with metadata, tags, sections
#   bundles.yaml  — Feature-grouped document sets with token estimates
#   graph.yaml    — Cross-reference dependency graph

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCHEMA_VERSION="1.0"
PROJECT_DIR="${1:-.}"
INDEX_DIR=""
CUSTOM_SECTION=""

# Global arrays
declare -a ALL_FILES=()
TOTAL_FILES=0
TOTAL_REFS=0
START_TIME=$(date +%s)

# Temp file for graph references
REF_TMPFILE=""

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

# Safely emit a YAML string value — always double-quoted for safety
emit_yaml_string() {
  local val="${1:-}"
  if [[ -z "$val" ]]; then
    printf '""'
    return
  fi
  local escaped
  escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$escaped"
}

# ISO 8601 timestamp with timezone
get_timestamp() {
  if date '+%Y-%m-%dT%H:%M:%S%:z' &>/dev/null; then
    date '+%Y-%m-%dT%H:%M:%S%:z'
  else
    date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/'
  fi
}

# ============================================================
# Frontmatter Extraction
# ============================================================

# Extract YAML frontmatter (between --- delimiters)
extract_frontmatter() {
  local file="$1"
  local first_line
  first_line=$(head -1 "$file" | tr -d '\r\n')
  if [[ "$first_line" != "---" ]]; then
    return 0
  fi
  awk 'BEGIN{n=0} /^---/{n++; next} n==1{print} n>=2{exit}' "$file" | tr -d '\r'
}

# Get a specific field from frontmatter text
get_fm_field() {
  local fm="${1:-}"
  local field="$2"
  [[ -z "$fm" ]] && return
  local match
  match=$(printf '%s\n' "$fm" | grep -m1 "^${field}:" 2>/dev/null || true)
  [[ -z "$match" ]] && return
  printf '%s' "$match" | sed "s/^${field}:[[:space:]]*//" \
    | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" | tr -d '\r'
}

# ============================================================
# Metadata Extraction
# ============================================================

# Title: frontmatter name > first # heading > filename stem
extract_title() {
  local file="$1" fm="$2"

  local val
  val=$(get_fm_field "$fm" "name")
  [[ -n "$val" ]] && { printf '%s' "$val"; return; }

  val=$(tr -d '\r' < "$file" | grep -m1 '^# ' 2>/dev/null || true)
  val=$(printf '%s' "$val" | sed 's/^# //')
  [[ -n "$val" ]] && { printf '%s' "$val"; return; }

  basename "$file" .md | sed 's/[-_]/ /g; s/\b\(.\)/\u\1/g'
}

# Description: frontmatter description > first content paragraph (120 chars)
extract_description() {
  local file="$1" fm="$2"

  local val
  val=$(get_fm_field "$fm" "description")
  [[ -n "$val" ]] && { printf '%s' "${val:0:80}"; return; }

  local in_fm=0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "---" ]]; then
      in_fm=$((in_fm + 1)); continue
    fi
    [[ $in_fm -eq 1 ]] && continue
    [[ -z "$line" || "$line" =~ ^#\  || "$line" =~ ^\> || "$line" =~ ^\<\!-- || "$line" =~ ^--- || "$line" =~ ^\*\* ]] && continue
    printf '%s' "${line:0:80}"
    return
  done < "$file"
}

# Category from path
classify_category() {
  local path="$1" bn
  bn=$(basename "$path")

  [[ "$bn" == "SKILL.md" ]]           && { echo "skill"; return; }
  [[ "$bn" == "_policy.md" ]]         && { echo "policy"; return; }
  [[ "$path" == */agents/* ]]          && { echo "agent"; return; }
  [[ "$path" == */rules/* ]]           && { echo "rule"; return; }
  [[ "$path" == */commands/* ]]        && { echo "command"; return; }
  [[ "$path" == */reference/* ]]       && { echo "reference"; return; }
  [[ "$path" == docs/design/* ]]       && { echo "design"; return; }
  [[ "$bn" =~ ^CLAUDE ]]              && { echo "config"; return; }
  [[ "$bn" == "VERSION_HISTORY.md" || "$bn" == "commit-settings.md" ]] && { echo "config"; return; }
  [[ "$path" == docs/* ]]             && { echo "reference"; return; }
  echo "root"
}

# Scope from path prefix
classify_scope() {
  local path="$1"
  case "$path" in
    global/*)      echo "global" ;;
    plugin-lite/*) echo "plugin-lite" ;;
    plugin/*)      echo "plugin" ;;
    project/*)     echo "project" ;;
    enterprise/*)  echo "enterprise" ;;
    docs/*)        echo "docs" ;;
    *)             echo "root" ;;
  esac
}

# Generate tags from path + frontmatter + content keywords
generate_tags() {
  local path="$1" fm="$2" file="$3"
  local tags=""

  # Stem tag
  local stem
  stem=$(basename "$path" .md)
  case "$stem" in
    SKILL|CLAUDE|README|_policy|VERSION_HISTORY|CLAUDE.local*) ;;
    *) tags="$stem" ;;
  esac

  # Leaf directory tag
  local leaf
  leaf=$(basename "$(dirname "$path")")
  case "$leaf" in
    .|rules|skills|agents|commands|reference|.claude|scripts|claude-config) ;;
    *)
      if [[ "$leaf" != "$stem" ]]; then
        [[ -n "$tags" ]] && tags="$tags, $leaf" || tags="$leaf"
      fi
      ;;
  esac

  # alwaysApply tag
  local aa
  aa=$(get_fm_field "$fm" "alwaysApply")
  if [[ "$aa" == "true" ]]; then
    [[ -n "$tags" ]] && tags="$tags, always-apply" || tags="always-apply"
  fi

  # Keyword scan (first 30 lines)
  local content
  content=$(head -30 "$file" | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  for kw in security testing performance api workflow git ci documentation; do
    if echo "$content" | grep -qw "$kw" 2>/dev/null; then
      if ! echo ", $tags, " | grep -q ", $kw, " 2>/dev/null; then
        [[ -n "$tags" ]] && tags="$tags, $kw" || tags="$kw"
      fi
    fi
  done

  [[ -z "$tags" ]] && printf '[]' || printf '[%s]' "$tags"
}

# Extract ## headings with line ranges
extract_sections() {
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
    printf '      - heading: %s\n' "$(emit_yaml_string "${h_names[$i]}")"
    printf '        line_range: [%d, %d]\n' "$s" "$e"
  done
}

# ============================================================
# Bundle Classification
# ============================================================

classify_bundle() {
  local path="$1"
  case "$path" in
    project/.claude/rules/core/*)               echo "core" ;;
    project/.claude/rules/coding/*)             echo "coding" ;;
    project/.claude/rules/api/*)                echo "api" ;;
    project/.claude/rules/workflow/*)           echo "workflow" ;;
    project/.claude/rules/security.md)          echo "security" ;;
    enterprise/*)                               echo "security" ;;
    project/.claude/rules/operations/*)         echo "project-mgmt" ;;
    project/.claude/rules/project-management/*) echo "project-mgmt" ;;
    project/.claude/rules/tools/*)              echo "project-mgmt" ;;
    global/skills/*)                            echo "skills-global" ;;
    plugin/skills/*)                            echo "skills-plugin" ;;
    project/.claude/skills/*)                   echo "skills-plugin" ;;
    */agents/*)                                 echo "agents" ;;
    project/.claude/commands/*)                 echo "commands" ;;
    docs/design/*)                              echo "design" ;;
    docs/*)                                     echo "docs-misc" ;;
    plugin-lite/*)                              echo "plugin-lite" ;;
    global/*.md)                                echo "config" ;;
    project/CLAUDE*|project/VERSION*)           echo "config" ;;
    project/claude-guidelines)                  echo "config" ;;
    plugin/README.md)                           echo "config" ;;
    *)                                          echo "root" ;;
  esac
}

bundle_description() {
  case "$1" in
    core)           echo "Core principles, communication, environment rules (always-apply)" ;;
    coding)         echo "Coding standards, error handling, performance, safety, anti-patterns" ;;
    api)            echo "API design, architecture, observability, REST conventions" ;;
    workflow)       echo "Git workflow, CI resilience, GitHub issues/PRs, session management" ;;
    security)       echo "Security rules, enterprise compliance, auth, input validation" ;;
    project-mgmt)   echo "Build verification, testing, documentation standards, operations" ;;
    skills-global)  echo "Global skills: harness, issue-work, pr-work, release, doc-review" ;;
    skills-plugin)  echo "Plugin and project skills: api-design, coding-guidelines, security-audit" ;;
    agents)         echo "Agent definitions: code-reviewer, qa-reviewer, documentation-writer" ;;
    commands)       echo "Slash commands: code-quality, git-status, pr-review" ;;
    design)         echo "Architecture and optimization design documents" ;;
    docs-misc)      echo "Project documentation: token reports, migration guides, extensions" ;;
    config)         echo "Configuration: CLAUDE.md, commit settings, version history" ;;
    plugin-lite)    echo "Lightweight plugin: behavioral guardrails" ;;
    root)           echo "Project overview: README, HOOKS, QUICKSTART, COMPATIBILITY" ;;
    *)              echo "Miscellaneous documents" ;;
  esac
}

# ============================================================
# Reference Scanning (for graph.yaml)
# ============================================================

# Scan one file for outgoing references
# Output: target_path|type|line_num
scan_references() {
  local file="$1"
  local file_dir
  file_dir=$(dirname "$file")

  # Strip fenced code blocks, then scan
  local content
  content=$(sed '/^```/,/^```/d' "$file" | tr -d '\r')

  # Pattern 1: Markdown links [text](path.md...)
  echo "$content" | grep -n '\[.*\](.*\.md' 2>/dev/null | while IFS= read -r line; do
    local lnum="${line%%:*}"
    local text="${line#*:}"
    printf '%s\n' "$text" | grep -oE '\]\([^)]*\.md[^)]*\)' | sed 's/^\](//' | sed 's/)$//' \
      | while IFS= read -r target; do
        case "$target" in http://*|https://*) continue ;; esac
        target="${target%%#*}"
        target="${target%%\?*}"
        local resolved
        resolved=$(resolve_ref "$file_dir" "$target")
        [[ -n "$resolved" ]] && printf '%s|link|%s\n' "$resolved" "$lnum"
      done
  done || true

  # Pattern 2: see `path.md`
  echo "$content" | grep -n 'see `[^`]*\.md`' 2>/dev/null | while IFS= read -r line; do
    local lnum="${line%%:*}"
    local text="${line#*:}"
    printf '%s\n' "$text" | grep -oE 'see `[^`]*\.md`' | sed 's/^see `//' | sed 's/`$//' \
      | while IFS= read -r target; do
        local resolved
        resolved=$(resolve_ref "$file_dir" "$target")
        [[ -n "$resolved" ]] && printf '%s|see|%s\n' "$resolved" "$lnum"
      done
  done || true

  # Pattern 3: @load: reference/name (no .md extension)
  echo "$content" | grep -n '@load:' 2>/dev/null | while IFS= read -r line; do
    local lnum="${line%%:*}"
    local text="${line#*:}"
    printf '%s\n' "$text" | grep -oE '@load:[[:space:]]*[^[:space:]`,]+' | sed 's/@load:[[:space:]]*//' \
      | while IFS= read -r ref; do
        ref=$(printf '%s' "$ref" | sed 's/[`.,;)>]//g')
        [[ -z "$ref" ]] && continue
        local resolved=""
        # Try exact path with .md
        resolved=$(resolve_ref "$file_dir" "${ref}.md")
        # Try under reference/ prefix
        [[ -z "$resolved" ]] && resolved=$(resolve_ref "$file_dir" "reference/${ref}.md")
        [[ -n "$resolved" ]] && printf '%s|load|%s\n' "$resolved" "$lnum"
      done
  done || true

  # Pattern 4: @./reference/file.md (direct import in skills)
  echo "$content" | grep -n '^@\./' 2>/dev/null | while IFS= read -r line; do
    local lnum="${line%%:*}"
    local text="${line#*:}"
    local target
    target=$(printf '%s\n' "$text" | grep -oE '^@\./[^[:space:]]+' | sed 's/^@\.\///' | head -1)
    [[ -z "$target" ]] && continue
    local resolved
    resolved=$(resolve_ref "$file_dir" "$target")
    [[ -n "$resolved" ]] && printf '%s|import|%s\n' "$resolved" "$lnum"
  done || true
}

# Resolve relative reference to project-root-relative path
resolve_ref() {
  local base_dir="$1"
  local target="$2"

  local abs_path
  if [[ "${target:0:1}" == "/" ]]; then
    abs_path="${PROJECT_DIR}${target}"
  else
    abs_path="${base_dir}/${target}"
  fi

  # Normalize and check existence
  local normalized
  normalized=$(realpath --relative-to="$PROJECT_DIR" "$abs_path" 2>/dev/null) || return
  [[ -f "${PROJECT_DIR}/${normalized}" ]] && printf '%s' "$normalized"
}

# ============================================================
# Generator: manifest.yaml
# ============================================================

generate_manifest() {
  local output="${INDEX_DIR}/manifest.yaml"
  info "Generating manifest.yaml..."

  {
    printf '# docs/.index/manifest.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT\n'
    printf '# Regenerate with: /doc-index\n\n'
    printf 'version: "%s"\n' "$SCHEMA_VERSION"
    printf 'generated: %s\n' "$(emit_yaml_string "$(get_timestamp)")"
    printf 'total_files: %d\n\n' "$TOTAL_FILES"
    printf 'documents:\n'

    local i
    for ((i = 0; i < TOTAL_FILES; i++)); do
      local file="${ALL_FILES[$i]}"
      local rel="${file#${PROJECT_DIR}/}"

      local fm
      fm=$(extract_frontmatter "$file")

      local title desc category scope fsize tags
      title=$(extract_title "$file" "$fm")
      desc=$(extract_description "$file" "$fm")
      category=$(classify_category "$rel")
      scope=$(classify_scope "$rel")
      fsize=$(wc -c < "$file" | tr -d ' ')
      tags=$(generate_tags "$rel" "$fm" "$file")

      printf '  - path: %s\n' "$(emit_yaml_string "$rel")"
      printf '    title: %s\n' "$(emit_yaml_string "$title")"
      printf '    description: %s\n' "$(emit_yaml_string "$desc")"
      printf '    category: %s\n' "$category"
      printf '    scope: %s\n' "$scope"
      printf '    size: %d\n' "$fsize"
      printf '    tags: %s\n' "$tags"

    done
  } > "$output"

  local msize
  msize=$(wc -c < "$output" | tr -d ' ')
  success "manifest.yaml generated ($((msize / 1024))KB, ${TOTAL_FILES} documents)"
}

# ============================================================
# Generator: bundles.yaml
# ============================================================

generate_bundles() {
  local output="${INDEX_DIR}/bundles.yaml"
  info "Generating bundles.yaml..."

  declare -A B_FILES=()
  declare -A B_SIZES=()

  local i
  for ((i = 0; i < TOTAL_FILES; i++)); do
    local file="${ALL_FILES[$i]}"
    local rel="${file#${PROJECT_DIR}/}"
    local bundle
    bundle=$(classify_bundle "$rel")
    B_FILES["$bundle"]+="${rel}"$'\n'
    local sz
    sz=$(wc -c < "$file" | tr -d ' ')
    B_SIZES["$bundle"]=$(( ${B_SIZES["$bundle"]:-0} + sz ))
  done

  {
    printf '# docs/.index/bundles.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT (auto section)\n'
    printf '# Custom section (below) is preserved across regeneration\n\n'
    printf 'version: "%s"\n' "$SCHEMA_VERSION"
    printf 'generated: %s\n\n' "$(emit_yaml_string "$(get_timestamp)")"
    printf 'auto:\n'

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

  local bsize num_bundles
  bsize=$(wc -c < "$output" | tr -d ' ')
  num_bundles=$(printf '%s\n' "${!B_FILES[@]}" | wc -l | tr -d ' ')
  success "bundles.yaml generated ($((bsize / 1024))KB, ${num_bundles} bundles)"
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
    printf '# Cross-reference dependency graph\n\n'
    printf 'version: "%s"\n' "$SCHEMA_VERSION"
    printf 'generated: %s\n\n' "$(emit_yaml_string "$(get_timestamp)")"

    if [[ ! -s "$REF_TMPFILE" ]]; then
      printf 'nodes: {}\n'
    else
      printf 'nodes:\n'

      # Only emit source nodes (outgoing only; incoming is derivable)
      local source_nodes
      source_nodes=$(awk -F'|' '{print $1}' "$REF_TMPFILE" | sort -u)

      while IFS= read -r node; do
        [[ -z "$node" ]] && continue

        # Deduplicate: unique source→target pairs (ignore line dups)
        local outgoing
        outgoing=$(grep "^${node}|" "$REF_TMPFILE" 2>/dev/null | sort -t'|' -k1,3 -u || true)
        [[ -z "$outgoing" ]] && continue

        printf '  %s:\n' "$(emit_yaml_string "$node")"
        while IFS='|' read -r _src tgt typ ln; do
          printf '    - target: %s\n' "$(emit_yaml_string "$tgt")"
          printf '      type: %s\n' "$typ"
        done <<< "$outgoing"
      done <<< "$source_nodes"
    fi
  } > "$output"

  local gsize
  gsize=$(wc -c < "$output" | tr -d ' ')
  success "graph.yaml generated ($((gsize / 1024))KB, ${TOTAL_REFS} references)"
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
        # Emit previous pair if exists
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
  # Emit last pair
  if [[ -n "$current_prefix" && -n "$current_source" ]]; then
    printf '%s|%s\n' "$current_prefix" "$current_source"
  fi
}

# Resolve a single ID pattern: detect format, categories, cross-refs
resolve_one_pattern() {
  local prefix="$1"
  local source="$2"

  local source_abs="${PROJECT_DIR}/${source}"
  local is_dir=false
  [[ -d "$source_abs" ]] && is_dir=true

  if $is_dir; then
    # Directory source: each file maps to one ID (e.g., SCR-001-login.md)
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

    # Cross-references
    emit_cross_refs "$prefix" "$source"
    return
  fi

  # File source: scan for ID occurrences within the file
  if [[ ! -f "$source_abs" ]]; then
    warn "ID pattern source not found: $source"
    return
  fi

  # Detect all IDs matching this prefix
  local all_ids
  all_ids=$(tr -d '\r' < "$source_abs" | grep -oE "${prefix}-[A-Z]+-[0-9]+" 2>/dev/null | head -500 || true)

  if [[ -n "$all_ids" ]]; then
    # Compound format: PREFIX-CAT-NNN
    printf '  %s:\n' "$prefix"
    printf '    format: "%s-{CAT}-{NNN}"\n' "$prefix"
    printf '    source: %s\n' "$(emit_yaml_string "$source")"
    printf '    categories:\n'

    # Extract unique categories with first line and count
    local cats
    cats=$(printf '%s\n' "$all_ids" | sed "s/^${prefix}-//" | sed 's/-[0-9]*$//' | sort -u)
    while IFS= read -r cat; do
      [[ -z "$cat" ]] && continue
      local first_line count
      first_line=$(tr -d '\r' < "$source_abs" | grep -n "${prefix}-${cat}-" -m1 2>/dev/null | cut -d: -f1 || true)
      count=$(tr -d '\r' < "$source_abs" | grep -c "${prefix}-${cat}-" 2>/dev/null || echo 0)
      [[ -z "$first_line" ]] && first_line=0
      printf '      %s: {line: %s, count: %s}\n' "$cat" "$first_line" "$count"
    done <<< "$cats"
  else
    # Try simple format: PREFIX-NNN
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

  # Cross-references
  emit_cross_refs "$prefix" "$source"
}

# Find files that reference this prefix (excluding source)
emit_cross_refs() {
  local prefix="$1"
  local source="$2"

  local refs_found=false
  local ref_files
  ref_files=$(grep -rl "${prefix}-" "$PROJECT_DIR" --include="*.md" 2>/dev/null \
    | sort | while IFS= read -r f; do
        local rel="${f#${PROJECT_DIR}/}"
        # Skip the source itself and .index files
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

  # Preserve id_patterns before regenerating
  preserve_id_patterns

  {
    printf '# docs/.index/router.yaml\n'
    printf '# Auto-generated by /doc-index -- DO NOT EDIT (auto sections)\n'
    printf '# id_patterns section (bottom) is preserved across regeneration\n\n'
    printf 'version: "%s"\n' "$SCHEMA_VERSION"
    printf 'generated: %s\n\n' "$(emit_yaml_string "$(get_timestamp)")"

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

    # Resolve id_patterns into identifiers section
    local patterns
    patterns=$(parse_id_patterns)
    if [[ -n "$patterns" ]]; then
      printf '\n# Auto-resolved from id_patterns declarations below\n'
      printf 'identifiers:\n'
      while IFS='|' read -r prefix source; do
        [[ -z "$prefix" ]] && continue
        resolve_one_pattern "$prefix" "$source"
      done <<< "$patterns"
    fi

    # Restore id_patterns section
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

  local rsize
  rsize=$(wc -c < "$output" | tr -d ' ')
  success "router.yaml generated ($((rsize / 1024))KB)"
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

  printf '\n## Document Index Generated\n\n'
  printf '| Metric | Value |\n'
  printf '|--------|-------|\n'
  printf '| Total documents | %d |\n' "$TOTAL_FILES"
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
