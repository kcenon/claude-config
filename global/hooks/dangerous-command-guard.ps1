#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# dangerous-command-guard.ps1
# Denies irreversible shell operations and asks before destructive local ones.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# PowerShell twin of dangerous-command-guard.sh; the decision tiers, payload
# scanning and logging rules are documented there and mirrored here:
#   deny  - recursive rm of /, an absolute path, ~ or $HOME; fetch piped to an
#           interpreter; chmod 777 / setuid; IFS obfuscation; a direct push to
#           main/master/develop; gh repo delete; gh api DELETE repos/<o>/<r>.
#   ask   - git reset --hard, git checkout -- <path> / . / -f, git switch -f /
#           --force / --discard-changes, git restore without --staged (dirty
#           work tree only); git clean -f; git stash drop|clear; git push
#           --force / -f / +<ref>; git push --delete / -d / <remote> :<ref>;
#           recursive rm of ., .., *, .*, .git or a path outside the
#           repository; find -delete / -exec rm; gh <group>
#           delete|delete-asset; every other gh api DELETE.
#   allow - everything else.
# `bash|sh|... -c` and `eval` payloads are inspected recursively (depth 3);
# an uninspectable payload is denied. Outside a payload, a `$X` / `${X}`
# command head is resolved from an earlier `X=value` / `export X=value`, or
# asks when its arguments would make rm deny or ask. Input over the tokenizer
# budget gets a regex scan: deny-tier shapes deny, ask-arm keywords ask.
# Only deny and ask decisions are logged
# to ${env:CLAUDE_LOG_DIR}/dangerous-command-guard.log (defaults to
# ~/.claude/logs). Plain allows emit the minimal allow JSON (#715).

$logDir = if ($env:CLAUDE_LOG_DIR) { $env:CLAUDE_LOG_DIR } else { Join-Path $HOME '.claude/logs' }
$logFile = Join-Path $logDir 'dangerous-command-guard.log'
$script:MaxPayloadDepth = 3

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

function Respond-Ask {
    param([string]$Reason)
    Write-Decision -Decision 'ask' -Reason $Reason -Command $CMD
    New-HookAskResponse -Reason $Reason
    exit 0
}

function Respond-Allow {
    # Plain allow is silent on stdout (issue #715) and not logged (#964).
    New-HookAllowResponse
    exit 0
}

function Respond-AllowWithContext {
    # Warning-class allow: the context has decision value for the model
    # (e.g. degraded coarse-scan inspection), so it stays on stdout.
    param([string]$Reason)
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
$CMD = [string]$CMD

# The work tree checks resolve paths against the session directory the hook
# input reports, falling back to the hook process directory.
$hookCwd = ''
try { $hookCwd = [string]$json.cwd } catch {}
if ([string]::IsNullOrEmpty($hookCwd)) { $hookCwd = (Get-Location).Path }

# --- Sub-command tokenization (PowerShell parity port of Issue #476) -------
# Mirrors global/hooks/lib/tokenize-shell.sh. The PowerShell port walks the
# command character-by-character, splits on shell separators while respecting
# quote contexts, and inspects argv[0] of every sub-command rather than
# regex-matching the raw string.
#
# The scan loops are labelled: inside a PowerShell `switch`, a bare
# `continue` only leaves the switch, so the loop's `$i++` ran as well and the
# character after an escape, `$(` or `&&` was skipped (`\rm` read as `r`).
# ----------------------------------------------------------------------------

# Line-based match with a time budget: .NET regexes backtrack, so a crafted
# input cannot stall the hook; the caller asks when the budget runs out.
function Test-CoarseMatch {
    param([string]$Text, [string]$Pattern)
    return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline, [TimeSpan]::FromSeconds(1))
}

# The deny and ask tiers for input over the tokenizer budget (#971); see
# coarse_scan in the bash twin. Any keyword of an ask arm asks, because the
# arm's own conditions were not evaluated.
function Invoke-CoarseScan {
    param([string]$Text, [int]$Budget)
    # A command word start, one sub-command's text, a space, a quote, and the
    # end of a word.
    $W = '(^|[^\w.-])'; $G = '[^;&|\r\n]*'; $S = '[ \t]'; $Q = '["'']'
    $E = '([ \t"'';&|)]|$)'
    $git = "${W}git${S}(${G}${S})?"
    $rmr = "${W}rm${S}(${G}${S})?(-[A-Za-z]*[rR][A-Za-z]*|--recursive)"

    # Cheap prefilter: none of the command words, nothing to scan.
    if (-not (Test-CoarseMatch $Text '(rm|git|gh|find)')) { return }

    if (Test-CoarseMatch $Text "${rmr}${S}(${G}${S})?${Q}?(~|\`$HOME|\`$\{HOME\})(/|${E})") {
        Respond-Deny 'Dangerous recursive delete at root directory blocked for safety'
    }
    if (Test-CoarseMatch $Text "${git}push${S}(${G}[ \t:+])?(refs/heads/)?(main|master|develop)${E}") {
        Respond-Deny "Direct push to a protected branch (main, master or develop) is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main)."
    }
    if (Test-CoarseMatch $Text "${W}gh${S}(${G}${S})?repo${S}+delete${E}") {
        Respond-Deny 'gh repo delete deletes a repository irreversibly. Blocked.'
    }
    $apis = [regex]::Matches($Text, "${W}gh${S}(${G}${S})?api${S}${G}", [System.Text.RegularExpressions.RegexOptions]::Multiline, [TimeSpan]::FromSeconds(1))
    foreach ($m in $apis) {
        if ((Test-CoarseMatch $m.Value "(-X|--method)(${S}*|=)${Q}?[Dd][Ee][Ll][Ee][Tt][Ee]${E}") -and
            (Test-CoarseMatch $m.Value "(^|${S})${Q}?(https?://[^/\s]+/)?(api/v3/)?/*repos/[^/\s]+/[^/\s?""']+/*(\?\S*)?${Q}?${E}")) {
            Respond-Deny 'gh api DELETE on repos/<owner>/<repo> deletes the repository itself, irreversibly. Blocked.'
        }
    }

    $askArms = @(
        @('git reset --hard', "${git}reset${S}(${G}${S})?--hard${E}"),
        @('git checkout -f / --force / -- / .', "${git}checkout${S}(${G}${S})?(-f|--force|--|\./?)${E}"),
        @('git restore', "${git}restore${E}"),
        @('git switch -f / --force / --discard-changes', "${git}switch${S}(${G}${S})?(-f|--force|--discard-changes)${E}"),
        @('git clean -', "${git}clean${S}+-"),
        @('git stash drop / clear', "${git}stash${S}+(drop|clear)${E}"),
        @('git push --force / --delete / +<ref> / :<ref>', "${git}push${S}(${G}${S})?(--force|--delete|-[A-Za-z]*[fd][A-Za-z]*|[+:]\S+)${E}"),
        @('rm -r', "${rmr}${E}"),
        @('find -delete / -exec rm', "${W}find${S}${G}${S}(-delete|-(exec|execdir|ok|okdir)${S}+(\S*/)?rm)${E}"),
        @('gh <group> delete', "${W}gh${S}(${G}${S})?[A-Za-z0-9-]+${S}+delete(-asset)?${E}"),
        @('gh api ... DELETE', "${W}gh${S}(${G}${S})?api${S}${G}[Dd][Ee][Ll][Ee][Tt][Ee]")
    )
    $all = ($askArms | ForEach-Object { '(' + $_[1] + ')' }) -join '|'
    if (-not (Test-CoarseMatch $Text $all)) { return }
    foreach ($arm in $askArms) {
        if (Test-CoarseMatch $Text $arm[1]) {
            Respond-Ask "Input of $($Text.Length) bytes exceeds the tokenizer budget ($Budget bytes) and contains $($arm[0]), so it was not inspected in full. Confirm to proceed."
        }
    }
}

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
    try {
        Invoke-CoarseScan -Text $CMD -Budget $maxBytes
    } catch {
        Respond-Ask "Input of $($CMD.Length) bytes exceeds the tokenizer budget ($maxBytes bytes) and the coarse scan did not finish ($($_.Exception.Message)), so it was not inspected. Confirm to proceed."
    }
    Respond-AllowWithContext "Coarse-scan allow (input exceeds tokenizer budget of $maxBytes bytes)"
}

function Split-Subcommands {
    param([string]$Cmd)

    $results = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    # Quote state to restore when a substitution closes: "$(cmd)" is parsed
    # unquoted inside and returns to the double-quoted string afterwards.
    $qstack = New-Object System.Collections.Generic.Stack[string]
    $hdWords = New-Object System.Collections.Generic.List[string]
    $hdTabs = New-Object System.Collections.Generic.List[bool]
    $buf = ''
    $quote = ''
    $depth = 0
    $i = 0
    $len = $Cmd.Length

    function Flush([System.Collections.Generic.List[string]]$list, [string]$s) {
        $t = $s.Trim()
        if ($t.Length -gt 0) { [void]$list.Add($t) }
    }

    :scan while ($i -lt $len) {
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
                $stack.Push($buf); $qstack.Push('"'); $buf = ''; $depth++
                $quote = ''
                $i += 2; continue
            }
            if ($ch -eq '`') {
                $buf += '`'
                $stack.Push($buf); $qstack.Push('"'); $buf = ''; $depth++
                $quote = '`'; $i++; continue
            }
            $buf += $ch; $i++; continue
        }
        if ($quote -eq '`') {
            if ($ch -eq '`') {
                Flush $results $buf
                $buf = $stack.Pop(); $buf += ' '; $depth--
                $quote = $qstack.Pop(); $i++; continue
            }
            $buf += $ch; $i++; continue
        }

        switch -CaseSensitive ($ch) {
            "'" { $buf += $ch; $quote = "'" }
            '"' { $buf += $ch; $quote = '"' }
            '\' {
                if ($i -lt $len - 1) { $buf += "$ch$next"; $i += 2; continue scan }
                $buf += $ch
            }
            '$' {
                if ($next -eq "'") { $buf += "`$'"; $quote = "`$'"; $i += 2; continue scan }
                if ($next -eq '(') {
                    $buf += '$('; $stack.Push($buf); $qstack.Push(''); $buf = ''; $depth++; $i += 2; continue scan
                }
                $buf += $ch
            }
            '<' {
                if ($next -eq '(') {
                    $buf += '<('; $stack.Push($buf); $qstack.Push(''); $buf = ''; $depth++; $i += 2; continue scan
                }
                if ($next -eq '<') {
                    # `<<<` here-string: the next token is an ordinary word.
                    if (($i + 2 -lt $len) -and $Cmd[$i + 2] -eq '<') { $buf += '<<<'; $i += 3; continue scan }
                    # `<<` / `<<-` heredoc: record the delimiter; the body is
                    # consumed at the next unquoted newline.
                    $buf += '<<'; $i += 2
                    $hdTab = $false
                    if ($i -lt $len -and $Cmd[$i] -eq '-') { $buf += '-'; $hdTab = $true; $i++ }
                    while ($i -lt $len -and ($Cmd[$i] -eq ' ' -or $Cmd[$i] -eq "`t")) { $buf += $Cmd[$i]; $i++ }
                    $raw = ''
                    while ($i -lt $len -and -not (" `t`n;&|<>()".Contains($Cmd[$i]))) { $raw += $Cmd[$i]; $i++ }
                    $buf += $raw
                    $word = $raw.Replace("'", '').Replace('"', '').Replace('\', '')
                    if ($word) { $hdWords.Add($word); $hdTabs.Add($hdTab) }
                    continue scan
                }
                $buf += $ch
            }
            "`n" {
                # Heredoc bodies are data: copy them line by line without
                # quote tracking (callers still inspect each line).
                $buf += $ch; $i++
                for ($k = 0; $k -lt $hdWords.Count; $k++) {
                    while ($i -lt $len) {
                        $nl = $Cmd.IndexOf("`n", $i)
                        $line = if ($nl -lt 0) { $Cmd.Substring($i) } else { $Cmd.Substring($i, $nl - $i) }
                        $buf += $line
                        $i += $line.Length
                        if ($i -lt $len) { $buf += "`n"; $i++ }
                        $cmp = if ($hdTabs[$k]) { $line.TrimStart("`t") } else { $line }
                        if ($cmp -ceq $hdWords[$k]) { break }
                    }
                }
                $hdWords.Clear(); $hdTabs.Clear()
                continue scan
            }
            '`' {
                $buf += '`'; $stack.Push($buf); $qstack.Push(''); $buf = ''; $depth++; $quote = '`'
            }
            ')' {
                if ($depth -gt 0) {
                    Flush $results $buf
                    $buf = $stack.Pop(); $buf += ') '; $depth--
                    $quote = $qstack.Pop(); $i++; continue scan
                }
                $buf += $ch
            }
            ';' {
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue scan }
                $buf += $ch
            }
            '&' {
                if ($next -eq '&' -and $depth -eq 0) { Flush $results $buf; $buf = ''; $i += 2; continue scan }
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue scan }
                $buf += $ch
            }
            '|' {
                if ($next -eq '|' -and $depth -eq 0) { Flush $results $buf; $buf = ''; $i += 2; continue scan }
                if ($depth -eq 0) { Flush $results $buf; $buf = ''; $i++; continue scan }
                $buf += $ch
            }
            default { $buf += $ch }
        }
        $i++
    }
    while ($depth -gt 0) {
        Flush $results $buf
        $buf = $stack.Pop()
        [void]$qstack.Pop()
        $depth--
    }
    Flush $results $buf
    return $results
}

# Split emitted sub-commands on newlines, like the bash side's line reads.
function Split-Lines {
    param([string[]]$Items)
    foreach ($item in $Items) {
        foreach ($l in ($item -split "`n")) {
            $t = $l.TrimEnd("`r").Trim()
            if ($t.Length -gt 0) { $t }
        }
    }
}

function Flatten-Subcommands {
    param([string]$Cmd)
    $current = @(Split-Lines -Items @(Split-Subcommands -Cmd $Cmd))
    while ($true) {
        $next = New-Object System.Collections.Generic.List[string]
        $changed = $false
        foreach ($line in $current) {
            $sub = @(Split-Lines -Items @(Split-Subcommands -Cmd $line))
            if ($sub.Count -gt 1) { $changed = $true }
            foreach ($s in $sub) { [void]$next.Add($s) }
        }
        $current = @($next)
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

    :scan while ($i -lt $len) {
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

        switch -CaseSensitive ($ch) {
            "'" { $buf += $ch; $quote = "'" }
            '"' { $buf += $ch; $quote = '"' }
            '\' {
                if ($i -lt $len - 1) { $buf += "$ch$next"; $i += 2; continue scan }
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

function Skip-First {
    # The leading comma keeps a one-element result an array; PowerShell would
    # otherwise unroll it to a bare string and `$x[0]` would read a char.
    param([string[]]$Items, [int]$Count = 1)
    return ,@($Items | Select-Object -Skip $Count)
}

function Strip-WrapperPrefix {
    param([string[]]$Tokens)
    if ($Tokens.Count -eq 0) { return $Tokens }
    $head = $Tokens[0]
    if (@('sudo','nice','nohup','time','stdbuf','exec') -ccontains $head) {
        return (Skip-First $Tokens)
    }
    if ($head -ceq 'env') {
        $rest = Skip-First $Tokens
        while ($rest.Count -gt 0 -and $rest[0] -match '=') { $rest = Skip-First $rest }
        return $rest
    }
    return $Tokens
}

function New-Verdict {
    param([string]$D, [string]$R = '')
    return @{ D = $D; R = $R }
}

# --- Path and work tree helpers ----------------------------------------------

function Test-AbsolutePath {
    param([string]$P)
    return ($P.StartsWith('/') -or $P.StartsWith('\\') -or $P -match '^[A-Za-z]:[\\/]')
}

# The directory <P> names when it runs from <Base>; '' when that cannot be
# known statically (a variable, a substitution, a glob, `cd -`, no base).
function Resolve-Dir {
    param([string]$Base, [string]$P)
    if ([string]::IsNullOrEmpty($P) -or $P -eq '-' -or $P -match '[$`*?]') { return '' }
    if ($P -eq '~') { return $HOME }
    if ($P.StartsWith('~/')) { return (Join-Path $HOME $P.Substring(2)) }
    if (Test-AbsolutePath $P) { return $P }
    if ([string]::IsNullOrEmpty($Base)) { return '' }
    return (Join-Path $Base $P)
}

# Lexically normalize a relative path: '' for the start directory itself,
# leading '..' segments kept ("a/../.." gives "..").
function Normalize-Rel {
    param([string]$Path)
    $stack = New-Object System.Collections.Generic.List[string]
    foreach ($seg in ($Path -split '[\\/]')) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') {
            if ($stack.Count -gt 0 -and $stack[$stack.Count - 1] -ne '..') { $stack.RemoveAt($stack.Count - 1) }
            else { $stack.Add('..') }
            continue
        }
        $stack.Add($seg)
    }
    return ($stack -join '/')
}

# '' (the directory itself) or only '..' segments (one of its ancestors).
function Test-DirOrAncestor {
    param([string]$N)
    return ($N -eq '' -or $N -match '^\.\.(/\.\.)*$')
}

function Get-WorktreeState {
    param([string]$Dir)
    if ([string]::IsNullOrEmpty($Dir) -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return 'unknown' }
    try {
        $out = & git -C $Dir --no-optional-locks status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { return 'norepo' }
    } catch { return 'norepo' }
    if ((@($out) -join '').Length -gt 0) { return 'dirty' }
    return 'clean'
}

function Ask-IfDirty {
    param([string]$Dir, [string]$What)
    switch (Get-WorktreeState -Dir $Dir) {
        'dirty' {
            return (New-Verdict 'ask' "$What, and the work tree at $Dir has some; they cannot be recovered afterwards. Confirm to proceed, or commit or stash them first.")
        }
        'unknown' {
            return (New-Verdict 'ask' "$What, and the work tree it targets cannot be determined statically. Confirm to proceed.")
        }
    }
    return (New-Verdict 'allow')
}

# --- Command inspectors --------------------------------------------------------

function Inspect-Rm {
    param([string[]]$Tokens, [string]$Cwd)
    $hasRecursive = $false
    $endOpts = $false
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($t in (Skip-First $Tokens)) {
        if (-not $endOpts) {
            if ($t -ceq '--') { $endOpts = $true; continue }
            if ($t -ceq '--recursive') { $hasRecursive = $true; continue }
            if ($t.StartsWith('--')) { continue }
            if ($t.StartsWith('-')) {
                if ($t -cmatch '[rR]') { $hasRecursive = $true }
                continue
            }
        }
        $targets.Add($t)
    }
    if (-not $hasRecursive) { return (New-Verdict 'allow') }

    # Deny: the root, any absolute path, or the home directory.
    foreach ($t in $targets) {
        if ((Test-AbsolutePath $t) -or $t -ceq '$HOME' -or $t.StartsWith('$HOME/') -or
            $t -ceq '${HOME}' -or $t.StartsWith('${HOME}/') -or $t -eq '~' -or $t.StartsWith('~/')) {
            return (New-Verdict 'deny' 'Dangerous recursive delete at root directory blocked for safety')
        }
    }

    # Ask: the current directory, a parent, a glob over either, .git, or a
    # path that resolves outside the repository work tree.
    $repo = 'unchecked'
    $prefix = ''
    foreach ($t in $targets) {
        if ($t -match '[$`]' -or $t.StartsWith('~')) { continue }
        $n = Normalize-Rel $t
        $base = ($n -split '/')[-1]
        $parent = if ($n.Contains('/')) { $n.Substring(0, $n.LastIndexOf('/')) } else { '' }
        $glob = ($base -ceq '*' -or $base -ceq '.*')
        if ((Test-DirOrAncestor $n) -or $base -ceq '.git' -or ($glob -and (Test-DirOrAncestor $parent))) {
            return (New-Verdict 'ask' "Recursive delete of '$t' (the current directory, a parent, a glob over one of them, or .git) cannot be undone. Confirm to proceed.")
        }
        if ($repo -eq 'unchecked') {
            $repo = 'no'
            if (-not [string]::IsNullOrEmpty($Cwd) -and (Test-Path -LiteralPath $Cwd -PathType Container)) {
                try {
                    $info = @(& git -C $Cwd rev-parse --is-inside-work-tree --show-prefix 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $info.Count -gt 0 -and $info[0] -eq 'true') {
                        $repo = 'yes'
                        $prefix = if ($info.Count -gt 1) { [string]$info[1] } else { '' }
                    }
                } catch {}
            }
        }
        if ($repo -ne 'yes') { continue }
        $n = Normalize-Rel ($prefix + $t)
        if ($n -eq '' -or $n -eq '..' -or $n.StartsWith('../')) {
            return (New-Verdict 'ask' "Recursive delete of '$t' reaches the repository top level or outside the work tree and cannot be undone. Confirm to proceed.")
        }
    }
    return (New-Verdict 'allow')
}

function Inspect-Chmod {
    param([string[]]$Tokens)
    foreach ($t in (Skip-First $Tokens)) {
        if ($t -match '^0?777$') {
            return (New-Verdict 'deny' 'Dangerous permission change (777/a+rwx) blocked for security')
        }
        if ($t -match '^[246][0-9][0-9][0-9]$') {
            return (New-Verdict 'deny' 'Dangerous permission change (setuid/setgid bit) blocked for security')
        }
        if ($t -ceq 'a+rwx' -or $t -clike '*+rwx') {
            return (New-Verdict 'deny' 'Dangerous permission change (777/a+rwx) blocked for security')
        }
        if ($t -clike '*+s') {
            return (New-Verdict 'deny' 'Dangerous permission change (setuid/setgid bit) blocked for security')
        }
    }
    return (New-Verdict 'allow')
}

function Inspect-Find {
    param([string[]]$Tokens)
    $prev = ''
    foreach ($t in (Skip-First $Tokens)) {
        if ($t -ceq '-delete') {
            return (New-Verdict 'ask' 'find -delete removes every match permanently. Confirm to proceed, or run the same find with -print first.')
        }
        if (@('-exec','-execdir','-ok','-okdir') -ccontains $prev -and ($t -ceq 'rm' -or $t -clike '*/rm')) {
            return (New-Verdict 'ask' 'find -exec rm removes every match permanently. Confirm to proceed, or run the same find with -print first.')
        }
        $prev = $t
    }
    return (New-Verdict 'allow')
}

# The branch a refspec-less `git push` updates: the current branch's
# upstream, else the current branch (push-target-guard).
function Get-PushDefaultTarget {
    param([string]$Dir)
    if ([string]::IsNullOrEmpty($Dir) -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return '' }
    try {
        $up = [string](& git -C $Dir rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $up) {
            return ($up -replace '^[^/]*/', '')
        }
        $head = [string](& git -C $Dir rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -eq 0) { return $head }
    } catch {}
    return ''
}

function Inspect-GitPush {
    param([string[]]$Args0, [string]$Dir)
    $force = $false; $delete = $false; $dry = $false; $skipValue = $false
    $pos = New-Object System.Collections.Generic.List[string]
    foreach ($t in $Args0) {
        if ($skipValue) { $skipValue = $false; continue }
        if ($t -ceq '--force') { $force = $true; continue }
        if ($t -ceq '--delete') { $delete = $true; continue }
        if ($t -ceq '--dry-run') { $dry = $true; continue }
        if (@('--repo','--push-option','--receive-pack','--exec','-o') -ccontains $t) { $skipValue = $true; continue }
        if ($t.StartsWith('--')) { continue }   # includes --force-with-lease / --force-if-includes
        if ($t.StartsWith('-')) {
            if ($t.Contains('f')) { $force = $true }
            if ($t.Contains('d')) { $delete = $true }
            if ($t.Contains('n')) { $dry = $true }
            continue
        }
        $pos.Add($t)
    }
    # A dry run updates nothing (push-target-guard, #782).
    if ($dry) { return (New-Verdict 'allow') }

    $dsts = New-Object System.Collections.Generic.List[string]
    if ($pos.Count -le 1) {
        $d = Get-PushDefaultTarget -Dir $Dir
        if ($d) { $dsts.Add($d) }
    } else {
        foreach ($spec in ($pos | Select-Object -Skip 1)) {
            if ($spec.StartsWith('+')) { $force = $true; $spec = $spec.Substring(1) }
            if ($spec.StartsWith(':')) { $delete = $true }
            $dst = ($spec -split ':')[-1]
            if ($dst -ceq 'HEAD' -and -not [string]::IsNullOrEmpty($Dir) -and (Test-Path -LiteralPath $Dir -PathType Container)) {
                try { $dst = [string](& git -C $Dir rev-parse --abbrev-ref HEAD 2>$null) } catch {}
            }
            $dsts.Add($dst)
        }
    }
    foreach ($dst in $dsts) {
        $d = $dst -replace '^refs/heads/', ''
        if (@('main','master','develop') -ccontains $d) {
            return (New-Verdict 'deny' "Direct push to protected branch '$d' is blocked by branching policy. Open a PR into 'develop' (feature/fix branches) or use the /release skill (develop -> main). If you must, push from a work branch instead.")
        }
    }
    $reasons = @()
    if ($force) { $reasons += 'git push --force overwrites remote history that other clones may depend on; prefer --force-with-lease' }
    if ($delete) { $reasons += 'git push --delete (or <remote> :<ref>) deletes a remote ref' }
    if ($reasons.Count -gt 0) { return (New-Verdict 'ask' (($reasons -join '; ') + '. Confirm to proceed.')) }
    return (New-Verdict 'allow')
}

function Inspect-Git {
    param([string[]]$Tokens, [string]$Cwd)
    $rest = Skip-First $Tokens
    $dir = $Cwd
    # Global options before the subcommand; see the bash twin.
    while ($rest.Count -gt 0) {
        $o = $rest[0]
        if ($o -ceq '-C') {
            if ($rest.Count -lt 2) { return (New-Verdict 'allow') }
            $dir = Resolve-Dir -Base $dir -P $rest[1]; $rest = Skip-First $rest 2; continue
        }
        if ($o -ceq '--git-dir' -or $o -ceq '--work-tree') {
            $dir = ''
            if ($rest.Count -lt 2) { return (New-Verdict 'allow') }
            $rest = Skip-First $rest 2; continue
        }
        if ($o.StartsWith('--git-dir=') -or $o.StartsWith('--work-tree=')) { $dir = ''; $rest = Skip-First $rest; continue }
        if (@('-c','--namespace','--super-prefix') -ccontains $o) {
            if ($rest.Count -lt 2) { return (New-Verdict 'allow') }
            $rest = Skip-First $rest 2; continue
        }
        if ($o.StartsWith('-')) { $rest = Skip-First $rest; continue }
        break
    }
    if ($rest.Count -eq 0) { return (New-Verdict 'allow') }
    $sub = $rest[0]
    $a = Skip-First $rest
    switch -CaseSensitive ($sub) {
        'reset' {
            if ($a -ccontains '--hard') { return (Ask-IfDirty -Dir $dir -What 'git reset --hard discards uncommitted changes') }
        }
        'checkout' {
            for ($k = 0; $k -lt $a.Count; $k++) {
                $t = $a[$k]
                if (@('-f','--force','.','./') -ccontains $t) {
                    return (Ask-IfDirty -Dir $dir -What "git checkout $t discards uncommitted changes")
                }
                if ($t -ceq '--' -and $k -lt $a.Count - 1) {
                    return (Ask-IfDirty -Dir $dir -What 'git checkout -- <path> discards uncommitted changes')
                }
            }
        }
        'switch' {
            # -C / --force-create only moves a branch ref (kept by the reflog);
            # -m merges the local changes instead of dropping them.
            foreach ($t in $a) {
                if (@('-f','--force','--discard-changes') -ccontains $t) {
                    return (Ask-IfDirty -Dir $dir -What "git switch $t discards uncommitted changes")
                }
            }
        }
        'restore' {
            $staged = $false; $worktree = $false
            foreach ($t in $a) {
                if ($t -ceq '--staged') { $staged = $true; continue }
                if ($t -ceq '--worktree') { $worktree = $true; continue }
                if ($t.StartsWith('--')) { continue }
                if ($t.StartsWith('-')) {
                    if ($t.Contains('S')) { $staged = $true }
                    if ($t.Contains('W')) { $worktree = $true }
                }
            }
            if ($staged -and -not $worktree) { return (New-Verdict 'allow') }
            return (Ask-IfDirty -Dir $dir -What 'git restore without --staged discards uncommitted changes')
        }
        'clean' {
            $force = $false; $dry = $false
            foreach ($t in $a) {
                if ($t -ceq '--force') { $force = $true; continue }
                if ($t -ceq '--dry-run') { $dry = $true; continue }
                if ($t.StartsWith('--')) { continue }
                if ($t.StartsWith('-')) {
                    if ($t.Contains('f')) { $force = $true }
                    if ($t.Contains('n')) { $dry = $true }
                }
            }
            if ($force -and -not $dry) {
                return (New-Verdict 'ask' 'git clean -f permanently deletes untracked files, which git history cannot restore. Confirm to proceed, or preview with git clean -n.')
            }
        }
        'stash' {
            foreach ($t in $a) {
                if ($t.StartsWith('-')) { continue }
                if ($t -ceq 'drop' -or $t -ceq 'clear') {
                    return (New-Verdict 'ask' "git stash $t permanently discards stashed changes. Confirm to proceed.")
                }
                break
            }
        }
        'push' { return (Inspect-GitPush -Args0 $a -Dir $dir) }
    }
    return (New-Verdict 'allow')
}

function Inspect-Gh {
    param([string[]]$Tokens)
    $pos = New-Object System.Collections.Generic.List[string]
    $method = ''
    $expect = ''
    $valueFlags = @('-R','--repo','-H','--header','-f','-F','--field','--raw-field','--input','-q','--jq','-t','--template','--hostname','-p','--preview','--cache')
    foreach ($t in (Skip-First $Tokens)) {
        if ($expect) {
            if ($expect -eq 'method') { $method = $t }
            $expect = ''
            continue
        }
        if ($t -ceq '-X' -or $t -ceq '--method') { $expect = 'method'; continue }
        if ($t.StartsWith('--method=')) { $method = $t.Substring(9); continue }
        if ($t.StartsWith('-X')) { $method = $t.Substring(2); continue }
        if ($valueFlags -ccontains $t) { $expect = 'value'; continue }
        if ($t.StartsWith('-')) { continue }
        $pos.Add($t)
    }
    $group = if ($pos.Count -gt 0) { $pos[0] } else { '' }
    $verb = if ($pos.Count -gt 1) { $pos[1] } else { '' }

    if ($group -ceq 'api') {
        if ($method -ine 'DELETE') { return (New-Verdict 'allow') }
        $ep = $verb -replace '^https?://[^/]+/', '' -replace '^api/v3/', '' -replace '^/+', '' -replace '\?.*$', '' -replace '/+$', ''
        if ($ep -match '^repos/[^/]+/[^/]+$') {
            return (New-Verdict 'deny' "gh api DELETE on $ep deletes the repository itself, irreversibly. Blocked.")
        }
        return (New-Verdict 'ask' "gh api DELETE $ep irreversibly deletes a GitHub resource. Confirm to proceed.")
    }
    if ($group -ceq 'repo' -and $verb -ceq 'delete') {
        return (New-Verdict 'deny' 'gh repo delete deletes a repository irreversibly. Blocked.')
    }
    if ($verb -ceq 'delete' -or $verb -ceq 'delete-asset') {
        return (New-Verdict 'ask' "gh $group $verb irreversibly deletes a GitHub resource. Confirm to proceed.")
    }
    return (New-Verdict 'allow')
}

# $false when a quote (single, double or $'...') is left open.
function Test-QuotesBalanced {
    param([string]$S)
    $q = ''
    for ($i = 0; $i -lt $S.Length; $i++) {
        $ch = $S[$i]
        $next = if ($i + 1 -lt $S.Length) { $S[$i + 1] } else { '' }
        if ($q -eq "'") {
            if ($ch -eq "'") { $q = '' }
        } elseif ($q -eq '"' -or $q -eq "`$'") {
            if ($ch -eq '\') { $i++ }
            elseif ($q -eq '"' -and $ch -eq '"') { $q = '' }
            elseif ($q -ne '"' -and $ch -eq "'") { $q = '' }
        } else {
            if ($ch -eq '\') { $i++ }
            elseif ($ch -eq '$' -and $next -eq "'") { $q = "`$'"; $i++ }
            elseif ($ch -eq "'" -or $ch -eq '"') { $q = [string]$ch }
        }
    }
    return ($q -eq '')
}

function Inspect-Payload {
    param([string]$Label, [string]$Payload, [int]$Depth, [string]$Cwd)
    if ($Depth -ge $script:MaxPayloadDepth) {
        return (New-Verdict 'deny' "Inline shell payload ($Label) nested deeper than $($script:MaxPayloadDepth) levels blocked: not statically inspectable")
    }
    if (-not (Test-QuotesBalanced $Payload)) {
        return (New-Verdict 'deny' "Inline shell payload ($Label) has unbalanced quotes and cannot be inspected; blocked (fail-closed)")
    }
    return (Inspect-Command -Cmd $Payload -Depth ($Depth + 1) -Cwd $Cwd)
}

function Inspect-InlineShell {
    param([string[]]$Tokens, [int]$Depth, [string]$Cwd)
    $sh = $Tokens[0]
    $hasC = $false
    $skip = $false
    foreach ($t in (Skip-First $Tokens)) {
        if ($skip) { $skip = $false; continue }
        if (@('-o','+o','-O','+O','--rcfile','--init-file') -ccontains $t) { $skip = $true; continue }
        if ($t.StartsWith('--')) { continue }
        if ($t.StartsWith('-')) { if ($t.Contains('c')) { $hasC = $true }; continue }
        if ($t.StartsWith('+')) { continue }
        # The first operand is the -c payload, or a script file.
        if ($hasC) { return (Inspect-Payload -Label "$sh -c" -Payload $t -Depth $Depth -Cwd $Cwd) }
        return (New-Verdict 'allow')
    }
    return (New-Verdict 'allow')
}

# The word after quote removal ("rm -rf" -> rm -rf).
function Get-DequotedWord {
    param([string]$S)
    $out = New-Object System.Text.StringBuilder
    $q = ''
    for ($i = 0; $i -lt $S.Length; $i++) {
        $ch = [string]$S[$i]
        if ($q -eq "'") {
            if ($ch -eq "'") { $q = '' } else { [void]$out.Append($ch) }
        } elseif ($ch -eq '\') {
            $i++
            if ($i -lt $S.Length) { [void]$out.Append($S[$i]) }
        } elseif ($q -ne '' -and $ch -eq $q) {
            $q = ''
        } elseif ($q -eq '' -and ($ch -eq "'" -or $ch -eq '"')) {
            $q = $ch
        } else {
            [void]$out.Append($ch)
        }
    }
    return $out.ToString()
}

# Record NAME=value, or forget NAME when the value still holds an expansion
# (`$`, `$(`, a backtick) or is an append (+=); see track_assign.
function Add-TrackedAssignment {
    param($Vars, [string]$Word)
    $eq = $Word.IndexOf('=')
    $name = $Word.Substring(0, $eq)
    $value = $Word.Substring($eq + 1)
    $known = $true
    if ($name.EndsWith('+')) { $name = $name.Substring(0, $name.Length - 1); $known = $false }
    if ($name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') { return }
    if ($value -match '[$`]') { $known = $false }
    if ($known) { $Vars[$name] = Get-DequotedWord $value } else { [void]$Vars.Remove($name) }
}

# The assignments of an assignment-only sub-command or of `export NAME=value`.
function Update-TrackedVars {
    param($Vars, [string[]]$Tokens)
    $words = $Tokens
    if ($Tokens[0] -ceq 'export') {
        $words = Skip-First $Tokens
    } elseif (@($Tokens | Where-Object { -not $_.Contains('=') }).Count -gt 0) {
        return
    }
    foreach ($t in $words) {
        if ($t.Contains('=')) { Add-TrackedAssignment -Vars $Vars -Word $t }
    }
}

# argv[0] is a variable outside a payload. A tracked `$NAME` / `${NAME}` is
# replaced by its words and inspected once; otherwise the arguments are
# inspected as rm's, and ask if rm would be refused.
function Inspect-VarHead {
    param([string[]]$Tokens, [string]$Cwd, $Vars)
    $head = $Tokens[0]
    $rest = Skip-First $Tokens
    $name = ''
    if ($head -cmatch '^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$' -or $head -cmatch '^\$([A-Za-z_][A-Za-z0-9_]*)$') {
        $name = $Matches[1]
    }
    if ($name -and $null -ne $Vars -and $Vars.ContainsKey($name)) {
        $words = @($Vars[$name] -split '\s+' | Where-Object { $_ -ne '' })
        return (Inspect-Argv -Tokens (@($words) + @($rest)) -Depth 0 -Cwd $Cwd -Vars $Vars -Resolved)
    }
    $r = Inspect-Rm -Tokens (@('rm') + @($rest)) -Cwd $Cwd
    if ($r.D -eq 'allow') { return $r }
    return (New-Verdict 'ask' "The command name comes from $head, which cannot be resolved statically; as rm this command would be refused ($($r.R)). Confirm to proceed.")
}

function Inspect-Argv {
    param([string[]]$Tokens, [int]$Depth, [string]$Cwd, $Vars = $null, [switch]$Resolved)
    $Tokens = @($Tokens | Where-Object { $null -ne $_ })
    if ($Tokens.Count -eq 0) { return (New-Verdict 'allow') }

    if ($Tokens[0] -match '=') {
        if ($Tokens[0] -clike 'IFS=*') {
            return (New-Verdict 'deny' 'Suspicious IFS reassignment in command scope')
        }
        $Tokens = Skip-First $Tokens
        if ($Tokens.Count -eq 0) { return (New-Verdict 'allow') }
    }

    $Tokens = @(Strip-WrapperPrefix -Tokens $Tokens)
    if ($Tokens.Count -eq 0) { return (New-Verdict 'allow') }

    $cmd0 = $Tokens[0]
    # Inside a payload, a head that is a parameter expansion runs text this
    # guard cannot see; `$(...)` heads were split out and inspected already.
    if ($Depth -gt 0 -and $cmd0.StartsWith('$') -and -not $cmd0.StartsWith('$(')) {
        return (New-Verdict 'deny' "Inline shell payload runs a variable expansion ($cmd0) that cannot be statically inspected; blocked (fail-closed)")
    }
    # Outside a payload, resolve a variable head once (#971). A head with a
    # path (`$X/bin/rm`) is matched on its basename below.
    if ($Depth -eq 0 -and -not $Resolved -and $cmd0.StartsWith('$') -and -not $cmd0.StartsWith('$(') -and $cmd0 -notmatch '[\\/]') {
        return (Inspect-VarHead -Tokens $Tokens -Cwd $Cwd -Vars $Vars)
    }

    # Match on the basename so `/bin/rm` and `/usr/bin/git` are inspected too.
    $name = $cmd0 -replace '^.*[\\/]', ''
    switch -CaseSensitive ($name) {
        'eval' {
            $rest = Skip-First $Tokens
            if ($rest.Count -eq 0) { return (New-Verdict 'allow') }
            return (Inspect-Payload -Label 'eval' -Payload ($rest -join ' ') -Depth $Depth -Cwd $Cwd)
        }
        { @('bash','sh','zsh','dash','ksh','fish') -ccontains $_ } { return (Inspect-InlineShell -Tokens $Tokens -Depth $Depth -Cwd $Cwd) }
        'rm'    { return (Inspect-Rm -Tokens $Tokens -Cwd $Cwd) }
        'chmod' { return (Inspect-Chmod -Tokens $Tokens) }
        'git'   { return (Inspect-Git -Tokens $Tokens -Cwd $Cwd) }
        'find'  { return (Inspect-Find -Tokens $Tokens) }
        'gh'    { return (Inspect-Gh -Tokens $Tokens) }
    }
    return (New-Verdict 'allow')
}

# Fetch piped (or substituted) into an interpreter: the splitter emits a
# substitution's inner command before its outer command, so
# `eval "$(curl ...)"` and `source <(curl ...)` arrive as curl, then eval.
function Detect-FetchPipeShell {
    param([string]$Prev, [string]$Curr)
    if (-not ($Prev -match '\bcurl\b' -or $Prev -match '\bwget\b')) { return $false }
    $first = @(Tokenize-Argv -Sub $Curr) | Select-Object -First 1
    $first = ([string]$first) -replace '^.*[\\/]', ''
    return @('sh','bash','zsh','dash','ksh','python','python2','python3','perl','ruby','node','eval','source','.') -ccontains $first
}

# Where a `cd`/`pushd` sub-command moves the directory later checks use.
function Get-CdTarget {
    param([string[]]$Tokens, [string]$Cwd)
    foreach ($t in (Skip-First $Tokens)) {
        if (@('-P','-L','-e','-@','--') -ccontains $t) { continue }
        return (Resolve-Dir -Base $Cwd -P $t)
    }
    return $HOME
}

# Inspect every sub-command. A deny returns at once; asks are collected and
# reported only when nothing denies.
function Inspect-Command {
    param([string]$Cmd, [int]$Depth, [string]$Cwd)
    $prev = ''
    $asks = New-Object System.Collections.Generic.List[string]
    # Shell variable names are case-sensitive.
    $vars = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
    foreach ($sub in @(Flatten-Subcommands -Cmd $Cmd)) {
        if ([string]::IsNullOrWhiteSpace($sub)) { continue }
        if ($prev -ne '' -and (Detect-FetchPipeShell -Prev $prev -Curr $sub)) {
            return (New-Verdict 'deny' 'Remote script execution via pipe blocked for security')
        }
        if ($sub -match '\$\{IFS\}' -or $sub -match '\$IFS\b') {
            return (New-Verdict 'deny' 'Suspicious IFS-based whitespace obfuscation in command')
        }
        $tokens = @(Tokenize-Argv -Sub $sub)
        if ($tokens.Count -gt 0 -and ($tokens[0] -ceq 'cd' -or $tokens[0] -ceq 'pushd')) {
            $Cwd = Get-CdTarget -Tokens $tokens -Cwd $Cwd
        }
        if ($tokens.Count -gt 0 -and ($tokens[0] -ceq 'export' -or $tokens[0].Contains('='))) {
            Update-TrackedVars -Vars $vars -Tokens $tokens
        }
        $r = Inspect-Argv -Tokens $tokens -Depth $Depth -Cwd $Cwd -Vars $vars
        if ($r.D -eq 'deny') { return $r }
        if ($r.D -eq 'ask' -and -not $asks.Contains($r.R)) { $asks.Add($r.R) }
        $prev = $sub
    }
    if ($asks.Count -gt 0) { return (New-Verdict 'ask' ($asks -join '; ')) }
    return (New-Verdict 'allow')
}

try {
    $verdict = Inspect-Command -Cmd $CMD -Depth 0 -Cwd $hookCwd
} catch {
    Respond-Deny "dangerous-command-guard: inspection failed (fail-closed): $($_.Exception.Message)"
}
switch ($verdict.D) {
    'deny' { Respond-Deny $verdict.R }
    'ask'  { Respond-Ask $verdict.R }
}
Respond-Allow
