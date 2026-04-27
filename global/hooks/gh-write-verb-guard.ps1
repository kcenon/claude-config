#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force

# gh-write-verb-guard.ps1
# PowerShell parity for gh-write-verb-guard.sh.
#
# Approximation note (Issue #478): this script implements the same policy
# (block `gh api` write methods unless allow-listed; block GraphQL
# mutations/subscriptions; deny cross-repo state-change subcommands; warn
# via additionalContext on in-scope state changes) but uses regex over
# the raw command string instead of the bash tokenizer. Substitution-aware
# splitting is therefore weaker on Windows. The bash variant is canonical.

$json = Read-HookInput
if (-not $json) { New-HookAllowResponse; exit 0 }

$cmd = ''
try { $cmd = [string]$json.tool_input.command } catch {}
if ([string]::IsNullOrEmpty($cmd)) { New-HookAllowResponse; exit 0 }

# Quick filter.
if ($cmd -notmatch '(^|[\s`(])gh\s') {
    New-HookAllowResponse; exit 0
}

$auditOnly = ($env:GH_WRITE_VERB_GUARD_AUDIT_ONLY -eq '1')

function Deny([string]$reason) {
    if ($auditOnly) {
        [Console]::Error.WriteLine("gh-write-verb-guard (audit-only) would deny: $reason")
        New-HookAllowResponse
        exit 0
    }
    New-HookDenyResponse -Reason $reason
    exit 0
}

function AllowWithContext([string]$context) {
    $payload = @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'allow'
            additionalContext = "gh-write-verb-guard: $context"
        }
    }
    $payload | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

# Split sub-commands on shell separators. This is intentionally simpler
# than the bash splitter: it does not respect quotes. Treat each segment
# as a candidate gh invocation.
$segments = [regex]::Split($cmd, '\s*(?:&&|\|\||;|\||&)\s*')

# --- GraphQL mutation scan (across the whole command string for safety) ---
if ($cmd -match 'gh\s+api\s+graphql\b') {
    $queryMatches = [regex]::Matches($cmd, '-(?:f|F|-field|-raw-field)(?:=|\s+)([^''"\s][^\s]*|''[^'']*''|"[^"]*")')
    foreach ($m in $queryMatches) {
        $payload = $m.Groups[1].Value.Trim('"', "'")
        if ($payload -match '^query=(.*)$') {
            $doc = $Matches[1]
            if ($doc -match '^@') {
                Deny "GraphQL opaque-file-reference blocked: payload references @$doc — cannot statically inspect for mutation/subscription operations."
            }
            $stripped = ($doc -replace '#[^\n]*','')
            if ($stripped -match '(^|[^A-Za-z0-9_])(mutation|subscription)([\s][A-Za-z_][A-Za-z0-9_]*)?\s*[\{(]') {
                Deny "GraphQL graphql-mutation-or-subscription blocked: gh api graphql may not carry mutating or subscription operations. Use a specific gh subcommand or restrict the document to a query."
            }
        }
    }
    # Explicit non-GET/POST methods on graphql.
    if ($cmd -match 'gh\s+api\s+graphql\b.*?(?:-X|--method)(?:\s+|=)(PATCH|PUT|DELETE)') {
        $m = $Matches[1]
        Deny "gh api graphql -X $m blocked: GraphQL endpoint only accepts GET/POST."
    }
    # Other gh api segments still need method checking below.
}

# --- gh api method gate (non-graphql) ---
$apiSegments = $segments | Where-Object { $_ -match 'gh\s+api\b' -and $_ -notmatch 'gh\s+api\s+graphql\b' }
foreach ($seg in $apiSegments) {
    $method = 'GET'
    if ($seg -match '(?:-X|--method)(?:\s+|=)(\w+)') {
        $method = $Matches[1].ToUpper()
    } elseif ($seg -match '(?:-f|-F|--field|--raw-field|--input)\b') {
        $method = 'POST'
    }
    if ($method -in @('GET','HEAD')) { continue }

    # Allowlist endpoints from $env:GH_API_WRITE_ALLOW (':' or newline separated).
    $endpoint = $null
    if ($seg -match 'gh\s+api(?:\s+-\S+(?:\s+\S+)?)*\s+([^\s-][^\s]*)') {
        $endpoint = $Matches[1]
    }
    $allowGlobs = @()
    if ($env:GH_API_WRITE_ALLOW) {
        $allowGlobs = $env:GH_API_WRITE_ALLOW -split '[:`r`n]' | Where-Object { $_ }
    }
    $allowed = $false
    foreach ($g in $allowGlobs) {
        if ($endpoint -and $endpoint -like $g) { $allowed = $true; break }
    }
    if (-not $allowed) {
        $ep = if ($endpoint) { $endpoint } else { '<no-endpoint>' }
        Deny "gh api -X $method $ep blocked: write methods require an explicit endpoint on the GH_API_WRITE_ALLOW allowlist. Use a dedicated gh subcommand."
    }
}

# --- gh state-change subcommands ---
$stateChangePattern = 'gh\s+(issue\s+(comment|edit|close|reopen|delete|develop|lock|unlock|pin|unpin|transfer)|pr\s+(comment|edit|close|reopen|review|merge|ready|lock|unlock)|workflow\s+(run|enable|disable)|secret\s+(set|delete|remove)|variable\s+(set|delete|remove)|ssh-key\s+(add|delete)|gpg-key\s+(add|delete)|gist\s+(create|edit|delete|clone)|release\s+(create|edit|upload|delete)|repo\s+(create|delete|edit|fork|rename|archive|unarchive)|cache\s+delete|label\s+(create|edit|delete|clone))'

$stateLabels = @()
foreach ($seg in $segments) {
    if ($seg -match $stateChangePattern) {
        $label = $Matches[1] -replace '\s+',' '
        # Cross-repo write check.
        if ($seg -match '(?:--repo(?:\s+|=)|\s-R\s+)(\S+)') {
            $targetRepo = $Matches[1].Trim('"', "'")
            $currentRepo = $null
            try {
                $url = (& git remote get-url origin 2>$null).Trim()
                if ($url -match 'github\.com[:/](.+?)(?:\.git)?$') {
                    $currentRepo = $Matches[1]
                }
            } catch {}
            if ($currentRepo -and $targetRepo -ne $currentRepo) {
                Deny "gh $label --repo $targetRepo blocked: cross-repo write does not match working tree origin ($currentRepo)."
            }
        }
        $stateLabels += $label
    }
}

if ($stateLabels.Count -gt 0) {
    AllowWithContext "state-changing gh operation(s) detected: $($stateLabels -join '; ')"
}

New-HookAllowResponse
exit 0
