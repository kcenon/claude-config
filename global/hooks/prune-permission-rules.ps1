#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# prune-permission-rules.ps1
# Prunes permissions.allow entries that can never match again from the project-scope settings.local.json
# Hook Type: SessionEnd
# Input: JSON via stdin with session_id, cwd, transcript_path, hook_event_name
# Exit codes: 0=always (fail-open; teardown is never blocked)
# Response format: none (lifecycle event, no JSON output needed)
# Fail policy: fail-open - any parse, classification, or IO error leaves the file byte-identical

$MaxEntryLen = 120

# --- classification -------------------------------------------------------
#
# Removed:
#   denylisted unbounded-argument rules; entries carrying a session-scoped
#   UUID path; compound entries (`;` or `|`); over-long literals; entries
#   already subsumed by a broader Tool(prefix:*) rule in the same file.
# Kept:
#   Tool(prefix:*) rules, bare-string entries (Read, WebFetch, Skill, ...),
#   and anything not positively classified as dead.

# Unbounded-argument destructive or arbitrary-execution rules. Fixed rather
# than configurable: a per-machine list drifts, which is how this exact class
# of rule returned after the 2026-07-27 manual cleanup (#923).
#   pattern 1: `Tool(<anything> *)`  - a space before the trailing star means
#              the argument list is unbounded, e.g. PowerShell(Remove-Item *)
#   pattern 2: `Tool(<anything>':*)` - a quote immediately before `:*` anchors
#              the prefix inside a quoted string, e.g. Bash(git commit -m ':*)
function Test-Denylisted {
    param([string]$Entry)
    if ($Entry -match '^[A-Za-z][A-Za-z]*\(.+ \*\)$') { return $true }
    if ($Entry -match '^[A-Za-z][A-Za-z]*\(.*[''"]:\*\)$') { return $true }
    return $false
}

# A reusable prefix rule: ends in `:*)`. These are the entries worth keeping.
function Test-PrefixRule {
    param([string]$Entry)
    return ($Entry -match '^[A-Za-z][A-Za-z]*\(.*:\*\)$')
}

# Bare-string entries carry no argument at all (Read, WebFetch, Skill, WebSearch).
function Test-BareString {
    param([string]$Entry)
    return ($Entry -match '^[A-Za-z][A-Za-z0-9_-]*$')
}

# A session scratchpad path embeds a session UUID, so the literal is dead the
# moment that session ends.
function Test-SessionUuid {
    param([string]$Entry)
    return ($Entry -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
}

# Compound one-off literals have no reducible prefix, so the whole command
# string was stored verbatim and will not match a second time.
function Test-Compound {
    param([string]$Entry)
    return ($Entry.Contains(';') -or $Entry.Contains('|'))
}

function Get-EntryTool {
    param([string]$Entry)
    $i = $Entry.IndexOf('(')
    if ($i -lt 1 -or -not $Entry.EndsWith(')')) { return $null }
    return $Entry.Substring(0, $i)
}

function Get-EntryBody {
    param([string]$Entry)
    $i = $Entry.IndexOf('(')
    if ($i -lt 1 -or -not $Entry.EndsWith(')')) { return $null }
    return $Entry.Substring($i + 1, $Entry.Length - $i - 2)
}

# Turn one array line (`      "Bash(git:*)",`) into its JSON string content.
# Returns $null when the line is not a plain quoted scalar, which makes the
# caller treat the whole file as unrecognized and leave it alone.
function Get-EntryFromLine {
    param([string]$Line)
    $t = $Line.Trim()
    if ($t.EndsWith(',')) { $t = $t.Substring(0, $t.Length - 1).TrimEnd() }
    if ($t.Length -lt 2 -or -not $t.StartsWith('"') -or -not $t.EndsWith('"')) { return $null }
    return $t.Substring(1, $t.Length - 2)
}

# Drop permissions.allow so the rest of the document can be compared verbatim.
function Get-DocumentWithoutAllow {
    param([string]$Text)
    $obj = $Text | ConvertFrom-Json
    if ($obj.PSObject.Properties['permissions'] -and
        $obj.permissions -and
        $obj.permissions.PSObject.Properties['allow']) {
        $obj.permissions.PSObject.Properties.Remove('allow')
    }
    return ($obj | ConvertTo-Json -Depth 100 -Compress)
}

# --- main -----------------------------------------------------------------
#
# The whole body is fail-open: any throw leaves the settings file untouched.
try {
    $json = Read-HookInput
    if (-not $json -or -not $json.cwd) { exit 0 }

    # Project scope only. The growth was measured there and the SessionEnd
    # payload hands us the project cwd directly; widening to the user-scope
    # file would add blast radius with no evidence behind it (#923).
    $target = Join-Path $json.cwd '.claude' 'settings.local.json'
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { exit 0 }

    $bytes = [System.IO.File]::ReadAllBytes($target)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $encoding = [System.Text.UTF8Encoding]::new($hasBom)
    $raw = [System.IO.File]::ReadAllText($target, $encoding)

    # Refuse to touch a file that is not already valid JSON.
    $null = $raw | ConvertFrom-Json

    # Preserve the file's own newline style; rewriting LF as CRLF would violate
    # the byte-for-byte requirement on every kept line.
    $newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"

    # Locate the permissions.allow array. Only the pretty-printed,
    # one-entry-per-line shape is handled; a collapsed array is left untouched
    # rather than reformatted.
    $startIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '"allow"\s*:\s*\[\s*$') { $startIdx = $i; break }
    }
    if ($startIdx -lt 0) { exit 0 }

    # The array ends at the first line that is nothing but a closing bracket. An
    # entry line always begins with a quote, so a `]` inside a rule string (e.g.
    # a sed character class) cannot be mistaken for the terminator.
    $endIdx = -1
    for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\]\s*,?\s*$') { $endIdx = $i; break }
    }
    if ($endIdx -lt 0) { exit 0 }

    # Pass 1: collect the prefix rules present in this file, so subsumption is
    # judged against what actually survives alongside the entry.
    $prefixes = [System.Collections.Generic.List[object]]::new()
    for ($i = $startIdx + 1; $i -lt $endIdx; $i++) {
        $entry = Get-EntryFromLine $lines[$i]
        if ($null -eq $entry) { continue }
        if ((Test-PrefixRule $entry) -and -not (Test-Denylisted $entry)) {
            $tool = Get-EntryTool $entry
            $body = Get-EntryBody $entry
            if ($tool -and $null -ne $body) {
                $prefixes.Add([pscustomobject]@{
                    Tool = $tool
                    Body = ($body -replace ':\*$', '')
                })
            }
        }
    }

    # An entry is subsumed when a prefix rule for the same tool already covers
    # its command, e.g. Bash(gh:*) makes Bash(gh pr list ...) unreachable.
    function Test-Subsumed {
        param([string]$Entry, $Prefixes)
        $tool = Get-EntryTool $Entry
        $body = Get-EntryBody $Entry
        if (-not $tool -or $null -eq $body) { return $false }
        foreach ($p in $Prefixes) {
            if ($p.Tool -ne $tool) { continue }
            if ([string]::IsNullOrEmpty($p.Body)) { continue }
            if ($body -eq $p.Body) { continue }
            if ($body.StartsWith($p.Body + ' ') -or $body.StartsWith($p.Body + ':')) { return $true }
        }
        return $false
    }

    # Pass 2: build the candidate, preserving every kept line byte for byte
    # apart from the trailing comma required to keep the array valid.
    $kept = [System.Collections.Generic.List[string]]::new()
    $removed = 0
    $cDeny = 0; $cUuid = 0; $cCompound = 0; $cLong = 0; $cSubsumed = 0
    $unparsed = $false

    for ($i = $startIdx + 1; $i -lt $endIdx; $i++) {
        $entry = Get-EntryFromLine $lines[$i]
        if ($null -eq $entry) { $unparsed = $true; break }

        if (Test-Denylisted $entry) {
            $removed++; $cDeny++
        }
        elseif ((Test-BareString $entry) -or (Test-PrefixRule $entry)) {
            $kept.Add($lines[$i])
        }
        elseif (Test-SessionUuid $entry) {
            $removed++; $cUuid++
        }
        elseif (Test-Compound $entry) {
            $removed++; $cCompound++
        }
        elseif ($entry.Length -gt $MaxEntryLen) {
            $removed++; $cLong++
        }
        elseif (Test-Subsumed $entry $prefixes) {
            $removed++; $cSubsumed++
        }
        else {
            $kept.Add($lines[$i])
        }
    }

    # An array line we cannot read as a plain string means the file is shaped in
    # a way this hook does not understand. Leave it alone.
    if ($unparsed) { exit 0 }
    if ($removed -eq 0) { exit 0 }

    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -le $startIdx; $i++) { $out.Add($lines[$i]) }

    for ($k = 0; $k -lt $kept.Count; $k++) {
        $line = $kept[$k]
        if ($k -eq $kept.Count - 1) {
            if ($line.TrimEnd().EndsWith(',')) {
                $line = $line.TrimEnd()
                $line = $line.Substring(0, $line.Length - 1)
            }
        }
        elseif (-not $line.TrimEnd().EndsWith(',')) {
            $line = $line + ','
        }
        $out.Add($line)
    }

    for ($i = $endIdx; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }

    $candidate = [string]::Join($newline, $out)

    # Re-parse before replacing: a candidate that is not valid JSON is discarded.
    $null = $candidate | ConvertFrom-Json

    # Every other key must survive. Compare the whole document minus the pruned
    # array; any other difference means the edit went wrong.
    if ((Get-DocumentWithoutAllow $raw) -ne (Get-DocumentWithoutAllow $candidate)) { exit 0 }

    # The temp file has to live in the target's own directory. Across volumes a
    # move degrades from an atomic rename to copy-then-delete, which is exactly
    # the truncation window the atomic-replace requirement exists to close.
    $tmp = "$target.prune.$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        [System.IO.File]::WriteAllText($tmp, $candidate, $encoding)
        [System.IO.File]::Move($tmp, $target, $true)
    }
    catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        exit 0
    }

    # Logging is best-effort and must never surface on a SessionEnd hook.
    try {
        $logDir = Join-Path $HOME '.claude' 'logs'
        Ensure-Directory $logDir | Out-Null
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $msg = "[$stamp] prune-permission-rules: pruned $removed of $($kept.Count + $removed) -> $($kept.Count) kept  " +
               "[denylisted=$cDeny scratchpad=$cUuid compound=$cCompound long=$cLong subsumed=$cSubsumed]  $target"
        Add-Content -Path (Join-Path $logDir 'permission-prune.log') -Value $msg -ErrorAction SilentlyContinue
    }
    catch {
        # ignore
    }
}
catch {
    exit 0
}

exit 0
