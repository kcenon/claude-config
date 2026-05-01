#!/bin/bash
# validate.sh - Memory file structural and format validator.
#
# Implements MEMORY_VALIDATION_SPEC.md (v1.0.1) for the cross-machine memory
# sync system. Read-only: never modifies input files.
#
# Exit codes (per spec section 7):
#   0   PASS            - file is fully valid
#   1   FAIL-STRUCT     - structural error (delimiters, required fields, body too short)
#   2   FAIL-FORMAT     - format error (field value violates type/length/enum)
#   3   WARN-SEMANTIC   - semantic warning (recommended field or marker missing)
#   64  USAGE           - usage error (invalid CLI arguments)
#
# In --all mode the worst per-file code wins (fail > warn > pass). Skipped files
# (MEMORY.md) are not counted in any of pass/warn/fail per spec section 9.
#
# Bash 3.2 compatible (macOS default) per spec section 8: empty-array guards,
# BASH_REMATCH save-then-use, wc -l output normalization with ${var:-0} default.

set -u

VALID_TYPES=("user" "feedback" "project" "reference")
VALID_TRUST=("verified" "inferred" "quarantined")

# Per-file scratch arrays. Reset at the start of validate_file().
errors=()
warnings=()

print_help() {
  cat <<'EOF'
validate.sh - validate a Claude memory file against MEMORY_VALIDATION_SPEC.md.

USAGE
    validate.sh <path/to/memory.md>      Validate a single file.
    validate.sh --all <dir>              Validate all *.md files under <dir>.
    validate.sh --help | -h              Show this help.

EXAMPLES
    validate.sh ~/.claude/agent-memory/main/user_github.md
    validate.sh --all ~/.claude/agent-memory/main/

EXIT CODES
    0   PASS
    1   FAIL-STRUCT  (structural error: delimiters, required fields, body length)
    2   FAIL-FORMAT  (format error: field type, length, or enum violated)
    3   WARN-SEMANTIC (recommended field or content marker missing)
    64  USAGE        (invalid arguments)

NOTES
    MEMORY.md is the auto-generated index and is skipped (not counted).
    Output is deterministic; per-file order in --all mode follows shell glob.
EOF
}

# Strip surrounding double or single quotes from a YAML scalar value.
strip_quotes() {
  local v="$1"
  # Trim leading/trailing whitespace.
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  # Strip a single matched pair of surrounding quotes.
  if [[ "$v" =~ ^\"(.*)\"$ ]]; then
    local m="${BASH_REMATCH[1]}"
    v="$m"
  elif [[ "$v" =~ ^\'(.*)\'$ ]]; then
    local m="${BASH_REMATCH[1]}"
    v="$m"
  fi
  printf '%s' "$v"
}

# Read a single-line YAML field value. Echoes the raw value (without the
# `key:` prefix); empty string when the key is absent or has no value.
get_field() {
  local fm="$1"
  local key="$2"
  printf '%s\n' "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

print_result() {
  local rel="$1"
  local code="$2"
  local label
  case "$code" in
    0) label="PASS" ;;
    1) label="FAIL-STRUCT" ;;
    2) label="FAIL-FORMAT" ;;
    3) label="WARN-SEMANTIC" ;;
    *) label="UNKNOWN" ;;
  esac
  printf "%-50s %s\n" "$rel" "$label"
  if (( ${#errors[@]} > 0 )); then
    for e in "${errors[@]}"; do
      printf "    [E] %s\n" "$e"
    done
  fi
  if (( ${#warnings[@]} > 0 )); then
    for w in "${warnings[@]}"; do
      printf "    [W] %s\n" "$w"
    done
  fi
}

# Validate a single file. Returns:
#   0   PASS
#   1   FAIL-STRUCT
#   2   FAIL-FORMAT
#   3   WARN-SEMANTIC
#   255 SKIPPED (MEMORY.md or non-memory index)
validate_file() {
  local f="$1"
  local rel
  rel="$(basename "$f")"
  errors=()
  warnings=()

  # Spec section 2: MEMORY.md is the auto-generated index, not a memory file.
  if [[ "$rel" == "MEMORY.md" ]]; then
    return 255
  fi

  if [[ ! -f "$f" ]]; then
    errors+=("file not found")
    print_result "$rel" 1
    return 1
  fi

  if [[ ! -r "$f" ]]; then
    errors+=("file not readable")
    print_result "$rel" 1
    return 1
  fi

  # Frontmatter open delimiter must be the first line exactly.
  local first_line
  first_line="$(head -1 "$f")"
  if [[ "$first_line" != "---" ]]; then
    errors+=("missing opening frontmatter delimiter")
    print_result "$rel" 1
    return 1
  fi

  # Find the closing delimiter line number.
  local fm_end
  fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$f")"
  fm_end="${fm_end:-}"
  if [[ -z "$fm_end" ]]; then
    errors+=("missing closing frontmatter delimiter")
    print_result "$rel" 1
    return 1
  fi

  local fm body
  fm="$(sed -n "2,$((fm_end - 1))p" "$f")"
  body="$(sed -n "$((fm_end + 1)),\$p" "$f")"

  # Required fields (spec section 3).
  local name desc type
  name="$(get_field "$fm" "name")"
  desc="$(get_field "$fm" "description")"
  type="$(get_field "$fm" "type")"

  [[ -z "$name" ]] && errors+=("missing required field: name")
  [[ -z "$desc" ]] && errors+=("missing required field: description")
  [[ -z "$type" ]] && errors+=("missing required field: type")

  # Recommended fields (spec section 3 / Phase 2 backfill).
  local sm ca tl lv
  sm="$(get_field "$fm" "source-machine")"
  ca="$(get_field "$fm" "created-at")"
  tl="$(get_field "$fm" "trust-level")"
  lv="$(get_field "$fm" "last-verified")"

  [[ -z "$sm" ]] && warnings+=("missing field: source-machine (Phase 2)")
  [[ -z "$ca" ]] && warnings+=("missing field: created-at (Phase 2)")
  [[ -z "$tl" ]] && warnings+=("missing field: trust-level (Phase 2)")
  [[ -z "$lv" ]] && warnings+=("missing field: last-verified (Phase 2)")

  # Format checks (spec section 4). Track whether any format error fires so we
  # can return exit code 2 (FAIL-FORMAT) when only format violations exist.
  local format_error=0

  # `name`: free-form display text, 2-100 chars, no newlines. Quotes stripped.
  if [[ -n "$name" ]]; then
    local name_clean
    name_clean="$(strip_quotes "$name")"
    local name_len=${#name_clean}
    if (( name_len < 2 || name_len > 100 )); then
      errors+=("name length invalid: $name_len chars (must be 2-100)")
      format_error=1
    fi
    case "$name_clean" in
      *$'\n'*)
        errors+=("name contains newline")
        format_error=1
        ;;
    esac
  fi

  # `description`: 1-256 chars, no newlines.
  if [[ -n "$desc" ]]; then
    local desc_clean
    desc_clean="$(strip_quotes "$desc")"
    local desc_len=${#desc_clean}
    if (( desc_len < 1 || desc_len > 256 )); then
      errors+=("description length invalid: $desc_len chars (must be 1-256)")
      format_error=1
    fi
    case "$desc_clean" in
      *$'\n'*)
        errors+=("description contains newline")
        format_error=1
        ;;
    esac
  fi

  # `type`: enum, case-sensitive.
  local type_clean=""
  if [[ -n "$type" ]]; then
    type_clean="$(strip_quotes "$type")"
    local type_valid=0
    for t in "${VALID_TYPES[@]}"; do
      [[ "$type_clean" == "$t" ]] && type_valid=1
    done
    if (( type_valid == 0 )); then
      errors+=("type invalid: $type_clean (must be one of: ${VALID_TYPES[*]})")
      format_error=1
    fi
  fi

  # `trust-level`: enum when present.
  if [[ -n "$tl" ]]; then
    local tl_clean
    tl_clean="$(strip_quotes "$tl")"
    local tl_valid=0
    for t in "${VALID_TRUST[@]}"; do
      [[ "$tl_clean" == "$t" ]] && tl_valid=1
    done
    if (( tl_valid == 0 )); then
      errors+=("trust-level invalid: $tl_clean (must be one of: ${VALID_TRUST[*]})")
      format_error=1
    fi
  fi

  # Filename pattern (spec section 2). Mismatch is a warning, not a failure.
  local fname_base
  fname_base="$(basename "$f" .md)"
  if [[ ! "$fname_base" =~ ^(user|feedback|project|reference)_[a-z0-9_]+$ ]]; then
    warnings+=("filename does not match pattern <type>_<topic>.md: $fname_base")
  fi

  # Body length (spec section 5).
  local body_len=${#body}
  if (( body_len < 30 )); then
    errors+=("body too short: $body_len chars (min 30)")
  elif (( body_len > 5000 )); then
    warnings+=("body too long: $body_len chars (consider splitting; max 5000)")
  fi

  # Structural markers for feedback/project (spec section 5).
  if [[ "$type_clean" == "feedback" ]] || [[ "$type_clean" == "project" ]]; then
    if ! printf '%s\n' "$body" | grep -q -i -E '(\*\*Why:\*\*|^Why:)'; then
      warnings+=("missing 'Why:' rationale (recommended for $type_clean type)")
    fi
    if ! printf '%s\n' "$body" | grep -q -i -E '(\*\*How to apply:\*\*|^How to apply:)'; then
      warnings+=("missing 'How to apply:' guidance (recommended for $type_clean type)")
    fi
  fi

  # Absolute-command justification (acceptance criteria).
  local abs_count just_count
  abs_count="$(printf '%s\n' "$body" | grep -i -o -E '\b(always|never|from now on|must always|must never)\b' 2>/dev/null | wc -l | tr -d ' ')"
  abs_count="${abs_count:-0}"
  if (( abs_count > 0 )); then
    just_count="$(printf '%s\n' "$body" | grep -i -o -E '\b(because|reason|why|due to|incident)\b' 2>/dev/null | wc -l | tr -d ' ')"
    just_count="${just_count:-0}"
    if (( just_count == 0 )); then
      warnings+=("absolute command pattern without justification (always/never/from now on)")
    fi
  fi

  # Compute the result code: structural errors take priority over format
  # errors; warnings only matter when no errors fired.
  local code=0
  if (( ${#errors[@]} > 0 )); then
    if (( format_error == 1 )); then
      # Walk the errors array to see if any non-format (structural) error
      # fired. The format_error flag is sticky once set, so we need to detect
      # whether structural errors are also present.
      local struct_err=0
      for e in "${errors[@]}"; do
        case "$e" in
          "missing required field:"*|\
          "missing opening frontmatter delimiter"|\
          "missing closing frontmatter delimiter"|\
          "body too short:"*|\
          "file not found"|\
          "file not readable")
            struct_err=1
            ;;
        esac
      done
      if (( struct_err == 1 )); then
        code=1
      else
        code=2
      fi
    else
      code=1
    fi
  elif (( ${#warnings[@]} > 0 )); then
    code=3
  fi

  print_result "$rel" "$code"
  return "$code"
}

main() {
  if [[ $# -eq 0 ]]; then
    print_help >&2
    exit 64
  fi

  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --all)
      if [[ $# -lt 2 ]]; then
        printf 'error: --all requires a directory argument\n' >&2
        exit 64
      fi
      local dir="$2"
      if [[ ! -d "$dir" ]]; then
        printf 'error: not a directory: %s\n' "$dir" >&2
        exit 64
      fi
      local pass=0 warn=0 fail=0
      local f rc
      # Bash 3.2 has no nullglob; guard against the literal pattern when no
      # *.md files exist.
      for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        validate_file "$f"
        rc=$?
        case "$rc" in
          0)   pass=$((pass + 1)) ;;
          3)   warn=$((warn + 1)) ;;
          255) ;;  # skipped (MEMORY.md); not counted
          *)   fail=$((fail + 1)) ;;
        esac
      done
      echo
      printf 'Summary: %d pass, %d warn, %d fail\n' "$pass" "$warn" "$fail"
      if (( fail > 0 )); then
        exit 1
      elif (( warn > 0 )); then
        exit 3
      fi
      exit 0
      ;;
    -*)
      printf 'error: unknown option: %s\n' "$1" >&2
      print_help >&2
      exit 64
      ;;
    *)
      if [[ $# -gt 1 ]]; then
        printf 'error: unexpected extra arguments\n' >&2
        exit 64
      fi
      validate_file "$1"
      local rc=$?
      if (( rc == 255 )); then
        # MEMORY.md skipped; treat as PASS for exit purposes.
        printf "%-50s %s\n" "$(basename "$1")" "SKIPPED"
        exit 0
      fi
      exit "$rc"
      ;;
  esac
}

main "$@"
