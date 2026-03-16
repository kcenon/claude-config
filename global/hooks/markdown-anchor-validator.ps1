# markdown-anchor-validator.ps1
# Validates markdown anchor references in git-staged files before commit
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=deny (broken anchors found)
# Response format: hookSpecificOutput (modern format)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read hook input from stdin
$inputJson = $input | Out-String
try {
    $hookData = $inputJson | ConvertFrom-Json
    $CMD = $hookData.tool_input.command
} catch {
    $CMD = ""
}

# Only check git commit commands
if ($CMD -notmatch 'git\s+commit') {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Get only staged markdown files
$stagedFiles = @()
try {
    $staged = & git diff --cached --name-only --diff-filter=ACM 2>/dev/null
    $stagedFiles = $staged | Where-Object { $_ -match '\.md$' } | ForEach-Object {
        $path = $_.Trim()
        if ($path -and (Test-Path $path -PathType Leaf)) { $path }
    }
} catch {
    # git not available or not in a repo
}

if (-not $stagedFiles -or $stagedFiles.Count -eq 0) {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Generate GitHub-style anchor from heading text
function Get-Anchor {
    param([string]$Text)
    $Text = $Text -replace '\*\*([^*]+)\*\*', '$1'
    $Text = $Text -replace '\*([^*]+)\*', '$1'
    $Text = $Text -replace '`([^`]+)`', '$1'
    $Text = $Text -replace '\[([^\]]+)\]\([^)]*\)', '$1'
    $Text = $Text -replace '<[^>]+>', ''
    $Text = $Text.ToLower()
    $Text = $Text -replace '[^\p{L}\p{N}\p{Pc} -]', ''
    $Text = $Text -replace ' ', '-'
    $Text = $Text.Trim('-')
    return $Text
}

# Helper: normalize path to forward slashes
function Get-RelPath {
    param([string]$Path)
    return $Path -replace '\\', '/'
}

# === Pass 1: Build anchor registry from staged files only ===
$Anchors = @{}
$AnchorCounts = @{}

foreach ($filePath in $stagedFiles) {
    $relPath = Get-RelPath $filePath
    $inCodeBlock = $false
    $lines = Get-Content -Path $filePath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { continue }

    foreach ($line in $lines) {
        if ($line -match '^\s*(```|~~~)') { $inCodeBlock = -not $inCodeBlock; continue }
        if ($inCodeBlock) { continue }

        if ($line -match '^#{1,6}\s+(.+)') {
            $heading = $Matches[1] -replace '[\s#]+$', ''
            $anchor = Get-Anchor $heading
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
}

# === Pass 2: Check intra-file references in staged files only ===
$Errors = [System.Collections.Generic.List[string]]::new()

foreach ($filePath in $stagedFiles) {
    $relPath = Get-RelPath $filePath
    $inCodeBlock = $false
    $lines = Get-Content -Path $filePath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { continue }
    $lineNum = 0

    foreach ($line in $lines) {
        $lineNum++
        if ($line -match '^\s*(```|~~~)') { $inCodeBlock = -not $inCodeBlock; continue }
        if ($inCodeBlock) { continue }

        # Intra-file references: ](#anchor)
        $intraRefs = [regex]::Matches($line, '\]\(#([^)]+)\)')
        foreach ($m in $intraRefs) {
            $anchor = $m.Groups[1].Value
            $key = "${relPath}::${anchor}"
            if (-not $Anchors.ContainsKey($key)) {
                $fileName = Split-Path $relPath -Leaf
                $Errors.Add("${fileName}:${lineNum}: #${anchor}")
            }
        }

        # Inter-file references to staged files: ](path.md#anchor)
        $interRefs = [regex]::Matches($line, '\]\(([^:)#]*\.md)#([^)]+)\)')
        foreach ($m in $interRefs) {
            $refFile = $m.Groups[1].Value -replace '^\.\/', ''
            $anchor = $m.Groups[2].Value

            $dir = Split-Path $relPath -Parent
            $target = if ([string]::IsNullOrEmpty($dir)) { $refFile } else { "${dir}/${refFile}" }
            $target = $target -replace '\\', '/' -replace '/\./', '/'

            # Only validate if target file is also staged
            if ($Anchors.ContainsKey("${target}::placeholder") -or
                ($stagedFiles | Where-Object { (Get-RelPath $_) -eq $target })) {
                $key = "${target}::${anchor}"
                if (-not $Anchors.ContainsKey($key)) {
                    $fileName = Split-Path $relPath -Leaf
                    $Errors.Add("${fileName}:${lineNum}: ${refFile}#${anchor}")
                }
            }
        }
    }
}

if ($Errors.Count -eq 0) {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

$errorList = ($Errors | Select-Object -First 20 | ForEach-Object { "  - $_" }) -join '\n'
$more = if ($Errors.Count -gt 20) { "\n  ... and $($Errors.Count - 20) more" } else { "" }
$reason = "Broken markdown anchor(s) in staged files:\n${errorList}${more}\n\nFix before committing."
$reason = $reason -replace '\\', '\\\\' -replace '"', '\"'

@"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
"@
exit 2
