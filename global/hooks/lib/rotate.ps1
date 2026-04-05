#Requires -Version 7.0
# rotate.ps1 — log rotation utility wrapper
# Thin wrapper that imports CommonHelpers.psm1 and exposes Invoke-LogRotation.
# For backward compatibility with scripts that source this file directly.
#
# Usage:
#   . (Join-Path $PSScriptRoot 'rotate.ps1')
#   Invoke-LogRotation -FilePath $logFile -MaxMB 5 -MaxArchives 3

Import-Module (Join-Path $PSScriptRoot 'CommonHelpers.psm1') -Force

# Invoke-LogRotation is already exported by CommonHelpers.psm1.
# No additional wrapper needed — importing the module makes it available
# in the caller's scope.
