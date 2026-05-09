# InstallerFetch.psm1 — PowerShell mirror of hooks/lib/installer-fetch.sh.
#
# Single source of truth for the supply-chain hardening contract used by
# bootstrap.ps1. The bash counterpart serves bootstrap.sh and
# scripts/install.sh; both implementations share the same exit-code
# semantics so the regression suite can exercise either side equivalently.
#
# Contract (mirror of installer-fetch.sh):
#   1. Download URL to a fresh temp file.
#   2. Compute sha256 with Get-FileHash and compare to expected pin.
#   3. On match: invoke the script (.ps1 via dot-source, .sh via bash if
#      present) and clean up the temp file.
#   4. On mismatch / download fail: return a typed exit code.
#
# Exit codes:
#   0  OK
#   10 DOWNLOAD
#   11 CHECKSUM   (Get-FileHash unexpectedly unavailable)
#   12 MISMATCH
#   13 RUN
#
# Usage:
#   Import-Module ./hooks/lib/InstallerFetch.psm1
#   Invoke-InstallerFetchVerifyRun `
#       -Url 'https://claude.ai/install.ps1' `
#       -ExpectedSha256 'acc15c3d844b8952e702a24b584d2fdc0b589ee1061c11202529cdd5702711df' `
#       -Label 'claude-installer'
#
# UX: callers may define Write-Info / Write-Ok / Write-Warn before importing;
# the module honors them if present, else falls back to Write-Host.

function Get-IfvUxAction {
    param([string]$Name, [string]$Color)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return { param($M) & $cmd $M }.GetNewClosure()
    }
    return { param($M) Write-Host "  $M" -ForegroundColor $Color }.GetNewClosure()
}

function Invoke-InstallerFetchVerifyRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Url,
        [Parameter(Mandatory = $true)] [string] $ExpectedSha256,
        [Parameter(Mandatory = $false)] [string] $Label = 'installer'
    )

    $info = Get-IfvUxAction -Name 'Write-Info' -Color 'Cyan'
    $ok   = Get-IfvUxAction -Name 'Write-Ok'   -Color 'Green'
    $warn = Get-IfvUxAction -Name 'Write-Warn' -Color 'Yellow'

    # Step 1 — download to fresh temp file. New-TemporaryFile guarantees a
    # unique path; we explicitly rename to .ps1 so dot-source resolves.
    $tmpRaw = [System.IO.Path]::GetTempFileName()
    $tmp    = "$tmpRaw.ps1"
    Rename-Item -LiteralPath $tmpRaw -NewName ([System.IO.Path]::GetFileName($tmp)) -Force

    try {
        & $info "${Label}: downloading $Url"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -ErrorAction Stop
        } catch {
            & $warn "${Label}: download failed: $($_.Exception.Message)"
            return 10
        }

        # Step 2 — sha256 verify. Get-FileHash is core in PS5+/PS7+; if it is
        # somehow unavailable we treat it as a CHECKSUM error (11).
        if (-not (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
            & $warn "${Label}: Get-FileHash not available — cannot verify integrity"
            return 11
        }

        & $info "${Label}: verifying sha256 (pin $($ExpectedSha256.Substring(0,12))...)"
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmp).Hash.ToLowerInvariant()
        $expected = $ExpectedSha256.ToLowerInvariant()
        if ($actual -ne $expected) {
            & $warn "${Label}: sha256 mismatch — installer aborted"
            & $warn "  expected: $expected"
            & $warn "  actual:   $actual"
            & $warn "  Anthropic may have rotated the script; wait for a maintainer re-pin."
            return 12
        }
        & $ok "${Label}: sha256 verified"

        # Step 3 — run the .ps1. Dot-source gives access to script-scoped
        # variables; if that is undesirable in the future, switch to a
        # fresh PowerShell sub-process.
        & $info "${Label}: running installer"
        try {
            & $tmp
        } catch {
            & $warn "${Label}: installer threw: $($_.Exception.Message)"
            return 13
        }
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            & $warn "${Label}: installer exited with code $LASTEXITCODE"
            return 13
        }
        return 0
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Invoke-InstallerFetchVerifyRun
