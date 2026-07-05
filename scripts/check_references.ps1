# Verify mapped reference mirrors match their canonical source.
# Exits with 2 if any mirror drifts from canonical; 0 otherwise.
#
# Usage: pwsh scripts/check_references.ps1 [repo-root] [reference-map.yml]

param(
    [string]$RootDir,
    [string]$MapFile
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RootDir) {
    $RootDir = Split-Path -Parent $ScriptDir
}
if (-not $MapFile) {
    $MapFile = Join-Path $RootDir 'reference-map.yml'
}

if (-not (Test-Path -LiteralPath $MapFile -PathType Leaf)) {
    Write-Error "reference map missing: $MapFile"
    exit 1
}

function Read-ReferenceMap {
    param([string]$Path)

    $entries = @()
    $current = $null
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*-\s+source:\s*(.+?)\s*$') {
            if ($null -ne $current) { $entries += [pscustomobject]$current }
            $current = @{
                Source = $matches[1].Trim('"')
                Target = $null
                Mode = $null
            }
            continue
        }
        if ($line -match '^\s+target:\s*(.+?)\s*$') {
            if ($null -eq $current) { throw 'malformed reference-map.yml: target before source' }
            $current.Target = $matches[1].Trim('"')
            continue
        }
        if ($line -match '^\s+mode:\s*(.+?)\s*$') {
            if ($null -eq $current) { throw 'malformed reference-map.yml: mode before source' }
            $current.Mode = $matches[1].Trim('"')
            continue
        }
    }
    if ($null -ne $current) { $entries += [pscustomobject]$current }

    foreach ($entry in $entries) {
        if (-not $entry.Source -or -not $entry.Target -or -not $entry.Mode) {
            throw 'malformed reference-map.yml entry'
        }
    }
    return $entries
}

function Get-ReferenceText {
    param(
        [string]$Path,
        [string]$Mode,
        [string]$Side
    )

    $text = Get-Content -Raw -LiteralPath $Path
    if ($Mode -eq 'exact' -or ($Mode -eq 'strip-source-frontmatter' -and $Side -eq 'target')) {
        return $text
    }
    if ($Mode -ne 'strip-source-frontmatter' -or $Side -ne 'source') {
        throw "unsupported reference comparison mode: $Mode"
    }

    $lines = [regex]::Split($text, "\r?\n")
    if ($lines.Count -gt 0) {
        $lines[0] = $lines[0].TrimStart([char]0xFEFF)
    }
    if ($lines.Count -eq 0 -or $lines[0].TrimEnd() -ne '---') {
        return $text
    }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimEnd() -eq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) {
        return $text
    }
    $start = $end + 1
    if ($start -lt $lines.Count -and $lines[$start] -eq '') {
        $start++
    }
    if ($start -ge $lines.Count) {
        return ''
    }
    return (($lines[$start..($lines.Count - 1)]) -join "`n")
}

function Normalize-ReferenceText {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function Get-TrackedProjectReferenceSymlinks {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @()
    }

    $null = & git -C $RootDir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $lines = & git -C $RootDir ls-files -s -- 'project/.claude/skills' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    foreach ($line in $lines) {
        if ($line -match '^120000\s+\S+\s+\d+\t(project/\.claude/skills/.*/reference/.*)$') {
            $matches[1]
        }
    }
}

$trackedSymlinks = @(Get-TrackedProjectReferenceSymlinks)
if ($trackedSymlinks.Count -gt 0) {
    foreach ($path in $trackedSymlinks) {
        Write-Host "FAIL: tracked symlink mode 120000: $path" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "check_references: project skill reference files must be tracked as regular files." -ForegroundColor Yellow
    exit 2
}

$entries = @(Read-ReferenceMap -Path $MapFile)
if ($entries.Count -eq 0) {
    Write-Error "no references declared in $MapFile"
    exit 1
}

$drift = 0
foreach ($entry in $entries) {
    $src = Join-Path $RootDir $entry.Source
    $dst = Join-Path $RootDir $entry.Target
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "FAIL: canonical missing: $($entry.Source)" -ForegroundColor Red
        $drift = 1
        continue
    }
    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) {
        Write-Host "FAIL: mirror missing: $($entry.Target)" -ForegroundColor Red
        $drift = 1
        continue
    }
    $srcText = Normalize-ReferenceText (Get-ReferenceText -Path $src -Mode $entry.Mode -Side source)
    $dstText = Normalize-ReferenceText (Get-ReferenceText -Path $dst -Mode $entry.Mode -Side target)
    if ($srcText -ne $dstText) {
        Write-Host "FAIL: drift detected: $($entry.Target) (source: $($entry.Source), mode: $($entry.Mode))" -ForegroundColor Red
        $drift = 1
    }
}

if ($drift -eq 0) {
    Write-Host "check_references: OK ($($entries.Count) mapped mirrors match)"
    exit 0
}

Write-Host ""
Write-Host "check_references: drift detected. Run scripts/sync_references.ps1 to regenerate mirrors." -ForegroundColor Yellow
exit 2
