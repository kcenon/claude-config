# sensitive-file-guard.ps1
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0=allow, 2=block
# Response format: hookSpecificOutput (modern format)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Deny-Response {
    param([string]$Reason)
    $safeReason = $Reason -replace '\\', '\\\\' -replace '"', '\"'
    @"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$safeReason"
  }
}
"@
    exit 2
}

function Allow-Response {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Read hook input from stdin
$inputJson = $input | Out-String

# Fail-closed: deny if input is empty or unparseable
if ([string]::IsNullOrWhiteSpace($inputJson)) {
    Deny-Response "Failed to parse hook input — denying for safety (fail-closed)"
}

try {
    $hookData = $inputJson | ConvertFrom-Json
    $FILE = $hookData.tool_input.file_path
} catch {
    Deny-Response "Failed to parse hook input — denying for safety (fail-closed)"
}

# Skip if no file path provided (allow by default)
if ([string]::IsNullOrEmpty($FILE)) {
    Allow-Response
}

# Check sensitive file extensions
if ($FILE -match '(^|[\\/])\.env($|\.)|\.(pem|key|p12|pfx)$') {
    Deny-Response "Access to sensitive file blocked: $FILE (protected extension)"
}

# Check sensitive directories
if ($FILE -match '(?i)(secrets|credentials|passwords)[/\\]') {
    Deny-Response "Access to sensitive directory blocked: $FILE (protected path)"
}

Allow-Response
