#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

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

# Rotate logs
Invoke-LogRotation -FilePath (Join-Path $HOME '.claude' 'session.log') -MaxMB 5 -MaxArchives 3
Invoke-LogRotation -FilePath (Join-Path $HOME '.claude' 'logs' 'subagents.log') -MaxMB 5 -MaxArchives 3
Invoke-LogRotation -FilePath (Join-Path $HOME '.claude' 'logs' 'tasks.log') -MaxMB 5 -MaxArchives 3
Invoke-LogRotation -FilePath (Join-Path $HOME '.claude' 'logs' 'tool-failures.log') -MaxMB 5 -MaxArchives 3

exit 0
