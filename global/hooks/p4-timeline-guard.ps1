#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# p4-timeline-guard.ps1
# Blocks Claude-initiated actions that violate the EPIC #454 P4 rollout timeline.
# PowerShell counterpart of p4-timeline-guard.sh.
# Hook Type: PreToolUse (Bash | Edit | Write)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName + permissionDecision
#
# Two protected actions:
#   1. gh pr merge of a PR whose diff touches global/skills/_internal/
#      -> blocked until p4_grace_until passes
#   2. Edit/Write to settings.json (or settings.windows.json) that flips
#      harness_policies.p4_strict_schema from false to true
#      -> blocked until p4_observation_until passes
#
# Override: set CLAUDE_P4_OVERRIDE=1 in the environment with the reason
# documented in COMPATIBILITY.md (incident response, RCA-required).

# Resolve settings + policy paths. Phase 1 dual-read: prefer policy file, fall back to settings.json.
# NOTE: do NOT use $home — it is a read-only PowerShell automatic variable, and
# under $ErrorActionPreference='Stop' (set above) any attempt to assign it
# raises a terminating WriteError that kills the whole hook.
$userProfile = [Environment]::GetFolderPath('UserProfile')
if (-not $userProfile) { $userProfile = $env:HOME }
$SettingsPath = $env:P4_SETTINGS_PATH
if (-not $SettingsPath) {
    $SettingsPath = Join-Path $userProfile '.claude' 'settings.json'
}
$PolicyPath = $env:P4_POLICY_PATH
if (-not $PolicyPath) {
    $PolicyPath = Join-Path $userProfile '.claude' 'policies' 'p4-timeline.json'
}

# Override gate
if ($env:CLAUDE_P4_OVERRIDE -eq '1') {
    New-HookAllowResponse
    exit 0
}

# Read input from stdin
$json = Read-HookInput
if (-not $json) {
    New-HookAllowResponse
    exit 0
}

# Neither policy file nor settings.json present on fresh installs - allow (fail-open)
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf) -and
    -not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    New-HookAllowResponse
    exit 0
}

# Parse policy file when present (Phase 1 primary source).
$policy = $null
if (Test-Path -LiteralPath $PolicyPath -PathType Leaf) {
    try {
        $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    } catch {
        $policy = $null
    }
}

# Parse settings.json when present (Phase 1 fallback source).
$settings = $null
if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
    try {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    } catch {
        $settings = $null
    }
}

# When both parses failed -> allow (other guards already enforce policy)
if ($null -eq $policy -and $null -eq $settings) {
    New-HookAllowResponse
    exit 0
}

# Helper: resolve a policy value. Reads $policy.<field> first, falls back to
# $settings.harness_policies.<field>. Returns $null when neither has the field.
function Get-PolicyValue {
    param([Parameter(Mandatory)][string]$Field)
    if ($null -ne $policy) {
        try {
            $v = $policy.$Field
            if ($null -ne $v -and -not ($v -is [string] -and [string]::IsNullOrEmpty($v))) {
                return $v
            }
        } catch {}
    }
    if ($null -ne $settings) {
        try {
            $v = $settings.harness_policies.$Field
            if ($null -ne $v -and -not ($v -is [string] -and [string]::IsNullOrEmpty($v))) {
                return $v
            }
        } catch {}
    }
    return $null
}

# Helper: read ISO-8601 timestamp field and return epoch seconds.
# Returns $null when the field is missing or unparseable.
function Get-IsoEpoch {
    param([Parameter(Mandatory)][string]$Field)
    $iso = Get-PolicyValue -Field $Field
    if (-not $iso) { return $null }
    try {
        $dto = [System.DateTimeOffset]::Parse(
            $iso,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        )
        return [int64]$dto.ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

$NowEpoch = [int64][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Extract tool name
$Tool = $null
try { $Tool = $json.tool_name } catch {}

# ── Branch 1: Bash matcher ──────────────────────────────────────
if ($Tool -eq 'Bash') {
    $cmd = $null
    try { $cmd = $json.tool_input.command } catch {}
    if ($cmd -and $cmd -match 'gh pr merge') {
        $graceEpoch = Get-IsoEpoch -Field 'p4_grace_until'
        if ($null -eq $graceEpoch) {
            New-HookAllowResponse
            exit 0
        }
        if ($NowEpoch -ge $graceEpoch) {
            New-HookAllowResponse
            exit 0
        }
        # Extract PR number; if missing, allow (cannot evaluate)
        $prNum = $null
        $prMatch = [regex]::Match($cmd, 'gh pr merge\s+(\d+)')
        if ($prMatch.Success) { $prNum = $prMatch.Groups[1].Value }
        if (-not $prNum) {
            New-HookAllowResponse
            exit 0
        }
        # Optional --repo flag
        $repoArg = @()
        $repoMatch = [regex]::Match($cmd, '--repo\s+(\S+)')
        if ($repoMatch.Success) {
            $repoArg = @('--repo', $repoMatch.Groups[1].Value)
        }
        # If gh unavailable or call fails, allow (cannot evaluate diff)
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            New-HookAllowResponse
            exit 0
        }
        $diffFiles = $null
        try {
            $diffFiles = & gh pr diff @repoArg $prNum --name-only 2>$null
        } catch {
            New-HookAllowResponse
            exit 0
        }
        if ($LASTEXITCODE -ne 0) {
            New-HookAllowResponse
            exit 0
        }
        if ($diffFiles -and ($diffFiles | Where-Object { $_ -match '^global/skills/_internal/' })) {
            $remain = $graceEpoch - $NowEpoch
            $days = [math]::Floor($remain / 86400)
            $hours = [math]::Floor(($remain % 86400) / 3600)
            New-HookDenyResponse -Reason ("P4 grace window not closed (${days}d ${hours}h remaining). PR #${prNum} touches global/skills/_internal/ which requires the 7-day grace window to pass first per EPIC #454. Override with CLAUDE_P4_OVERRIDE=1 (RCA required).")
            exit 0
        }
        New-HookAllowResponse
        exit 0
    }
}

# ── Branch 2: Edit/Write matcher (settings.json toggle flip) ────
if ($Tool -eq 'Edit' -or $Tool -eq 'Write') {
    $filePath = $null
    try { $filePath = $json.tool_input.file_path } catch {}
    if ($filePath -and ($filePath -match 'settings\.json$' -or $filePath -match 'settings\.windows\.json$')) {
        $obsEpoch = Get-IsoEpoch -Field 'p4_observation_until'
        if ($null -eq $obsEpoch -or $NowEpoch -ge $obsEpoch) {
            New-HookAllowResponse
            exit 0
        }
        # If current toggle is already true, nothing to flip -> allow
        $current = Get-PolicyValue -Field 'p4_strict_schema'
        if ($current -eq $true) {
            New-HookAllowResponse
            exit 0
        }
        # Detect a flip: new content sets p4_strict_schema true.
        $newBlob = ''
        if ($Tool -eq 'Write') {
            try { $newBlob = $json.tool_input.content } catch {}
        } else {
            try { $newBlob = $json.tool_input.new_string } catch {}
        }
        if ($newBlob -and ($newBlob -match '"p4_strict_schema"\s*:\s*true')) {
            $remain = $obsEpoch - $NowEpoch
            $days = [math]::Floor($remain / 86400)
            $hours = [math]::Floor(($remain % 86400) / 3600)
            New-HookDenyResponse -Reason ("P4 observation window not closed (${days}d ${hours}h remaining). harness_policies.p4_strict_schema cannot be flipped to true until the 14-day observation window passes per EPIC #454. Override with CLAUDE_P4_OVERRIDE=1 (RCA required).")
            exit 0
        }
    }
}

New-HookAllowResponse
exit 0
