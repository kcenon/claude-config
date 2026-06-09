#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# bash-write-guard.ps1
# Detects file-mutation patterns in Bash commands. Partial mirror of
# bash-write-guard.sh (Issue #477).
#
# Coverage on PowerShell hosts:
#   - Sensitive-target blocking: enforced for BOTH redirection targets and
#     write-tool argv targets (cp/mv/tee/install/sed -i/...) via pattern
#     match — the security-relevant cases are covered on every host.
#   - Uninspectable mutations (python/node/perl/ruby -c|-e, awk bodies):
#     denied with a message to use the Edit/Write tool instead.
#   - Read-before-Edit: enforced for redirection targets ONLY. Unlike
#     bash-write-guard.sh it is NOT applied to argv write-tool destinations
#     (e.g. `cp src existing.py`), because faithful per-tool argv target
#     extraction needs the shell tokenizer the .sh sources from hooks/lib
#     (tokenize-shell.sh). Closing that soft-guard gap is tracked as a
#     follow-up; it does not affect the sensitive-target protection above.

$json = Read-HookInput
if (-not $json) {
    New-HookAllowResponse
    exit 0
}

$cmd = ''
try { $cmd = [string]$json.tool_input.command } catch {}
if ([string]::IsNullOrEmpty($cmd)) {
    New-HookAllowResponse
    exit 0
}

$sessionId = $env:CLAUDE_SESSION_ID
if ([string]::IsNullOrEmpty($sessionId)) {
    try { $sessionId = [string]$json.session_id } catch {}
}
if ([string]::IsNullOrEmpty($sessionId)) { $sessionId = 'unknown' }

$trackerDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
$tracker = Join-Path $trackerDir ("claude-read-set-{0}" -f $sessionId)

$sensitiveTargetRegex = '(\.env([.\s''"]|$))|((\.ssh)[/\\](id_|[A-Za-z0-9_-]+_(rsa|dsa|ecdsa|ed25519)))|(\.aws[/\\]credentials)|(\.kube[/\\]config)|(/etc/(shadow|sudoers|passwd|hosts))|(\.(pem|key|p12|pfx)(\s|$|[''"]))|([/\\]secrets[/\\])|([/\\]credentials[/\\])'

# Uninspectable patterns — always denied.
$uninspectableRegex = '\b(python\d?|node|perl|ruby)\s+-(c|e|E)\b|\b(awk|gawk|mawk)\b'

# Known write-tool argv heads.
$writeToolRegex = '\b(tee|cp|mv|install|rsync|scp|dd|truncate|ln|chmod|chown|chgrp|sed\s+-i|sed\s+--in-place)\b'

# Redirect-to-file target extraction (best-effort; ignores `&>`/`2>&1`/`/dev/null`).
function Get-RedirectTarget([string]$cmdLine) {
    $matches = [regex]::Matches($cmdLine, '(?<![0-9&])>+\s*([^\s|;&<>]+)')
    foreach ($m in $matches) {
        $tgt = $m.Groups[1].Value.Trim('"', "'")
        if ($tgt -ne '/dev/null' -and $tgt -ne '/dev/stderr' -and $tgt -ne '/dev/stdout' -and $tgt -ne '/dev/tty') {
            Write-Output $tgt
        }
    }
}

# Sensitive-target check on any redirect target.
foreach ($target in (Get-RedirectTarget $cmd)) {
    if ($target -match $sensitiveTargetRegex) {
        New-HookDenyResponse -Reason "Bash write to sensitive file blocked: $target"
        exit 0
    }
}

# Uninspectable mutation pattern.
if ($cmd -match $uninspectableRegex) {
    New-HookDenyResponse -Reason "Uninspectable file mutation pattern; use Edit/Write tool instead"
    exit 0
}

# Sensitive-target check via cp/mv/tee/install argument scan: any sensitive
# pattern preceded by a write tool (best-effort regex).
if ($cmd -match $writeToolRegex) {
    if ($cmd -match $sensitiveTargetRegex) {
        New-HookDenyResponse -Reason "Bash write to sensitive file blocked (write-tool argument matches sensitive pattern)"
        exit 0
    }
}

# Read-before-Edit on existing redirect targets.
if (Test-Path -LiteralPath $tracker) {
    foreach ($target in (Get-RedirectTarget $cmd)) {
        $resolved = $target
        try {
            if (Test-Path -LiteralPath $target) {
                $resolved = (Resolve-Path -LiteralPath $target -ErrorAction Stop).Path
            }
        } catch {}
        if (Test-Path -LiteralPath $resolved -PathType Leaf) {
            $hit = $false
            try { $hit = (Get-Content -LiteralPath $tracker -ErrorAction SilentlyContinue) -contains $resolved } catch {}
            if (-not $hit) {
                New-HookDenyResponse -Reason "Cannot Bash-write '$target' without reading it first in this session. Call Read on '$target' and retry."
                exit 0
            }
        }
    }
}

New-HookAllowResponse
exit 0
