#Requires -Version 7.0
# workspace.ps1
# issue-work: workspace lifecycle (CLAIMED -> CLONING -> READY)
# ================================================================
# PowerShell parity port of scripts/workspace.sh. Same functions, same
# behavior, same manifest format, same credential-redaction rule, same
# REJECTED path, same final JSON schema. See
# reference/workspace-lifecycle.md for the contract both scripts satisfy.
#
# NOTE (authoring-time caveat): pwsh was not available in the environment
# this port was written in, so it was produced by mirroring the
# bash-verified logic in workspace.sh line-for-line rather than by running
# it. It has NOT been executed. Cross-platform regression coverage is
# tracked in issue #832, consistent with the existing PowerShell-parity note
# in tests/issue-work/README.md for the triage stage.
#
# The script is both a sourceable library (dot-source it to get the
# functions below) and a CLI:
#   pwsh -File workspace.ps1 --repo <owner/name> --base <tmpbase> --issue <n>
#        [--clone-url <url>] [--manifest <path>]
# CLI flags intentionally mirror workspace.sh's flags exactly (rather than
# native PowerShell parameter binding) so the two entry points are
# interchangeable from a caller's point of view.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit from git is data here, not an error: workspace.sh reads it as
# a plain "false" -- a failed clone becomes a REJECTED outcome, a missing origin
# becomes a failed identity check. A host that has enabled
# $PSNativeCommandUseErrorActionPreference would promote those exits to
# terminating errors under the 'Stop' preference above and destroy the
# structured outcome, so the setting is pinned off for this script.
#
# Pinned at script scope rather than inside _workspace_git because several call
# sites invoke $script:GitBin directly (the clone, the origin lookup, and the
# baseline rev-parse); a wrapper-local guard would leave those unprotected.
$PSNativeCommandUseErrorActionPreference = $false

# Injection seams (overridable by tests and callers via environment
# variables, mirroring the bash GIT_BIN / WORKSPACE_* seams).
$script:GitBin = if ($env:GIT_BIN) { $env:GIT_BIN } else { 'git' }

# Marker filename dropped into the run root once claimed.
$script:WorkspaceMarkerFile = '.iw-run-marker'

# Set by _workspace_clone on failure; consumed by run_workspace to build a
# redacted REJECTED reason without ever touching git's raw output again.
$script:WorkspaceLastError = ''

# ── Low-level git wrapper ────────────────────────────────────────────
# All git access funnels through here so a fake git can shadow it via
# $env:GIT_BIN, mirroring _workspace_git in workspace.sh.
#
# Native-command failure is surfaced via $LASTEXITCODE, never a thrown
# exception: $ErrorActionPreference is locally lowered to 'Continue' so a benign
# non-zero git exit (a failed clone, or `remote get-url origin` on a repository
# without an origin) does NOT become a terminating error when the caller has
# enabled $PSNativeCommandUseErrorActionPreference under the script-scope 'Stop'
# preference. workspace.sh relies on that tolerance for the REJECTED clone path
# and the identity check; without this guard both would throw instead of
# returning a structured outcome. Mirrors _triage_gh in triage.ps1.
function _workspace_git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    & $script:GitBin @GitArgs
}

# ── Pure helpers (unit-testable without git) ──────────────────────────

# Strip credentials from a URL/string so `https://user:token@host/...`
# becomes `https://host/...`. Handles any `<userinfo>@` segment immediately
# following a `<scheme>://`, which covers the `x-access-token:<token>@` form
# used by gh/CI credential helpers. Matches anywhere in the input (not just
# at the start), so a credential embedded mid-sentence in a git error
# message is also redacted. A no-op on input with no scheme://userinfo@
# pattern.
function workspace_redact_credentials {
    param([AllowEmptyString()][string]$InputString = '')
    return [regex]::Replace($InputString, '([A-Za-z][A-Za-z0-9+.\-]*://)[^/@\s]*@', '$1')
}

function _workspace_default_suffix {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return "$ts$PID"
}

# Compute a unique run-root path under the given temp base, using a short
# issue-scoped name: "<base>/iw-<issue>-<suffix>". The suffix comes from the
# WORKSPACE_RUN_SUFFIX injection seam when set (tests use this for
# determinism); otherwise it falls back to a timestamp+pid combination so
# concurrent real runs do not collide.
function workspace_run_root {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string]$Issue)
    $suffix = if ($env:WORKSPACE_RUN_SUFFIX) { $env:WORKSPACE_RUN_SUFFIX } else { _workspace_default_suffix }
    $trimmedBase = $Base.TrimEnd('/', '\')
    return "$trimmedBase/iw-$Issue-$suffix"
}

# Reduce a (already-redacted) git remote URL to its trailing "owner/name"
# path component. Host-agnostic by design: strips a "<scheme>://<host>/"
# prefix or an SSH-shorthand "<user>@<host>:" prefix (or neither, for a bare
# local path used by tests), then takes the final two "/"-separated
# segments. Accepts both "https://github.com/owner/name(.git)" and
# "git@github.com:owner/name(.git)" as specified, while remaining usable
# against GitHub Enterprise hosts and local test doubles.
function _workspace_owner_name_from_origin {
    param([AllowEmptyString()][string]$Url = '')
    if ([string]::IsNullOrEmpty($Url)) { return $null }
    $cleaned = $Url
    if ($cleaned.EndsWith('.git')) { $cleaned = $cleaned.Substring(0, $cleaned.Length - 4) }

    $path = $null
    $schemeIdx = $cleaned.IndexOf('://')
    if ($schemeIdx -ge 0) {
        $noScheme = $cleaned.Substring($schemeIdx + 3)
        $slashIdx = $noScheme.IndexOf('/')
        $path = if ($slashIdx -ge 0) { $noScheme.Substring($slashIdx + 1) } else { $noScheme }
    } else {
        $colonIdx = $cleaned.IndexOf(':')
        $path = if ($colonIdx -ge 0) { $cleaned.Substring($colonIdx + 1) } else { $cleaned }
    }
    $path = $path.TrimEnd('/')
    $segments = $path -split '/'
    if ($segments.Count -lt 2) { return $null }
    $name = $segments[$segments.Count - 1]
    $owner = $segments[$segments.Count - 2]
    if ([string]::IsNullOrEmpty($owner) -or [string]::IsNullOrEmpty($name)) { return $null }
    return "$owner/$name"
}

# Read the origin remote of RepoDir, redact it, and succeed only when it
# resolves to the expected "owner/name". Rejects on mismatch, a missing
# origin, or an empty expected value. Native-command failure is detected via
# $LASTEXITCODE rather than a thrown exception, since whether a non-zero git
# exit becomes a terminating error depends on the pwsh minor version.
function workspace_verify_identity {
    param([string]$RepoDir, [string]$Expected)
    if ([string]::IsNullOrEmpty($RepoDir) -or [string]::IsNullOrEmpty($Expected)) { return $false }
    $origin = & $script:GitBin -C $RepoDir remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($origin)) { return $false }
    $origin = workspace_redact_credentials $origin
    $actual = _workspace_owner_name_from_origin $origin
    if ([string]::IsNullOrEmpty($actual)) { return $false }
    return [string]::Equals($actual, $Expected, [System.StringComparison]::Ordinal)
}

# Atomically update a single `key=value` line in a portable line-based
# manifest (no JSON dependency; readable by bash and PowerShell alike).
# Writes to "<path>.tmp.$PID" then moves it into place so a reader never
# observes a partially-written file. The value is always passed through
# workspace_redact_credentials before being written, so a URL-shaped value
# can never land in the manifest with embedded credentials.
function workspace_manifest_write {
    param([string]$Path, [string]$Key, [AllowEmptyString()][string]$Value = '')
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Key)) { return $false }
    $Value = workspace_redact_credentials $Value
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "$Path.tmp.$PID"
    $escapedKey = [regex]::Escape($Key)
    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $existing = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
        $lines = @($existing | Where-Object { $_ -notmatch "^$escapedKey=" })
    }
    $lines += "$Key=$Value"
    Set-Content -LiteralPath $tmp -Value $lines
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    return $true
}

# Print the value for Key in the manifest ("" if the manifest or key is
# absent). When a key was written more than once, the last write wins.
function workspace_manifest_read {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $escapedKey = [regex]::Escape($Key)
    $match = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^$escapedKey=" } |
        Select-Object -Last 1
    if (-not $match) { return '' }
    return $match.Substring($Key.Length + 1)
}

# Convenience accessor for the current `state=` value.
function workspace_manifest_state {
    param([string]$Path)
    return workspace_manifest_read -Path $Path -Key 'state'
}

# ── Marker ──────────────────────────────────────────────────────────
# Writes the run marker into RunRoot and returns its path. Content is a tiny
# key=value block (reuses the manifest line format) whose issue= line is the
# field a resumed session checks before trusting the run root.
function _workspace_write_marker {
    param([string]$RunRoot, [string]$Issue)
    $trimmedRoot = $RunRoot.TrimEnd('/', '\')
    $path = "$trimmedRoot/$script:WorkspaceMarkerFile"
    $created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content -LiteralPath $path -Value @("issue=$Issue", "created=$created")
    return $path
}

# ── Clone ───────────────────────────────────────────────────────────
# Clones Url's Branch into Dest. Shallowable via the WORKSPACE_CLONE_DEPTH
# seam (adds --depth when set); never recurses submodules. All git output is
# captured (never streamed to the caller's stdout/stderr) and, on failure,
# redacted into $script:WorkspaceLastError so a caller can report a reason
# without ever risking a credential leak through git's own error text.
function _workspace_clone {
    param([string]$Url, [string]$Branch, [string]$Dest)
    $depthArgs = @()
    if ($env:WORKSPACE_CLONE_DEPTH) { $depthArgs = @('--depth', $env:WORKSPACE_CLONE_DEPTH) }
    $out = & $script:GitBin clone --branch $Branch --single-branch --no-recurse-submodules @depthArgs $Url $Dest 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $joined = ($out | Out-String)
        $redacted = workspace_redact_credentials $joined
        $lastLine = ($redacted -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
        $script:WorkspaceLastError = if ($lastLine) { $lastLine } else { 'unknown error' }
    }
    return ($rc -eq 0)
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
function _workspace_emit_ready {
    param([string]$RunRoot, [string]$RepoDir, [string]$Baseline, [string]$Manifest, [string]$Marker)
    Write-Output ('{{"state":"READY","run_root":"{0}","repo_dir":"{1}","baseline":"{2}","manifest":"{3}","marker":"{4}"}}' `
        -f $RunRoot, $RepoDir, $Baseline, $Manifest, $Marker)
}

function _workspace_emit_rejected {
    param([string]$RunRoot, [string]$RepoDir, [string]$Manifest, [string]$Marker, [string]$Reason)
    $Reason = workspace_redact_credentials $Reason
    Write-Output ('{{"state":"REJECTED","reason":"{0}","run_root":"{1}","repo_dir":"{2}","manifest":"{3}","marker":"{4}"}}' `
        -f $Reason, $RunRoot, $RepoDir, $Manifest, $Marker)
}

# ── Driver ──────────────────────────────────────────────────────────
# run_workspace -Repo <owner/name> -Base <tmpbase> -Issue <n>
#                [-CloneUrl <url>] [-ManifestOverride <path>]
#
# Repo   expected "owner/name" identity, also used to derive the default
#        clone URL when CloneUrl is omitted.
# Base   temp base directory the run root is created under.
# Issue  issue number; scopes the run-root name and is recorded in the marker.
function run_workspace {
    param(
        [string]$Repo,
        [string]$Base,
        [string]$Issue,
        [string]$CloneUrl = '',
        [string]$ManifestOverride = ''
    )

    if ([string]::IsNullOrEmpty($Repo) -or [string]::IsNullOrEmpty($Base) -or [string]::IsNullOrEmpty($Issue)) {
        _workspace_emit_rejected '' '' '' '' 'missing required repo/base/issue'
        return 2
    }

    $runRoot = workspace_run_root -Base $Base -Issue $Issue
    try {
        New-Item -ItemType Directory -Path $runRoot -Force -ErrorAction Stop | Out-Null
    } catch {
        _workspace_emit_rejected $runRoot '' '' '' 'failed to create run root'
        return 1
    }

    $marker = _workspace_write_marker -RunRoot $runRoot -Issue $Issue
    $manifest = if ($ManifestOverride) { $ManifestOverride } else { "$runRoot/manifest" }

    workspace_manifest_write -Path $manifest -Key 'issue' -Value $Issue | Out-Null
    workspace_manifest_write -Path $manifest -Key 'repo' -Value $Repo | Out-Null
    workspace_manifest_write -Path $manifest -Key 'run_root' -Value $runRoot | Out-Null
    workspace_manifest_write -Path $manifest -Key 'marker' -Value $marker | Out-Null
    workspace_manifest_write -Path $manifest -Key 'state' -Value 'CLAIMED' | Out-Null

    # Enter CLONING before the clone actually starts, so a crash mid-clone
    # leaves the manifest correctly reflecting the in-progress phase rather
    # than the stale CLAIMED state.
    workspace_manifest_write -Path $manifest -Key 'state' -Value 'CLONING' | Out-Null
    $repoDir = "$runRoot/repo"
    $url = if ($CloneUrl) { $CloneUrl } else { "https://github.com/$Repo.git" }
    if (-not (_workspace_clone -Url $url -Branch 'develop' -Dest $repoDir)) {
        workspace_manifest_write -Path $manifest -Key 'state' -Value 'REJECTED' | Out-Null
        $errText = if ($script:WorkspaceLastError) { $script:WorkspaceLastError } else { 'unknown error' }
        _workspace_emit_rejected $runRoot $repoDir $manifest $marker "clone failed: $errText"
        return 1
    }

    $baseline = (& $script:GitBin -C $repoDir rev-parse HEAD 2>$null)

    if (-not (workspace_verify_identity -RepoDir $repoDir -Expected $Repo)) {
        workspace_manifest_write -Path $manifest -Key 'state' -Value 'REJECTED' | Out-Null
        _workspace_emit_rejected $runRoot $repoDir $manifest $marker "origin identity does not match expected repo $Repo"
        return 1
    }

    workspace_manifest_write -Path $manifest -Key 'repo_dir' -Value $repoDir | Out-Null
    workspace_manifest_write -Path $manifest -Key 'baseline' -Value $baseline | Out-Null
    workspace_manifest_write -Path $manifest -Key 'state' -Value 'READY' | Out-Null

    _workspace_emit_ready $runRoot $repoDir $baseline $manifest $marker
    return 0
}

# ── CLI entry ────────────────────────────────────────────────────────

# Split a driver result into "emit on stdout" and "use as the exit code".
#
# run_workspace writes its JSON to the success stream and then `return`s an int
# exit code -- but in PowerShell a `return` value also lands on the success
# stream, so the caller receives @(<json>, <int>) as one array. Passing that
# array straight to `exit` casts the whole array to int, which throws and takes
# the JSON down with it, so `pwsh -File workspace.ps1 ...` printed nothing at
# all while workspace.sh printed the outcome JSON (issue #847 S2).
#
# This helper writes every non-int item straight to the console and returns the
# trailing int as the exit code, restoring parity with the bash CLI.
# Dot-sourced callers are unaffected -- they consume the driver's return value
# directly.
#
# The payload goes out via [Console]::Out rather than Write-Output on purpose:
# Write-Output would put it back on the success stream alongside the returned
# exit code, reproducing the very merge this helper exists to undo.
function Split-WorkspaceCliResult {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Result)
    $items = @($Result)
    $code = 0
    if ($items.Count -gt 0 -and $items[-1] -is [int]) {
        $code = [int]$items[-1]
        # Note the explicit Count check: $items[0..($items.Count - 2)] would be
        # $items[0..-1] for a single-element array, and PowerShell reads -1 as
        # "last element", silently re-emitting the exit code as output.
        if ($items.Count -gt 1) {
            $items = $items[0..($items.Count - 2)]
        } else {
            $items = @()
        }
    }
    foreach ($item in $items) { [Console]::Out.WriteLine([string]$item) }
    return $code
}

function Invoke-WorkspaceMain {
    param([string[]]$Arguments = @())
    $repo = ''; $base = ''; $issue = ''; $cloneUrl = ''; $manifest = ''
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '--repo' { $repo = $Arguments[$i + 1]; $i += 2 }
            '--base' { $base = $Arguments[$i + 1]; $i += 2 }
            '--issue' { $issue = $Arguments[$i + 1]; $i += 2 }
            '--clone-url' { $cloneUrl = $Arguments[$i + 1]; $i += 2 }
            '--manifest' { $manifest = $Arguments[$i + 1]; $i += 2 }
            default {
                Write-Error "unknown argument: $($Arguments[$i])"
                return 2
            }
        }
    }
    if (-not $repo -or -not $base -or -not $issue) {
        Write-Error 'error: --repo <owner/name>, --base <tmpbase>, and --issue <n> are required'
        return 2
    }
    return run_workspace -Repo $repo -Base $base -Issue $issue -CloneUrl $cloneUrl -ManifestOverride $manifest
}

# Run as CLI only when executed directly; stay quiet when dot-sourced by
# tests (mirrors workspace.sh's BASH_SOURCE guard).
if ($MyInvocation.InvocationName -ne '.') {
    exit (Split-WorkspaceCliResult (Invoke-WorkspaceMain -Arguments $args))
}
