#!/bin/bash
# secret-check.sh -- Detect PII / tokens / private network info in memory files.
#
# Per docs/MEMORY_VALIDATION_SPEC.md (v1.0.1) Sections 6 and 7.
#
# Exit codes:
#   0  -- CLEAN (no findings)
#   1  -- SECRET-DETECTED (at least one finding; blocks merge)
#   64 -- usage error
#
# Usage:
#   secret-check.sh <file>          single-file mode
#   secret-check.sh --all <dir>     batch mode (skips MEMORY.md)
#   secret-check.sh --help|-h       show usage
#
# Environment overrides (all optional):
#   OWNER_EMAILS         space-separated owner email allowlist (default: kcenon@gmail.com)
#   OWNER_GITHUB_HANDLE  GitHub handle for no-reply allowlist (default: kcenon)
#   OWNER_HOME_USER      owner Unix home directory user (default: raphaelshin)

set -u

# Default owner identity. Caller may override via env vars.
DEFAULT_OWNER_EMAILS="kcenon@gmail.com"
DEFAULT_OWNER_GITHUB_HANDLE="kcenon"
DEFAULT_OWNER_HOME_USER="raphaelshin"

# Parse OWNER_EMAILS into a bash array (space-separated).
# Use ${VAR:-default} to avoid mutating the caller's environment.
read -r -a OWNER_EMAILS_ARR <<< "${OWNER_EMAILS:-$DEFAULT_OWNER_EMAILS}"
OWNER_GITHUB_HANDLE="${OWNER_GITHUB_HANDLE:-$DEFAULT_OWNER_GITHUB_HANDLE}"
OWNER_HOME_USER="${OWNER_HOME_USER:-$DEFAULT_OWNER_HOME_USER}"

usage() {
  cat <<EOF
secret-check.sh -- detect PII / tokens / private network info in memory files

Usage:
  $(basename "$0") <file>          scan a single .md file
  $(basename "$0") --all <dir>     scan every .md in <dir> (MEMORY.md skipped)
  $(basename "$0") --help|-h       show this help

Exit codes: 0=clean, 1=finding (blocks), 64=usage error.

Environment overrides:
  OWNER_EMAILS          space-separated allowlist (default: ${DEFAULT_OWNER_EMAILS})
  OWNER_GITHUB_HANDLE   GitHub handle for noreply allowlist (default: ${DEFAULT_OWNER_GITHUB_HANDLE})
  OWNER_HOME_USER       owner Unix home dir name (default: ${DEFAULT_OWNER_HOME_USER})
EOF
}

# is_owner_email <email> -- return 0 if email matches the configured owner allowlist.
# Recognized forms (per spec Section 6):
#   1. exact match against any element of OWNER_EMAILS_ARR
#   2. <numeric>+<HANDLE>@users.noreply.github.com
#   3. <HANDLE>@users.noreply.github.com
is_owner_email() {
  local e="$1"
  local owned
  if (( ${#OWNER_EMAILS_ARR[@]} > 0 )); then
    for owned in "${OWNER_EMAILS_ARR[@]}"; do
      [[ "$e" == "$owned" ]] && return 0
    done
  fi
  if [[ "$e" =~ ^[0-9]+\+${OWNER_GITHUB_HANDLE}@users\.noreply\.github\.com$ ]]; then
    return 0
  fi
  if [[ "$e" == "${OWNER_GITHUB_HANDLE}@users.noreply.github.com" ]]; then
    return 0
  fi
  return 1
}

# scan_file <path> -- scan a single file. Returns 0 if clean, 1 if findings.
scan_file() {
  local f="$1"
  local rel
  rel="$(basename "$f")"
  # Skip the index file per spec Section 2.
  [[ "$rel" == "MEMORY.md" ]] && return 0

  if [[ ! -r "$f" ]]; then
    printf "%-50s ERROR (unreadable)\n" "$rel" >&2
    return 1
  fi

  local hits=()
  local line email content ln

  # 1. Email scan: any non-owner email is a finding.
  #    Loop within a line so multiple emails in one line are reported.
  #    Per spec Section 8, save BASH_REMATCH immediately to a named variable.
  while IFS= read -r line || [[ -n "$line" ]]; do
    while [[ "$line" =~ ([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}) ]]; do
      email="${BASH_REMATCH[1]}"
      if ! is_owner_email "$email"; then
        hits+=("non-owner email: $email")
      fi
      # Strip the matched email so the loop advances.
      line="${line//"$email"/}"
    done
  done < "$f"

  # 2. Token signatures.
  #    sk- requires 20+ alphanumerics (load-bearing per spec Section 6 -- prevents sk-learn).
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    hits+=("token pattern at line $ln: $(printf '%s' "$content" | head -c 60)")
  done < <(grep -n -E '(ghp_|gho_|ghu_|ghs_|ghr_|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]+-----)' "$f" 2>/dev/null || true)

  # 3. Private IPv4 ranges (10/8, 192.168/16, 172.16/12).
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    if [[ "$content" =~ (10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+) ]]; then
      local ip="${BASH_REMATCH[1]}"
      hits+=("private IP at line $ln: $ip")
    fi
  done < <(grep -n -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null || true)

  # 4. Foreign home directory paths.
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    if [[ "$content" =~ /Users/([A-Za-z0-9_-]+)/ ]]; then
      local user_u="${BASH_REMATCH[1]}"
      if [[ "$user_u" != "$OWNER_HOME_USER" ]]; then
        hits+=("foreign /Users/ path at line $ln: /Users/${user_u}/")
      fi
    fi
    if [[ "$content" =~ /home/([A-Za-z0-9_-]+)/ ]]; then
      local user_h="${BASH_REMATCH[1]}"
      if [[ "$user_h" != "$OWNER_HOME_USER" ]] && [[ "$user_h" != "$OWNER_GITHUB_HANDLE" ]]; then
        hits+=("foreign /home/ path at line $ln: /home/${user_h}/")
      fi
    fi
  done < <(grep -n -E '(/Users/|/home/)' "$f" 2>/dev/null || true)

  # 5. SSH key fingerprints (SHA256:<43 base64 chars>).
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    hits+=("ssh fingerprint at line $ln")
  done < <(grep -n -E 'SHA256:[A-Za-z0-9+/=]{43}' "$f" 2>/dev/null || true)

  # Report. Guard array expansion with length check (spec Section 8).
  if (( ${#hits[@]} == 0 )); then
    printf "%-50s CLEAN\n" "$rel"
    return 0
  fi

  printf "%-50s SECRET-DETECTED\n" "$rel"
  local h
  for h in "${hits[@]}"; do
    printf "    [!] %s\n" "$h"
  done
  return 1
}

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 64
  fi

  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --all)
      if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
        echo "error: --all requires a directory argument" >&2
        usage >&2
        exit 64
      fi
      local dir="$2"
      if [[ ! -d "$dir" ]]; then
        echo "error: not a directory: $dir" >&2
        exit 64
      fi
      local clean=0 dirty=0
      local f
      for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        if scan_file "$f"; then
          clean=$((clean + 1))
        else
          dirty=$((dirty + 1))
        fi
      done
      echo
      echo "Summary: $clean clean, $dirty with findings"
      if (( dirty > 0 )); then
        exit 1
      fi
      exit 0
      ;;
    *)
      if [[ ! -f "$1" ]]; then
        echo "error: file not found: $1" >&2
        exit 64
      fi
      scan_file "$1"
      exit $?
      ;;
  esac
}

main "$@"
