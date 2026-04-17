#!/bin/bash

# Claude Configuration Project Initializer
# ==========================================
# Deploy project-level Claude Code configuration template to a target directory.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_TEMPLATE="$REPO_DIR/project"
HOOKS_DIR="$REPO_DIR/hooks"

info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }

usage() {
    cat << 'EOF'
Usage: init-project.sh <target-directory> [OPTIONS]

Deploy Claude Code project configuration to a target directory.

Options:
  --profile <level>   Configuration profile (default: standard)
                        minimal  — CLAUDE.md + core rules + .claudeignore
                        standard — minimal + coding + workflow rules
                        full     — standard + api + operations + agents + skills
  --force             Overwrite existing files
  --install-hooks     Install git hooks without prompting
  --no-hooks          Skip git hooks installation
  --dry-run           Show what would be copied without copying
  -h, --help          Show this help message

Examples:
  ./scripts/init-project.sh ~/projects/my-app
  ./scripts/init-project.sh ~/projects/my-app --profile full
  ./scripts/init-project.sh ~/projects/my-app --profile minimal --force
EOF
}

# Parse arguments
TARGET=""
PROFILE="standard"
FORCE=false
DRY_RUN=false
HOOKS_MODE=""  # ask | install | skip

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)   PROFILE="$2"; shift 2 ;;
        --force)     FORCE=true; shift ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --install-hooks) HOOKS_MODE="install"; shift ;;
        --no-hooks)  HOOKS_MODE="skip"; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          error "Unknown option: $1"; usage; exit 1 ;;
        *)           TARGET="$1"; shift ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    error "Target directory is required."
    usage
    exit 1
fi

# Resolve to absolute path
TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")"

if [[ ! -d "$TARGET" ]]; then
    error "Target directory does not exist: $TARGET"
    exit 1
fi

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       Claude Code Project Initializer                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

info "Target:  $TARGET"
info "Profile: $PROFILE"
echo ""

# Define what each profile includes
declare -a COPY_LIST=()
COPIED=0
SKIPPED=0

# Helper: copy a file or directory
copy_item() {
    local src="$1"
    local dst="$2"
    local rel="${src#$PROJECT_TEMPLATE/}"

    if [[ ! -e "$src" ]]; then
        return
    fi

    if [[ -e "$dst" && "$FORCE" == false ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "  SKIP  $rel (exists)"
        fi
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  COPY  $rel"
        COPIED=$((COPIED + 1))
        return
    fi

    if [[ -d "$src" ]]; then
        mkdir -p "$dst"
        cp -r "$src/." "$dst/"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    fi
    COPIED=$((COPIED + 1))
}

# Profile: minimal
copy_minimal() {
    copy_item "$PROJECT_TEMPLATE/CLAUDE.md" "$TARGET/CLAUDE.md"
    copy_item "$PROJECT_TEMPLATE/.claudeignore" "$TARGET/.claudeignore"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/core" "$TARGET/.claude/rules/core"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/security.md" "$TARGET/.claude/rules/security.md"
    copy_item "$PROJECT_TEMPLATE/.claude/settings.json" "$TARGET/.claude/settings.json"
}

# Profile: standard (includes minimal)
copy_standard() {
    copy_minimal
    copy_item "$PROJECT_TEMPLATE/.claude/rules/coding" "$TARGET/.claude/rules/coding"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/workflow" "$TARGET/.claude/rules/workflow"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/project-management" "$TARGET/.claude/rules/project-management"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/tools" "$TARGET/.claude/rules/tools"
    copy_item "$PROJECT_TEMPLATE/.claude/commands" "$TARGET/.claude/commands"
}

# Profile: full (includes standard)
copy_full() {
    copy_standard
    copy_item "$PROJECT_TEMPLATE/.claude/rules/api" "$TARGET/.claude/rules/api"
    copy_item "$PROJECT_TEMPLATE/.claude/rules/operations" "$TARGET/.claude/rules/operations"
    copy_item "$PROJECT_TEMPLATE/.claude/agents" "$TARGET/.claude/agents"
    copy_item "$PROJECT_TEMPLATE/.claude/skills" "$TARGET/.claude/skills"
    copy_item "$PROJECT_TEMPLATE/.mcp.json.example" "$TARGET/.mcp.json.example"
    copy_item "$PROJECT_TEMPLATE/.lsp.json.example" "$TARGET/.lsp.json.example"
    copy_item "$PROJECT_TEMPLATE/CLAUDE.local.md.template" "$TARGET/CLAUDE.local.md.template"
    copy_item "$PROJECT_TEMPLATE/.claude/settings.local.json.template" "$TARGET/.claude/settings.local.json.template"
}

# Execute profile
case "$PROFILE" in
    minimal)  copy_minimal ;;
    standard) copy_standard ;;
    full)     copy_full ;;
    *)        error "Unknown profile: $PROFILE (expected: minimal, standard, full)"; exit 1 ;;
esac

echo ""
if [[ "$DRY_RUN" == true ]]; then
    info "Dry run complete. $COPIED would be copied, $SKIPPED would be skipped."
    exit 0
fi

success "$COPIED items copied, $SKIPPED skipped (already exist)."

# Git hooks installation
IS_GIT_REPO=false
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IS_GIT_REPO=true
fi

if [[ "$IS_GIT_REPO" == true && "$HOOKS_MODE" != "skip" ]]; then
    if [[ "$HOOKS_MODE" == "install" ]]; then
        INSTALL_HOOKS=true
    else
        echo ""
        read -p "$(echo -e "${YELLOW}Install git hooks (commit-msg, pre-commit) to $TARGET? [Y/n] ${NC}")" answer
        INSTALL_HOOKS=true
        if [[ "$answer" =~ ^[Nn] ]]; then
            INSTALL_HOOKS=false
        fi
    fi

    if [[ "$INSTALL_HOOKS" == true && -f "$HOOKS_DIR/install-hooks.sh" ]]; then
        info "Installing git hooks..."
        bash "$HOOKS_DIR/install-hooks.sh" "$TARGET"
        success "Git hooks installed."
    elif [[ "$INSTALL_HOOKS" == true ]]; then
        warn "install-hooks.sh not found at $HOOKS_DIR"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Project initialized: $TARGET"
info "Profile: $PROFILE"
info "Items: $COPIED copied, $SKIPPED skipped"
if [[ "$IS_GIT_REPO" == true ]]; then
    info "Git hooks: $(git -C "$TARGET" config --local core.hooksPath 2>/dev/null || echo 'default')"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
