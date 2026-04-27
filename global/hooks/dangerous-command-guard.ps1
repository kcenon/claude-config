#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# dangerous-command-guard.ps1
# Blocks dangerous bash commands and records every decision.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Side effects:
#   Writes one JSON line per invocation to
#   ${env:CLAUDE_LOG_DIR}/dangerous-command-guard.log (defaults to
#   ~/.claude/logs) so an operator can verify whether the hook returned
#   allow/deny for a specific command.

$logDir = if ($env:CLAUDE_LOG_DIR) { $env:CLAUDE_LOG_DIR } else { Join-Path $HOME '.claude/logs' }
$logFile = Join-Path $logDir 'dangerous-command-guard.log'

function Write-Decision {
    param(
        [string]$Decision,
        [string]$Reason,
        [string]$Command
    )
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $entry = [ordered]@{
            ts       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            decision = $Decision
            reason   = $Reason
            command  = $Command
        }
        ($entry | ConvertTo-Json -Compress -Depth 3) | Out-File -FilePath $logFile -Append -Encoding utf8
    } catch {
        # Best-effort; never fail the decision on a logging failure.
    }
}

function Respond-Deny {
    param([string]$Reason)
    Write-Decision -Decision 'deny' -Reason $Reason -Command $CMD
    New-HookDenyResponse -Reason $Reason
    exit 0
}

function Respond-Allow {
    param([string]$Reason = 'dangerous-command-guard: no dangerous pattern matched')
    Write-Decision -Decision 'allow' -Reason $Reason -Command $CMD
    New-HookAllowResponse -AdditionalContext $Reason
    exit 0
}

$json = Read-HookInput
$CMD = $null

if (-not $json) {
    Respond-Deny 'Failed to parse hook input - denying for safety (fail-closed)'
}

try {
    $CMD = $json.tool_input.command
} catch {}

if (-not $CMD) {
    $CMD = $env:CLAUDE_TOOL_INPUT
}

# --- Sub-command tokenization (PowerShell parity port of Issue #476) -------
# Mirrors global/hooks/lib/tokenize-shell.sh. The PowerShell port walks the
# command character-by-character, splits on shell separators while respecting
# quote contexts, and inspects argv[0] of every sub-command rather than
# regex-matching the raw string.
# ----------------------------------------------------------------------------

# Performance guard: bail to coarse regex for very large inputs (matches the
# bash variant's 16 KiB threshold).
$maxBytes = if ($env:DCG_TOKENIZER_MAX_BYTES) { [int]$env:DCG_TOKENIZER_MAX_BYTES } else { 16384 }
if ($CMD.Length -gt $maxBytes) {
    if ($CMD -match 'rm\s+(-[rRf]*[rR][rRf]*|--recursive)\s+/') {
        Respond-Deny 'Dangerous recursive delete at root directory blocked for safety'
    }
    if ($CMD -match 'chmod\s+(0?777|a\+rwx|[246][0-9][0-9][0-9])') {
        Respond-Deny 'Dangerous permission change (777/a+rwx) blocked for security'
    }
    if ($CMD -match '(curl|wget)\s.*\|\s*(sh|bash|zsh|dash|python[23]?|perl|ruby|node)\b') {
        Respond-Deny 'Remote script execution via pipe blocked for security'
    }
    Respond-Allow "Coarse-scan allow (input exceeds tokenizer budget of $maxBytes bytes)"
}

function Split-Subcommands {
    param([string]$Cmd)

    $results = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $buf = ''
    $quote = ''
    $depth = 0
    $i = 0
    $len = $Cmd.Length

    function Flush([System.Collections.Generic.List[string]]$list, [string]$s) {
        $t = $s.Trim()
        if ($t.Length -gt 0) { [void]$list.Add($t) }
    }

    while ($i -lt $len) {
        $ch = $Cmd[$i]
        $next = if ($i + 1 -lt $len) { $Cmd[$i + 1] } else { '' }

        if ($quote -eq "'") {
            $buf += $ch
            if ($ch -eq "'") { $quote = '' }
            $i++; continue
        }
        if ($quote -eq "`$'") {
            $buf += $ch
            if ($ch -eq '\' -and ($i -lt $len - 1)) { $buf += $next; $i += 2; continue }
            if ($ch -eq "'") { $quote = '' }
            $i++; continue
        }
        if ($quote -eq '"') {
            if ($ch -eq '\' -and ($i -lt $len - 1)) { $buf += "$ch$next"; $i += 2; continue }
            if ($ch -eq '"') { $buf += $ch; $quote = ''; $i++; continue }
            if ($ch -eq '$' -and $next -eq '(') {
                $buf += '$('
                $stack.Push($buf); $buf = ''; $depth++
                $i += 2; continue
            }
            if ($ch -eq '`') {
                $buf += '`'
                $stack.Push($buf); $buf = ''; $depth++
                $quote = '`'; $i++; continue
            }
            $buf += $ch; $i++; continue
        }
        if ($quote -eq '`') {
            if ($ch -eq '`') {
                Flush $results $buf
                $buf = $stack.Pop(); $buf += ' '; $depth--; $quote = ''; $i++; continue
            }
            $buf += $ch; $i++; continue
        }

        switch ($ch) {
            "'" { $buf += $ch; $quote = "'" }
            '"' { $buf += $ch; $quote = '"' }
            '\' {
                if ($i -lt $len - 1) { $buf += "$ch$next"; $i += 2; continue }
                $buf += $ch
            }
            '$' {
                if ($next -eq "'") { $buf += "`$'"; $quote = "`$'"; $i += 2; continue }
                if ($next -eq '(') {
                    $buf += '$('; $stack.Push($buf); $buf = ''; $depth++; $i += 2; continue
                }
                $buf += $ch
            }
            '<' {
                if ($next -eq '(') { $buf += '<('; $stack.Push($buf); $buf = ''; $depth++; $i += 2; continue }
                if ($next -eq '<') { $buf += '<<'; $i += 2; continue }
                $buf += $ch
            }
            '`' {
                $buf += '`'; $stack.Push($buf); $buf = ''; $depth++; $quote = '`'
            }
            ')' {
                if ($depth -gt 0) {
                    Flush $results $buf
                    $buf = $stack.Pop(); $buf += ') '; $depth--; $i++; continue
                }
                $buf += $ch
            }
            ';' {
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue }
                $buf += $ch
            }
            '&' {
                if ($next -eq '&' -and $depth -eq 0) { Flush $results $buf; $buf = ''; $i += 2; continue }
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue }
                $buf += $ch
            }
            '|' {
                if ($next -eq '|' -and $depth -eq 0) { Flush $results $buf; $buf = ''; $i += 2; continue }
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue }
                $buf += $ch
            }
            default { $buf += $ch }
        }
        $i++
    }
    while ($depth -gt 0) {
        Flush $results $buf
        $buf = $stack.Pop()
        $depth--
    }
    Flush $results $buf
    return $results
}

function Flatten-Subcommands {
    param([string]$Cmd)
    $current = Split-Subcommands -Cmd $Cmd
    while ($true) {
        $next = New-Object System.Collections.Generic.List[string]
        $changed = $false
        foreach ($line in $current) {
            $sub = Split-Subcommands -Cmd $line
            if ($sub.Count -gt 1) { $changed = $true }
            foreach ($s in $sub) { [void]$next.Add($s) }
        }
        $current = $next
        if (-not $changed) { break }
    }
    return $current
}

function Tokenize-Argv {
    param([string]$Sub)

    # Pre-expand IFS substitutions to a space.
    $s = $Sub.Replace('${IFS}', ' ').Replace('$IFS', ' ')
    $tokens = New-Object System.Collections.Generic.List[string]
    $buf = ''
    $quote = ''
    $i = 0
    $len = $s.Length

    function Emit([System.Collections.Generic.List[string]]$list, [string]$t) {
        if ([string]::IsNullOrEmpty($t)) { return }
        if ($t.StartsWith('\') -and $t.Length -gt 1) { $t = $t.Substring(1) }
        if ($t.Length -ge 2) {
            $first = $t[0]; $last = $t[$t.Length - 1]
            if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
                $t = $t.Substring(1, $t.Length - 2)
            }
        }
        [void]$list.Add($t)
    }

    while ($i -lt $len) {
        $ch = $s[$i]
        $next = if ($i + 1 -lt $len) { $s[$i + 1] } else { '' }

        if ($quote -eq "'") {
            $buf += $ch
            if ($ch -eq "'") { $quote = '' }
            $i++; continue
        }
        if ($quote -eq '"') {
            if ($ch -eq '\' -and ($i -lt $len - 1)) { $buf += "$ch$next"; $i += 2; continue }
            $buf += $ch
            if ($ch -eq '"') { $quote = '' }
            $i++; continue
        }

        switch ($ch) {
            "'" { $buf += $ch; $quote = "'" }
            '"' { $buf += $ch; $quote = '"' }
            '\' {
                if ($i -lt $len - 1) { $buf += "$ch$next"; $i += 2; continue }
                $buf += $ch
            }
            ' '  { Emit $tokens $buf; $buf = '' }
            "`t" { Emit $tokens $buf; $buf = '' }
            "`n" { Emit $tokens $buf; $buf = '' }
            default { $buf += $ch }
        }
        $i++
    }
    Emit $tokens $buf
    return $tokens
}

function Strip-WrapperPrefix {
    param([string[]]$Tokens)
    if ($Tokens.Count -eq 0) { return $Tokens }
    $head = $Tokens[0]
    if (@('sudo','nice','nohup','time','stdbuf','exec') -contains $head) {
        return $Tokens[1..($Tokens.Count - 1)]
    }
    if ($head -eq 'env') {
        $rest = if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() }
        while ($rest.Count -gt 0 -and $rest[0] -match '=') { $rest = $rest[1..($rest.Count - 1)] }
        return $rest
    }
    return $Tokens
}

function Inspect-Argv {
    param([string[]]$Tokens)
    if ($Tokens.Count -eq 0) { return @{ Allow = $true } }

    if ($Tokens[0] -match '=') {
        if ($Tokens[0] -like 'IFS=*') {
            return @{ Allow = $false; Reason = 'Suspicious IFS reassignment in command scope' }
        }
        $Tokens = if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() }
        if ($Tokens.Count -eq 0) { return @{ Allow = $true } }
    }

    $Tokens = Strip-WrapperPrefix -Tokens $Tokens
    if ($Tokens.Count -eq 0) { return @{ Allow = $true } }

    $cmd0 = $Tokens[0]

    if (@('eval','source','.') -contains $cmd0) {
        return @{ Allow = $false; Reason = "Shell-evaluation wrapper ($cmd0) blocked: hides intent from static inspection" }
    }
    if (@('bash','sh','zsh','dash','ksh','fish') -contains $cmd0) {
        if ($Tokens.Count -ge 2 -and $Tokens[1] -eq '-c') {
            return @{ Allow = $false; Reason = "Inline shell ($cmd0 -c ...) blocked: payload is not statically inspectable" }
        }
    }

    if ($cmd0 -eq 'rm') {
        $hasRecursive = $false
        $hasRootTarget = $false
        for ($k = 1; $k -lt $Tokens.Count; $k++) {
            $t = $Tokens[$k]
            if ($t -match '^-[a-zA-Z]*[rR][a-zA-Z]*$' -or $t -eq '--recursive') { $hasRecursive = $true }
            if ($t -eq '/' -or $t -match '^/[a-zA-Z]') { $hasRootTarget = $true }
            if ($t -eq '$HOME' -or $t -like '$HOME/*' -or $t -eq '~' -or $t -like '~/*') { $hasRootTarget = $true }
        }
        if ($hasRecursive -and $hasRootTarget) {
            return @{ Allow = $false; Reason = 'Dangerous recursive delete at root directory blocked for safety' }
        }
    }

    if ($cmd0 -eq 'chmod') {
        for ($k = 1; $k -lt $Tokens.Count; $k++) {
            $t = $Tokens[$k]
            if ($t -match '^0?777$') {
                return @{ Allow = $false; Reason = 'Dangerous permission change (777/a+rwx) blocked for security' }
            }
            if ($t -match '^[246][0-9][0-9][0-9]$') {
                return @{ Allow = $false; Reason = 'Dangerous permission change (setuid/setgid bit) blocked for security' }
            }
            if ($t -eq 'a+rwx' -or $t -like '*+rwx') {
                return @{ Allow = $false; Reason = 'Dangerous permission change (777/a+rwx) blocked for security' }
            }
            if ($t -like '*+s') {
                return @{ Allow = $false; Reason = 'Dangerous permission change (setuid/setgid bit) blocked for security' }
            }
        }
    }

    return @{ Allow = $true }
}

function Detect-FetchPipeShell {
    param([string]$Prev, [string]$Curr)
    if (-not ($Prev -match '\bcurl\b' -or $Prev -match '\bwget\b')) { return $false }
    $first = (Tokenize-Argv -Sub $Curr) | Select-Object -First 1
    return @('sh','bash','zsh','dash','ksh','python','python2','python3','perl','ruby','node') -contains $first
}

$prev = ''
foreach ($sub in (Flatten-Subcommands -Cmd $CMD)) {
    if ([string]::IsNullOrWhiteSpace($sub)) { continue }
    if ($prev -ne '' -and (Detect-FetchPipeShell -Prev $prev -Curr $sub)) {
        Respond-Deny 'Remote script execution via pipe blocked for security'
    }
    if ($sub -match '\$\{IFS\}' -or $sub -match '\$IFS\b') {
        Respond-Deny 'Suspicious IFS-based whitespace obfuscation in command'
    }
    $tokens = Tokenize-Argv -Sub $sub
    $r = Inspect-Argv -Tokens $tokens
    if (-not $r.Allow) { Respond-Deny $r.Reason }
    $prev = $sub
}

# Tag well-known safe read-only compound patterns so the reason line explains
# why a pipe-bearing command was auto-allowed.
$safeHead = '^(git\s+(status|log|diff|show|branch|tag|remote|ls-files|rev-parse|describe|for-each-ref|worktree|fetch)|gh\s+(pr|issue|run|workflow|repo|release|auth)\s+(view|list|status|diff|checks))\b'
if (($CMD -match '\|') -or ($CMD -match '2>&1') -or ($CMD -match '>\s*/dev/null')) {
    if ($CMD -match $safeHead) {
        Respond-Allow 'Safe read-only compound command (pipe/redirect with git/gh read verb)'
    }
}

Respond-Allow
