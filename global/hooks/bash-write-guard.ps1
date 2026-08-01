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

# The directory-token arm accepts a bare anchor (start, whitespace, quote,
# redirect, or `=` for `dd of=`) in addition to a path separator, so relative
# forms like `> secrets/db.yml` are denied in lockstep with the .sh guard,
# and covers all three tokens — `passwords` was previously missing even in
# the separator-anchored form (issue #871).
# The shell has not expanded pathname globs yet, so `*` and `?` must count as
# boundaries after `.env`. Otherwise `*.env*` matches no env arm here and can
# expand over a real env file only after the hook has allowed it (issue #876).
$sensitiveTargetRegex = '(\.env([.\s''"*?]|$))|((\.ssh)[/\\](id_|[A-Za-z0-9_-]+_(rsa|dsa|ecdsa|ed25519)))|(\.aws[/\\]credentials)|(\.kube[/\\]config)|(/etc/(shadow|sudoers|passwd|hosts))|(\.(pem|key|p12|pfx)(\s|$|[''"]))|((^|[\s/\\''">=])(secrets|credentials|passwords)[/\\])'

# Env-file templates (.env.example, .env.example.*, .env.sample, .env.template)
# are committed on purpose and never carry real secrets; sensitive-file-guard.ps1
# allows the same four names on the file channel, so denying them here was a
# cross-channel divergence (issue #866). Applied by masking the template mention
# out of the text handed to $sensitiveTargetRegex, so a template named alongside
# a real secret (`cp x .env.example && cp y .env`) still denies on the secret.
# The placeholder is deliberately dot-free and slash-free so it cannot match any
# arm of the regex above.
$envTemplateMention = '(?i)(^|[\s/\\])\.env\.(?:example(?:\.[^\s''";|&]*)?|sample|template)(?=[\s''";|&]|$)'
function Get-EnvTemplateMasked([string]$text) {
    return [regex]::Replace($text, $envTemplateMention, '${1}env_template_placeholder')
}

# Uninspectable patterns — always denied. Inline interpreter code (-c/-e) is
# opaque and routinely rewrites files, so the arm stays unconditional.
$uninspectableRegex = '\b(python\d?|node|perl|ruby)\s+-(c|e|E)\b'

# awk is NOT denied on the bare command word. This mirrors the whitelist branch
# in bash-write-guard.sh: an awk body writes via `print > FILE`, `print >> FILE`
# or `print | "cmd"`, so only the awk PROGRAM token is inspected and a redirect
# operator inside it is what denies. Flag values (-F'|', -F '|', -v sep='a|b')
# are skipped so a field separator never false-positives as a write operator.
#
# The previous `\b(awk|gawk|mawk)\b` arm denied EVERY awk invocation, including
# read-only projections like `ps aux | awk '{print $2}'`. That divergence from
# the bash guard was pinned in tests/hooks/test-bash-write-guard.ps1 as an
# approximation artifact; this restores .ps1/.sh parity and unpins it.
function Get-AwkProgram([string]$cmdLine) {
    # Quote-aware tokenizer: single-quoted (no escapes, per POSIX shell),
    # double-quoted (backslash escapes honoured), else a bare word. Escapes must
    # be handled or `awk "BEGIN{print \"x\" > \"f\"}"` truncates at the first
    # \" and its redirect goes unseen.
    $tokens = [regex]::Matches($cmdLine, '''[^'']*''|"(?:\\.|[^"\\])*"|\S+') |
              ForEach-Object { $_.Value }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i].Trim('"', "'") -notmatch '^(awk|gawk|mawk)$') { continue }
        $j = $i + 1
        while ($j -lt $tokens.Count) {
            $arg = $tokens[$j]
            if ($arg -match '^(-F|-v|-f|--file)$') { $j += 2; continue }  # flag, value separate
            if ($arg -match '^(-F|-v|-f).+')       { $j += 1; continue }  # flag, value attached
            if ($arg -match '^--')                 { $j += 1; continue }
            if ($arg -match '^-.')                 { $j += 1; continue }
            break
        }
        if ($j -lt $tokens.Count) { Write-Output ($tokens[$j].Trim('"', "'")) }
    }
}

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
    if ((Get-EnvTemplateMasked $target) -match $sensitiveTargetRegex) {
        New-HookDenyResponse -Reason "Bash write to sensitive file blocked: $target"
        exit 0
    }
}

# Uninspectable mutation pattern.
if ($cmd -match $uninspectableRegex) {
    New-HookDenyResponse -Reason "Uninspectable file mutation pattern; use Edit/Write tool instead"
    exit 0
}

# awk: deny only when the program token carries a redirect or pipe operator.
foreach ($program in (Get-AwkProgram $cmd)) {
    if ($program -match '[>|]') {
        New-HookDenyResponse -Reason "Uninspectable file mutation pattern (awk script may write via redirection); use Edit/Write tool instead"
        exit 0
    }
}

# Sensitive-target check via cp/mv/tee/install argument scan: any sensitive
# pattern preceded by a write tool (best-effort regex).
if ($cmd -match $writeToolRegex) {
    if ((Get-EnvTemplateMasked $cmd) -match $sensitiveTargetRegex) {
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
