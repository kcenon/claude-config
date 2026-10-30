#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

# cleanup.ps1
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success
# Response format: none (lifecycle event, no JSON output needed)

# Clean up temporary Claude files (older than 60 minutes)
$tempDir = if ($env:TMPDIR) { $env:TMPDIR } elseif ($env:TEMP) { $env:TEMP } else { '/tmp' }
$cutoff = (Get-Date).AddMinutes(-60)

if (Test-Path -LiteralPath $tempDir -PathType Container) {
    Get-ChildItem -Path $tempDir -Filter 'claude_*' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Get-ChildItem -Path $tempDir -Filter 'tmp.*' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# No log rotation here: the loggers whose logs this hook used to rotate were
# removed by #964, and the hooks that still log rotate their own files. Logs
# the removed loggers left behind are deliberately not touched.

exit 0
