#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# p4-timeline-reminder.ps1
# SessionStart banner that surfaces the active P4 rollout window.
# PowerShell counterpart of p4-timeline-reminder.sh.
# Hook Type: SessionStart
# Exit codes: 0 (always - lifecycle event)
# Response format: none (writes to stderr; visible in terminal)
#
# Reads harness_policies timestamps from ~/.claude/settings.json and prints
# a banner on stderr indicating which window is currently active and how
# much time remains. Silent when the rollout is fully complete (now() >=
# p4_freeze_until) or when the relevant fields are absent.

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

# Neither policy file nor settings.json present on fresh installs - silent
if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf) -and
    -not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
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

# When both parses failed -> silent
if ($null -eq $policy -and $null -eq $settings) {
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

$GraceEpoch  = Get-IsoEpoch -Field 'p4_grace_until'
$ObsEpoch    = Get-IsoEpoch -Field 'p4_observation_until'
$FreezeEpoch = Get-IsoEpoch -Field 'p4_freeze_until'

# Silent when no timeline is configured at all
if ($null -eq $GraceEpoch -and $null -eq $ObsEpoch -and $null -eq $FreezeEpoch) {
    exit 0
}

$NowEpoch = [int64][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Silent when the rollout is fully complete
if ($null -ne $FreezeEpoch -and $NowEpoch -ge $FreezeEpoch) {
    exit 0
}

# Determine active window
$Window = $null
$Deadline = $null
$NextAction = $null

if ($null -ne $GraceEpoch -and $NowEpoch -lt $GraceEpoch) {
    $Window = 'GRACE (lenient only)'
    $Deadline = $GraceEpoch
    $NextAction = 'D2 (#462) merge eligible after grace ends'
}
elseif ($null -ne $ObsEpoch -and $NowEpoch -lt $ObsEpoch) {
    $Window = 'OBSERVATION (collecting metrics)'
    $Deadline = $ObsEpoch
    $NextAction = 'p4_strict_schema flip eligible after observation ends'
}
elseif ($null -ne $FreezeEpoch -and $NowEpoch -lt $FreezeEpoch) {
    $Window = 'FREEZE (72h post-D2)'
    $Deadline = $FreezeEpoch
    $NextAction = 'Default toggle flip eligible after freeze ends'
}
else {
    exit 0
}

# Format remaining time
$remain = $Deadline - $NowEpoch
if ($remain -le 0) {
    $remaining = 'ended'
} else {
    $days = [math]::Floor($remain / 86400)
    $hours = [math]::Floor(($remain % 86400) / 3600)
    $remaining = "${days}d ${hours}h remaining"
}

# Format ISO deadline (UTC)
$deadlineIso = [System.DateTimeOffset]::FromUnixTimeSeconds($Deadline).UtcDateTime.ToString('yyyy-MM-dd HH:mm') + ' UTC'

# Emit banner to stderr. Use Write-Host with -ForegroundColor when stderr is a TTY;
# fall back to plain [Console]::Error.WriteLine() for non-interactive sessions.
$isTty = -not [Console]::IsErrorRedirected

if ($isTty) {
    [Console]::Error.WriteLine('')
    Write-Host 'P4 Rollout Active' -ForegroundColor Yellow
    Write-Host '  Window:   ' -NoNewline
    Write-Host $Window -ForegroundColor Cyan
    [Console]::Error.WriteLine("  Ends:     $deadlineIso ($remaining)")
    Write-Host '  Next:     ' -NoNewline
    Write-Host $NextAction -ForegroundColor Green
    [Console]::Error.WriteLine('  Override: CLAUDE_P4_OVERRIDE=1 (RCA required; see COMPATIBILITY.md)')
} else {
    [Console]::Error.WriteLine('P4 Rollout Active')
    [Console]::Error.WriteLine("  Window:   $Window")
    [Console]::Error.WriteLine("  Ends:     $deadlineIso ($remaining)")
    [Console]::Error.WriteLine("  Next:     $NextAction")
    [Console]::Error.WriteLine('  Override: CLAUDE_P4_OVERRIDE=1 (RCA required; see COMPATIBILITY.md)')
}

exit 0
