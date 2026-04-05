#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# markdown-anchor-validator.ps1
# Validates markdown anchor references in git-staged files before commit
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Performance: Uses single-pass line-by-line extraction with hashtable registry
# to minimize overhead. Port of bash awk-based single-pass approach.

# Read input from stdin (Claude Code passes JSON via stdin)
$json = Read-HookInput

$CMD = $null
try {
    $CMD = $json.tool_input.command
} catch {}
# Fallback to environment variable for backward compatibility
if ([string]::IsNullOrEmpty($CMD)) {
    $CMD = $env:CLAUDE_TOOL_INPUT
}

# Only check git commit commands
if ($CMD -notmatch 'git\s+commit') {
    New-HookAllowResponse
    exit 0
}

# Get only staged markdown files (deleted files excluded via --diff-filter=d)
$stagedFiles = @()
try {
    $staged = & git diff --cached --name-only --diff-filter=d -- '*.md' 2>$null
    if ($staged) {
        $stagedFiles = @($staged | ForEach-Object {
            $path = $_.Trim()
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { $path }
        } | Where-Object { $_ })
    }
} catch {
    # git not available or not in a repo
}

if ($stagedFiles.Count -eq 0) {
    New-HookAllowResponse
    exit 0
}

# === ConvertTo-GitHubAnchor: Transform heading text to GitHub-style anchor ===
# Strip markdown formatting, lowercase, remove non-alnum except spaces/hyphens/underscores,
# spaces to hyphens. IMPORTANT: Do NOT collapse consecutive hyphens.
function ConvertTo-GitHubAnchor {
    param([string]$Text)
    # Strip markdown link formatting: [text](url) -> text
    $Text = $Text -replace '\](\([^)]*\))', ''
    $Text = $Text -replace '\[', ''
    # Strip bold/italic markers
    $Text = $Text -replace '\*', ''
    # Strip inline code
    $Text = $Text -replace '`', ''
    # Strip HTML tags
    $Text = $Text -replace '<[^>]*>', ''
    # Lowercase
    $Text = $Text.ToLower()
    # Remove non-alphanumeric except spaces, hyphens, underscores
    # Use Unicode-aware character classes to preserve Korean etc.
    $Text = $Text -replace '[^\p{L}\p{N}\p{Pc} -]', ''
    # Spaces to hyphens (do NOT collapse consecutive hyphens)
    $Text = $Text -replace ' ', '-'
    # Trim leading/trailing hyphens
    $Text = $Text.Trim('-')
    return $Text
}

# === Get-MarkdownReferences: Single-pass extraction of headings and references ===
# Returns hashtable with keys: Headings (list), IntraRefs (list), InterRefs (list)
function Get-MarkdownReferences {
    param([string]$FilePath)

    $result = @{
        Headings  = [System.Collections.Generic.List[string]]::new()
        IntraRefs = [System.Collections.Generic.List[object]]::new()
        InterRefs = [System.Collections.Generic.List[object]]::new()
    }

    $lines = Get-Content -Path $FilePath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { return $result }

    $inCodeBlock = $false
    $lineNum = 0

    foreach ($line in $lines) {
        $lineNum++

        # Track code fence state
        if ($line -match '^\s*(```|~~~)') {
            $inCodeBlock = -not $inCodeBlock
            continue
        }
        if ($inCodeBlock) { continue }

        # Extract headings (^#{1,6}\s)
        if ($line -match '^#{1,6}\s+(.+)') {
            $headingText = $Matches[1] -replace '[\s#]+$', ''
            if ($headingText) {
                $result.Headings.Add($headingText)
            }
        }

        # Extract intra-file references: ](#anchor)
        $intraMatches = [regex]::Matches($line, '\]\(#([^)]+)\)')
        foreach ($m in $intraMatches) {
            $result.IntraRefs.Add(@{
                LineNum = $lineNum
                Anchor  = $m.Groups[1].Value
            })
        }

        # Extract inter-file references: ](path.md#anchor) — exclude URLs (no colon in path)
        $interMatches = [regex]::Matches($line, '\]\(([^:)#]*\.md)#([^)]+)\)')
        foreach ($m in $interMatches) {
            $result.InterRefs.Add(@{
                LineNum = $lineNum
                RefFile = $m.Groups[1].Value -replace '^\.\/', ''
                Anchor  = $m.Groups[2].Value
            })
        }
    }

    return $result
}

# === Build anchor registry ===
$Anchors = @{}
$AnchorCounts = @{}

foreach ($filePath in $stagedFiles) {
    $relPath = $filePath -replace '\\', '/'
    $refs = Get-MarkdownReferences -FilePath $filePath

    foreach ($headingText in $refs.Headings) {
        $anchor = ConvertTo-GitHubAnchor -Text $headingText
        if ([string]::IsNullOrEmpty($anchor)) { continue }

        $countKey = "${relPath}::${anchor}"
        if ($AnchorCounts.ContainsKey($countKey)) {
            $AnchorCounts[$countKey]++
            $Anchors["${relPath}::${anchor}-$($AnchorCounts[$countKey])"] = $true
        } else {
            $AnchorCounts[$countKey] = 0
            $Anchors["${relPath}::${anchor}"] = $true
        }
    }
}

# === Check references ===
$Errors = [System.Collections.Generic.List[string]]::new()

foreach ($filePath in $stagedFiles) {
    $relPath = $filePath -replace '\\', '/'
    $refs = Get-MarkdownReferences -FilePath $filePath

    # Check intra-file references
    foreach ($ref in $refs.IntraRefs) {
        $key = "${relPath}::$($ref.Anchor)"
        if (-not $Anchors.ContainsKey($key)) {
            $fileName = Split-Path $relPath -Leaf
            $Errors.Add("${fileName}:$($ref.LineNum): #$($ref.Anchor)")
        }
    }

    # Check inter-file references
    foreach ($ref in $refs.InterRefs) {
        $dir = Split-Path $relPath -Parent
        if ([string]::IsNullOrEmpty($dir)) { $dir = '.' }
        $target = "${dir}/$($ref.RefFile)" -replace '\\', '/' -replace '/\./', '/'

        $key = "${target}::$($ref.Anchor)"
        if (-not $Anchors.ContainsKey($key)) {
            $fileName = Split-Path $relPath -Leaf
            $Errors.Add("${fileName}:$($ref.LineNum): $($ref.RefFile)#$($ref.Anchor)")
        }
    }
}

# === Output ===
if ($Errors.Count -eq 0) {
    New-HookAllowResponse
    exit 0
}

# Build error message
$errorList = ($Errors | Select-Object -First 20 | ForEach-Object { "  - $_" }) -join "`n"
$more = if ($Errors.Count -gt 20) { "`n  ... and $($Errors.Count - 20) more" } else { '' }
$reason = "Broken markdown anchor(s) found:`n${errorList}${more}`n`nFix the anchors or update the references before committing."

New-HookDenyResponse -Reason $reason
exit 0
