#!/bin/bash
# injection-check.sh — Flag suspicious natural-language patterns suggesting prompt injection
#
# Purpose:
#   Heuristic scanner for memory files. Flags 7 categories of suspicious
#   patterns (role markers, persona overrides, destructive commands,
#   auto-fetch URLs, encoded payloads, high-density absolute commands,
#   direct injection phrases). False positives are expected and accepted —
#   this tool WARNS but never blocks. The decision to act on a flag belongs
#   to the caller (a human reviewer, /memory-review, or a quarantine policy).
#
# Why warn-only (do not tighten to block):
#   The 17-file baseline contains 3 legitimately-flagged files
#   (CI-policy memories with multiple "Never" emphasis). A blocking detector
#   would force users to weaken legitimate emphasis. Flag + human review
#   preserves both safety and expressiveness. See spec §9.
#
# Usage:
#   injection-check.sh <path/to/memory.md>          # single-file mode
#   injection-check.sh --all <dir>                  # batch mode
#   injection-check.sh --help                       # this message
#
# Exit codes (per docs/MEMORY_VALIDATION_SPEC.md §7):
#   0   clean — no flags
#   3   flagged (warn, NEVER block)
#   64  usage error

set -u

print_help() {
  cat <<'EOF'
injection-check.sh — Flag suspicious natural-language patterns in memory files.

USAGE:
  injection-check.sh <file>           Scan a single memory file
  injection-check.sh --all <dir>      Scan all *.md files in a directory
  injection-check.sh --help           Show this help

EXIT CODES:
  0   clean
  3   flagged (warn-only, never blocks)
  64  usage error

DETECTED PATTERNS (heuristic, false positives accepted):
  1. Direct injection phrases    (ignore previous, disregard, forget everything)
  2. System role markers          (system:, assistant:, <|im_start|>, <instructions>)
  3. Persona override             (you are now, act as, pretend to be, roleplay as)
  4. Destructive commands         (rm -rf /, DROP TABLE, git push --force main, fork bomb)
  5. Auto-fetch URLs              (https?://...\.(php|cgi|exe|sh|ps1))
  6. Encoded payloads             (base64-like blob >= 120 chars)
  7. Absolute-command density     (>= 3 of always|never|must always|must never|from now on)
EOF
}

scan_file() {
  local f="$1"
  local rel
  rel="$(basename "$f")"

  # Skip the synthesized index file — its job is to summarize others.
  [[ "$rel" == "MEMORY.md" ]] && return 0

  if [[ ! -f "$f" ]]; then
    printf "%-50s ERROR: not a regular file\n" "$rel" >&2
    return 0
  fi

  local flags=()
  local ln content

  # 1. Direct injection phrases (case-insensitive)
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    flags+=("injection phrase at line $ln: $(printf '%s' "$content" | head -c 80)")
  done < <(grep -in -E 'ignore (previous|above|prior|earlier)|disregard (previous|the|all)|forget (everything|all|previous)' "$f" 2>/dev/null || true)

  # 2. System role markers (case-sensitive for <|im_*|> exactness; line-leading or
  #    after a non-letter to avoid matching "ecosystem:" etc.)
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    flags+=("system role marker at line $ln: $(printf '%s' "$content" | head -c 80)")
  done < <(grep -n -E '(^|[^a-zA-Z])(system:|assistant:|user:)|<\|im_(start|end)\|>|</?instructions>|</?system>' "$f" 2>/dev/null || true)

  # 3. Persona override (case-insensitive)
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    flags+=("persona override at line $ln: $(printf '%s' "$content" | head -c 80)")
  done < <(grep -in -E '(you are now|from this point forward|act as|pretend (to be|you are)|roleplay as)' "$f" 2>/dev/null || true)

  # 4. Destructive commands (rm -rf /, DROP TABLE, TRUNCATE TABLE,
  #    git push --force [origin] main|master, fork bomb)
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    flags+=("destructive command at line $ln: $(printf '%s' "$content" | head -c 80)")
  done < <(grep -n -E '\brm[[:space:]]+-rf[[:space:]]+/|DROP[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE|git[[:space:]]+push[[:space:]]+--force[[:space:]]+(origin[[:space:]]+)?(main|master)|:\(\)\{[[:space:]]*:' "$f" 2>/dev/null || true)

  # 5. Auto-fetch URLs (executable suffix)
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    if printf '%s' "$content" | grep -q -E 'https?://[^[:space:]]+\.(php|cgi|exe|sh|ps1)\b'; then
      flags+=("auto-fetch URL at line $ln")
    fi
  done < <(grep -n -E 'https?://' "$f" 2>/dev/null || true)

  # 6. Encoded payloads — base64-like blob >= 120 chars
  while IFS=: read -r ln content; do
    [[ -z "$ln" ]] && continue
    if [[ "$content" =~ [A-Za-z0-9+/=]{120,} ]]; then
      flags+=("long base64-like blob at line $ln")
    fi
  done < <(grep -n -E '[A-Za-z0-9+/=]{120,}' "$f" 2>/dev/null || true)

  # 7. Absolute-command density (per-file aggregate, not per-line).
  #    macOS bash 3.2: `wc -l` may pad with spaces, so normalize via tr,
  #    then default to 0 if empty.
  local absolute_count
  absolute_count="$(grep -i -o -E '\b(always|never|must always|must never|from now on)\b' "$f" 2>/dev/null | wc -l | tr -d ' ')"
  absolute_count="${absolute_count:-0}"
  if (( absolute_count >= 3 )); then
    flags+=("high density of absolute commands ($absolute_count occurrences)")
  fi

  if (( ${#flags[@]} == 0 )); then
    printf "%-50s CLEAN\n" "$rel"
    return 0
  else
    printf "%-50s FLAGGED\n" "$rel"
    local fl
    for fl in "${flags[@]}"; do
      printf "    [?] %s\n" "$fl"
    done
    return 3
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    print_help >&2
    exit 64
  fi

  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --all)
      if [[ $# -lt 2 ]]; then
        echo "error: --all requires a directory argument" >&2
        exit 64
      fi
      local dir="$2"
      if [[ ! -d "$dir" ]]; then
        echo "error: not a directory: $dir" >&2
        exit 64
      fi
      local clean=0 flagged=0
      local f base
      for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        # MEMORY.md is the synthesized index — don't count it either way.
        [[ "$base" == "MEMORY.md" ]] && continue
        if scan_file "$f"; then
          clean=$((clean + 1))
        else
          flagged=$((flagged + 1))
        fi
      done
      echo
      echo "Summary: $clean clean, $flagged flagged"
      if (( flagged > 0 )); then
        exit 3
      fi
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      exit 64
      ;;
    *)
      if [[ ! -f "$1" ]]; then
        echo "error: not a file: $1" >&2
        exit 64
      fi
      scan_file "$1"
      exit $?
      ;;
  esac
}

main "$@"
