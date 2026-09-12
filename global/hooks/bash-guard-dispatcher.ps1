#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -WarningAction SilentlyContinue

# bash-guard-dispatcher.ps1
# Single entry point for every PreToolUse (Bash) guard.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always - the decision travels in the JSON payload)
#
# Why this exists: the 15 Bash guards were each registered as their own hook
# command, so one Bash tool call spawned 15 `pwsh -NoProfile` processes. Cold
# process start dominates (~350ms each, measured) while the actual guard logic
# costs ~13ms. This dispatcher pays the process cost once, reads stdin once,
# imports CommonHelpers once, and invokes only the guards whose command family
# is present in the tool input.
#
# Guard contract (see any *-guard.ps1): each guard accepts an optional
# -HookInput parameter carrying the already-parsed payload and falls back to
# reading stdin when it is absent, so every guard still runs standalone.
# Guards are invoked with `&` (never dot-sourced) so their `exit` terminates
# only the guard, not this dispatcher.
#
# Routing is deliberately COARSER than each guard's own filter: the prefilter
# only skips a guard when its command family is definitely absent, and every
# guard re-applies its own precise filter. A prefilter that is too narrow would
# silently disable a guard; too wide merely costs a few milliseconds.

# Unparseable input is fail-CLOSED, matching the strictest guard this dispatcher
# replaces: dangerous-command-guard denies on exactly this condition. Allowing
# here would silently weaken that guarantee the moment the guards stop being
# registered individually. Read-HookInput already absorbs the transient Windows
# stdin race with a bounded retry, so reaching $null here means the payload is
# genuinely absent or malformed.
$json = Read-HookInput
if (-not $json) {
    New-HookDenyResponse -Reason 'bash-guard-dispatcher: failed to parse hook input - denying for safety (fail-closed)'
    exit 0
}

$cmd = ''
try { $cmd = [string]$json.tool_input.command } catch {}

# ──────────────────────────────────────────────────────────────
# Routing table
#   closed = $true  -> a crash in this guard DENIES the call (security /
#                      branch-policy gates must never fail silently open)
#   closed = $false -> a crash warns via additionalContext and allows
#                      (validators whose authoritative gate lives elsewhere,
#                      e.g. the commit-msg git hook or CI)
# ──────────────────────────────────────────────────────────────
$guards = [System.Collections.Generic.List[hashtable]]::new()

# Always-on: these have no command filter of their own.
$guards.Add(@{ name = 'dangerous-command-guard';   closed = $true  })
$guards.Add(@{ name = 'bash-sensitive-read-guard'; closed = $true  })
$guards.Add(@{ name = 'shell-env-secret-guard';    closed = $true  })
$guards.Add(@{ name = 'bash-write-guard';          closed = $true  })

# gh family.
if ($cmd -match '(?i)(^|[\s`(;&|])gh\s') {
    $guards.Add(@{ name = 'gh-write-verb-guard';  closed = $true  })
    $guards.Add(@{ name = 'pr-target-guard';      closed = $true  })
    $guards.Add(@{ name = 'github-api-preflight'; closed = $false })
    $guards.Add(@{ name = 'traceability-guard';   closed = $false })
    $guards.Add(@{ name = 'attribution-guard';    closed = $false })
    $guards.Add(@{ name = 'pr-language-guard';    closed = $false })
    $guards.Add(@{ name = 'merge-gate-guard';     closed = $false })
}

# git family.
if ($cmd -match '(?i)(^|[\s`(;&|])git\s') {
    $guards.Add(@{ name = 'push-target-guard';         closed = $true  })
    $guards.Add(@{ name = 'markdown-anchor-validator'; closed = $false })
    $guards.Add(@{ name = 'commit-message-guard';      closed = $false })
    $guards.Add(@{ name = 'conflict-guard';            closed = $false })
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
        $contexts.Add("bash-guard-dispatcher: time budget exhausted, skipped $($g.name)")
        continue
    }

    $path = Join-Path $PSScriptRoot "$($g.name).ps1"
    if (-not (Test-Path $path)) {
        if ($g.closed) { $denies.Add("[$($g.name)] guard script missing: $path") }
        else           { $contexts.Add("[$($g.name)] guard script missing (fail-open)") }
        continue
    }

    try {
        $raw = & $path -HookInput $json
        if (-not $raw) { continue }

        # A guard may emit incidental lines; the response is the last one.
        $lastLine = ($raw | Where-Object { $_ } | Select-Object -Last 1)
        if (-not $lastLine) { continue }

        $r = ($lastLine | ConvertFrom-Json).hookSpecificOutput
        switch ($r.permissionDecision) {
            'deny' { $denies.Add("[$($g.name)] $($r.permissionDecisionReason)") }
            'ask'  { $denies.Add("[$($g.name)] $($r.permissionDecisionReason)") }
        }
        if ($r.additionalContext) { $contexts.Add([string]$r.additionalContext) }
    }
    catch {
        if ($g.closed) {
            $denies.Add("[$($g.name)] guard failed (fail-closed): $($_.Exception.Message)")
        } else {
            $contexts.Add("[$($g.name)] guard failed (fail-open): $($_.Exception.Message)")
        }
    }
}

if ($denies.Count -gt 0) {
    New-HookDenyResponse -Reason ($denies -join "`n")
} else {
    New-HookAllowResponse -AdditionalContext ($contexts -join "`n")
}
exit 0
