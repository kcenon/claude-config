#!/usr/bin/env bash
# instructions-loaded-reinforcer.sh
# Re-asserts critical policy after CLAUDE.md / .claude/rules/*.md loads.
# Hook Type: InstructionsLoaded (sync)
# Exit codes: 0 (always — context is delivered via JSON)
# Response format: hookSpecificOutput.additionalContext

set -euo pipefail

# --- Locate commit-settings.md (try canonical user path, fall back to inline) ---
POLICY_TEXT=""
for candidate in \
    "${HOME}/.claude/commit-settings.md" \
    "${CLAUDE_HOME:-${HOME}/.claude}/commit-settings.md"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
        POLICY_TEXT="$(cat "$candidate")"
        break
    fi
done

if [ -z "$POLICY_TEXT" ]; then
    POLICY_TEXT=$(cat <<'EOF'
# Commit, Issue, and PR Settings

No AI/Claude attribution in commits, issues, or PRs.
All GitHub Issues and Pull Requests must be written in English.
EOF
)
fi

REINFORCEMENT=$(cat <<EOF
## Critical Policy Reinforcement (auto-injected after instruction load)

${POLICY_TEXT}

## Branching

- Default working branch: \`develop\`. Never push directly to \`main\` or \`develop\`.
- Feature/fix PRs target \`develop\`; release PRs target \`main\`.
- Squash merge required.

## Commit Format

Conventional Commits: \`type(scope): description\` or \`type: description\`.
Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, security.
Description: lowercase start, no trailing period, no emojis, no AI attribution.
EOF
)

# Emit JSON via jq if available (safe escaping); fall back to manual escaping.
if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$REINFORCEMENT" '{hookSpecificOutput: {hookEventName: "InstructionsLoaded", additionalContext: $ctx}}'
else
    ESCAPED=$(printf '%s' "$REINFORCEMENT" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
        | awk 'BEGIN{ORS="\\n"} {print}')
    printf '{"hookSpecificOutput":{"hookEventName":"InstructionsLoaded","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
