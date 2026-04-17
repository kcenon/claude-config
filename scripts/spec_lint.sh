#!/bin/bash
# Claude Configuration Official-Spec Linter (bash entrypoint)
# ==========================================================
# Validates SKILL.md frontmatter, plugin.json, and settings.json against
# canonical Claude Code 2026 schemas under scripts/schemas/.
#
# Usage:
#   scripts/spec_lint.sh                 # lint all known files in the repo
#   scripts/spec_lint.sh --warn-only     # advisory mode (always exit 0)
#   scripts/spec_lint.sh --quiet         # only print violations + summary
#   scripts/spec_lint.sh --mode skill <file> [<file> ...]
#
# Exit code: 0 on success, 1 on any violation (unless --warn-only), 2 on setup error.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SPEC_LINT_PY="$SCRIPT_DIR/spec_lint.py"

# Parse args
WARN_ONLY=""
STRICT=""
QUIET=""
EXPLICIT_MODE=""
EXPLICIT_FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --warn-only) WARN_ONLY="--warn-only"; shift ;;
        --strict)    STRICT="--strict"; shift ;;
        --quiet)     QUIET="--quiet"; shift ;;
        --mode)
            EXPLICIT_MODE="${2:-}"
            shift 2 || true
            while [ $# -gt 0 ]; do
                EXPLICIT_FILES+=("$1")
                shift
            done
            ;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# Locate Python interpreter
PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    echo "ERROR: python3 (or python) not found in PATH" >&2
    exit 2
fi

# Verify Python deps
if ! "$PYTHON" -c "import yaml, jsonschema" >/dev/null 2>&1; then
    echo "ERROR: missing Python dependencies. Install with: pip install pyyaml jsonschema" >&2
    exit 2
fi

if [ ! -f "$SPEC_LINT_PY" ]; then
    echo "ERROR: spec_lint.py not found at $SPEC_LINT_PY" >&2
    exit 2
fi

# Explicit mode: caller supplied files
if [ -n "$EXPLICIT_MODE" ]; then
    if [ ${#EXPLICIT_FILES[@]} -eq 0 ]; then
        echo "ERROR: --mode requires at least one file path" >&2
        exit 2
    fi
    exec "$PYTHON" "$SPEC_LINT_PY" --mode "$EXPLICIT_MODE" $WARN_ONLY $STRICT $QUIET "${EXPLICIT_FILES[@]}"
fi

# Default mode: discover and lint all known files in the repo
overall_rc=0

# 1. SKILL.md frontmatter
SKILL_DIRS=(
    "$ROOT_DIR/project/.claude/skills"
    "$ROOT_DIR/plugin/skills"
    "$ROOT_DIR/plugin-lite/skills"
    "$ROOT_DIR/global/skills"
)
SKILL_FILES=()
for dir in "${SKILL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        while IFS= read -r -d '' file; do
            SKILL_FILES+=("$file")
        done < <(find "$dir" -name "SKILL.md" -type f -print0)
    fi
done
if [ ${#SKILL_FILES[@]} -gt 0 ]; then
    echo "[spec_lint] mode=skill files=${#SKILL_FILES[@]}"
    if ! "$PYTHON" "$SPEC_LINT_PY" --mode skill $WARN_ONLY $STRICT $QUIET "${SKILL_FILES[@]}"; then
        overall_rc=1
    fi
fi

# 2. plugin.json
PLUGIN_FILES=()
for candidate in \
    "$ROOT_DIR/plugin/.claude-plugin/plugin.json" \
    "$ROOT_DIR/plugin-lite/.claude-plugin/plugin.json"; do
    [ -f "$candidate" ] && PLUGIN_FILES+=("$candidate")
done
if [ ${#PLUGIN_FILES[@]} -gt 0 ]; then
    echo "[spec_lint] mode=plugin files=${#PLUGIN_FILES[@]}"
    if ! "$PYTHON" "$SPEC_LINT_PY" --mode plugin $WARN_ONLY $STRICT $QUIET "${PLUGIN_FILES[@]}"; then
        overall_rc=1
    fi
fi

# 3. settings.json
SETTINGS_FILES=()
for candidate in \
    "$ROOT_DIR/global/settings.json" \
    "$ROOT_DIR/global/settings.windows.json" \
    "$ROOT_DIR/project/.claude/settings.json"; do
    [ -f "$candidate" ] && SETTINGS_FILES+=("$candidate")
done
if [ ${#SETTINGS_FILES[@]} -gt 0 ]; then
    echo "[spec_lint] mode=settings files=${#SETTINGS_FILES[@]}"
    if ! "$PYTHON" "$SPEC_LINT_PY" --mode settings $WARN_ONLY $STRICT $QUIET "${SETTINGS_FILES[@]}"; then
        overall_rc=1
    fi
fi

exit "$overall_rc"
