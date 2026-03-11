# markdown-anchor-validator.ps1
# Validates markdown anchor references before git commit
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=deny (broken anchors found)
# Response format: hookSpecificOutput (modern format)

$ErrorActionPreference = 'Stop'

$CMD = $env:CLAUDE_TOOL_INPUT

# Only check git commit commands
if ($CMD -notmatch 'git\s+commit') {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Auto-detect markdown directory
if (Test-Path 'docs/reference' -PathType Container) {
    $DocsDir = 'docs/reference'
} elseif (Test-Path 'docs' -PathType Container) {
    $DocsDir = 'docs'
} else {
    $DocsDir = '.'
}

# Collect markdown files
$MdFiles = Get-ChildItem -Path $DocsDir -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName

if (-not $MdFiles -or $MdFiles.Count -eq 0) {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Generate GitHub-style anchor from heading text
# Algorithm: strip formatting -> lowercase -> remove non-alnum/space/hyphen (keep Unicode) -> spaces to hyphens -> collapse
function Get-Anchor {
    param([string]$Text)
    # Strip inline formatting: bold, italic, code, links, HTML tags
    $Text = $Text -replace '\*\*([^*]+)\*\*', '$1'
    $Text = $Text -replace '\*([^*]+)\*', '$1'
    $Text = $Text -replace '`([^`]+)`', '$1'
    $Text = $Text -replace '\[([^\]]+)\]\([^)]*\)', '$1'
    $Text = $Text -replace '<[^>]+>', ''
    # Lowercase
    $Text = $Text.ToLower()
    # Remove non-alnum/space/hyphen/underscore (keep Unicode letters and digits via \p{L}\p{N})
    $Text = $Text -replace '[^\p{L}\p{N}\p{Pc} -]', ''
    # Spaces to hyphens
    $Text = $Text -replace ' ', '-'
    # NOTE: GitHub does NOT collapse consecutive hyphens (e.g., "A / B" -> "a--b")
    # Trim leading/trailing hyphens
    $Text = $Text.Trim('-')
    return $Text
}

# Helper: get relative path from current directory with forward slashes
function Get-RelativePath {
    param([string]$FullPath)
    $rel = Resolve-Path -Relative $FullPath -ErrorAction SilentlyContinue
    if (-not $rel) { $rel = $FullPath }
    $rel = $rel -replace '^\.[\\/]', ''
    $rel = $rel -replace '\\', '/'
    return $rel
}

# === Pass 1: Build anchor registry ===
# Key format: "filepath::anchor" -> $true
$Anchors = @{}
$AnchorCounts = @{}

foreach ($file in $MdFiles) {
    $relativePath = Get-RelativePath $file.FullName
    $inCodeBlock = $false
    $lines = Get-Content -Path $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue

    foreach ($line in $lines) {
        # Toggle code block state on ``` or ~~~ delimiters
        if ($line -match '^\s*(```|~~~)') {
            $inCodeBlock = -not $inCodeBlock
            continue
        }
        if ($inCodeBlock) { continue }

        # Match heading lines (# through ######)
        if ($line -match '^#{1,6}\s+(.+)') {
            $heading = $Matches[1] -replace '[\s#]+$', ''
            $anchor = Get-Anchor $heading
            if ([string]::IsNullOrEmpty($anchor)) { continue }

            # Handle duplicate anchors (GitHub appends -1, -2, etc.)
            $countKey = "${relativePath}::${anchor}"
            if ($AnchorCounts.ContainsKey($countKey)) {
                $AnchorCounts[$countKey]++
                $Anchors["${relativePath}::${anchor}-$($AnchorCounts[$countKey])"] = $true
            } else {
                $AnchorCounts[$countKey] = 0
                $Anchors["${relativePath}::${anchor}"] = $true
            }
        }
    }
}

# === Pass 2: Check references ===
$Errors = [System.Collections.Generic.List[string]]::new()

foreach ($file in $MdFiles) {
    $relativePath = Get-RelativePath $file.FullName
    $inCodeBlock = $false
    $lines = Get-Content -Path $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    $lineNum = 0

    foreach ($line in $lines) {
        $lineNum++

        # Toggle code block state
        if ($line -match '^\s*(```|~~~)') {
            $inCodeBlock = -not $inCodeBlock
            continue
        }
        if ($inCodeBlock) { continue }

        # Intra-file references: ](#anchor)
        $intraRefs = [regex]::Matches($line, '\]\(#([^)]+)\)')
        foreach ($m in $intraRefs) {
            $anchor = $m.Groups[1].Value
            $key = "${relativePath}::${anchor}"
            if (-not $Anchors.ContainsKey($key)) {
                $fileName = Split-Path $relativePath -Leaf
                $Errors.Add("${fileName}:${lineNum}: #${anchor}")
            }
        }

        # Inter-file references: ](path.md#anchor) — excludes URLs (no colon before .md)
        $interRefs = [regex]::Matches($line, '\]\(([^:)#]*\.md)#([^)]+)\)')
        foreach ($m in $interRefs) {
            $refFile = $m.Groups[1].Value -replace '^\.\/', ''
            $anchor = $m.Groups[2].Value

            # Resolve relative to current file's directory
            $dir = Split-Path $relativePath -Parent
            if ([string]::IsNullOrEmpty($dir)) {
                $target = $refFile
            } else {
                $target = "${dir}/${refFile}"
            }
            $target = $target -replace '\\', '/' -replace '/\./', '/'

            $key = "${target}::${anchor}"
            if (-not $Anchors.ContainsKey($key)) {
                $fileName = Split-Path $relativePath -Leaf
                $Errors.Add("${fileName}:${lineNum}: ${refFile}#${anchor}")
            }
        }
    }
}

# === Output ===
if ($Errors.Count -eq 0) {
    '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
}

# Build error message
$errorList = ($Errors | ForEach-Object { "  - $_" }) -join '\n'
$reason = "Broken markdown anchor(s) found:\n${errorList}\n\nFix the anchors or update the references before committing."
# Escape double quotes for JSON
$reason = $reason -replace '"', '\"'

@"
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
"@
exit 2
