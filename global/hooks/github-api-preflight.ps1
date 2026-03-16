# github-api-preflight.ps1
# Checks GitHub API connectivity before executing GitHub-related commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow (always, warning only)
# Response format: hookSpecificOutput (modern format)

# Read hook input from stdin
$inputJson = $input | Out-String
try {
    $hookData = $inputJson | ConvertFrom-Json
    $CMD = $hookData.tool_input.command
} catch {
    $CMD = ""
}

# Only check GitHub-related commands
if ($CMD -notmatch '(gh |github\.com|api\.github\.com)') {
    @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
    exit 0
}

# Test GitHub API connectivity with short timeout
try {
    $response = Invoke-WebRequest -Uri 'https://api.github.com/zen' -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
} catch {
    @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "message": "GitHub API may be unreachable (sandbox/TLS issue detected). Suggestions: Use local git operations if possible, check network/certificate settings, consider /sandbox to manage restrictions."
  }
}
'@
    exit 0
}

# Check GitHub CLI auth status for gh commands
if ($CMD -match '^gh ') {
    $ghAuth = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "message": "GitHub CLI not authenticated. Run 'gh auth login' or 'gh auth status' to check."
  }
}
'@
        exit 0
    }
}

# All checks passed
@'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
exit 0
