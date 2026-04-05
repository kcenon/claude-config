#Requires -Version 7.0
# CommonHelpers.psm1 — Shared PowerShell module for claude-config scripts
# Ported from bash utility functions used across all hook and utility scripts.

# ──────────────────────────────────────────────────────────────
# Group 1: Message Functions
# Replaces bash info(), success(), warning(), error()
# ──────────────────────────────────────────────────────────────

function Write-InfoMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-SuccessMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

# ──────────────────────────────────────────────────────────────
# Group 2: Hook Response Builders
# Replaces bash deny_response(), allow_response()
# ──────────────────────────────────────────────────────────────

function New-HookDenyResponse {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string]$EventName = 'PreToolUse'
    )
    $response = @{
        hookSpecificOutput = @{
            hookEventName           = $EventName
            permissionDecision       = 'deny'
            permissionDecisionReason = $Reason
        }
    }
    return ($response | ConvertTo-Json -Depth 3 -Compress)
}

function New-HookAllowResponse {
    param(
        [string]$AdditionalContext = '',
        [string]$EventName = 'PreToolUse'
    )
    $output = @{
        hookEventName      = $EventName
        permissionDecision = 'allow'
    }
    if ($AdditionalContext) {
        $output['additionalContext'] = $AdditionalContext
    }
    $response = @{ hookSpecificOutput = $output }
    return ($response | ConvertTo-Json -Depth 3 -Compress)
}

function New-HookWarningResponse {
    param(
        [Parameter(Mandatory)][string]$Warning,
        [string]$EventName = 'UserPromptSubmit'
    )
    $response = @{
        hookSpecificOutput = @{
            hookEventName     = $EventName
            additionalContext = $Warning
        }
    }
    return ($response | ConvertTo-Json -Depth 3 -Compress)
}

# ──────────────────────────────────────────────────────────────
# Group 3: Hook Input Reader
# Replaces bash INPUT=$(cat) + jq parsing
# ──────────────────────────────────────────────────────────────

function Read-HookInput {
    <#
    .SYNOPSIS
        Reads JSON from stdin and returns a PSCustomObject.
    .DESCRIPTION
        Replacement for the bash pattern: INPUT=$(cat); echo "$INPUT" | jq -r '.field'
        Returns $null if stdin is empty or contains invalid JSON.
    #>
    try {
        if ([Console]::IsInputRedirected) {
            $raw = [Console]::In.ReadToEnd()
            if ([string]::IsNullOrWhiteSpace($raw)) {
                return $null
            }
            return ($raw | ConvertFrom-Json)
        }
        return $null
    }
    catch {
        return $null
    }
}

# ──────────────────────────────────────────────────────────────
# Group 4: Platform Detection
# Replaces bash uname -s + case statement
# ──────────────────────────────────────────────────────────────

function Get-Platform {
    <#
    .SYNOPSIS
        Returns 'Windows', 'macOS', or 'Linux'.
    #>
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'macOS' }
    if ($IsLinux)    { return 'Linux' }
    return 'Unknown'
}

function Get-EnterprisePath {
    <#
    .SYNOPSIS
        Returns the enterprise config directory path per platform.
    #>
    switch (Get-Platform) {
        'Windows' { return Join-Path $env:ProgramFiles 'ClaudeCode' }
        'macOS'   { return '/Library/Application Support/ClaudeCode' }
        'Linux'   { return '/etc/claude-code' }
        default   { return '/etc/claude-code' }
    }
}

# ──────────────────────────────────────────────────────────────
# Group 5: Version Comparison
# Replaces bash sort -V -C trick
# ──────────────────────────────────────────────────────────────

function Compare-SemanticVersion {
    <#
    .SYNOPSIS
        Compares two semantic version strings.
    .OUTPUTS
        -1 if Version1 < Version2, 0 if equal, 1 if Version1 > Version2.
    #>
    param(
        [Parameter(Mandatory)][string]$Version1,
        [Parameter(Mandatory)][string]$Version2
    )
    # Strip leading 'v' if present
    $v1 = $Version1 -replace '^v', ''
    $v2 = $Version2 -replace '^v', ''

    try {
        $sv1 = [System.Version]::new($v1)
        $sv2 = [System.Version]::new($v2)
        return $sv1.CompareTo($sv2)
    }
    catch {
        # Fallback: string comparison
        return [string]::Compare($v1, $v2, [System.StringComparison]::Ordinal)
    }
}

function Test-VersionGte {
    <#
    .SYNOPSIS
        Returns $true if Version1 >= Version2.
    #>
    param(
        [Parameter(Mandatory)][string]$Version1,
        [Parameter(Mandatory)][string]$Version2
    )
    return (Compare-SemanticVersion -Version1 $Version1 -Version2 $Version2) -ge 0
}

# ──────────────────────────────────────────────────────────────
# Group 6: File Utilities
# Replaces bash stat -f%z / stat -c%s
# ──────────────────────────────────────────────────────────────

function Get-FileSizeBytes {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0
    }
    return (Get-Item -LiteralPath $Path).Length
}

# ──────────────────────────────────────────────────────────────
# Group 7: Log Rotation
# Ported from global/hooks/lib/rotate.sh
# ──────────────────────────────────────────────────────────────

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Rotates a log file when it exceeds the size limit.
    .DESCRIPTION
        Port of rotate_log() from rotate.sh.
        Uses .NET GZipStream instead of external gzip command.
    .PARAMETER FilePath
        Path to the log file to rotate.
    .PARAMETER MaxMB
        Rotate when file exceeds this size in megabytes. Default: 10.
    .PARAMETER MaxArchives
        Keep at most this many .N.gz archives. Default: 5.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [int]$MaxMB = 10,
        [int]$MaxArchives = 5
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return
    }

    $sizeBytes = (Get-Item -LiteralPath $FilePath).Length
    $maxBytes = $MaxMB * 1024 * 1024

    if ($sizeBytes -le $maxBytes) {
        return
    }

    # Shift existing archives: .4.gz -> .5.gz, .3.gz -> .4.gz, ...
    for ($i = $MaxArchives; $i -gt 1; $i--) {
        $prev = $i - 1
        $prevArchive = "${FilePath}.${prev}.gz"
        if (Test-Path -LiteralPath $prevArchive) {
            if ($i -gt $MaxArchives) {
                Remove-Item -LiteralPath $prevArchive -Force
            }
            else {
                $targetArchive = "${FilePath}.${i}.gz"
                Move-Item -LiteralPath $prevArchive -Destination $targetArchive -Force
            }
        }
    }

    # Compress current file to .1.gz using .NET GZipStream
    try {
        $sourceBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $gzPath = "${FilePath}.1.gz"
        $fileStream = [System.IO.File]::Create($gzPath)
        $gzStream = [System.IO.Compression.GZipStream]::new(
            $fileStream,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
        $gzStream.Write($sourceBytes, 0, $sourceBytes.Length)
        $gzStream.Dispose()
        $fileStream.Dispose()
    }
    catch {
        return
    }

    # Truncate the original file
    Clear-Content -LiteralPath $FilePath

    # Remove archives beyond max count
    $j = $MaxArchives + 1
    while (Test-Path -LiteralPath "${FilePath}.${j}.gz") {
        Remove-Item -LiteralPath "${FilePath}.${j}.gz" -Force
        $j++
    }
}

# ──────────────────────────────────────────────────────────────
# Group 8: Banner / Header Printer
# Replaces bash box-drawing character banners
# ──────────────────────────────────────────────────────────────

function Write-Banner {
    <#
    .SYNOPSIS
        Prints a box-drawing banner used by utility scripts.
    #>
    param([Parameter(Mandatory)][string]$Title)
    $width = 63
    $padding = $width - $Title.Length - 2
    if ($padding -lt 0) { $padding = 0 }
    $left = [math]::Floor($padding / 2)
    $right = [math]::Ceiling($padding / 2)

    Write-Host ""
    Write-Host "`u{2554}$('═' * $width)`u{2557}" -ForegroundColor Cyan
    Write-Host "`u{2551}$(' ' * $left) $Title $(' ' * $right)`u{2551}" -ForegroundColor Cyan
    Write-Host "`u{255A}$('═' * $width)`u{255D}" -ForegroundColor Cyan
    Write-Host ""
}

# ──────────────────────────────────────────────────────────────
# Group 9: TTY Detection
# Replaces bash [[ -t 1 ]]
# ──────────────────────────────────────────────────────────────

function Test-InteractiveTerminal {
    <#
    .SYNOPSIS
        Returns $true if stdout is connected to a terminal.
    #>
    return -not [Console]::IsOutputRedirected
}

# ──────────────────────────────────────────────────────────────
# Group 10: Prerequisite Checker
# Replaces bash command -v checks
# ──────────────────────────────────────────────────────────────

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Checks that required commands are available.
    .PARAMETER Commands
        Array of command names to check.
    .OUTPUTS
        Returns $true if all commands are found, $false otherwise.
        Writes error messages for missing commands.
    #>
    param([Parameter(Mandatory)][string[]]$Commands)
    $allFound = $true
    foreach ($cmd in $Commands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-ErrorMessage "'$cmd' is not installed or not in PATH."
            $allFound = $false
        }
    }

    # Special check: gh auth status
    if ($Commands -contains 'gh' -and $allFound) {
        try {
            $null = & gh auth status 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMessage "gh CLI is not authenticated. Run 'gh auth login' first."
                $allFound = $false
            }
        }
        catch {
            Write-ErrorMessage "gh CLI authentication check failed."
            $allFound = $false
        }
    }
    return $allFound
}

# ──────────────────────────────────────────────────────────────
# Group 11: GitHub Repo Detection
# Replaces bash gh repo view detection
# ──────────────────────────────────────────────────────────────

function Get-GitHubRepo {
    <#
    .SYNOPSIS
        Auto-detects the GitHub repo (owner/name) from the current git directory.
    #>
    try {
        $repo = & gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
            return $null
        }
        return $repo.Trim()
    }
    catch {
        return $null
    }
}

# ──────────────────────────────────────────────────────────────
# Group 12: Administrator Check
# Replaces bash sudo permission checks
# ──────────────────────────────────────────────────────────────

function Test-Administrator {
    <#
    .SYNOPSIS
        Returns $true if the current process has administrator/root privileges.
    #>
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    else {
        # macOS / Linux: check if running as root
        return ((& id -u 2>$null) -eq '0')
    }
}

# ──────────────────────────────────────────────────────────────
# Group 13: Ensure Directory
# Replaces bash mkdir -p
# ──────────────────────────────────────────────────────────────

function Ensure-Directory {
    <#
    .SYNOPSIS
        Creates a directory if it does not exist. Returns the path.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
    return $Path
}

# ──────────────────────────────────────────────────────────────
# Export all functions
# ──────────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Write-InfoMessage'
    'Write-SuccessMessage'
    'Write-WarningMessage'
    'Write-ErrorMessage'
    'New-HookDenyResponse'
    'New-HookAllowResponse'
    'New-HookWarningResponse'
    'Read-HookInput'
    'Get-Platform'
    'Get-EnterprisePath'
    'Compare-SemanticVersion'
    'Test-VersionGte'
    'Get-FileSizeBytes'
    'Invoke-LogRotation'
    'Write-Banner'
    'Test-InteractiveTerminal'
    'Test-Prerequisites'
    'Get-GitHubRepo'
    'Test-Administrator'
    'Ensure-Directory'
)
