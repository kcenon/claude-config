#!/bin/bash
# quarantine-move.sh -- Move a memory file from memories/ to quarantine/.
#
# Implements docs/MEMORY_TRUST_MODEL.md (v1.0.0) Section 8 storage-layer rules
# for the validator-driven and user-driven demotion paths defined in Section 6.
# A "quarantine" is a directory move plus frontmatter rewrite, not a flag-only
# state. Body content is never modified.
#
# Usage:
#   quarantine-move.sh <file> [--reason "<text>"] [--no-edit]
#   quarantine-move.sh --help|-h
#
# Behavior:
#   - Resolves <file> against the source memories/ directory of the parent
#     claude-memory tree. If the file is already in quarantine/, exits 0
#     (idempotent no-op per acceptance criteria).
#   - Rewrites frontmatter: sets trust-level to quarantined, adds quarantined-at
#     (ISO 8601 UTC), quarantine-reason (if --reason supplied), quarantined-by
#     (current source-machine if known).
#   - Updates last-verified to today (ISO 8601 date) per trust-model Section 6:
#     last-verified records the demotion date for retention math.
#   - Moves the file using git mv when inside a git working tree, else plain mv.
#
# Exit codes:
#   0   success (or already-quarantined no-op)
#   1   failure (file not found, frontmatter parse, write/move error, sibling
#       missing in quarantine/ already, etc.)
#   64  usage error
#
# Bash 3.2 compatible (macOS default): no associative arrays, no mapfile, no
# process-substitution into named pipes, BASH_REMATCH saved before reuse,
# explicit ${var:-default} for empties.

set -u

print_help() {
  cat <<'EOF'
quarantine-move.sh -- move a memory file to the quarantine directory.

USAGE
    quarantine-move.sh <file> [--reason "<text>"] [--no-edit]
    quarantine-move.sh --help | -h

ARGUMENTS
    <file>          Path to the memory file. May be either an absolute path,
                    a path relative to the current working directory, or a
                    path of the form memories/<name>.md within a claude-memory
                    tree. The script auto-detects the claude-memory root by
                    walking upward looking for a sibling memories/ directory.

OPTIONS
    --reason TEXT   Free-form reason recorded as quarantine-reason in the
                    target frontmatter. Optional; if omitted, the field is
                    not added. Quoted at use; never evaluated as shell.
    --no-edit       Do not modify frontmatter; only perform the directory
                    move. Useful for re-syncing an already-rewritten file.
    --help, -h      Show this help.

EXIT CODES
    0   success, or already-quarantined no-op
    1   failure (file not found, frontmatter parse error, write/move error)
    64  usage error

EXAMPLES
    # Quarantine a memory the secret-check flagged
    quarantine-move.sh memories/feedback_suspicious.md \
        --reason "secret-check flagged non-owner email"

    # Move only, leave existing frontmatter as-is
    quarantine-move.sh memories/project_old.md --no-edit

NOTES
    Idempotent: if <file> already lives in quarantine/, the script reports
    "already quarantined" and exits 0. Body content is never modified.
EOF
}

# Strip surrounding double or single quotes from a YAML scalar value.
# Mirrors validate.sh:strip_quotes for consistent parsing semantics.
strip_quotes() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  if [[ "$v" =~ ^\"(.*)\"$ ]]; then
    local m="${BASH_REMATCH[1]}"
    v="$m"
  elif [[ "$v" =~ ^\'(.*)\'$ ]]; then
    local m="${BASH_REMATCH[1]}"
    v="$m"
  fi
  printf '%s' "$v"
}

# Read a single-line YAML field from frontmatter text.
# Echoes the raw value (without `key:` prefix); empty if absent.
get_field() {
  local fm="$1"
  local key="$2"
  printf '%s\n' "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

# Detect whether a directory is inside a git working tree.
# Returns 0 (true) when `git -C <dir> rev-parse --is-inside-work-tree` succeeds.
is_inside_git() {
  local d="$1"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Move src to dst, preferring `git mv` when both live in a git working tree.
# Falls back to plain `mv`. Returns 0 on success, 1 on error.
move_file() {
  local src="$1"
  local dst="$2"
  local src_dir
  src_dir="$(dirname "$src")"
  if is_inside_git "$src_dir"; then
    if git -C "$src_dir" mv "$src" "$dst" 2>/dev/null; then
      return 0
    fi
    # `git mv` may refuse if the file is untracked; fall through to plain mv.
  fi
  mv "$src" "$dst"
}

# Detect the claude-memory root for <file>. The root is the first ancestor
# directory that contains a `memories/` subdirectory. Echoes the absolute path
# of that root, or empty string if not found.
find_memory_root() {
  local f="$1"
  local d
  d="$(cd "$(dirname "$f")" && pwd -P)"
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -d "$d/memories" ]]; then
      printf '%s' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

main() {
  local file=""
  local reason=""
  local no_edit=0

  if [[ $# -eq 0 ]]; then
    print_help >&2
    exit 64
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
        exit 0
        ;;
      --reason)
        if [[ $# -lt 2 ]]; then
          printf 'error: --reason requires a value\n' >&2
          exit 64
        fi
        reason="$2"
        shift 2
        ;;
      --no-edit)
        no_edit=1
        shift
        ;;
      -*)
        printf 'error: unknown option: %s\n' "$1" >&2
        print_help >&2
        exit 64
        ;;
      *)
        if [[ -n "$file" ]]; then
          printf 'error: unexpected extra argument: %s\n' "$1" >&2
          exit 64
        fi
        file="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$file" ]]; then
    printf 'error: missing <file> argument\n' >&2
    exit 64
  fi

  if [[ ! -f "$file" ]]; then
    printf 'error: file not found: %s\n' "$file" >&2
    exit 1
  fi

  local file_abs
  file_abs="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"

  local root
  root="$(find_memory_root "$file_abs")"
  if [[ -z "${root:-}" ]]; then
    printf 'error: cannot locate claude-memory root (no sibling memories/ dir): %s\n' "$file_abs" >&2
    exit 1
  fi

  local memories_dir="$root/memories"
  local quarantine_dir="$root/quarantine"
  local base
  base="$(basename "$file_abs")"

  # Idempotency: file already in quarantine/ -> no-op success.
  case "$file_abs" in
    "$quarantine_dir"/*)
      printf '[OK] %s already quarantined; no-op\n' "$base"
      exit 0
      ;;
  esac

  # Reject MEMORY.md (it is the synthesized index, not a memory).
  if [[ "$base" == "MEMORY.md" ]]; then
    printf 'error: refusing to quarantine MEMORY.md (auto-generated index)\n' >&2
    exit 1
  fi

  # Source must live in memories/.
  case "$file_abs" in
    "$memories_dir"/*) ;;
    *)
      printf 'error: source file is not under %s/\n' "$memories_dir" >&2
      exit 1
      ;;
  esac

  # Parse frontmatter (re-uses the validate.sh delimiter convention).
  local first_line
  first_line="$(head -1 "$file_abs")"
  if [[ "$first_line" != "---" ]]; then
    printf 'error: cannot read frontmatter (missing opening delimiter): %s\n' "$base" >&2
    exit 1
  fi

  local fm_end
  fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$file_abs")"
  fm_end="${fm_end:-}"
  if [[ -z "$fm_end" ]]; then
    printf 'error: cannot read frontmatter (missing closing delimiter): %s\n' "$base" >&2
    exit 1
  fi

  local fm
  fm="$(sed -n "2,$((fm_end - 1))p" "$file_abs")"

  # Pre-create quarantine directory if absent.
  if [[ ! -d "$quarantine_dir" ]]; then
    if ! mkdir -p "$quarantine_dir"; then
      printf 'error: cannot create quarantine directory: %s\n' "$quarantine_dir" >&2
      exit 1
    fi
  fi

  local target="$quarantine_dir/$base"

  # Restore-side conflict mirror: if a same-name file already exists in
  # quarantine/, refuse rather than overwrite. The user must resolve manually.
  if [[ -e "$target" ]]; then
    printf 'error: target already exists in quarantine/: %s (resolve manually)\n' "$target" >&2
    exit 1
  fi

  # Compute frontmatter rewrite values.
  local now_iso today_iso
  now_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  today_iso="$(date -u +'%Y-%m-%d')"

  # Inherit source-machine for quarantined-by when present; else hostname -s.
  local sm
  sm="$(get_field "$fm" "source-machine")"
  sm="$(strip_quotes "$sm")"
  if [[ -z "$sm" ]]; then
    sm="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
  fi

  # If --no-edit, skip frontmatter rewrite and just move.
  if (( no_edit == 1 )); then
    if ! move_file "$file_abs" "$target"; then
      printf 'error: move failed: %s -> %s\n' "$file_abs" "$target" >&2
      exit 1
    fi
    printf '[OK] %s -> quarantine/%s (no-edit)\n' "$base" "$base"
    exit 0
  fi

  # Build a rewritten frontmatter via temp file. We:
  #   - Replace any existing trust-level / quarantined-at / quarantine-reason /
  #     quarantined-by / last-verified line with the new value (or drop and
  #     re-emit at end). This keeps key order stable for fields we don't touch.
  #   - Append any missing fields after the last existing line.
  # No `awk` redirections per implementation notes (bash-write-guard).

  local tmp
  tmp="$(mktemp 2>/dev/null || mktemp -t quar-move)"
  if [[ -z "${tmp:-}" || ! -w "$tmp" ]]; then
    printf 'error: cannot create temporary file\n' >&2
    exit 1
  fi
  # Best-effort cleanup. EXIT trap covers normal and error paths.
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT

  # Open delimiter.
  printf -- '---\n' > "$tmp" || { printf 'error: write failed\n' >&2; exit 1; }

  # Track which keys we have already emitted from the rewrite plan; remaining
  # ones are appended at the end of the FM block.
  local seen_trust=0 seen_qat=0 seen_qreason=0 seen_qby=0 seen_lv=0

  # Read frontmatter line-by-line and rewrite the keys we manage.
  # Bash 3.2 read with IFS= preserves leading whitespace.
  local line key
  while IFS= read -r line; do
    # Match `key: value` (allow keys with hyphens). Other lines pass through
    # unchanged so multi-line YAML structures survive (we never produce them
    # here, but pre-existing files may have them).
    if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_-]*): ]]; then
      key="${BASH_REMATCH[1]}"
      case "$key" in
        trust-level)
          printf 'trust-level: quarantined\n' >> "$tmp" || exit 1
          seen_trust=1
          continue
          ;;
        quarantined-at)
          printf 'quarantined-at: %s\n' "$now_iso" >> "$tmp" || exit 1
          seen_qat=1
          continue
          ;;
        quarantine-reason)
          if [[ -n "$reason" ]]; then
            # Quote the value to preserve shell metacharacters; embedded
            # double quotes are escaped. eval is never used.
            printf 'quarantine-reason: "%s"\n' "${reason//\"/\\\"}" >> "$tmp" || exit 1
          fi
          # If no --reason supplied and an existing reason field is present,
          # we drop it (the new quarantine episode replaces the old reason).
          seen_qreason=1
          continue
          ;;
        quarantined-by)
          printf 'quarantined-by: %s\n' "$sm" >> "$tmp" || exit 1
          seen_qby=1
          continue
          ;;
        last-verified)
          printf 'last-verified: %s\n' "$today_iso" >> "$tmp" || exit 1
          seen_lv=1
          continue
          ;;
      esac
    fi
    printf '%s\n' "$line" >> "$tmp" || exit 1
  done <<< "$fm"

  # Emit any rewrite-plan keys not previously present.
  if (( seen_trust == 0 )); then
    printf 'trust-level: quarantined\n' >> "$tmp" || exit 1
  fi
  if (( seen_qat == 0 )); then
    printf 'quarantined-at: %s\n' "$now_iso" >> "$tmp" || exit 1
  fi
  if (( seen_qby == 0 )); then
    printf 'quarantined-by: %s\n' "$sm" >> "$tmp" || exit 1
  fi
  if (( seen_lv == 0 )); then
    printf 'last-verified: %s\n' "$today_iso" >> "$tmp" || exit 1
  fi
  if (( seen_qreason == 0 )) && [[ -n "$reason" ]]; then
    printf 'quarantine-reason: "%s"\n' "${reason//\"/\\\"}" >> "$tmp" || exit 1
  fi

  # Close delimiter and append the original body verbatim.
  printf -- '---\n' >> "$tmp" || exit 1
  if (( fm_end >= 1 )); then
    sed -n "$((fm_end + 1)),\$p" "$file_abs" >> "$tmp" || exit 1
  fi

  # Atomically replace source content, then move. Writing through a temp file
  # then `mv` avoids partial writes on disk-full or SIGINT. Preserve the
  # source file's mode so the 0600 mktemp default does not leak through.
  local src_mode
  src_mode="$(stat -c '%a' "$file_abs" 2>/dev/null || stat -f '%Lp' "$file_abs" 2>/dev/null || printf '644')"
  if ! mv "$tmp" "$file_abs"; then
    printf 'error: failed to write rewritten frontmatter to %s\n' "$file_abs" >&2
    exit 1
  fi
  chmod "$src_mode" "$file_abs" 2>/dev/null || true
  # The trap will fail to remove $tmp now that mv consumed it; harmless.
  trap - EXIT

  if ! move_file "$file_abs" "$target"; then
    printf 'error: move failed: %s -> %s\n' "$file_abs" "$target" >&2
    exit 1
  fi

  printf '[OK] %s -> quarantine/%s\n' "$base" "$base"
  if [[ -n "$reason" ]]; then
    printf '     reason: %s\n' "$reason"
  fi
  printf '     quarantined-at: %s\n' "$now_iso"
  exit 0
}

main "$@"
