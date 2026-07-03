# Sync mapped canonical reference files to mirror locations.
#
# Usage: pwsh scripts/sync_references.ps1 [repo-root] [reference-map.yml]

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
        [string]$Mode
    )

    $text = Get-Content -Raw -LiteralPath $Path
    if ($Mode -eq 'exact') {
        return $text
    }
    if ($Mode -ne 'strip-source-frontmatter') {
        throw "unsupported reference sync mode: $Mode"
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

$entries = @(Read-ReferenceMap -Path $MapFile)
if ($entries.Count -eq 0) {
    Write-Error "no references declared in $MapFile"
    exit 1
}

foreach ($entry in $entries) {
    $src = Join-Path $RootDir $entry.Source
    $dst = Join-Path $RootDir $entry.Target
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Error "canonical file missing: $($entry.Source)"
        exit 1
    }
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }

    $content = Get-ReferenceText -Path $src -Mode $entry.Mode
    [System.IO.File]::WriteAllText($dst, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "synced: $($entry.Source) -> $($entry.Target) ($($entry.Mode))"
}

Write-Host "sync_references: done ($($entries.Count) mapped mirrors)"
