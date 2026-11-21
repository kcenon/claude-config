#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for bash-guard-dispatcher.ps1
# Run: pwsh tests/hooks/test-bash-guard-dispatcher.ps1
#
# The dispatcher is the sole PreToolUse/Bash hook on Windows: it reads the
# payload once, then invokes the individual guards in-process. Two properties
# are load-bearing and neither is visible from a decision alone:
#
#   1. The payload must REACH each guard. stdin can only be drained once, so
#      the guards' own Read-HookInput calls depend on the process-lifetime cache
#      in lib/CommonHelpers.psm1. If that cache regresses, every guard sees
#      $null - fail-closed guards deny everything, fail-open guards silently
#      stop checking. A test that only asserts "deny" would still pass in the
#      first case, so the reason string is asserted too.
#   2. Unparseable input must fail CLOSED, matching dangerous-command-guard.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'bash-guard-dispatcher.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

# The real guards behind the dispatcher log their decisions. They write to a
# scratch directory, so the suite never touches ~/.claude/logs (#1030).
$script:SavedLogDir = $env:CLAUDE_LOG_DIR
$script:LogRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bgd-logs-" + [guid]::NewGuid().ToString('N'))
$env:CLAUDE_LOG_DIR = $script:LogRoot

function Invoke-Dispatcher {
    param([string]$InputJson)
    $raw = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    $line = ($raw | Where-Object { $_ -match '"hookSpecificOutput"' } | Select-Object -Last 1)
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json).hookSpecificOutput } catch { return $null }
}

function Assert-Decision {
    param([string]$InputJson, [string]$Expected, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    if ($r -and $r.permissionDecision -eq $Expected) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $got = if ($r) { $r.permissionDecision } else { '(no parseable response)' }
        $script:Errors.Add("FAIL: $Label - expected $Expected, got: $got")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-ReasonMatches {
    param([string]$InputJson, [string]$Pattern, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    $reason = if ($r) { [string]$r.permissionDecisionReason } else { '' }
    if ($reason -match $Pattern) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - reason did not match /$Pattern/, got: $reason")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-ReasonNotMatches {
    param([string]$InputJson, [string]$Pattern, [string]$Label)
    $r = Invoke-Dispatcher $InputJson
    $reason = if ($r) { [string]$r.permissionDecisionReason } else { '' }
    if ($reason -notmatch $Pattern) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - reason unexpectedly matched /$Pattern/, got: $reason")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

$benign    = '{"tool_name":"Bash","tool_input":{"command":"git status --short"}}'
$dangerous = '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
$readEnv   = '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
$ghMerge   = '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --merge"}}'

Write-Host '=== bash-guard-dispatcher.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-closed on unparseable input]'
Assert-Decision -InputJson ''             -Expected 'deny' -Label 'Empty input -> deny'
Assert-Decision -InputJson 'INVALID_JSON' -Expected 'deny' -Label 'Malformed JSON -> deny'

Write-Host ''
Write-Host '[Routing: always-on guards]'
Assert-Decision -InputJson $dangerous -Expected 'deny'  -Label 'rm -rf / -> deny'
Assert-Decision -InputJson $benign    -Expected 'allow' -Label 'git status --short -> allow'

Write-Host ''
Write-Host '[Routing: Windows-only sensitive-read guard (#964)]'
Assert-Decision -InputJson $readEnv -Expected 'deny' -Label 'cat .env -> deny'

Write-Host ''
Write-Host '[Routing: Windows-only env-secret guard (#964)]'
# A printed secret-bearing variable is denied; a bare environment dump is
# allowed with a warning. Both leave a log line, checked further down (#1040).
$echoSecret = '{"tool_name":"Bash","tool_input":{"command":"echo $API_KEY"}}'
$envDump    = '{"tool_name":"Bash","tool_input":{"command":"env"}}'
Assert-Decision      -InputJson $echoSecret -Expected 'deny'  -Label 'echo $API_KEY -> deny'
Assert-ReasonMatches -InputJson $echoSecret -Pattern '\[shell-env-secret-guard\]' `
    -Label 'env-secret deny is attributed to shell-env-secret-guard'
Assert-Decision      -InputJson $envDump    -Expected 'allow' -Label 'env -> allow (warning only)'

Write-Host ''
Write-Host '[Routing: gh family]'
# merge-gate-guard no longer restricts the merge method (#964). Without a PR
# number it never calls gh, so the --merge decision is deterministic: allow.
Assert-Decision -InputJson $ghMerge -Expected 'allow' -Label 'gh pr merge --merge -> allow'

Write-Host ''
Write-Host '[Payload reaches the guards (process-lifetime cache)]'
# The distinguishing evidence: a guard that received the payload denies with its
# own diagnosis. A guard that received $null denies with a parse-failure string.
# Both are "deny", so only the reason separates a working cache from a broken one.
Assert-ReasonMatches    -InputJson $dangerous -Pattern 'dangerous-command-guard' `
    -Label 'Deny is attributed to the guard that made it'
Assert-ReasonNotMatches -InputJson $dangerous -Pattern 'failed to parse hook input' `
    -Label 'Deny is NOT a parse failure (cache delivered the payload)'
Assert-ReasonNotMatches -InputJson $dangerous -Pattern 'guard failed \(fail-closed\)' `
    -Label 'No guard crashed while being invoked'
Assert-ReasonMatches    -InputJson $readEnv   -Pattern 'bash-sensitive-read-guard' `
    -Label 'sensitive-read deny is attributed to bash-sensitive-read-guard'

Write-Host ''
Write-Host '[Decision merge: deny > ask > allow (#964)]'
# Real guards: dangerous-command-guard asks before `git stash clear`, and
# bash-sensitive-read-guard denies a read of .env. The ask must survive the
# merge instead of being turned into a deny, and a deny must still win over it.
$askOnly  = '{"tool_name":"Bash","tool_input":{"command":"git stash clear"}}'
$askDeny  = '{"tool_name":"Bash","tool_input":{"command":"git stash clear && cat .env"}}'
Assert-Decision      -InputJson $askOnly -Expected 'ask'  -Label 'ask alone -> ask'
Assert-ReasonMatches -InputJson $askOnly -Pattern '\[dangerous-command-guard\]' `
    -Label 'ask reason is attributed to the guard that asked'
Assert-Decision      -InputJson $askDeny -Expected 'deny' -Label 'ask + deny -> deny'
Assert-ReasonMatches -InputJson $askDeny -Pattern '\[bash-sensitive-read-guard\]' `
    -Label 'ask + deny reason names the denying guard'
Assert-Decision      -InputJson $benign  -Expected 'allow' -Label 'allow only -> allow'

Write-Host ''
Write-Host '[Both stages, as settings.windows.json runs them (#1041)]'
# The registered command sources bash-guard-dispatcher.sh into the Git Bash
# process of the hook. That stage answers a call no guard rule can match and
# hands every other payload to this dispatcher. The decisions must be the ones
# the dispatcher gives on its own.
function Get-HookBash {
    # A bare `bash` on Windows can be the WSL launcher; take the one that ships
    # with git, which is the one Claude Code uses.
    if ($IsWindows) {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git) {
            $dir = Split-Path -Parent $git.Source
            foreach ($up in 1..3) {
                $dir = Split-Path -Parent $dir
                if (-not $dir) { break }
                foreach ($rel in 'bin\bash.exe', 'usr\bin\bash.exe') {
                    $candidate = Join-Path $dir $rel
                    if (Test-Path -LiteralPath $candidate) { return $candidate }
                }
            }
        }
    }
    $found = Get-Command bash -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

function Invoke-BothStages {
    param([string]$InputJson, [string]$FirstStage)
    $raw = $InputJson | & $script:HookBash -c ". '$FirstStage'" 2>$null
    $line = ($raw | Where-Object { $_ -match '"hookSpecificOutput"' } | Select-Object -Last 1)
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json).hookSpecificOutput } catch { return $null }
}

$script:HookBash = Get-HookBash
if (-not $script:HookBash) {
    Write-Host '  SKIP: no bash found; the Bash tool does not run on such a machine either'
} else {
    $firstStage = (Join-Path $script:RepoRoot 'global' 'hooks' 'bash-guard-dispatcher.sh') -replace '\\', '/'
    $chainCases = @(
        @($benign,        'allow', 'git status --short -> allow (first stage alone)'),
        @($dangerous,     'deny',  'rm -rf / -> deny'),
        @($readEnv,       'deny',  'cat .env -> deny'),
        @($echoSecret,    'deny',  'echo $API_KEY -> deny'),
        @($askOnly,       'ask',   'git stash clear -> ask'),
        @($ghMerge,       'allow', 'gh pr merge --merge -> allow (through the guards)'),
        @('',             'deny',  'Empty input -> deny'),
        @('INVALID_JSON', 'deny',  'Malformed JSON -> deny')
    )
    foreach ($c in $chainCases) {
        $r = Invoke-BothStages -InputJson $c[0] -FirstStage $firstStage
        $got = if ($r) { $r.permissionDecision } else { '(no parseable response)' }
        if ($got -eq $c[1]) {
            $script:Passed++
            Write-Host "  PASS: both stages: $($c[2])" -ForegroundColor Green
        } else {
            $script:Failed++
            $script:Errors.Add("FAIL: both stages: $($c[2]) - expected $($c[1]), got: $got")
            Write-Host "  FAIL: both stages: $($c[2])" -ForegroundColor Red
        }
    }

    # The fast path must not need the second stage at all. Run the first stage
    # from a directory that holds nothing else: a call it answers itself is
    # still allowed, and one it hands on has nobody to answer it.
    $aloneRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bgd-first-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $aloneRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'global' 'hooks' 'bash-guard-dispatcher.sh') -Destination $aloneRoot
    $aloneStage = (Join-Path $aloneRoot 'bash-guard-dispatcher.sh') -replace '\\', '/'
    $alone = Invoke-BothStages -InputJson $benign -FirstStage $aloneStage
    $handed = Invoke-BothStages -InputJson $dangerous -FirstStage $aloneStage
    Remove-Item -LiteralPath $aloneRoot -Recurse -Force -ErrorAction SilentlyContinue
    $aloneChecks = @(
        @('first stage answers git status --short without the second stage', ($alone -and $alone.permissionDecision -eq 'allow')),
        @('first stage does not answer rm -rf / itself', (-not $handed -or $handed.permissionDecision -ne 'allow'))
    )
    foreach ($c in $aloneChecks) {
        if ($c[1]) {
            $script:Passed++
            Write-Host "  PASS: $($c[0])" -ForegroundColor Green
        } else {
            $script:Failed++
            $script:Errors.Add("FAIL: $($c[0])")
            Write-Host "  FAIL: $($c[0])" -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host '[Decision logs go to CLAUDE_LOG_DIR (#1030)]'
# The guards above wrote their lines here and nowhere else: each one logs to
# a single directory, CLAUDE_LOG_DIR when it is set.
$dcgLog = Join-Path $script:LogRoot 'dangerous-command-guard.log'
$secretLog = Join-Path $script:LogRoot 'shell-env-secret-guard.log'
$dcgText = if (Test-Path -LiteralPath $dcgLog) { Get-Content -LiteralPath $dcgLog -Raw } else { '' }
$secretText = if (Test-Path -LiteralPath $secretLog) { Get-Content -LiteralPath $secretLog -Raw } else { '' }
# Every command above that shell-env-secret-guard allowed plainly must have
# left no line: only deny and allow-warn are logged (#1040). The closing quote
# keeps "allow" from matching "allow-warn".
$logChecks = @(
    @('dangerous-command-guard logged the rm -rf / deny in the scratch directory', ($dcgText -match '"decision":"deny"[^\n]*"command":"rm -rf /"')),
    @('shell-env-secret-guard logged the echo $API_KEY deny in the scratch directory', ($secretText -match '"decision":"deny"[^\n]*"command":"echo \$API_KEY"')),
    @('shell-env-secret-guard logged the env dump as allow-warn', ($secretText -match '"decision":"allow-warn"[^\n]*"command":"env"')),
    @('shell-env-secret-guard logged no plain allow', ($secretText -notmatch '"decision":"allow"'))
)
foreach ($c in $logChecks) {
    if ($c[1]) {
        $script:Passed++
        Write-Host "  PASS: $($c[0])" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $($c[0]) - nothing found under $($script:LogRoot)")
        Write-Host "  FAIL: $($c[0])" -ForegroundColor Red
    }
}

# Stub guards pin the merge itself, independent of any real guard's rules:
# a copy of the dispatcher runs next to stubs that answer from markers in
# the command (ASK:<guard> / DENY:<guard>).
$stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bgd-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stubRoot 'lib') -Force | Out-Null
Copy-Item -LiteralPath $script:HookPath -Destination $stubRoot
Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'global' 'hooks' 'lib' 'CommonHelpers.psm1') -Destination (Join-Path $stubRoot 'lib')
$stub = @'
param($HookInput)
$name = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$cmd = [string]$HookInput.tool_input.command
$d = 'allow'
if ($cmd -match "DENY:$name\b") { $d = 'deny' } elseif ($cmd -match "ASK:$name\b") { $d = 'ask' }
$o = @{ hookEventName = 'PreToolUse'; permissionDecision = $d }
if ($d -ne 'allow') { $o.permissionDecisionReason = "stub $d from $name" }
@{ hookSpecificOutput = $o } | ConvertTo-Json -Compress -Depth 3
'@
foreach ($g in @('dangerous-command-guard', 'bash-sensitive-read-guard', 'shell-env-secret-guard')) {
    Set-Content -LiteralPath (Join-Path $stubRoot "$g.ps1") -Value $stub
}
$realHook = $script:HookPath
$script:HookPath = Join-Path $stubRoot 'bash-guard-dispatcher.ps1'
$stubAsk     = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard"}}'
$stubAskDeny = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard DENY:shell-env-secret-guard"}}'
$stubTwoAsks = '{"tool_name":"Bash","tool_input":{"command":"echo ASK:dangerous-command-guard ASK:shell-env-secret-guard"}}'
$stubAllow   = '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
Assert-Decision      -InputJson $stubAsk     -Expected 'ask'   -Label 'stub: ask alone -> ask'
Assert-Decision      -InputJson $stubAskDeny -Expected 'deny'  -Label 'stub: ask + deny -> deny'
Assert-ReasonNotMatches -InputJson $stubAskDeny -Pattern 'stub ask' `
    -Label 'stub: deny reason does not carry the ask reason'
Assert-Decision      -InputJson $stubTwoAsks -Expected 'ask'   -Label 'stub: two asks -> one ask'
Assert-ReasonMatches -InputJson $stubTwoAsks -Pattern '(?s)\[dangerous-command-guard\].*\[shell-env-secret-guard\]' `
    -Label 'stub: one ask joins every asking guard''s reason'
Assert-Decision      -InputJson $stubAllow   -Expected 'allow' -Label 'stub: allow only -> allow'
$script:HookPath = $realHook
Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $script:LogRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($null -eq $script:SavedLogDir) { Remove-Item Env:CLAUDE_LOG_DIR -ErrorAction SilentlyContinue } else { $env:CLAUDE_LOG_DIR = $script:SavedLogDir }

Write-Host ''
# Emit the summary in the repo-standard shape. test-runner.ps1 aggregates with
# /(\d+)\s+passed/ and /(\d+)\s+failed/, and PowerShell -match is
# case-insensitive, so a "Passed: N  Failed: M" line has its N read as the
# FAILED count ("N  Failed" matches the second pattern).
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Failed -gt 0) {
    Write-Host ''
    $script:Errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
exit 0
