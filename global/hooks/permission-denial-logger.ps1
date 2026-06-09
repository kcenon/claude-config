#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# permission-denial-logger.ps1
# Appends a redacted JSONL audit record for every denied tool call.
# Hook Type: PermissionDenied
# Exit codes: 0 (always - passive logger, never alters the permission decision)
# Response format: none (observation-only event; no JSON emitted, never blocks)
#
# PowerShell parity port of permission-denial-logger.sh. Reads the official
# PermissionDenied payload from stdin ({ tool_name, tool_input,
# permission_suggestions }), redacts secrets from tool_input, and appends one
# JSON line to ${env:CLAUDE_LOG_DIR} (defaults to ~/.claude/logs) /
# permission-denials.jsonl. Purely passive: emits no permission-altering output
# and always exits 0.
#
# Opt-out: set CLAUDE_PERMISSION_LOGGER=0 to disable (early no-op exit).
#
# Privacy: secrets in tool_input are scrubbed before the write so raw tool_input
# never reaches disk; the log is tail-rotated at 10 MB via Invoke-LogRotation.

# Opt-out switch: a single "0" disables the logger entirely.
if ($env:CLAUDE_PERMISSION_LOGGER -eq '0') {
    exit 0
}

$logDir = if ($env:CLAUDE_LOG_DIR) { $env:CLAUDE_LOG_DIR } else { Join-Path $HOME '.claude/logs' }
$logFile = Join-Path $logDir 'permission-denials.jsonl'

# Redact secrets from an arbitrary string. Mirrors the sed pattern set in
# permission-denial-logger.sh: authorization/bearer, token/key/secret/password
# assignments, URL inline credentials, AWS access keys, GitHub PATs, and PEM
# private-key blocks. Over-redaction is preferable to leaking a credential.
function Get-RedactedText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    $t = [regex]::Replace($t, '(authorization)([\s:=]+)(bearer|token|basic)?\s*[A-Za-z0-9._~+/=-]+', '$1$2<REDACTED>', 'IgnoreCase')
    $t = [regex]::Replace($t, '(bearer)(\s+)[A-Za-z0-9._~+/=-]+', '$1$2<REDACTED>', 'IgnoreCase')
    $t = [regex]::Replace($t, '((api[_-]?key|access[_-]?key|secret|token|password|passwd|pwd|client[_-]?secret|refresh[_-]?token)["'']?\s*[:=]\s*["'']?)[^"''\s,}&]+', '$1<REDACTED>', 'IgnoreCase')
    $t = [regex]::Replace($t, '(://[^/\s:@]+):[^/\s@]+@', '$1:<REDACTED>@')
    $t = [regex]::Replace($t, '\b(AKIA|ASIA)[A-Z0-9]{16}\b', '$1<REDACTED>')
    $t = [regex]::Replace($t, '\b(gh[pousr]_)[A-Za-z0-9]{20,}', '$1<REDACTED>')
    $t = [regex]::Replace($t, '-----BEGIN[^-]*PRIVATE KEY-----[^-]*-----END[^-]*PRIVATE KEY-----', '<REDACTED PRIVATE KEY>')
    return $t
}

# Best-effort: never fail the (already-made) permission decision on a logging
# error. Every disk touch is wrapped in try/catch.
try {
    if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
} catch {
    exit 0
}

# Tail-rotate at 10 MB so the audit trail cannot grow unbounded.
try { Invoke-LogRotation -FilePath $logFile -MaxMB 10 -MaxArchives 5 } catch {}

$ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')

# Read raw stdin.
$raw = ''
try {
    if ([Console]::IsInputRedirected) {
        $raw = [Console]::In.ReadToEnd()
    }
} catch {}

function Write-JsonLine {
    param([hashtable]$Entry)
    try {
        ($Entry | ConvertTo-Json -Compress -Depth 10) | Out-File -FilePath $logFile -Append -Encoding utf8
    } catch {}
}

# Empty / unparseable stdin: log a marker line and exit cleanly.
$json = $null
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
}
if ($null -eq $json) {
    Write-JsonLine ([ordered]@{ ts = $ts; tool_name = 'unknown'; note = 'empty or unparseable hook input' })
    exit 0
}

$toolName = if ($json.PSObject.Properties.Name -contains 'tool_name' -and $json.tool_name) { [string]$json.tool_name } else { 'unknown' }
$sessionId = if ($json.PSObject.Properties.Name -contains 'session_id' -and $json.session_id) { [string]$json.session_id } else { '' }

# Serialize tool_input to compact JSON, scrub textually, then re-parse. On
# re-parse failure fall back to a flat redacted string so the record is always
# valid JSON and never carries a raw secret.
$toolInputObj = if ($json.PSObject.Properties.Name -contains 'tool_input' -and $null -ne $json.tool_input) { $json.tool_input } else { [PSCustomObject]@{} }
$toolInputRaw = $toolInputObj | ConvertTo-Json -Compress -Depth 10
$toolInputRedactedStr = Get-RedactedText -Text $toolInputRaw

$suggestions = if ($json.PSObject.Properties.Name -contains 'permission_suggestions' -and $null -ne $json.permission_suggestions) { $json.permission_suggestions } else { @() }

$toolInputRedacted = $null
$parsedOk = $true
try { $toolInputRedacted = $toolInputRedactedStr | ConvertFrom-Json -ErrorAction Stop } catch { $parsedOk = $false }

if ($parsedOk) {
    $entry = [ordered]@{
        ts                     = $ts
        session_id             = $sessionId
        tool_name              = $toolName
        tool_input_redacted    = $toolInputRedacted
        permission_suggestions = $suggestions
    }
} else {
    $entry = [ordered]@{
        ts                     = $ts
        session_id             = $sessionId
        tool_name              = $toolName
        tool_input_redacted    = $toolInputRedactedStr
        permission_suggestions = $suggestions
    }
}

Write-JsonLine $entry
exit 0
