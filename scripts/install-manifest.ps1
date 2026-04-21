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

function Get-ManifestPath {
    if ($env:MANIFEST_PATH) { return $env:MANIFEST_PATH }
    return (Join-Path $HOME '.claude' '.install-manifest.json')
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Read-ManifestEntry {
    param([Parameter(Mandatory)][string]$Key)
    $manifestPath = Get-ManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath)) { return '' }
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($m.files -and $m.files.PSObject.Properties.Name -contains $Key) {
            return [string]$m.files.$Key
        }
    }
    catch { }
    return ''
}

function Write-ManifestEntry {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Sha
    )
    $manifestPath = Get-ManifestPath
    $dir = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json -ErrorAction Stop
        }
        catch { $manifest = $null }
    }

    # Rebuild into a hashtable so updates are deterministic.
    $files = @{}
    if ($manifest -and $manifest.files) {
        foreach ($prop in $manifest.files.PSObject.Properties) {
            $files[$prop.Name] = [string]$prop.Value
        }
    }
    $files[$Key] = $Sha

    $out = [ordered]@{
        schema = $script:ManifestSchema
        files  = $files
    }
    $out | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
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
