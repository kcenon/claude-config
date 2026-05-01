#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# memory-integrity-check.ps1
# SessionStart hook: prints a brief memory health summary at session start.
# Reads ~/.claude/memory-shared/ metadata only -- no network, no validators.
#
# Hook Type: SessionStart (sync)
# Exit codes: 0 always (SessionStart must never block the session)
# Output prefix: [memory]
#
# Silent (no stdout) when system is healthy AND no recent activity AND
# no unread alerts AND last sync within 24 hours.
#
# Performance budget: < 300ms typical; hard cap 500ms with warning to stderr.
# Issue: kcenon/claude-config#522 (Phase D engine).

# --- Constants ---------------------------------------------------------------

$memorySharedDir   = if ($env:MEMORY_SHARED_DIR)        { $env:MEMORY_SHARED_DIR }        else { Join-Path $HOME '.claude' 'memory-shared' }
$memoriesDir       = Join-Path $memorySharedDir 'memories'
$quarantineDir     = Join-Path $memorySharedDir 'quarantine'
$alertsLog         = if ($env:MEMORY_ALERTS_LOG)        { $env:MEMORY_ALERTS_LOG }        else { Join-Path $HOME '.claude' 'logs' 'memory-alerts.log' }
$alertsReadMark    = if ($env:MEMORY_ALERTS_READ_MARK)  { $env:MEMORY_ALERTS_READ_MARK }  else { Join-Path $HOME '.claude' '.memory-alerts-read-mark' }

$RecentSecs    = 86400      # 24h
$StaleSecs     = 7776000    # 90d
$SyncStaleSecs = 86400      # 24h triggers warning per epic R1 mitigation
$PerfWarnMs    = 500        # hard cap

# --- Setup -------------------------------------------------------------------

# SessionStart hooks may receive JSON on stdin; drain and ignore.
try {
    if (-not [Console]::IsInputRedirected) {
        # No piped stdin; nothing to read.
    } else {
        [Console]::In.ReadToEnd() | Out-Null
    }
} catch {
    # ignore
}

$startTime = Get-Date

# Silent exit if the memory system is not deployed yet.
if (-not (Test-Path -LiteralPath $memorySharedDir -PathType Container)) {
    exit 0
}

# --- Helpers -----------------------------------------------------------------

function Read-Frontmatter {
    param([Parameter(Mandatory)][string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $null }
    $lines = $null
    try {
        $lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
    } catch {
        return $null
    }
    if ($lines.Count -lt 1) { return $null }
    if ($lines[0] -ne '---') { return $null }
    $endIdx = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*$') { $endIdx = $i; break }
    }
    if ($endIdx -lt 1) { return $null }
    $fm = @{}
    for ($i = 1; $i -lt $endIdx; $i++) {
        $line = $lines[$i]
        if ($line -match '^([A-Za-z0-9_\-]+):\s*(.*)$') {
            $key   = $matches[1]
            $value = $matches[2]
            # Strip surrounding single or double quotes.
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                $value = $matches[1]
            }
            $fm[$key] = $value.Trim()
        }
    }
    return $fm
}

function ConvertFrom-IsoToEpoch {
    param([string]$Iso)
    if ([string]::IsNullOrWhiteSpace($Iso)) { return $null }
    $clean = $Iso.Trim('"', "'", ' ')
    try {
        $dt = [DateTimeOffset]::Parse($clean, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $dt.ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

function Format-TimeAgo {
    param([Parameter(Mandatory)][long]$Seconds)
    if ($Seconds -lt 60)    { return "$Seconds sec ago" }
    if ($Seconds -lt 3600)  { return "$([math]::Floor($Seconds / 60)) min ago" }
    if ($Seconds -lt 86400) { return "$([math]::Floor($Seconds / 3600)) hr ago" }
    return "$([math]::Floor($Seconds / 86400)) days ago"
}

# --- Counts by trust-level ---------------------------------------------------

$countTotal       = 0
$countVerified    = 0
$countInferred    = 0
$countOther       = 0
$countQuarantined = 0
$recentNames      = New-Object System.Collections.Generic.List[string]
$staleNames       = New-Object System.Collections.Generic.List[string]

$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

if (Test-Path -LiteralPath $memoriesDir -PathType Container) {
    $memoryFiles = Get-ChildItem -LiteralPath $memoriesDir -Filter '*.md' -File -ErrorAction SilentlyContinue
    foreach ($file in $memoryFiles) {
        if ($file.Name -eq 'MEMORY.md') { continue }   # auto-generated index
        $countTotal++
        $fm = Read-Frontmatter -FilePath $file.FullName
        if ($null -eq $fm) {
            [Console]::Error.WriteLine("[memory] warning: cannot parse frontmatter: $($file.Name)")
            continue
        }

        $tl = if ($fm.ContainsKey('trust-level')) { $fm['trust-level'] } else { '' }
        switch ($tl) {
            'verified'    { $countVerified++ }
            'inferred'    { $countInferred++ }
            'quarantined' { $countQuarantined++ }
            default       { $countOther++ }
        }

        # Recent: created-at within 24h.
        if ($fm.ContainsKey('created-at')) {
            $caEpoch = ConvertFrom-IsoToEpoch -Iso $fm['created-at']
            if ($null -ne $caEpoch) {
                $age = $nowEpoch - $caEpoch
                if ($age -ge 0 -and $age -lt $RecentSecs) {
                    $recentNames.Add($file.BaseName)
                }
            }
        }

        # Stale: verified memory whose last-verified > 90d ago. Missing
        # last-verified on a verified memory counts as stale (per #511).
        if ($tl -eq 'verified') {
            $staleName = $file.BaseName
            if (-not $fm.ContainsKey('last-verified') -or [string]::IsNullOrWhiteSpace($fm['last-verified'])) {
                $staleNames.Add($staleName)
            } else {
                $lvEpoch = ConvertFrom-IsoToEpoch -Iso $fm['last-verified']
                if ($null -ne $lvEpoch -and ($nowEpoch - $lvEpoch) -ge $StaleSecs) {
                    $staleNames.Add($staleName)
                }
            }
        }
    }
}

# Quarantined directory adds to the quarantined count.
if (Test-Path -LiteralPath $quarantineDir -PathType Container) {
    $qFiles = Get-ChildItem -LiteralPath $quarantineDir -Filter '*.md' -File -ErrorAction SilentlyContinue
    $countQuarantined += $qFiles.Count
}

# --- Last-sync time + source machine via git log -----------------------------

$syncSecsAgo = $null
$syncHost    = ''
$syncWarn    = $false
$gitFailed   = $false
$dotGit      = Join-Path $memorySharedDir '.git'
if ((Test-Path -LiteralPath $dotGit) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $syncLine = $null
    try {
        $syncLine = & git -C $memorySharedDir log -1 --format='%ct|%an' 2>$null
    } catch {
        $syncLine = $null
    }
    if ($syncLine -and ($syncLine -match '^(\d+)\|(.*)$')) {
        $syncEpoch   = [long]$matches[1]
        $syncHost    = $matches[2]
        $syncSecsAgo = $nowEpoch - $syncEpoch
        if ($syncSecsAgo -ge $SyncStaleSecs) { $syncWarn = $true }
    } else {
        $gitFailed = $true
    }
} else {
    $gitFailed = $true
}

# --- Unread alerts -----------------------------------------------------------

$unreadCount     = 0
$unreadRecentMsg = ''
if (Test-Path -LiteralPath $alertsLog -PathType Leaf) {
    $readMarkEpoch = 0
    if (Test-Path -LiteralPath $alertsReadMark -PathType Leaf) {
        try {
            $rmRaw = (Get-Content -LiteralPath $alertsReadMark -TotalCount 1 -ErrorAction SilentlyContinue).Trim()
            if ($rmRaw -match '^\d+$') {
                $readMarkEpoch = [long]$rmRaw
            } else {
                $converted = ConvertFrom-IsoToEpoch -Iso $rmRaw
                if ($null -ne $converted) { $readMarkEpoch = $converted }
            }
        } catch {
            $readMarkEpoch = 0
        }
    }

    # Per #524 spec each line is: <ISO timestamp> <severity> <hash> <message>
    try {
        $tail = Get-Content -LiteralPath $alertsLog -Tail 200 -ErrorAction SilentlyContinue
        foreach ($line in $tail) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+', 4
            if ($parts.Count -lt 4) { continue }
            $tsEpoch = ConvertFrom-IsoToEpoch -Iso $parts[0]
            if ($null -eq $tsEpoch) { continue }
            if ($tsEpoch -gt $readMarkEpoch) {
                $unreadCount++
                $unreadRecentMsg = $parts[3]
            }
        }
    } catch {
        # ignore alert log read failures
    }
}

# --- Decide whether to emit summary ------------------------------------------

$emit = $false
if ($recentNames.Count -gt 0)   { $emit = $true }
if ($staleNames.Count -gt 0)    { $emit = $true }
if ($syncWarn)                  { $emit = $true }
if ($unreadCount -gt 0)         { $emit = $true }
if ($countQuarantined -gt 0)    { $emit = $true }
if ($gitFailed -and $countTotal -gt 0) { $emit = $true }

if (-not $emit) { exit 0 }

# --- Build summary block -----------------------------------------------------

# Line 1: counts.
Write-Output ("[memory] {0} entries (verified:{1}, inferred:{2}, quarantined:{3})" -f $countTotal, $countVerified, $countInferred, $countQuarantined)

# Line 2: last-sync info.
if ($gitFailed) {
    Write-Output ("[memory] cannot read git log; check {0}" -f $memorySharedDir)
} elseif ($null -ne $syncSecsAgo) {
    $hostLabel = if ([string]::IsNullOrWhiteSpace($syncHost)) { 'unknown' } else { $syncHost }
    if ($syncWarn) {
        Write-Output ("[memory] WARN last sync {0} (host: {1}) -- sync may be stuck" -f (Format-TimeAgo -Seconds $syncSecsAgo), $hostLabel)
    } else {
        Write-Output ("[memory] last sync {0} (host: {1})" -f (Format-TimeAgo -Seconds $syncSecsAgo), $hostLabel)
    }
}

# Line 3: recent activity.
if ($recentNames.Count -gt 0) {
    $display = ($recentNames | Select-Object -First 3) -join ', '
    if ($recentNames.Count -gt 3) { $display = "{0} (+{1} more)" -f $display, ($recentNames.Count - 3) }
    Write-Output ("[memory] {0} added in last 24h: {1} -- review with /memory-review" -f $recentNames.Count, $display)
}

# Line 4: stale memories.
if ($staleNames.Count -gt 0) {
    $display = ($staleNames | Select-Object -First 3) -join ', '
    if ($staleNames.Count -gt 3) { $display = "{0} (+{1} more)" -f $display, ($staleNames.Count - 3) }
    Write-Output ("[memory] {0} stale (last-verified > 90d): {1} -- review with /memory-review" -f $staleNames.Count, $display)
}

# Line 5: unread alerts.
if ($unreadCount -gt 0) {
    if ([string]::IsNullOrWhiteSpace($unreadRecentMsg)) {
        Write-Output ("[memory] WARN {0} unread alert(s)" -f $unreadCount)
    } else {
        $msg = $unreadRecentMsg
        if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 77) + '...' }
        Write-Output ("[memory] WARN {0} unread alert(s); latest: {1}" -f $unreadCount, $msg)
    }
    Write-Output ("[memory]   run /memory-review or check {0}" -f $alertsLog)
}

# --- Performance budget check ------------------------------------------------

$elapsed = (Get-Date) - $startTime
$elapsedMs = [int]$elapsed.TotalMilliseconds
if ($elapsedMs -ge $PerfWarnMs) {
    [Console]::Error.WriteLine("[memory] note: hook took ~${elapsedMs}ms (>${PerfWarnMs}ms budget)")
}

exit 0
