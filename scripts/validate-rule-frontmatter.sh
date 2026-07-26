#!/bin/bash
# validate-rule-frontmatter.sh — enforce the conditional-loading contract on
# project/.claude/rules/**/*.md (#880).
#
# Contract (documented in docs/TOKEN_OPTIMIZATION.md):
#   "paths frontmatter alone does NOT prevent loading. alwaysApply: false is
#    required alongside paths for conditional loading to work."
#
# The corollary is the failure mode this script exists to catch: the context
# loader scans project/.claude/rules/ physically and gates a file only on its
# paths: globs. So `alwaysApply: false` WITHOUT a paths: trigger is not an off
# switch — it is "no condition", and the file loads in every session. Same for
# a file with no frontmatter at all, or a catch-all `paths: ["**/*"]`.
#
# Each rule file must therefore be exactly one of:
#   1. alwaysApply: true                      -> deliberately always resident
#   2. alwaysApply: false + non-catch-all paths: -> loads on demand
#
# Reference documents live in project/.claude/reference/, outside the rules
# tree, and are not checked here — placement is what defers them.
#
# Exit codes:
#   0  every targeted file satisfies the contract
#   1  one or more files violate it
#   2  no files matched (configuration error)
#
# Usage:
#   bash scripts/validate-rule-frontmatter.sh              # project/.claude/rules
#   bash scripts/validate-rule-frontmatter.sh path/...     # explicit list

set -uo pipefail

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    mapfile -t files < <(find project/.claude/rules -name '*.md' -type f | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "validate-rule-frontmatter: no files matched" >&2
    exit 2
fi

failures=0
total=0
always=0
conditional=0

for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
        printf 'MISSING %s\n' "$f"
        failures=$((failures + 1))
        continue
    fi
    total=$((total + 1))

    # Frontmatter must open on line 1 with a literal '---'.
    if ! head -1 "$f" | grep -qx '\-\-\-'; then
        printf 'NO-FRONTMATTER %s: loads in every session (add alwaysApply + paths)\n' "$f"
        failures=$((failures + 1))
        continue
    fi
    block=$(awk 'NR==1 && /^---$/ {flag=1; next} flag && /^---$/ {exit} flag' "$f")

    # 'globs:' is not the key the loader reads; it silently disables the filter.
    if grep -qE '^globs:' <<<"$block"; then
        printf 'WRONG-KEY %s: uses "globs:" — the loader reads "paths:"\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    always_v=$(grep -E '^alwaysApply:' <<<"$block" | head -1 \
        | sed -E 's/^alwaysApply:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+$//')

    if [[ "$always_v" == "true" ]]; then
        always=$((always + 1))
        printf 'OK(always) %s\n' "$f"
        continue
    fi

    if [[ -z "$always_v" ]]; then
        printf 'MISSING-KEY %s: no alwaysApply — declare true, or false with paths\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    if [[ "$always_v" != "false" ]]; then
        printf 'BAD-ALWAYSAPPLY %s: "%s" (expected true|false)\n' "$f" "$always_v"
        failures=$((failures + 1))
        continue
    fi

    # alwaysApply: false — a usable paths: trigger is mandatory.
    if ! grep -qE '^paths:' <<<"$block"; then
        printf 'NO-PATHS-TRIGGER %s: alwaysApply false without paths still loads always\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    # Collect glob values from both the inline and block list forms.
    inline=$(grep -E '^paths:' <<<"$block" | head -1 | sed -E 's/^paths:[[:space:]]*//')
    listed=$(awk '/^paths:/{flag=1; next} flag && /^[[:space:]]*-[[:space:]]/{print; next} flag && /^[^[:space:]]/{exit}' <<<"$block")
    globs="${inline}"$'\n'"${listed}"

    if ! grep -qE '["'"'"'*/]' <<<"$globs"; then
        printf 'EMPTY-PATHS %s: paths declared but no globs listed\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    # A catch-all matches everything, which defeats conditional loading.
    if grep -qE '(^|[^*])\*\*/\*("|'"'"'|[[:space:]]|,|\]|$)' <<<"$globs"; then
        printf 'CATCH-ALL-GLOB %s: paths contains "**/*" — matches every file\n' "$f"
        failures=$((failures + 1))
        continue
    fi

    conditional=$((conditional + 1))
    printf 'OK(conditional) %s\n' "$f"
done

echo
if (( failures == 0 )); then
    echo "validate-rule-frontmatter: ${total} files OK (${always} always-loaded, ${conditional} conditional)"
    exit 0
else
    echo "validate-rule-frontmatter: ${failures} of ${total} files failed"
    echo "See docs/TOKEN_OPTIMIZATION.md for the conditional-loading contract."
    exit 1
fi
