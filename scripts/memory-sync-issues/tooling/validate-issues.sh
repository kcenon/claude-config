#!/bin/bash
# validate-issues.sh — Sanity check the 30 issue markdown files
# Checks: frontmatter required keys, label/milestone references, blocked_by graph,
# placeholder ID consistency, cross-reference targets exist.

set -u

ISSUES_DIR="${1:-/tmp/claude/issues}"
errors=0
warnings=0

err()  { echo "  [E] $1"; errors=$((errors + 1)); }
warn() { echo "  [W] $1"; warnings=$((warnings + 1)); }

# Allowed values
ALLOWED_TYPES="type/epic type/feature type/chore type/docs type/test type/ci"
ALLOWED_PRIORITIES="priority/high priority/medium priority/low"
ALLOWED_SIZES="size/XS size/S size/M size/L size/XL"
ALLOWED_PHASES="phase/A-validation phase/B-trust phase/C-bootstrap phase/D-engine phase/E-migration phase/F-audit phase/G-rollout"
ALLOWED_MILESTONES="memory-sync-v1-validation memory-sync-v1-trust memory-sync-v1-bootstrap memory-sync-v1-engine memory-sync-v1-single memory-sync-v1-audit memory-sync-v1-multi"
ALLOWED_IDS="EPIC A1 A2 A3 A4 A5 B1 B2 B3 B4 C1 C2 C3 C4 C5 D1 D2 D3 D4 D5 E1 E2 E3 F1 F2 F3 F4 G1 G2 G3"

in_set() {
  local needle="$1" haystack="$2"
  for item in $haystack; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

extract_fm() {
  local file="$1"
  awk '/^---$/{c++; next} c==1{print}' "$file"
}

extract_field() {
  local fm="$1" key="$2"
  echo "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

extract_list_field() {
  # For YAML list fields like:  blocked_by: [A1, A2]  OR  multiline list
  local fm="$1" key="$2"
  local line
  line="$(echo "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//")"
  if [[ "$line" == "["*"]" ]]; then
    # Inline form
    echo "$line" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
  else
    # Multiline form (lines starting with "  - " under the key)
    echo "$fm" | awk -v k="$key" '
      $0 ~ "^"k":" { in_block=1; next }
      in_block && /^  - / { sub(/^  - /, ""); print; next }
      in_block && /^[a-zA-Z]/ { in_block=0 }
    '
  fi
}

# Get all known issue IDs from filenames (sanity)
declare -a known_ids
known_ids=()
for f in "$ISSUES_DIR"/*.md; do
  base="$(basename "$f" .md)"
  if [[ "$base" == "EPIC" ]]; then
    known_ids+=("EPIC")
  else
    id="${base%%-*}"   # take chars before first dash
    known_ids+=("$id")
  fi
done

is_known_id() {
  local needle="$1"
  for id in "${known_ids[@]}"; do
    [[ "$id" == "$needle" ]] && return 0
  done
  return 1
}

# Validate one file
validate_file() {
  local f="$1"
  local rel; rel="$(basename "$f")"
  local base="${rel%.md}"
  local fid
  if [[ "$base" == "EPIC" ]]; then
    fid="EPIC"
  else
    fid="${base%%-*}"
  fi

  echo "[$fid] $rel"

  local fm; fm="$(extract_fm "$f")"
  if [[ -z "$fm" ]]; then
    err "no frontmatter found"
    return
  fi

  # Required fields
  for k in title labels milestone blocked_by blocks; do
    if ! echo "$fm" | grep -qE "^${k}:"; then
      err "missing field: $k"
    fi
  done

  # parent_epic optional for EPIC itself but required for children
  if [[ "$fid" != "EPIC" ]]; then
    if ! echo "$fm" | grep -qE "^parent_epic:"; then
      err "missing field: parent_epic (children must declare)"
    fi
  fi

  # Validate labels (multiline form)
  local labels; labels="$(extract_list_field "$fm" labels)"
  if [[ -z "$labels" ]]; then
    err "labels list empty"
  else
    # Each label must match one of our allowed sets
    local has_type=0 has_priority=0 has_phase=0 has_area=0
    while IFS= read -r lab; do
      [[ -z "$lab" ]] && continue
      case "$lab" in
        area/memory) has_area=1 ;;
        type/*)
          has_type=1
          in_set "$lab" "$ALLOWED_TYPES" || err "unknown label: $lab"
          ;;
        priority/*)
          has_priority=1
          in_set "$lab" "$ALLOWED_PRIORITIES" || err "unknown label: $lab"
          ;;
        size/*)
          in_set "$lab" "$ALLOWED_SIZES" || err "unknown label: $lab"
          ;;
        phase/*)
          has_phase=1
          in_set "$lab" "$ALLOWED_PHASES" || err "unknown label: $lab"
          ;;
        *) warn "unrecognized label (still allowed): $lab" ;;
      esac
    done <<EOF
$labels
EOF

    [[ $has_type -eq 0 ]]     && err "missing type/* label"
    [[ $has_priority -eq 0 ]] && err "missing priority/* label"
    [[ $has_area -eq 0 ]]     && err "missing area/memory label"
    if [[ "$fid" != "EPIC" ]] && [[ $has_phase -eq 0 ]]; then
      err "missing phase/* label (required for children)"
    fi
  fi

  # Validate milestone
  local ms; ms="$(extract_field "$fm" milestone)"
  if [[ -n "$ms" ]] && ! in_set "$ms" "$ALLOWED_MILESTONES"; then
    err "unknown milestone: $ms"
  fi

  # Validate blocked_by IDs
  local bb; bb="$(extract_list_field "$fm" blocked_by)"
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! in_set "$id" "$ALLOWED_IDS"; then
      err "blocked_by references unknown id: $id"
    fi
    if ! is_known_id "$id"; then
      err "blocked_by references missing file for: $id"
    fi
    if [[ "$id" == "$fid" ]]; then
      err "blocked_by includes self: $id"
    fi
  done <<EOF
$bb
EOF

  # Validate blocks IDs
  local bl; bl="$(extract_list_field "$fm" blocks)"
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! in_set "$id" "$ALLOWED_IDS"; then
      err "blocks references unknown id: $id"
    fi
    if ! is_known_id "$id"; then
      err "blocks references missing file for: $id"
    fi
    if [[ "$id" == "$fid" ]]; then
      err "blocks includes self: $id"
    fi
  done <<EOF
$bl
EOF

  # parent_epic must be "EPIC" for children
  if [[ "$fid" != "EPIC" ]]; then
    local pe; pe="$(extract_field "$fm" parent_epic)"
    if [[ "$pe" != "EPIC" ]]; then
      err "parent_epic must be 'EPIC', got: $pe"
    fi
  fi

  # Required body sections (per type)
  local body; body="$(awk '/^---$/{c++; next} c>=2{print}' "$f")"
  for sec in "## What" "## Why" "## Who" "## When" "## Where" "## How"; do
    if ! echo "$body" | grep -qF "$sec"; then
      err "missing section: $sec"
    fi
  done

  # Cross-references section required (uses ## form)
  if ! echo "$body" | grep -qF "## Cross-references"; then
    err "missing section: ## Cross-references"
  fi

  # Acceptance Criteria required
  if ! echo "$body" | grep -qF "### Acceptance Criteria"; then
    err "missing section: ### Acceptance Criteria"
  fi
}

# Symmetric blocked_by/blocks check across all files
check_symmetry() {
  echo
  echo "[symmetry] cross-checking blocked_by ↔ blocks consistency"
  for f in "$ISSUES_DIR"/*.md; do
    local base; base="$(basename "$f" .md)"
    local fid
    if [[ "$base" == "EPIC" ]]; then
      fid="EPIC"
    else
      fid="${base%%-*}"
    fi
    local fm; fm="$(extract_fm "$f")"
    local bb; bb="$(extract_list_field "$fm" blocked_by)"
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      # Find dep's file and check its blocks contains fid
      local depfile
      if [[ "$dep" == "EPIC" ]]; then
        depfile="$ISSUES_DIR/EPIC.md"
      else
        depfile="$(ls "$ISSUES_DIR"/${dep}-*.md 2>/dev/null | head -1)"
      fi
      [[ -z "$depfile" ]] && continue
      local depfm; depfm="$(extract_fm "$depfile")"
      local depblocks; depblocks="$(extract_list_field "$depfm" blocks)"
      if ! echo "$depblocks" | grep -qxF "$fid"; then
        echo "  [W] $fid says blocked_by=[$dep], but $dep does not list $fid in blocks"
        warnings=$((warnings + 1))
      fi
    done <<EOF
$bb
EOF
  done
}

main() {
  echo "=== Validating issues in $ISSUES_DIR ==="
  echo "Found ${#known_ids[@]} files: ${known_ids[*]}"
  echo

  for f in "$ISSUES_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    validate_file "$f"
  done

  check_symmetry

  echo
  echo "=== Summary ==="
  echo "Errors:   $errors"
  echo "Warnings: $warnings"

  [[ $errors -gt 0 ]] && exit 1
  [[ $warnings -gt 0 ]] && exit 3
  exit 0
}

main "$@"
