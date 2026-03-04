# sensitive-file-guard.ps1
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

$FILE = $env:CLAUDE_FILE_PATH

function Deny-Response {
    param([string]$Reason)
    @"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$Reason"
  }
}
"@
    exit 2
}

function Allow-Response {
    @'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
    exit 0
}

# Skip if no file path provided (allow by default)
if ([string]::IsNullOrEmpty($FILE)) {
    Allow-Response
}

# Check sensitive file extensions
if ($FILE -match '\.(env|pem|key|p12|pfx)$') {
    Deny-Response "Access to sensitive file blocked: $FILE (protected extension)"
}

# Check sensitive directories
if ($FILE -match '(?i)(secrets|credentials|passwords|private)[/\\]') {
    Deny-Response "Access to sensitive directory blocked: $FILE (protected path)"
}

Allow-Response
