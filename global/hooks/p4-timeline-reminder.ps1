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

# Resolve settings path: P4_SETTINGS_PATH overrides, else ~/.claude/settings.json.
# NOTE: do NOT use $home — it is a read-only PowerShell automatic variable, and
# under $ErrorActionPreference='Stop' (set above) any attempt to assign it
# raises a terminating WriteError that kills the whole hook.
$SettingsPath = $env:P4_SETTINGS_PATH
if (-not $SettingsPath) {
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    if (-not $userProfile) { $userProfile = $env:HOME }
    $SettingsPath = Join-Path $userProfile '.claude' 'settings.json'
}

# Settings file may not exist on fresh installs - silent
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    exit 0
}

# Parse settings.json
$settings = $null
try {
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
}
catch {
    exit 0
}

function Get-IsoEpoch {
    param([Parameter(Mandatory)][string]$Field)
    $iso = $null
    try {
        $iso = $settings.harness_policies.$Field
    } catch { return $null }
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
