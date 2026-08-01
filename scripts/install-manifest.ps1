# install-manifest.ps1
# PowerShell counterpart of scripts/install-manifest.sh.
# Provides Invoke-GuardedCopy for preserving local customizations across
# re-installs of bootstrap.ps1.
#
# Usage (dot-source):
#   . "$InstallDir/scripts/install-manifest.ps1"
#   Invoke-GuardedCopy -Src $src -Dest $dest -Key $key
#
# Environment:
#   MANIFEST_PATH    override manifest location
#   BOOTSTRAP_FORCE  "1" bypasses the divergence prompt and overwrites

$script:ManifestSchema = 1
$script:ManifestManagedKeys = @()

function Get-ManifestPath {
    if ($env:MANIFEST_PATH) { return $env:MANIFEST_PATH }
    return (Join-Path $HOME '.claude' '.install-manifest.json')
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-FileSha256LfNormalized {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $content = [System.IO.File]::ReadAllText($Path)
    $normalized = $content -replace "`r", ''
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ManifestWindowsPlatform {
    $isWindowsVariable = Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue
    if ($isWindowsVariable) { return [bool]$isWindowsVariable.Value }
    return ($env:OS -eq 'Windows_NT')
}

function Reset-ManifestManagedKeys {
    $script:ManifestManagedKeys = @()
}

function Add-ManifestManagedKey {
    param([Parameter(Mandatory)][string]$Key)
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $script:ManifestManagedKeys += $Key
    }
}

function Read-ManifestEntry {
    param([Parameter(Mandatory)][string]$Key)
    $files = Get-ManifestFiles
    if ($files.ContainsKey($Key)) { return [string]$files[$Key] }
    return ''
}

function Get-ManifestFiles {
    $manifestPath = Get-ManifestPath
    $files = @{}
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json -ErrorAction Stop
        }
        catch { $manifest = $null }
    }

    if ($manifest -and $manifest.files) {
        foreach ($prop in $manifest.files.PSObject.Properties) {
            $files[$prop.Name] = [string]$prop.Value
        }
    }
    return $files
}

function Write-ManifestFiles {
    param([Parameter(Mandatory)][hashtable]$Files)

    $manifestPath = Get-ManifestPath
    $dir = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $orderedFiles = [ordered]@{}
    foreach ($key in ($Files.Keys | Sort-Object)) {
        $orderedFiles[$key] = [string]$Files[$key]
    }

    $out = [ordered]@{
        schema = $script:ManifestSchema
        files  = $orderedFiles
    }
    $out | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

function Write-ManifestEntry {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Sha
    )
    $files = Get-ManifestFiles
    $files[$Key] = $Sha
    Write-ManifestFiles -Files $files
}

function Join-ManagedManifestPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Key
    )

    if ([System.IO.Path]::IsPathRooted($Key)) { return $null }

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Key))
    $comparison = if (Test-ManifestWindowsPlatform) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    if ([string]::Equals($candidate, $rootFull, $comparison)) { return $candidate }

    $rootPrefix = $rootFull.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if ($candidate.StartsWith($rootPrefix, $comparison)) { return $candidate }
    return $null
}

function Invoke-ManifestPrune {
    <#
    .SYNOPSIS
    Removes obsolete managed files when they are unchanged from the previous
    manifest entry, preserving locally edited files.
    .OUTPUTS
    PSCustomObject with Deleted, Preserved, Missing, Unsafe, and RemovedEntries.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$ManagedKeys
    )

    if (-not $ManagedKeys -or $ManagedKeys.Count -eq 0) {
        Write-Host 'Manifest prune: skipped; no current managed files'
        return [pscustomobject]@{ Deleted = 0; Preserved = 0; Missing = 0; Unsafe = 0; RemovedEntries = 0 }
    }

    $manifestPath = Get-ManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return [pscustomobject]@{ Deleted = 0; Preserved = 0; Missing = 0; Unsafe = 0; RemovedEntries = 0 }
    }

    $files = Get-ManifestFiles
    if ($files.Count -eq 0) {
        return [pscustomobject]@{ Deleted = 0; Preserved = 0; Missing = 0; Unsafe = 0; RemovedEntries = 0 }
    }

    $comparison = if (Test-ManifestWindowsPlatform) {
        [System.StringComparer]::OrdinalIgnoreCase
    } else {
        [System.StringComparer]::Ordinal
    }
    $managed = [System.Collections.Generic.HashSet[string]]::new($comparison)
    foreach ($key in $ManagedKeys) {
        if (-not [string]::IsNullOrWhiteSpace($key)) { [void]$managed.Add($key) }
    }

    $deleted = 0
    $preserved = 0
    $missing = 0
    $unsafe = 0
    $removedEntries = 0
    $changed = $false

    foreach ($key in @($files.Keys | Sort-Object)) {
        if ($managed.Contains($key)) { continue }

        $path = Join-ManagedManifestPath -Root $Root -Key $key
        if (-not $path) {
            Write-Host "Manifest prune: skipped unsafe obsolete path: $key"
            $unsafe++
            continue
        }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "Manifest prune: removed stale manifest entry for missing file: $key"
            $files.Remove($key)
            $missing++
            $removedEntries++
            $changed = $true
            continue
        }

        $currentSha = Get-FileSha256 -Path $path
        $storedSha = [string]$files[$key]
        if ($currentSha -and $storedSha -and ($currentSha -eq $storedSha)) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "Manifest prune: deleted obsolete managed file: $key"
            $files.Remove($key)
            $deleted++
            $removedEntries++
            $changed = $true
        } else {
            Write-Host "Manifest prune: preserved locally modified obsolete file: $key"
            $preserved++
        }
    }

    if ($changed) { Write-ManifestFiles -Files $files }

    return [pscustomobject]@{
        Deleted        = $deleted
        Preserved      = $preserved
        Missing        = $missing
        Unsafe         = $unsafe
        RemovedEntries = $removedEntries
    }
}

function Invoke-ManifestPruneTracked {
    param([Parameter(Mandatory)][string]$Root)
    return Invoke-ManifestPrune -Root $Root -ManagedKeys $script:ManifestManagedKeys
}

function Invoke-ManifestTrackedCopy {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { return $true }
    $destDir = Split-Path -Parent $Dest
    if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $result = Invoke-GuardedCopy -Src $Src -Dest $Dest -Key $Key
    Add-ManifestManagedKey -Key $Key
    return $result
}

function Copy-ManifestFiles {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][AllowEmptyString()][string]$KeyPrefix,
        [Parameter(Mandatory)][string[]]$Filters
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    if (-not (Test-Path -LiteralPath $DestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    foreach ($filter in $Filters) {
        Get-ChildItem -LiteralPath $SourceDir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
            $key = if ([string]::IsNullOrEmpty($KeyPrefix)) {
                $_.Name
            } else {
                (($KeyPrefix, $_.Name) -join '/') -replace '\\', '/'
            }
            $null = Invoke-ManifestTrackedCopy -Src $_.FullName -Dest (Join-Path $DestinationDir $_.Name) -Key $key
        }
    }
}

function Copy-ManifestTree {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][AllowEmptyString()][string]$KeyPrefix
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    if (-not (Test-Path -LiteralPath $DestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $sourceRoot = [System.IO.Path]::GetFullPath($SourceDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    Get-ChildItem -LiteralPath $SourceDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        $rel = $full.Substring($sourceRoot.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $relKey = $rel -replace '\\', '/'
        $key = if ([string]::IsNullOrEmpty($KeyPrefix)) {
            $relKey
        } else {
            (($KeyPrefix, $relKey) -join '/') -replace '\\', '/'
        }
        $dest = Join-Path $DestinationDir $rel
        $null = Invoke-ManifestTrackedCopy -Src $_.FullName -Dest $dest -Key $key
    }
}

function Add-RetiredManagedManifestEntries {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][hashtable]$Entries
    )

    foreach ($key in ($Entries.Keys | Sort-Object)) {
        if (Read-ManifestEntry -Key $key) { continue }

        $path = Join-ManagedManifestPath -Root $Root -Key $key
        if (-not $path) {
            Write-Host "Manifest prune: skipped unsafe retired path: $key"
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        $currentSha = Get-FileSha256 -Path $path
        $currentLfSha = Get-FileSha256LfNormalized -Path $path
        $retiredSha = [string]$Entries[$key]
        if ($currentSha -and ($currentSha -eq $retiredSha)) {
            Write-ManifestEntry -Key $key -Sha $retiredSha
            Write-Host "Manifest prune: matched retired managed file: $key"
        } elseif ($currentSha -and $currentLfSha -and ($currentLfSha -eq $retiredSha)) {
            Write-ManifestEntry -Key $key -Sha $currentSha
            Write-Host "Manifest prune: matched retired managed file: $key"
        } else {
            Write-Host "Manifest prune: preserved locally edited retired file: $key"
        }
    }
}

function Invoke-GuardedCopy {
    <#
    .SYNOPSIS
    Copies Src to Dest with manifest-based preservation of local edits.
    .OUTPUTS
    System.Boolean. $true when the file was copied (or no change was
    needed), $false when the local file was kept by user choice.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not (Test-Path -LiteralPath $Src)) { return $true }

    # Fresh install for this destination.
    if (-not (Test-Path -LiteralPath $Dest)) {
        Copy-Item -LiteralPath $Src -Destination $Dest -Force
        $sha = Get-FileSha256 -Path $Src
        if ($sha) { Write-ManifestEntry -Key $Key -Sha $sha }
        return $true
    }

    $srcSha    = Get-FileSha256 -Path $Src
    $destSha   = Get-FileSha256 -Path $Dest
    $storedSha = Read-ManifestEntry -Key $Key

    if ($srcSha -and ($srcSha -eq $destSha)) {
        if (-not $storedSha) { Write-ManifestEntry -Key $Key -Sha $srcSha }
        return $true
    }

    if ($storedSha -and ($destSha -eq $storedSha)) {
        Copy-Item -LiteralPath $Src -Destination $Dest -Force
        Write-ManifestEntry -Key $Key -Sha $srcSha
        return $true
    }

    # Divergence: destination differs from both source and stored hash.
    if ($env:BOOTSTRAP_FORCE -eq '1') {
        Copy-Item -LiteralPath $Src -Destination $Dest -Force
        Write-ManifestEntry -Key $Key -Sha $srcSha
        return $true
    }

    Write-Host ''
    Write-Host "  Local changes detected in: $Dest"
    Write-Host '  Incoming version differs from both local and the last install.'
    $choice = Read-Host '  [k]eep local / [o]verwrite (default: keep)'
    if ([string]::IsNullOrEmpty($choice)) { $choice = 'k' }

    if ($choice -match '^[oO]$') {
        Copy-Item -LiteralPath $Src -Destination $Dest -Force
        Write-ManifestEntry -Key $Key -Sha $srcSha
        return $true
    }

    return $false
}

function Invoke-GuardedTemplateCopy {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$SrcTmpl,
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$DisplayLang
    )

    if (-not (Test-Path -LiteralPath $SrcTmpl)) { return $true }

    $tmpLang = Join-Path ([System.IO.Path]::GetTempPath()) "conversation-language_$([guid]::NewGuid()).md"
    $tmplContent = [System.IO.File]::ReadAllText($SrcTmpl)
    $rendered = $tmplContent -replace '\{\{AGENT_LANGUAGE_POLICY\}\}', $DisplayLang
    # Strip the developer-only tmpl-contract comment line so it does not leak into the rendered .md (issue #773, parity with #771).
    $rendered = (($rendered -split "`n") | Where-Object { $_ -notmatch 'tmpl-contract' }) -join "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tmpLang, $rendered, $utf8NoBom)
    
    $result = Invoke-GuardedCopy -Src $tmpLang -Dest $Dest -Key $Key
    
    Remove-Item -LiteralPath $tmpLang -Force -ErrorAction SilentlyContinue
    return $result
}

function Update-ClaudeSettingsJson {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$AgentLang,
        [Parameter(Mandatory)][string]$ContentLang
    )

    if (-not (Test-Path -LiteralPath $SettingsPath)) { return $true }

    try {
        $settingsObj = Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json
        
        # Update agent language
        if ($settingsObj.PSObject.Properties.Name -contains 'language') {
            $settingsObj.language = $AgentLang
        } else {
            $settingsObj | Add-Member -NotePropertyName 'language' -NotePropertyValue $AgentLang -Force
        }

        if ($ContentLang -ne 'english') {
            if (-not ($settingsObj.PSObject.Properties.Name -contains 'env')) {
                $settingsObj | Add-Member -NotePropertyName 'env' -NotePropertyValue ([PSCustomObject]@{})
            }
            if (-not $settingsObj.env) {
                $settingsObj.env = [PSCustomObject]@{}
            }
            if ($settingsObj.env.PSObject.Properties.Name -contains 'CLAUDE_CONTENT_LANGUAGE') {
                $settingsObj.env.CLAUDE_CONTENT_LANGUAGE = $ContentLang
            } else {
                $settingsObj.env | Add-Member -NotePropertyName 'CLAUDE_CONTENT_LANGUAGE' -NotePropertyValue $ContentLang -Force
            }
        } else {
            # Idempotent reset for english policy
            if (($settingsObj.PSObject.Properties.Name -contains 'env') -and ($settingsObj.env)) {
                if ($settingsObj.env.PSObject.Properties.Name -contains 'CLAUDE_CONTENT_LANGUAGE') {
                    $settingsObj.env.PSObject.Properties.Remove('CLAUDE_CONTENT_LANGUAGE')
                    
                    # If env is now empty, remove it entirely to keep settings.json clean
                    if (@($settingsObj.env.PSObject.Properties).Count -eq 0) {
                        $settingsObj.PSObject.Properties.Remove('env')
                    }
                }
            }
        }

        ($settingsObj | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}
