#!/bin/bash
# backfill-frontmatter.sh -- Add Phase 2 frontmatter fields to memory files.
#
# Adds `source-machine`, `created-at`, `trust-level`, `last-verified` to memory
# files that lack them. Idempotent (re-running on complete files is a no-op),
# dry-run by default, auto-creates timestamped backups before in-place writes.
#
# Per docs/MEMORY_TRUST_MODEL.md (v1.0.0) Section 9 and
# docs/MEMORY_VALIDATION_SPEC.md (v1.0.1) Section 3.
#
# Exit codes (per issue #512):
#   0   success (or dry-run completed)
#   1   at least one file failed to write
#   2   bad target directory or no .md files found
#   64  usage error
#
# Bash 3.2 compatible (macOS default). macOS and Linux `stat` both handled.
#
# Environment overrides (all optional):
#   MACHINE_NAME   override `hostname -s` for `source-machine`

set -u

# Field defaults from docs/MEMORY_TRUST_MODEL.md Section 9 ("Default tier by
# type"). Per the table:
#   user      -> verified
#   feedback  -> verified
#   project   -> verified (default; case-by-case inferred per #513 review)
#   reference -> inferred
# The conservative-default rule (§9) further dictates `inferred` when the
# origin is ambiguous. This tool applies the table-default; #513 baseline
# classification handles per-file overrides.
trust_level_for_type() {
  case "$1" in
    user|feedback|project) printf 'verified' ;;
    reference) printf 'inferred' ;;
    *) printf '' ;;  # unknown type -- caller must handle
  esac
}

# Cross-platform file mtime in ISO 8601 UTC. Detects platform via `uname`.
# macOS: stat -f %m / Linux: stat -c %Y. Both feed `date -u` to format.
file_mtime_iso8601() {
  local f="$1"
  local epoch
  case "$(uname)" in
    Darwin)
      epoch="$(stat -f %m "$f" 2>/dev/null)" || return 1
      date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
      ;;
    *)
      epoch="$(stat -c %Y "$f" 2>/dev/null)" || return 1
      date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
      ;;
  esac
}

# Strip surrounding double or single quotes from a YAML scalar value.
# Mirrors validate.sh strip_quotes() so behavior stays in sync.
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

# Read a single-line YAML field value from a frontmatter block.
get_field() {
  local fm="$1"
  local key="$2"
  printf '%s\n' "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

print_help() {
  cat <<'EOF'
backfill-frontmatter.sh -- add Phase 2 frontmatter fields to memory files.

USAGE
    backfill-frontmatter.sh [--dry-run | --execute] [--target-dir DIR] [--no-backup]
    backfill-frontmatter.sh --help | -h

OPTIONS
    --dry-run       Report what would change. Default when neither flag given.
    --execute       Actually modify files. Mutually exclusive with --dry-run.
    --target-dir D  Directory to scan. Default: current working directory.
    --no-backup     Skip backup creation on --execute. Use only after a clean
                    git commit.
    --help, -h      Show this help.

ADDED FIELDS
    source-machine  $(hostname -s)             [override: MACHINE_NAME env]
    created-at      file mtime in ISO 8601 UTC
    trust-level     per type (see TRUST DEFAULTS below)
    last-verified   today's UTC date (verified entries only; omitted for
                    inferred per docs/MEMORY_TRUST_MODEL.md Section 9)

TRUST DEFAULTS (by frontmatter `type`)
    user       -> verified
    feedback   -> verified
    project    -> verified
    reference  -> inferred

BEHAVIOR
    * Idempotent: existing fields are never overwritten. Files with all four
      Phase 2 fields are reported SKIP and not modified.
    * MEMORY.md is the auto-generated index and is always skipped.
    * On --execute, a backup `<file>.bak.<UTCstamp>` is written before the
      in-place edit, unless --no-backup.
    * On error reading or writing one file, processing continues; final exit
      code reflects whether any file failed.

EXIT CODES
    0   success (or dry-run completed)
    1   at least one file failed to write
    2   bad target directory or no .md files found
    64  usage error

ROLLBACK
    Backups (`<file>.bak.<UTCstamp>`) restore by `mv`. Example:
        mv FILE.bak.20260501T091500 FILE
EOF
}

# Per-file scratch state. Reset at the start of process_file().
fields_to_add=()
field_lines=()

# Read the frontmatter, compute which Phase 2 fields are missing, populate
# `fields_to_add` (label list for reporting) and `field_lines` (lines to
# insert before the closing delimiter). Returns:
#   0   computed; may have added zero or more fields
#   1   structural error (no closing delimiter, bad type); caller logs and skips
plan_file() {
  local f="$1"
  fields_to_add=()
  field_lines=()

  local first_line
  first_line="$(head -1 "$f")"
  if [[ "$first_line" != "---" ]]; then
    return 1
  fi

  local fm_end
  fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$f")"
  fm_end="${fm_end:-}"
  if [[ -z "$fm_end" ]]; then
    return 1
  fi

  local fm
  fm="$(sed -n "2,$((fm_end - 1))p" "$f")"

  local type sm ca tl lv
  type="$(strip_quotes "$(get_field "$fm" "type")")"
  sm="$(get_field "$fm" "source-machine")"
  ca="$(get_field "$fm" "created-at")"
  tl="$(get_field "$fm" "trust-level")"
  lv="$(get_field "$fm" "last-verified")"

  # Default trust-level depends on the existing `type` field. If `type` is
  # missing or unrecognized, we cannot pick a sensible default; treat as
  # structural so the caller logs and continues.
  if [[ -z "$type" ]]; then
    return 1
  fi
  local default_trust
  default_trust="$(trust_level_for_type "$type")"
  if [[ -z "$default_trust" ]]; then
    return 1
  fi

  # Resolve machine name once (env override beats hostname -s).
  local machine
  machine="${MACHINE_NAME:-$(hostname -s)}"

  # ISO 8601 UTC mtime for created-at. Failure here is not fatal; we just
  # skip the field and report it as a missing add.
  local mtime_iso=""
  if [[ -z "$ca" ]]; then
    mtime_iso="$(file_mtime_iso8601 "$f")" || mtime_iso=""
  fi

  # Today's date (UTC) for last-verified.
  local today
  today="$(date -u '+%Y-%m-%d')"

  # Build the add list in canonical order: source-machine, created-at,
  # trust-level, last-verified. Per trust model Section 9 the
  # `last-verified` field is omitted when default trust is `inferred`; the
  # 7-day observation window starts from `created-at` instead.
  if [[ -z "$sm" ]]; then
    fields_to_add+=("source-machine")
    field_lines+=("source-machine: $machine")
  fi
  if [[ -z "$ca" ]] && [[ -n "$mtime_iso" ]]; then
    fields_to_add+=("created-at")
    field_lines+=("created-at: $mtime_iso")
  fi
  if [[ -z "$tl" ]]; then
    fields_to_add+=("trust-level=$default_trust")
    field_lines+=("trust-level: $default_trust")
  fi
  if [[ -z "$lv" ]] && [[ "$default_trust" == "verified" ]]; then
    fields_to_add+=("last-verified")
    field_lines+=("last-verified: $today")
  fi

  return 0
}

# Insert the planned `field_lines` into <f> just before the closing
# frontmatter delimiter, atomically via a temp file. Returns 0 on success,
# nonzero on I/O failure.
write_file() {
  local f="$1"
  local fm_end
  fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$f")"
  fm_end="${fm_end:-}"
  if [[ -z "$fm_end" ]]; then
    return 1
  fi

  local tmp
  tmp="$(mktemp "${f}.tmp.XXXXXX")" || return 1

  # Preserve original file mode across the atomic rename (mktemp creates 600
  # by default; without this, the file's permissions would be tightened).
  if ! chmod --reference="$f" "$tmp" 2>/dev/null; then
    # macOS chmod has no --reference; fall back to stat -f %Lp + chmod.
    local mode
    mode="$(stat -f %Lp "$f" 2>/dev/null)" || mode=""
    if [[ -n "$mode" ]]; then
      chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
    fi
  fi

  # Head: lines 1..(fm_end - 1).
  sed -n "1,$((fm_end - 1))p" "$f" > "$tmp" || { rm -f "$tmp"; return 1; }

  # Inserted fields (canonical order).
  local line
  for line in "${field_lines[@]}"; do
    printf '%s\n' "$line" >> "$tmp" || { rm -f "$tmp"; return 1; }
  done

  # Tail: lines fm_end..end (closing --- and body).
  sed -n "${fm_end},\$p" "$f" >> "$tmp" || { rm -f "$tmp"; return 1; }

  # Atomic rename.
  mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  return 0
}

# Process a single file in the chosen mode. Updates the global counters
# `cnt_modified`, `cnt_skipped`, `cnt_errors`, `cnt_backups`.
process_file() {
  local f="$1"
  local mode="$2"     # dry-run | execute
  local with_backup="$3"
  local rel
  rel="$(basename "$f")"

  if [[ "$rel" == "MEMORY.md" ]]; then
    return 0
  fi

  if [[ ! -f "$f" ]] || [[ ! -r "$f" ]]; then
    printf "[ERROR] %s: not readable\n" "$rel" >&2
    cnt_errors=$((cnt_errors + 1))
    return 0
  fi

  if ! plan_file "$f"; then
    printf "[WARN]  %s: skipped (missing/invalid frontmatter or unknown type)\n" "$rel" >&2
    cnt_errors=$((cnt_errors + 1))
    return 0
  fi

  if (( ${#fields_to_add[@]} == 0 )); then
    if [[ "$mode" == "dry-run" ]]; then
      printf "[DRY-RUN] %s: already complete\n" "$rel"
    else
      printf "[SKIP]    %s: already complete\n" "$rel"
    fi
    cnt_skipped=$((cnt_skipped + 1))
    return 0
  fi

  # Comma-join the field labels for reporting.
  local IFS=','
  local added_csv="${fields_to_add[*]}"
  unset IFS

  if [[ "$mode" == "dry-run" ]]; then
    printf "[DRY-RUN] %s: would add %s\n" "$rel" "$added_csv"
    cnt_modified=$((cnt_modified + 1))
    return 0
  fi

  # Execute path.
  local stamp
  stamp="$(date -u '+%Y%m%dT%H%M%S')"

  if [[ "$with_backup" == "yes" ]]; then
    local bak="${f}.bak.${stamp}"
    if ! cp -p "$f" "$bak"; then
      printf "[ERROR] %s: backup failed; not modifying\n" "$rel" >&2
      cnt_errors=$((cnt_errors + 1))
      return 0
    fi
    cnt_backups=$((cnt_backups + 1))
  fi

  if ! write_file "$f"; then
    printf "[ERROR] %s: write failed\n" "$rel" >&2
    cnt_errors=$((cnt_errors + 1))
    return 0
  fi

  printf "[OK]      %s: added %s\n" "$rel" "$added_csv"
  if [[ "$with_backup" == "yes" ]]; then
    printf "          backup: %s.bak.%s\n" "$rel" "$stamp"
  fi
  cnt_modified=$((cnt_modified + 1))
}

main() {
  local mode="dry-run"
  local target_dir="."
  local with_backup="yes"

  # Argument parsing. Bash 3.2 compatible; no getopts long flags.
  while (( $# > 0 )); do
    case "$1" in
      --help|-h) print_help; exit 0 ;;
      --dry-run) mode="dry-run"; shift ;;
      --execute) mode="execute"; shift ;;
      --no-backup) with_backup="no"; shift ;;
      --target-dir)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          printf 'error: --target-dir requires a directory argument\n' >&2
          exit 64
        fi
        target_dir="$2"
        shift 2
        ;;
      *)
        printf 'error: unknown option: %s\n' "$1" >&2
        print_help >&2
        exit 64
        ;;
    esac
  done

  if [[ ! -d "$target_dir" ]]; then
    printf 'error: not a directory: %s\n' "$target_dir" >&2
    exit 2
  fi

  # Counters.
  cnt_modified=0
  cnt_skipped=0
  cnt_errors=0
  cnt_backups=0

  # Bash 3.2 has no nullglob; guard against the literal pattern when no
  # *.md files exist.
  local found=0
  local f
  for f in "$target_dir"/*.md; do
    [[ -f "$f" ]] || continue
    found=1
    process_file "$f" "$mode" "$with_backup"
  done

  if (( found == 0 )); then
    printf 'error: no .md files found in %s\n' "$target_dir" >&2
    exit 2
  fi

  echo
  if [[ "$mode" == "dry-run" ]]; then
    printf 'Summary: %d files would be modified, %d already complete, %d errors\n' \
      "$cnt_modified" "$cnt_skipped" "$cnt_errors"
    printf 'Run with --execute to apply.\n'
  else
    printf 'Summary: %d modified, %d skipped, %d backups created, %d errors\n' \
      "$cnt_modified" "$cnt_skipped" "$cnt_backups" "$cnt_errors"
  fi

  if (( cnt_errors > 0 )); then
    exit 1
  fi
  exit 0
}

main "$@"
