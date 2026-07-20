#Requires -Version 7.0
# Test suite for global/skills/_internal/issue-work/scripts/workspace.ps1
# Run: pwsh -NoProfile -File tests/issue-work/test-workspace.ps1
#
# PowerShell parity suite for tests/issue-work/test-workspace.sh. Drives the
# workspace lifecycle stage (CLAIMED -> CLONING -> READY) against a real local
# bare git repository -- no fake gh shim is needed because this stage never
# calls gh, and driving real git exercises the actual clone and remote-identity
# codepaths instead of a stand-in.
#
# AC -> test mapping (see reference/workspace-lifecycle.md):
#   AC1  run root layout        -> under temp base, uniquely named, valid marker
#   AC2  clone -> READY         -> develop clone reaches READY with correct baseline sha
#   AC3  identity mismatch      -> REJECTED, never reaches READY
#   AC4  credential redaction   -> manifest and stdout never contain a token
#   AC5  manifest atomicity     -> key=value round-trips via read; no tmp leftovers
#   UNIT pure-function coverage -> redact / verify_identity / manifest write+read
#
# PowerShell-only regression coverage (issue #847, commit 38df2ec):
#   S1   native-error pinning   -> a host with $PSNativeCommandUseErrorActionPreference
#                                  enabled still gets a structured REJECTED outcome
#                                  from a failing clone instead of a thrown
#                                  NativeCommandExitException
#   S2   CLI stdout parity      -> `pwsh -File workspace.ps1 ...` actually prints the
#                                  outcome JSON (it previously printed nothing at all,
#                                  because the driver's @(json, exitcode) success-stream
#                                  array was cast whole to int by `exit`)

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Workspace = Join-Path $RootDir 'global/skills/_internal/issue-work/scripts/workspace.ps1'

$Pass = 0
$Fail = 0
$Errors = @()

# GetTempPath() honors $TMPDIR, so this suite is stable under sandboxes that
# restrict the OS default temp directory but expose $TMPDIR, as well as under
# plain CI runners where $TMPDIR is unset. Resolve-Path collapses the macOS
# /var -> /private/var symlink so derived paths match what git reports.
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("iw-workspace-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
$Work = (Resolve-Path -LiteralPath $Work).Path.TrimEnd('/', '\')

function Add-Pass {
    param([string]$Label)
    $script:Pass++
    Write-Host "  PASS: $Label"
}

function Add-Fail {
    param([string]$Label, [string]$Detail = '')
    $script:Fail++
    $script:Errors += "FAIL: $Label$(if ($Detail) { " -- $Detail" })"
    Write-Host "  FAIL: $Label$(if ($Detail) { " -- $Detail" })"
}

# String comparison throughout, mirroring bash's `[ "$a" = "$b" ]`.
function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ([string]$Expected -eq [string]$Actual) {
        Add-Pass $Label
    } else {
        Add-Fail $Label "expected '$Expected', got '$Actual'"
    }
}

function Assert-Contains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) {
        Add-Pass $Label
    } else {
        Add-Fail $Label "'$Needle' not in output"
    }
}

function Assert-NotContains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) {
        Add-Fail $Label "'$Needle' unexpectedly present"
    } else {
        Add-Pass $Label
    }
}

function Assert-True {
    param($Value, [string]$Label)
    if ($Value -is [bool] -and $Value) {
        Add-Pass $Label
    } else {
        Add-Fail $Label "expected \$true, got '$Value'"
    }
}

function Assert-False {
    param($Value, [string]$Label)
    if ($Value -is [bool] -and -not $Value) {
        Add-Pass $Label
    } else {
        Add-Fail $Label "expected \$false, got '$Value'"
    }
}

# Read one field out of the driver's outcome JSON. Guarded for StrictMode:
# an absent property is reported as '' rather than throwing.
function Get-JsonField {
    param([string]$Json, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    try { $obj = $Json | ConvertFrom-Json } catch { return '' }
    if ($obj.PSObject.Properties.Name -contains $Field) { return [string]$obj.$Field }
    return ''
}

# Reads whose path is derived from the driver's JSON must degrade to '' rather
# than throw when the driver emitted nothing. Otherwise a single regression
# aborts the run mid-way instead of reporting every failing assertion -- bash's
# `cat`/`workspace_manifest_read` degrade this way, and the summary block at the
# bottom is only useful if execution reaches it.
function Get-FileText {
    param([AllowEmptyString()][string]$Path = '')
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
}

function Get-ManifestValue {
    param([AllowEmptyString()][string]$Path = '', [string]$Key)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [string](workspace_manifest_read -Path $Path -Key $Key)
}

function Get-ManifestState {
    param([AllowEmptyString()][string]$Path = '')
    return (Get-ManifestValue -Path $Path -Key 'state')
}

# Builds a bare "remote" laid out as <owner>/<name>.git under $Work/remote,
# seeds it with one commit on a "develop" branch, and returns the bare repo
# path (used as --clone-url so the origin recorded after cloning reduces to
# "<owner>/<name>", matching workspace_verify_identity's expectations).
function New-FixtureRemote {
    param([string]$Owner, [string]$Name)
    $remote = "$Work/remote/$Owner/$Name.git"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $remote) | Out-Null
    & git init --bare -q $remote
    $seed = "$Work/seed-$Owner-$Name"
    & git init -q -b develop $seed
    & git -C $seed config user.email 'test@example.com'
    & git -C $seed config user.name 'test'
    Set-Content -LiteralPath "$seed/file.txt" -Value 'content'
    & git -C $seed add file.txt
    & git -C $seed commit -q -m 'seed commit' | Out-Null
    & git -C $seed remote add origin $remote
    & git -C $seed push -q origin develop 2>&1 | Out-Null
    return $remote
}

# Run workspace.ps1 through its CLI entry point, the way a caller would. This
# is deliberately an out-of-process `pwsh -File` run rather than a dot-sourced
# call to run_workspace, so every scenario below also exercises the S2 CLI
# stdout path (Split-WorkspaceCliResult).
function Invoke-WorkspaceCli {
    param([string]$Suffix, [string[]]$CliArgs, [string]$GitBin = '')
    $prevSuffix = $env:WORKSPACE_RUN_SUFFIX
    $prevGitBin = $env:GIT_BIN
    $env:WORKSPACE_RUN_SUFFIX = $Suffix
    if ($GitBin) { $env:GIT_BIN = $GitBin }
    try {
        return ((& pwsh -NoProfile -File $Workspace @CliArgs 2>&1 | Out-String).Trim())
    } finally {
        if ($null -eq $prevSuffix) {
            Remove-Item Env:WORKSPACE_RUN_SUFFIX -ErrorAction SilentlyContinue
        } else {
            $env:WORKSPACE_RUN_SUFFIX = $prevSuffix
        }
        if ($null -eq $prevGitBin) {
            Remove-Item Env:GIT_BIN -ErrorAction SilentlyContinue
        } else {
            $env:GIT_BIN = $prevGitBin
        }
    }
}

try {
    Write-Host "=== workspace.ps1 unit tests (pure functions) ==="
    . $Workspace

    # --- Fake credential material (secret-scanner-safe) --------------------
    # Redaction is structural (it strips a "scheme://<userinfo>@" span), so the
    # placeholder value is irrelevant to what is tested. We use a low-entropy,
    # clearly-fake secret with NO real token prefix and assemble credential URLs
    # from it, so no complete "scheme://user:secret@host" literal (or token-shaped
    # string) is ever committed to source. This satisfies the no-secrets-in-source
    # policy and keeps secret scanners (e.g. GitGuardian) quiet.
    $FakeSecret = 'placeholder-not-a-real-secret'
    $FakeUserinfo = "x-access-token:$FakeSecret"

    # workspace_redact_credentials.
    $r1 = workspace_redact_credentials "https://$FakeUserinfo@github.com/owner/name.git"
    Assert-Equal 'https://github.com/owner/name.git' $r1 'redact strips x-access-token userinfo'
    $r2 = workspace_redact_credentials "fatal: unable to access 'https://$FakeUserinfo@host/owner/name.git/': could not resolve"
    Assert-NotContains $FakeSecret $r2 'redact strips creds embedded mid-message'
    Assert-Contains 'https://host/owner/name.git' $r2 'redact preserves the scheme and path'
    $r3 = workspace_redact_credentials 'plain text, no url here'
    Assert-Equal 'plain text, no url here' $r3 'redact is a no-op on non-URL input'
    $r4 = workspace_redact_credentials 'git@github.com:owner/name.git'
    Assert-Equal 'git@github.com:owner/name.git' $r4 'redact leaves SSH shorthand untouched (no embedded secret)'

    # workspace_run_root.
    $env:WORKSPACE_RUN_SUFFIX = 'abc123'
    $rr1 = workspace_run_root -Base "$Work/base" -Issue 838
    Assert-Equal "$Work/base/iw-838-abc123" $rr1 'run_root composes base/iw-<issue>-<suffix>'
    $env:WORKSPACE_RUN_SUFFIX = 'xyz789'
    $rr2 = workspace_run_root -Base "$Work/base" -Issue 838
    if ($rr1 -ne $rr2) {
        Add-Pass 'run_root differs when the suffix seam differs'
    } else {
        Add-Fail 'run_root should differ for a different suffix'
    }
    Remove-Item Env:WORKSPACE_RUN_SUFFIX -ErrorAction SilentlyContinue

    # workspace_manifest_write / workspace_manifest_read round trip + atomicity.
    $mpath = "$Work/unit-manifest"
    workspace_manifest_write -Path $mpath -Key 'state' -Value 'CLAIMED' | Out-Null
    Assert-Equal 'CLAIMED' (workspace_manifest_read -Path $mpath -Key 'state') 'manifest round-trips a fresh key'
    workspace_manifest_write -Path $mpath -Key 'state' -Value 'CLONING' | Out-Null
    Assert-Equal 'CLONING' (workspace_manifest_state -Path $mpath) 'manifest_state reflects the latest write'
    $stateLines = @(Get-Content -LiteralPath $mpath | Where-Object { $_ -match '^state=' })
    Assert-Equal 1 $stateLines.Count 'manifest update replaces the key rather than duplicating it'
    $leftover = @(Get-ChildItem -LiteralPath $Work -Filter 'unit-manifest.tmp.*' -File -ErrorAction SilentlyContinue)
    Assert-Equal 0 $leftover.Count 'manifest write leaves no .tmp.$PID file behind'
    Assert-Equal '' (workspace_manifest_read -Path $mpath -Key 'nonexistent_key') 'manifest_read is empty for an absent key'

    # workspace_manifest_write redacts a credential-bearing value before it ever
    # touches disk (AC4, targeted at the manifest half of the guarantee).
    workspace_manifest_write -Path $mpath -Key 'origin_seen' -Value "https://$FakeUserinfo@github.com/o/n.git" | Out-Null
    Assert-NotContains $FakeSecret (Get-Content -LiteralPath $mpath -Raw) 'manifest never stores a raw credential'
    Assert-Equal 'https://github.com/o/n.git' (workspace_manifest_read -Path $mpath -Key 'origin_seen') 'manifest stores the redacted form'

    # workspace_verify_identity.
    $idRepo = "$Work/id-repo"
    & git init -q $idRepo
    & git -C $idRepo remote add origin 'https://github.com/acme/widgets.git'
    Assert-True (workspace_verify_identity -RepoDir $idRepo -Expected 'acme/widgets') 'verify_identity accepts a matching https origin'
    Assert-False (workspace_verify_identity -RepoDir $idRepo -Expected 'someone/else') 'verify_identity rejects a mismatched owner/name'

    & git -C $idRepo remote set-url origin 'git@github.com:acme/widgets.git'
    Assert-True (workspace_verify_identity -RepoDir $idRepo -Expected 'acme/widgets') 'verify_identity accepts a matching SSH-shorthand origin'

    $noOriginRepo = "$Work/no-origin-repo"
    & git init -q $noOriginRepo
    Assert-False (workspace_verify_identity -RepoDir $noOriginRepo -Expected 'acme/widgets') 'verify_identity rejects a repo with no origin'
    Assert-False (workspace_verify_identity -RepoDir $idRepo -Expected '') 'verify_identity rejects an empty expected value'

    Write-Host ""
    Write-Host "=== AC1: run root under temp base, uniquely named, valid marker ==="
    $base1 = "$Work/base1"
    New-Item -ItemType Directory -Force -Path $base1 | Out-Null
    $remote1 = New-FixtureRemote 'acme' 'widgets'
    $out1 = Invoke-WorkspaceCli 'run1' @('--repo', 'acme/widgets', '--base', $base1, '--issue', '838', '--clone-url', $remote1)
    $runRoot1 = Get-JsonField $out1 'run_root'
    Assert-Contains "$base1/iw-838-run1" $runRoot1 'AC1 run root is under the temp base with the expected name'
    Assert-Equal $true (Test-Path -LiteralPath "$runRoot1/.iw-run-marker" -PathType Leaf) 'AC1 marker file exists in the run root'
    Assert-Contains 'issue=838' (Get-FileText "$runRoot1/.iw-run-marker") 'AC1 marker content includes the issue number'

    $out1b = Invoke-WorkspaceCli 'run1b' @('--repo', 'acme/widgets', '--base', $base1, '--issue', '838', '--clone-url', $remote1)
    $runRoot1b = Get-JsonField $out1b 'run_root'
    if ($runRoot1 -ne $runRoot1b) {
        Add-Pass 'AC1 two runs for the same issue get uniquely named run roots'
    } else {
        Add-Fail 'AC1 run roots should differ across runs'
    }

    Write-Host ""
    Write-Host "=== AC2: clone from develop reaches READY with correct baseline sha ==="
    $base2 = "$Work/base2"
    New-Item -ItemType Directory -Force -Path $base2 | Out-Null
    $remote2 = New-FixtureRemote 'acme' 'gadgets'
    $expectedSha = (& git -C "$Work/seed-acme-gadgets" rev-parse develop).Trim()
    $out2 = Invoke-WorkspaceCli 'run2' @('--repo', 'acme/gadgets', '--base', $base2, '--issue', '900', '--clone-url', $remote2)
    Assert-Equal 'READY' (Get-JsonField $out2 'state') 'AC2 outcome=READY'
    Assert-Equal $expectedSha (Get-JsonField $out2 'baseline') 'AC2 baseline matches the seeded develop HEAD'
    $repoDir2 = Get-JsonField $out2 'repo_dir'
    Assert-Equal $true (Test-Path -LiteralPath "$repoDir2/file.txt" -PathType Leaf) 'AC2 clone actually checked out the working tree'
    $manifest2 = Get-JsonField $out2 'manifest'
    Assert-Equal 'READY' (Get-ManifestState $manifest2) 'AC2 manifest state reaches READY'
    Assert-Equal $expectedSha (Get-ManifestValue $manifest2 'baseline') 'AC2 manifest records the baseline'

    Write-Host ""
    Write-Host "=== AC3: identity/origin mismatch is REJECTED, never reaches READY ==="
    $base3 = "$Work/base3"
    New-Item -ItemType Directory -Force -Path $base3 | Out-Null
    $remote3 = New-FixtureRemote 'other' 'owner'
    $out3 = Invoke-WorkspaceCli 'run3' @('--repo', 'acme/mismatch', '--base', $base3, '--issue', '901', '--clone-url', $remote3)
    Assert-Equal 'REJECTED' (Get-JsonField $out3 'state') 'AC3 outcome=REJECTED on identity mismatch'
    Assert-Contains 'acme/mismatch' (Get-JsonField $out3 'reason') 'AC3 reason names the expected repo'
    $manifest3 = Get-JsonField $out3 'manifest'
    Assert-Equal 'REJECTED' (Get-ManifestState $manifest3) 'AC3 manifest never advances to READY'
    Assert-NotContains 'READY' $out3 'AC3 stdout JSON never claims READY'

    Write-Host ""
    Write-Host "=== AC4: credentials never appear in stdout or the manifest ==="
    $base4 = "$Work/base4"
    New-Item -ItemType Directory -Force -Path $base4 | Out-Null
    $remote4 = New-FixtureRemote 'acme' 'secure'
    $out4 = Invoke-WorkspaceCli 'run4' @('--repo', 'acme/secure', '--base', $base4, '--issue', '902', '--clone-url', $remote4, '--manifest', "$base4/iw-902-run4/manifest")
    Assert-Equal 'READY' (Get-JsonField $out4 'state') 'AC4 baseline run reaches READY (sanity precondition)'
    Assert-NotContains $FakeSecret $out4 'AC4 stdout never contains the fake token'
    Assert-NotContains $FakeSecret (Get-FileText "$base4/iw-902-run4/manifest") 'AC4 manifest never contains the fake token'
    # The token above never entered the run at all (defense-in-depth baseline);
    # the manifest_write unit test earlier already proves a credential-bearing
    # value handed directly to the manifest primitive is redacted before write.

    # AC4b: exercise the real clone-failure redaction path (_workspace_clone's
    # $script:WorkspaceLastError handling) without any network access, by
    # shadowing git with a local shim (via the GIT_BIN seam) whose "clone"
    # subcommand fails and emits a credential-bearing URL, mimicking what a real
    # git failure against an authenticated remote looks like.
    #
    # The shim is a .ps1 rather than an executable shell script (which is what
    # test-workspace.sh uses): PowerShell runs a .ps1 named by `& $GitBin`
    # in-process, so no executable bit or shebang is needed and the shim works
    # unchanged on Windows. This mirrors the fake-gh.ps1 invocation contract.
    # It writes the error text to the success stream because _workspace_clone
    # captures with `2>&1` -- the merged stream is what the script reads, so
    # stdout and stderr are equivalent here, and Write-Output avoids the
    # multi-line formatting Write-Error would splice into the reason.
    $fakeGit = "$Work/fake-git-clone-fail.ps1"
    $fakeGitBody = @'
if ($args.Count -gt 0 -and $args[0] -eq 'clone') {
    Write-Output "fatal: unable to access 'https://__USERINFO__@github.com/acme/failing.git/': Could not resolve host"
    exit 1
}
exit 0
'@
    Set-Content -LiteralPath $fakeGit -Value $fakeGitBody.Replace('__USERINFO__', $FakeUserinfo)

    $base4b = "$Work/base4b"
    New-Item -ItemType Directory -Force -Path $base4b | Out-Null
    $out4b = Invoke-WorkspaceCli 'run4b' @('--repo', 'acme/failing', '--base', $base4b, '--issue', '903', '--clone-url', "https://$FakeUserinfo@github.com/acme/failing.git") -GitBin $fakeGit
    Assert-Equal 'REJECTED' (Get-JsonField $out4b 'state') 'AC4b clone failure yields REJECTED'
    Assert-Contains 'clone failed' (Get-JsonField $out4b 'reason') 'AC4b reason names the clone failure'
    Assert-NotContains $FakeSecret $out4b "AC4b stdout never contains git's own credential-bearing error"
    $manifest4b = "$base4b/iw-903-run4b/manifest"
    Assert-NotContains $FakeSecret (Get-FileText $manifest4b) "AC4b manifest never contains git's own credential-bearing error"

    Write-Host ""
    Write-Host "=== AC5: manifest updates are atomic and key=value round-trips ==="
    $manifest5 = "$Work/atomic-manifest"
    workspace_manifest_write -Path $manifest5 -Key 'a' -Value '1' | Out-Null
    workspace_manifest_write -Path $manifest5 -Key 'b' -Value '2' | Out-Null
    workspace_manifest_write -Path $manifest5 -Key 'a' -Value '3' | Out-Null
    Assert-Equal '3' (workspace_manifest_read -Path $manifest5 -Key 'a') 'AC5 later write for the same key wins'
    Assert-Equal '2' (workspace_manifest_read -Path $manifest5 -Key 'b') 'AC5 unrelated key is preserved across updates'
    $kvLines = @(Get-Content -LiteralPath $manifest5 | Where-Object { $_ -match '=' })
    Assert-Equal 2 $kvLines.Count 'AC5 manifest has exactly one line per key'

    Write-Host ""
    Write-Host "=== S2 (#847): the CLI entry point actually prints its outcome JSON ==="
    # Before commit 38df2ec, `pwsh -File workspace.ps1 ...` printed nothing:
    # run_workspace returns @(<json>, <int>) on the success stream and `exit`
    # cast the whole array to int, throwing and taking the JSON with it. Every
    # scenario above already runs through the CLI, so these assertions pin the
    # specific shape that regressed.
    $base6 = "$Work/base6"
    New-Item -ItemType Directory -Force -Path $base6 | Out-Null
    $remote6 = New-FixtureRemote 'acme' 'cliparity'
    $outS2 = Invoke-WorkspaceCli 'runs2' @('--repo', 'acme/cliparity', '--base', $base6, '--issue', '905', '--clone-url', $remote6)
    if (-not [string]::IsNullOrWhiteSpace($outS2)) {
        Add-Pass 'S2 CLI stdout is non-empty'
    } else {
        Add-Fail 'S2 CLI stdout is non-empty' 'the CLI printed nothing'
    }
    $s2Lines = @($outS2 -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    Assert-Equal 1 $s2Lines.Count 'S2 CLI emits exactly one line (the exit code is not re-emitted as output)'
    Assert-Contains '"state":"READY"' $outS2 'S2 CLI stdout carries the outcome JSON'
    Assert-Equal 'READY' (Get-JsonField $outS2 'state') 'S2 CLI stdout parses as JSON with a state field'
    Assert-Equal 'acme/cliparity' (Get-ManifestValue (Get-JsonField $outS2 'manifest') 'repo') 'S2 CLI JSON manifest path is usable by the caller'

    # Split-WorkspaceCliResult in isolation, including the single-element edge
    # case the helper explicitly guards ($items[0..-1] would otherwise re-emit
    # the exit code as output).
    # Each call gets its own capture buffer so the "lone int emits nothing"
    # assertion is exact rather than an absence-check over shared output.
    $origOut = [Console]::Out
    $swBoth = [System.IO.StringWriter]::new()
    $swOnly = [System.IO.StringWriter]::new()
    try {
        [Console]::SetOut($swBoth)
        $codeBoth = Split-WorkspaceCliResult '{"state":"READY"}' 0
        [Console]::SetOut($swOnly)
        $codeOnly = Split-WorkspaceCliResult 2
    } finally {
        [Console]::SetOut($origOut)
    }
    Assert-Equal 0 $codeBoth 'S2 Split-WorkspaceCliResult returns the trailing int as the exit code'
    Assert-Equal 2 $codeOnly 'S2 Split-WorkspaceCliResult returns a lone int as the exit code'
    Assert-Contains '{"state":"READY"}' $swBoth.ToString() 'S2 Split-WorkspaceCliResult writes the payload to the console'
    Assert-Equal '' $swOnly.ToString().Trim() 'S2 Split-WorkspaceCliResult never re-emits a lone exit code as output'

    Write-Host ""
    Write-Host "=== S1 (#847): native-command error action is pinned off ==="
    # workspace.ps1 sets $ErrorActionPreference='Stop' at script scope. A host
    # that has enabled $PSNativeCommandUseErrorActionPreference would therefore
    # promote git's non-zero exit to a terminating NativeCommandExitException and
    # destroy the structured REJECTED outcome. The script pins the setting off;
    # this drives a failing clone from a host session that explicitly turns it on.
    $s1Driver = "$Work/s1-driver.ps1"
    $s1Body = @'
$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
& '__WORKSPACE__' --repo acme/ghost --base '__BASE__' --issue 904 --clone-url '__URL__'
exit $LASTEXITCODE
'@
    $s1Body = $s1Body.Replace('__WORKSPACE__', $Workspace).Replace('__BASE__', "$Work/base-s1").Replace('__URL__', "$Work/definitely-does-not-exist.git")
    Set-Content -LiteralPath $s1Driver -Value $s1Body

    $env:WORKSPACE_RUN_SUFFIX = 'runs1'
    $outS1 = (& pwsh -NoProfile -File $s1Driver 2>&1 | Out-String).Trim()
    $codeS1 = $LASTEXITCODE
    Remove-Item Env:WORKSPACE_RUN_SUFFIX -ErrorAction SilentlyContinue

    Assert-NotContains 'NativeCommandExitException' $outS1 'S1 a failing clone does not throw NativeCommandExitException'
    Assert-Equal 'REJECTED' (Get-JsonField $outS1 'state') 'S1 a failing clone still yields a structured REJECTED outcome'
    Assert-Contains 'clone failed' (Get-JsonField $outS1 'reason') 'S1 the REJECTED reason still names the clone failure'
    Assert-Equal 1 $codeS1 'S1 the CLI still exits 1 rather than crashing'
    Assert-Equal 'REJECTED' (Get-ManifestState "$Work/base-s1/iw-904-runs1/manifest") 'S1 the manifest still records REJECTED'
}
finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  $Pass passed, $Fail failed"
if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:"
    foreach ($err in $Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
