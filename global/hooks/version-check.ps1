# version-check.ps1
# Checks Claude Code version against known problematic versions
# Hook Type: SessionStart
# Usage: Called automatically on session start
# Response format: none (lifecycle event, no JSON output needed)
#
# Known cache efficiency bugs:
# - Resume cache regression: https://github.com/anthropics/claude-code/issues/34629
# - Sentinel replacement: https://github.com/anthropics/claude-code/issues/40524

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KnownIssuesJson = Join-Path $ScriptDir "known-issues.json"
$LogFile = Join-Path $HOME ".claude/session.log"

# Hardcoded fallback if JSON not found
$FallbackVersions = @(
    "2.1.69", "2.1.70", "2.1.71", "2.1.72", "2.1.73",
    "2.1.74", "2.1.75", "2.1.76", "2.1.77", "2.1.78",
    "2.1.79", "2.1.80", "2.1.81"
)

# Get Claude Code version
$ccVersion = ""
try {
    $versionOutput = & claude --version 2>$null
    if ($versionOutput -match '(\d+\.\d+\.\d+)') {
        $ccVersion = $Matches[1]
    }
} catch {
    exit 0
}

if (-not $ccVersion) {
    exit 0
}

# Load known problematic versions from JSON (prefer) or fallback
$KnownCacheBugVersions = @()
if (Test-Path $KnownIssuesJson) {
    try {
        $json = Get-Content $KnownIssuesJson -Raw | ConvertFrom-Json
        foreach ($issue in $json.known_issues) {
            $KnownCacheBugVersions += $issue.version_list
        }
    } catch {
        $KnownCacheBugVersions = @()
    }
}
if ($KnownCacheBugVersions.Count -eq 0) {
    $KnownCacheBugVersions = $FallbackVersions
}

# Check against known problematic versions
if ($KnownCacheBugVersions -contains $ccVersion) {
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $message = "[VersionCheck] WARNING: Claude Code v${ccVersion} has known cache bugs (resume cache regression, sentinel replacement). See: https://github.com/anthropics/claude-code/issues/34629 — $Timestamp"
    Add-Content -Path $LogFile -Value $message -ErrorAction SilentlyContinue
}

exit 0
