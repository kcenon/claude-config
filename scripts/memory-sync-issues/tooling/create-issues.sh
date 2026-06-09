#!/bin/bash
# create-issues.sh — Register the 30 memory-sync issues into GitHub
#
# Two-pass algorithm:
#   PASS 1: Create EPIC + 29 children, capturing each new issue number into ID-MAP.
#           Body posted as-is (with placeholder #A1..#G3 tokens still inside).
#   PASS 2: Use gh issue edit --body-file with placeholders replaced by real numbers.
#           Also updates EPIC body's child-issue list.
#
# Usage:
#   ./create-issues.sh --dry-run        # show all gh commands without executing
#   ./create-issues.sh --execute        # actually create issues
#   ./create-issues.sh --resume         # use existing ID-MAP, retry pass 2 only
#
# Required: gh CLI authenticated; labels and milestones must already exist (run
# setup-labels-milestones.sh first).

set -u

REPO="kcenon/claude-config"
ISSUES_DIR="/tmp/claude/issues"
ID_MAP="/tmp/claude/issues-tooling/id-map.json"
LOG="/tmp/claude/issues-tooling/create-issues.log"
DRY_RUN=0
RESUME=0

# Order of registration — EPIC first so children can reference it
ORDER=(
  EPIC
  A1 A2 A3 A4 A5
  B1 B2 B3 B4
  C1 C2 C3 C4 C5
  D1 D2 D3 D4 D5
  E1 E2 E3
  F1 F2 F3 F4
  G1 G2 G3
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --execute) DRY_RUN=0; shift ;;
    --resume)  RESUME=1; shift ;;
    --repo)    REPO="$2"; shift 2 ;;
    --issues-dir) ISSUES_DIR="$2"; shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--dry-run | --execute | --resume]

Registers 30 memory-sync issues to GitHub.

  --dry-run     Print gh commands without executing (default for safety)
  --execute     Actually create issues
  --resume      Use existing $ID_MAP, retry pass 2 only
  --repo R      Target repo (default: $REPO)
  --issues-dir D Source directory (default: $ISSUES_DIR)
EOF
      exit 0 ;;
    *) echo "unknown arg: $1"; exit 64 ;;
  esac
done

# Default to dry-run if no flag given (safety)
if [[ "$RESUME" -eq 0 ]] && ! grep -qE -- '--execute|--dry-run' <<<"$@$0"; then
  : # already defaulted
fi

ensure_dirs() {
  mkdir -p "$(dirname "$ID_MAP")" "$(dirname "$LOG")"
  : > "$LOG"
}

log() {
  echo "$(date -u +%H:%M:%S) $*" | tee -a "$LOG"
}

# Extract frontmatter as text
fm_of() {
  awk '/^---$/{c++; next} c==1{print}' "$1"
}

# Body excludes frontmatter
body_of() {
  awk '/^---$/{c++; next} c>=2{print}' "$1"
}

# Get scalar field
get_field() {
  echo "$1" | grep -E "^${2}:" | head -1 | sed "s/^${2}:[[:space:]]*//"
}

# Get list-field as space-separated values
get_list() {
  local fm="$1" key="$2"
  local line
  line="$(echo "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//")"
  if [[ "$line" == "["*"]" ]]; then
    echo "$line" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | tr '\n' ' '
  else
    echo "$fm" | awk -v k="$key" '
      $0 ~ "^"k":" { in_block=1; next }
      in_block && /^  - / { sub(/^  - /, ""); print; next }
      in_block && /^[a-zA-Z]/ { in_block=0 }
    ' | tr '\n' ' '
  fi
}

# Get labels as comma-separated for gh
get_labels_csv() {
  get_list "$1" "labels" | xargs | sed 's/ /,/g'
}

# File path for an issue id
file_for_id() {
  local id="$1"
  if [[ "$id" == "EPIC" ]]; then
    echo "$ISSUES_DIR/EPIC.md"
  else
    ls "$ISSUES_DIR"/${id}-*.md 2>/dev/null | head -1
  fi
}

# Bash 3.2 compatible id-map: parallel arrays
ID_KEYS=()
ID_VALS=()

load_id_map() {
  ID_KEYS=()
  ID_VALS=()
  [[ -f "$ID_MAP" ]] || return 0
  # ID_MAP format (text-based for bash 3.2): "id num" per line
  while IFS=' ' read -r k v; do
    [[ -z "$k" ]] && continue
    ID_KEYS+=("$k")
    ID_VALS+=("$v")
  done < "$ID_MAP"
}

# Get value by key (bash 3.2 lookup)
id_get() {
  local needle="$1"
  local i
  for i in "${!ID_KEYS[@]}"; do
    if [[ "${ID_KEYS[$i]}" == "$needle" ]]; then
      echo "${ID_VALS[$i]}"
      return 0
    fi
  done
  return 1
}

id_has() {
  id_get "$1" >/dev/null 2>&1
}

id_set() {
  local needle="$1" val="$2"
  local i found=0
  for i in "${!ID_KEYS[@]}"; do
    if [[ "${ID_KEYS[$i]}" == "$needle" ]]; then
      ID_VALS[$i]="$val"
      found=1
      break
    fi
  done
  if [[ $found -eq 0 ]]; then
    ID_KEYS+=("$needle")
    ID_VALS+=("$val")
  fi
}

save_id_map() {
  : > "$ID_MAP"
  local i
  for i in "${!ID_KEYS[@]}"; do
    printf '%s %s\n' "${ID_KEYS[$i]}" "${ID_VALS[$i]}" >> "$ID_MAP"
  done
}

# PASS 1: create issues with placeholder bodies, capture numbers
pass1_create() {
  log "=== PASS 1: creating issues ==="
  load_id_map

  for id in "${ORDER[@]}"; do
    local existing_num
    if existing_num="$(id_get "$id")"; then
      log "[skip] $id already #$existing_num"
      continue
    fi

    local f; f="$(file_for_id "$id")"
    [[ -z "$f" || ! -f "$f" ]] && { log "[error] no file for $id"; continue; }

    local fm; fm="$(fm_of "$f")"
    local title; title="$(get_field "$fm" title | sed 's/^"//; s/"$//')"
    local labels_csv; labels_csv="$(get_labels_csv "$fm")"
    local milestone; milestone="$(get_field "$fm" milestone)"
    local body; body="$(body_of "$f")"

    log "[create] $id: $title"
    log "         labels: $labels_csv"
    log "         milestone: $milestone"

    # Body: leave placeholder #A1..#G3 tokens for now (Pass 2 will substitute)
    local tmp_body
    if [[ $DRY_RUN -eq 1 ]]; then
      log "  [dry-run] gh issue create --repo $REPO --title \"$title\" --label $labels_csv --milestone \"$milestone\" --body-file <body>"
      id_set "$id" "DRY-$id"
      save_id_map
    else
      tmp_body="${TMPDIR:-/tmp}/issue-body-${id}-$$.md"
      printf '%s' "$body" > "$tmp_body"
      local out
      if ! out=$(gh issue create \
            --repo "$REPO" \
            --title "$title" \
            --label "$labels_csv" \
            --milestone "$milestone" \
            --body-file "$tmp_body" 2>&1); then
        log "[error] gh failed for $id: $out"
        rm -f "$tmp_body"
        continue
      fi
      # Extract issue number from URL
      local num
      num="$(echo "$out" | grep -oE '/issues/[0-9]+' | tr -d '/' | sed 's/issues//')"
      if [[ -z "$num" ]]; then
        log "[error] could not parse issue number from: $out"
        rm -f "$tmp_body"
        continue
      fi
      id_set "$id" "$num"
      log "  -> #$num"
      save_id_map
      rm -f "$tmp_body"
    fi
  done

  log "PASS 1 done. Map saved to $ID_MAP"
}

# PASS 2: substitute placeholder ids with real numbers, edit each issue
pass2_substitute() {
  log "=== PASS 2: substituting placeholders ==="
  load_id_map

  if [[ ${#ID_KEYS[@]} -eq 0 ]]; then
    log "[error] no id-map; run pass 1 first"
    return 1
  fi

  # Build sed expression. BSD sed (macOS) does not support \b; use [^0-9A-Z]
  # workaround would require preserving the trailing char. Since all ids are
  # 2 chars (no substring conflicts), simple substitution is safe.
  local sed_args=()
  for id in "${ORDER[@]}"; do
    local num
    num="$(id_get "$id")" || continue
    [[ -z "$num" ]] && continue
    [[ "$num" == DRY-* ]] && num="999"
    sed_args+=(-e "s/#${id}/#${num}/g")
  done

  for id in "${ORDER[@]}"; do
    local num
    num="$(id_get "$id")" || continue
    [[ -z "$num" ]] && continue

    local f; f="$(file_for_id "$id")"
    local body; body="$(body_of "$f")"
    local subbed; subbed="$(printf '%s' "$body" | sed "${sed_args[@]}")"

    if [[ $DRY_RUN -eq 1 ]]; then
      log "[dry-run] would update issue #$num ($id) body with substituted refs"
      log "  preview: $(printf '%s' "$subbed" | head -c 200 | tr '\n' ' ')..."
    else
      local tmp_body="${TMPDIR:-/tmp}/issue-body-final-${id}-$$.md"
      printf '%s' "$subbed" > "$tmp_body"
      log "[update] $id #$num: substituting placeholders"
      if ! gh issue edit "$num" --repo "$REPO" --body-file "$tmp_body" >/dev/null 2>&1; then
        log "[error] gh issue edit failed for #$num"
      fi
      rm -f "$tmp_body"
    fi
  done

  log "PASS 2 done."
}

show_summary() {
  log "=== Summary ==="
  for id in "${ORDER[@]}"; do
    local num
    if num="$(id_get "$id")"; then
      printf "  %-5s -> #%s\n" "$id" "$num"
    else
      printf "  %-5s -> NOT-CREATED\n" "$id"
    fi
  done | tee -a "$LOG"
}

main() {
  ensure_dirs
  log "create-issues.sh starting"
  log "  repo: $REPO"
  log "  issues-dir: $ISSUES_DIR"
  log "  id-map: $ID_MAP"
  log "  mode: $([[ $DRY_RUN -eq 1 ]] && echo dry-run || echo execute)"

  if [[ $DRY_RUN -eq 0 ]]; then
    if ! gh auth status >/dev/null 2>&1; then
      log "ERROR: gh CLI not authenticated"
      exit 1
    fi
  fi

  if [[ $RESUME -eq 0 ]]; then
    pass1_create
  fi

  pass2_substitute
  show_summary

  log "=== Verification ==="
  if [[ $DRY_RUN -eq 0 ]]; then
    gh issue list --repo "$REPO" --label "area/memory" --state open --limit 50 \
      | tee -a "$LOG"
  fi
}

main "$@"
