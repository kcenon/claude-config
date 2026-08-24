#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -WarningAction SilentlyContinue

# edit-guard-dispatcher.ps1
# Single entry point for every PreToolUse (Edit|Write|Read) guard.
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0 (always - the decision travels in the JSON payload)
#
# Why this exists: the three Edit|Write|Read guards were each registered as
# their own hook command, so one file edit spawned three `pwsh -NoProfile`
# processes. Cold process start dominates while the guard logic itself costs a
# few milliseconds. This dispatcher pays the process cost once, reads stdin
# once, imports CommonHelpers once, and invokes only the guards that can act on
# the payload. Same pattern as bash-guard-dispatcher.ps1 (issue #895).
#
# How the payload reaches each guard: NOT through a parameter. No guard declares
# a param() block, so the -HookInput argument below lands in $args and is
# ignored. What actually delivers the payload is the process-lifetime cache in
# Read-HookInput (lib/CommonHelpers.psm1): this dispatcher drains stdin once and
# every guard's own Read-HookInput call then returns the cached object. The
# argument is passed anyway to stay forward-compatible with a guard that later
# declares the parameter. Guards are invoked with `&` (never dot-sourced) so
# their `exit` terminates only the guard, not this dispatcher.
#
# Routing is deliberately COARSER than each guard's own filter: the prefilter
# only skips a guard when it definitely cannot act, and every guard re-applies
# its own precise filter. A prefilter that is too narrow would silently disable
# a guard; too wide merely costs a few milliseconds.

# Unparseable input is fail-CLOSED, matching the strictest guard this dispatcher
# replaces: sensitive-file-guard denies on exactly this condition, while the
# other two fail open. stdin can only be drained once, so the dispatcher has to
# pick one policy for all three, and weakening the security guard is not an
# option. Read-HookInput already absorbs the transient Windows stdin race with a
# bounded retry, so reaching $null here means the payload is genuinely absent or
# malformed.
$json = Read-HookInput
if (-not $json) {
    New-HookDenyResponse -Reason 'edit-guard-dispatcher: failed to parse hook input - denying for safety (fail-closed)'
    exit 0
}

$toolName = ''
$filePath = ''
try { $toolName = [string]$json.tool_name } catch {}
try { $filePath = [string]$json.tool_input.file_path } catch {}

# ──────────────────────────────────────────────────────────────
# Routing table. ORDER IS LOAD-BEARING - see issues #424, #521.
#
#   closed       = $true  -> a crash in this guard DENIES the call (security
#                            gates must never fail silently open)
#   closed       = $false -> a crash warns via additionalContext and allows
#   shortCircuit = $true  -> a deny from this guard stops the chain immediately
#
# sensitive-file-guard must run BEFORE pre-edit-read-guard so that files it
# denies are never recorded in the read-set tracker. The harness does not stop
# at the first denying hook - measured on 212 denied calls, guards after the
# denial still ran, and two live trackers contain *.env paths that
# sensitive-file-guard denies. Registering the guards separately therefore could
# not enforce the documented order at all. In-process, it can: shortCircuit is
# what actually makes the invariant hold.
#
# Only sensitive-file-guard short-circuits. A deny from the other two is
# collected and merged as usual, so a caller still sees every applicable reason
# rather than just the first one.
# ──────────────────────────────────────────────────────────────
$guards = [System.Collections.Generic.List[hashtable]]::new()

# Always-on: applies to Edit, Write and Read alike.
$guards.Add(@{ name = 'sensitive-file-guard'; closed = $true; shortCircuit = $true })

# Always-on: guard mode on Edit/Write, track mode on Read (emits no JSON there).
$guards.Add(@{ name = 'pre-edit-read-guard'; closed = $false; shortCircuit = $false })

# Memory writes only. This is the one heavy guard - it shells out to validate.sh,
# secret-check.sh and injection-check.sh - and its own gate accepts nothing
# outside $HOME/.claude/memory-shared/memories/*.md. Prefiltering on the coarse
# 'memory-shared' substring keeps every path the guard could act on while
# skipping the subprocess cost for ordinary edits. Read is excluded because the
# guard returns allow for any tool that is not Edit or Write.
if (($toolName -eq 'Edit' -or $toolName -eq 'Write') -and $filePath -match '(?i)memory-shared') {
    $guards.Add(@{ name = 'memory-write-guard'; closed = $false; shortCircuit = $false })
}

# ──────────────────────────────────────────────────────────────
# Execution and decision merge
# ──────────────────────────────────────────────────────────────
$denies   = [System.Collections.Generic.List[string]]::new()
$contexts = [System.Collections.Generic.List[string]]::new()
$budgetMs = 25000
$sw       = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($g in $guards) {
    if ($sw.ElapsedMilliseconds -gt $budgetMs) {
        # Never truncate silently: say which guards did not run.
        $contexts.Add("edit-guard-dispatcher: time budget exhausted, skipped $($g.name)")
        continue
    }

    $path = Join-Path $PSScriptRoot "$($g.name).ps1"
    if (-not (Test-Path $path)) {
        if ($g.closed) { $denies.Add("[$($g.name)] guard script missing: $path") }
        else           { $contexts.Add("[$($g.name)] guard script missing (fail-open)") }
        continue
    }

    $decision = ''
    try {
        $raw = & $path -HookInput $json

        # A guard may emit incidental lines, and pre-edit-read-guard emits
        # nothing at all in track mode; the response, if any, is the last line.
        $lastLine = ($raw | Where-Object { $_ } | Select-Object -Last 1)
        if ($lastLine) {
            $r = ($lastLine | ConvertFrom-Json).hookSpecificOutput
            $decision = [string]$r.permissionDecision
            switch ($decision) {
                'deny' { $denies.Add("[$($g.name)] $($r.permissionDecisionReason)") }
                'ask'  { $denies.Add("[$($g.name)] $($r.permissionDecisionReason)") }
            }
            if ($r.additionalContext) { $contexts.Add([string]$r.additionalContext) }
        }
    }
    catch {
        if ($g.closed) {
            $denies.Add("[$($g.name)] guard failed (fail-closed): $($_.Exception.Message)")
            $decision = 'deny'
        } else {
            $contexts.Add("[$($g.name)] guard failed (fail-open): $($_.Exception.Message)")
        }
    }

    # Stop before the next guard can observe a target this one rejected.
    if ($g.shortCircuit -and ($decision -eq 'deny' -or $decision -eq 'ask')) {
        New-HookDenyResponse -Reason ($denies -join "`n")
        exit 0
    }
}

if ($denies.Count -gt 0) {
    New-HookDenyResponse -Reason ($denies -join "`n")
} else {
    New-HookAllowResponse -AdditionalContext ($contexts -join "`n")
}
exit 0
