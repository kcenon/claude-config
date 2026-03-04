# cleanup.ps1
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success
# Response format: hookSpecificOutput (modern format)

$ErrorActionPreference = 'SilentlyContinue'

# Clean up temporary Claude files (older than 60 minutes)
$cutoff = (Get-Date).AddMinutes(-60)
Get-ChildItem -Path $env:TEMP -Filter "claude_*" -File |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force

Get-ChildItem -Path $env:TEMP -Filter "tmp.*" -File |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force

# Output modern response format
@'
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
'@
exit 0
