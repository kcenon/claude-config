#!/bin/bash
# quarantine-restore.sh -- Move a quarantined memory file back to memories/.
#
# Implements docs/MEMORY_TRUST_MODEL.md (v1.0.0) Section 6 "restore" action:
# the file must pass all validators (validate.sh, secret-check.sh,
# injection-check.sh) before it may return to memories/. Restoration always
# lands at trust-level: verified per Section 3 (no partial restore).
#
# Usage:
#   quarantine-restore.sh <file> [--reason "<text>"]
#   quarantine-restore.sh --help|-h
#
# Behavior:
#   - Resolves <file> against the quarantine/ directory of the parent
#     claude-memory tree.
#   - Re-runs validate.sh, secret-check.sh, injection-check.sh against the
#     file. Any blocking failure (validate.sh exits 1 or 2; secret-check.sh
#     exits 1) refuses the restore. injection-check.sh is warn-only per
#     spec; flagged output does not block.
#   - On pass: rewrites frontmatter to trust-level: verified, sets
#     last-verified to today, removes quarantined-at / quarantine-reason /
#     quarantined-by, then moves to memories/.
#
# Exit codes:
#   0   success
#   1   usage error or non-revalidation failure (file missing, conflict, etc.)
#   2   revalidation failed; file remains in quarantine
#   64  CLI usage error (missing argument, unknown flag)
#
# Bash 3.2 compatible (macOS default).

set -u

print_help() {
  cat <<'EOF'
quarantine-restore.sh -- restore a quarantined memory after revalidation.

USAGE
    quarantine-restore.sh <file> [--reason "<text>"]
    quarantine-restore.sh --help | -h

ARGUMENTS
    <file>          Path to the quarantined memory file (under quarantine/).
                    May be absolute or relative; the claude-memory root is
                    auto-detected.

OPTIONS
    --reason TEXT   Free-form note recorded only in stdout (e.g. "false
                    positive confirmed"). Not written to frontmatter.
    --help, -h      Show this help.

EXIT CODES
    0   success
    1   usage / pre-flight error (file missing, conflict in memories/, etc.)
    2   revalidation failed; file stays in quarantine
    64  CLI usage error (handled before validation)

VALIDATORS RUN
    validate.sh         (exit 1 = FAIL-STRUCT, 2 = FAIL-FORMAT both block)
    secret-check.sh     (exit 1 = SECRET-DETECTED blocks)
    injection-check.sh  (warn-only; never blocks restore)

NOTES
    On success:
      - trust-level becomes verified (per spec Section 3 "no partial restore")
      - last-verified becomes today
      - quarantined-at, quarantine-reason, quarantined-by are removed
      - file moves from quarantine/ to memories/
    Body content is never modified.
EOF
}

# Resolve the directory in which this script lives (real path).
script_dir() {
  local s="${BASH_SOURCE[0]}"
  # Resolve symlinks one hop (sufficient for our install layout).
  while [[ -L "$s" ]]; do
    local d
    d="$(cd "$(dirname "$s")" && pwd -P)"
    s="$(readlink "$s")"
    case "$s" in
      /*) ;;
      *) s="$d/$s" ;;
    esac
  done
  cd "$(dirname "$s")" && pwd -P
}

is_inside_git() {
  local d="$1"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

move_file() {
  local src="$1"
  local dst="$2"
  local src_dir
  src_dir="$(dirname "$src")"
  if is_inside_git "$src_dir"; then
    if git -C "$src_dir" mv "$src" "$dst" 2>/dev/null; then
      return 0
    fi
  fi
  mv "$src" "$dst"
}

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

# Locate a sibling validator script. Search:
#   1. Same directory as this script
#   2. PATH (typical install on the user's system)
# Echo path or empty string.
locate_validator() {
  local name="$1"
  local sd
  sd="$(script_dir)"
  if [[ -x "$sd/$name" ]]; then
    printf '%s' "$sd/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  return 1
}

main() {
  local file=""
  local reason=""

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
      -*)
        printf 'error: unknown option: %s\n' "$1" >&2
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
    printf 'error: cannot locate claude-memory root: %s\n' "$file_abs" >&2
    exit 1
  fi

  local memories_dir="$root/memories"
  local quarantine_dir="$root/quarantine"
  local base
  base="$(basename "$file_abs")"

  # Refuse to operate on MEMORY.md.
  if [[ "$base" == "MEMORY.md" ]]; then
    printf 'error: refusing to restore MEMORY.md (auto-generated index)\n' >&2
    exit 1
  fi

  # Source must be in quarantine/.
  case "$file_abs" in
    "$quarantine_dir"/*) ;;
    *)
      printf 'error: source file is not under %s/ (use quarantine-move.sh first)\n' "$quarantine_dir" >&2
      exit 1
      ;;
  esac

  local target="$memories_dir/$base"
  if [[ -e "$target" ]]; then
    printf 'error: target already exists in memories/: %s (resolve manually)\n' "$target" >&2
    exit 1
  fi

  # Locate validators. validate.sh is required; secret-check.sh is required;
  # injection-check.sh is best-effort (warn-only and the spec lets it run
  # even if missing, but we attempt to find it for parity with the issue's
  # acceptance criteria).
  local val_path sec_path inj_path
  val_path="$(locate_validator validate.sh || true)"
  sec_path="$(locate_validator secret-check.sh || true)"
  inj_path="$(locate_validator injection-check.sh || true)"

  if [[ -z "${val_path:-}" ]]; then
    printf 'error: validate.sh not found (sibling or PATH)\n' >&2
    exit 1
  fi
  if [[ -z "${sec_path:-}" ]]; then
    printf 'error: secret-check.sh not found (sibling or PATH)\n' >&2
    exit 1
  fi

  printf '[VALIDATING] %s\n' "$base"

  # Run validate.sh. Exit codes 1 (FAIL-STRUCT) and 2 (FAIL-FORMAT) block.
  # Exit 3 (WARN-SEMANTIC) is non-blocking but we surface the result.
  local val_rc=0
  local val_label="PASS"
  local val_out
  val_out="$("$val_path" "$file_abs" 2>&1)" || val_rc=$?
  case "$val_rc" in
    0) val_label="PASS" ;;
    1) val_label="FAIL-STRUCT" ;;
    2) val_label="FAIL-FORMAT" ;;
    3) val_label="WARN-SEMANTIC" ;;
    *) val_label="UNKNOWN($val_rc)" ;;
  esac
  printf '  validate.sh:    %s\n' "$val_label"

  # secret-check.sh: 0 = CLEAN, 1 = SECRET-DETECTED (blocks).
  local sec_rc=0
  local sec_label="CLEAN"
  local sec_out
  sec_out="$("$sec_path" "$file_abs" 2>&1)" || sec_rc=$?
  case "$sec_rc" in
    0) sec_label="CLEAN" ;;
    1) sec_label="SECRET-DETECTED" ;;
    *) sec_label="UNKNOWN($sec_rc)" ;;
  esac
  printf '  secret-check.sh: %s\n' "$sec_label"

  # injection-check.sh: warn-only, never blocks. Run if available.
  local inj_rc=0
  local inj_label="SKIPPED"
  local inj_out=""
  if [[ -n "${inj_path:-}" ]]; then
    inj_out="$("$inj_path" "$file_abs" 2>&1)" || inj_rc=$?
    case "$inj_rc" in
      0) inj_label="CLEAN" ;;
      3) inj_label="FLAGGED (warn-only)" ;;
      *) inj_label="UNKNOWN($inj_rc)" ;;
    esac
    printf '  injection-check.sh: %s\n' "$inj_label"
  fi

  # Decide whether to refuse. Blocking failures: validate.sh in (1, 2),
  # secret-check.sh == 1. injection-check.sh never blocks (per spec).
  if (( val_rc == 1 || val_rc == 2 || sec_rc == 1 )); then
    printf '%s\n' "$val_out"
    printf '%s\n' "$sec_out"
    if [[ -n "$inj_out" ]] && (( inj_rc != 0 )); then
      printf '%s\n' "$inj_out"
    fi
    printf '[REFUSED] revalidation failed; remains in quarantine\n'
    exit 2
  fi

  # Parse frontmatter for rewrite. Same convention as quarantine-move.sh.
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

  local today_iso
  today_iso="$(date -u +'%Y-%m-%d')"

  # Rewrite plan: set trust-level to verified, last-verified to today,
  # remove quarantined-at, quarantine-reason, quarantined-by.
  local tmp
  tmp="$(mktemp 2>/dev/null || mktemp -t quar-restore)"
  if [[ -z "${tmp:-}" || ! -w "$tmp" ]]; then
    printf 'error: cannot create temporary file\n' >&2
    exit 1
  fi
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT

  printf -- '---\n' > "$tmp" || { printf 'error: write failed\n' >&2; exit 1; }

  local seen_trust=0 seen_lv=0
  local line key
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9_-]*): ]]; then
      key="${BASH_REMATCH[1]}"
      case "$key" in
        trust-level)
          printf 'trust-level: verified\n' >> "$tmp" || exit 1
          seen_trust=1
          continue
          ;;
        last-verified)
          printf 'last-verified: %s\n' "$today_iso" >> "$tmp" || exit 1
          seen_lv=1
          continue
          ;;
        quarantined-at|quarantine-reason|quarantined-by)
          # Drop these fields entirely.
          continue
          ;;
      esac
    fi
    printf '%s\n' "$line" >> "$tmp" || exit 1
  done <<< "$fm"

  if (( seen_trust == 0 )); then
    printf 'trust-level: verified\n' >> "$tmp" || exit 1
  fi
  if (( seen_lv == 0 )); then
    printf 'last-verified: %s\n' "$today_iso" >> "$tmp" || exit 1
  fi

  printf -- '---\n' >> "$tmp" || exit 1
  sed -n "$((fm_end + 1)),\$p" "$file_abs" >> "$tmp" || exit 1

  # Preserve source file's mode so the 0600 mktemp default does not leak.
  local src_mode
  src_mode="$(stat -c '%a' "$file_abs" 2>/dev/null || stat -f '%Lp' "$file_abs" 2>/dev/null || printf '644')"
  if ! mv "$tmp" "$file_abs"; then
    printf 'error: failed to write rewritten frontmatter to %s\n' "$file_abs" >&2
    exit 1
  fi
  chmod "$src_mode" "$file_abs" 2>/dev/null || true
  trap - EXIT

  if ! move_file "$file_abs" "$target"; then
    printf 'error: move failed: %s -> %s\n' "$file_abs" "$target" >&2
    exit 1
  fi

  printf '[OK] quarantine/%s -> memories/%s\n' "$base" "$base"
  printf '     last-verified: %s\n' "$today_iso"
  if [[ -n "$reason" ]]; then
    printf '     restore note: %s\n' "$reason"
  fi
  exit 0
}

main "$@"
