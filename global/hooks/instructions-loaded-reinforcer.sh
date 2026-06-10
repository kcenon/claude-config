#!/usr/bin/env bash
# instructions-loaded-reinforcer.sh
# Re-asserts critical policy after CLAUDE.md / .claude/rules/*.md loads.
# Hook Type: InstructionsLoaded (sync)
# Exit codes: 0 (always — context is delivered via JSON)
# Response format: hookSpecificOutput.additionalContext

set -euo pipefail

# Fixed short digest (issue #716): the full commit-settings.md text already
# reaches context via the CLAUDE.md @import chain, so re-injecting it verbatim
# on every InstructionsLoaded event is pure duplication. Keep the payload to
# ~10 lines / ~500 bytes and never read policy file contents into it.
REINFORCEMENT=$(cat <<'EOF'
## Critical Policy Reinforcement (digest)

- No AI/Claude attribution in commits, issues, or PRs.
- Issue/PR/commit prose: follow the CLAUDE_CONTENT_LANGUAGE policy (see commit-settings.md).
- Branches: work branches from develop; never push directly to main or develop; squash merge only.
- Commits: Conventional Commits `type(scope): description`; lowercase first char, no trailing period.
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
