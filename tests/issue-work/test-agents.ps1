#Requires -Version 7.0
# Test suite for global/skills/_internal/issue-work/scripts/agents.ps1
# Run: pwsh -NoProfile -File tests/issue-work/test-agents.ps1
#
# PowerShell parity suite for tests/issue-work/test-agents.sh. Drives the
# subagent spawn-contract + single-writer-lease stage
# (READY -> AGENTS_RUNNING -> COMMITTED) against a real local git repository --
# no fake gh shim is needed because this stage never calls gh, and driving real
# git exercises the actual worktree add/remove codepaths instead of a stand-in.
# Dot-sourcing agents.ps1 also loads workspace.ps1, so the #838 manifest
# primitive (workspace_manifest_*) is available for assertions.
#
# AC -> test mapping (see reference/workspace-lifecycle.md, #839 sections):
#   AC1  path normalization    -> a relative path resolves to an absolute path
#   AC2  spawn-prompt contract -> prompt carries every required field + the
#                                 full prohibition clause
#   AC3  lease mutual exclusion -> one writer at a time; re-acquire after release
#   AC4  lease fail-safe       -> non-owner release refused; missing lease fails cleanly
#   AC5  per-agent worktree    -> add then remove leaves no orphan
#   AC6  state transitions     -> READY -> AGENTS_RUNNING -> COMMITTED
#   AC7  capability guard      -> script performs no gh call and no remote push
#
# PowerShell-only regression coverage (issue #847, commit 38df2ec):
#   S1   native-error pinning  -> a host with $PSNativeCommandUseErrorActionPreference
#                                 enabled still gets a structured $false from a failing
#                                 worktree operation instead of a thrown
#                                 NativeCommandExitException
#   S2   CLI stdout parity     -> `pwsh -File agents.ps1 ...` actually prints the phase
#                                 JSON (it previously printed nothing at all, because
#                                 the driver's @(json, exitcode) success-stream array
#                                 was cast whole to int by `exit`)

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Agents = Join-Path $RootDir 'global/skills/_internal/issue-work/scripts/agents.ps1'

$Pass = 0
$Fail = 0
$Errors = @()

# GetTempPath() honors $TMPDIR, so this suite is stable under sandboxes that
# restrict the OS default temp directory but expose $TMPDIR, as well as under
# plain CI runners where $TMPDIR is unset. Resolve-Path collapses the macOS
# /var -> /private/var symlink so derived paths match `git worktree list` output,
# which git canonicalizes (the PowerShell equivalent of the suite's `pwd -P`).
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("iw-agents-test-" + [guid]::NewGuid().ToString('N'))
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

# run_agents writes its JSON to the success stream and then returns an int exit
# code, so a dot-sourced caller receives @(<json>, <int>). These two helpers are
# the dot-sourced equivalent of what Split-AgentsCliResult does for the CLI.
function Get-DriverPayload {
    param([object[]]$Result)
    return ((@($Result) | Where-Object { $_ -isnot [int] }) -join "`n")
}

function Get-DriverCode {
    param([object[]]$Result)
    $ints = @(@($Result) | Where-Object { $_ -is [int] })
    if ($ints.Count -eq 0) { return $null }
    return $ints[-1]
}

# Builds a real (non-bare) repository with one commit on a "develop" branch and
# returns its path. Worktree tests operate directly on this checkout.
function New-FixtureRepo {
    param([string]$Name)
    $repo = "$Work/repos/$Name"
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    & git init -q -b develop $repo
    & git -C $repo config user.email 'test@example.com'
    & git -C $repo config user.name 'test'
    Set-Content -LiteralPath "$repo/file.txt" -Value 'content'
    & git -C $repo add file.txt
    & git -C $repo commit -q -m 'seed commit' | Out-Null
    return $repo
}

try {
    Write-Host "=== agents.ps1 unit + scenario tests ==="
    . $Agents

    # Low-entropy, clearly-fake owner ids assembled at runtime. No credential is
    # needed for any lease/worktree/transition test; these are opaque identity
    # strings, never tokens, and carry no secret-scanner-shaped prefix.
    $OwnerA = "agent-a-$PID"
    $OwnerB = "agent-b-$PID"

    Write-Host ""
    Write-Host "=== AC1: path normalization -- a relative path resolves to an absolute path ==="
    $normDir = "$Work/norm/sub"
    New-Item -ItemType Directory -Force -Path $normDir | Out-Null
    Push-Location "$Work/norm"
    try {
        $relOut = agents_normalize_path 'sub'
        $pureOut = agents_normalize_path 'a/b/../c'
    } finally {
        Pop-Location
    }
    if ($relOut -match '^/') {
        Add-Pass 'AC1 relative existing dir resolves to an absolute path'
    } else {
        Add-Fail 'AC1 relative path did not resolve to an absolute path' "got '$relOut'"
    }
    Assert-Contains '/norm/sub' $relOut 'AC1 normalized path retains the resolved directory'
    # Pure (non-existent) path is still made absolute and lexically collapsed.
    if ($pureOut -match '^/') {
        Add-Pass 'AC1 non-existent relative path is made absolute'
    } else {
        Add-Fail 'AC1 non-existent relative path not absolute' "got '$pureOut'"
    }
    Assert-Contains '/a/c' $pureOut "AC1 '..' is collapsed lexically"
    $emptyOut = agents_normalize_path ''
    if ($null -eq $emptyOut) {
        Add-Pass 'AC1 empty input fails'
    } else {
        Add-Fail 'AC1 empty input must fail' "got '$emptyOut'"
    }

    Write-Host ""
    Write-Host "=== AC2: spawn-prompt contract carries every required field ==="
    $promptRepo = "$Work/repos/promptrepo"
    New-Item -ItemType Directory -Force -Path $promptRepo | Out-Null
    $absRepo = agents_normalize_path $promptRepo
    $scopeText = 'scripts/agents.ps1, tests/issue-work/test-agents.ps1'
    $prompt = agents_build_prompt $promptRepo 839 'feat/issue-839-subagent-spawn-lease' 'deadbeefcafe' $scopeText
    Assert-Contains $absRepo $prompt 'AC2 prompt contains the normalized absolute repo path'
    Assert-Contains '#839' $prompt 'AC2 prompt contains the active issue number'
    Assert-Contains 'feat/issue-839-subagent-spawn-lease' $prompt 'AC2 prompt contains the target branch'
    Assert-Contains 'deadbeefcafe' $prompt 'AC2 prompt contains the baseline commit'
    Assert-Contains $scopeText $prompt 'AC2 prompt contains the explicit write scope'
    # Prohibition clause: each ban must be present.
    Assert-Contains 'push any commit' $prompt 'AC2 prohibition forbids pushing to the remote'
    Assert-Contains 'GitHub CLI' $prompt 'AC2 prohibition forbids the GitHub CLI'
    Assert-Contains 'pull request (PR)' $prompt 'AC2 prohibition forbids opening/merging a PR'
    Assert-Contains 'merge a pull request' $prompt 'AC2 prohibition forbids merging a PR'
    Assert-Contains 'clean up' $prompt 'AC2 prohibition forbids workspace cleanup'
    Assert-Contains 'coordinator owns ALL git and GitHub mutations' $prompt 'AC2 prompt states coordinator ownership'

    Write-Host ""
    Write-Host "=== AC3: lease mutual exclusion -- one writer at a time ==="
    $lease = "$Work/checkout/$script:AgentsLeaseDirname"
    Assert-True (agents_acquire_lease $lease $OwnerA) 'AC3 first writer acquires the lease'
    Assert-Equal $OwnerA (agents_lease_owner $lease) 'AC3 lease records the owning writer'
    Assert-False (agents_acquire_lease $lease $OwnerB) 'AC3 second writer is refused while the lease is held'
    Assert-Equal $OwnerA (agents_lease_owner $lease) 'AC3 held lease still owned by the first writer'
    Assert-True (agents_release_lease $lease $OwnerA) 'AC3 owner releases the lease'
    if (Test-Path -LiteralPath $lease) {
        Add-Fail 'AC3 lease directory must be gone after release'
    } else {
        Add-Pass 'AC3 lease directory removed on release'
    }
    Assert-True (agents_acquire_lease $lease $OwnerB) 'AC3 lease is re-acquirable after release'
    # Clean up for later independence.
    agents_release_lease $lease $OwnerB | Out-Null

    Write-Host ""
    Write-Host "=== AC4: lease fail-safe -- non-owner release refused; missing lease fails cleanly ==="
    $lease2 = "$Work/checkout2/$script:AgentsLeaseDirname"
    agents_acquire_lease $lease2 $OwnerA | Out-Null
    Assert-False (agents_release_lease $lease2 $OwnerB) 'AC4 non-owner release is refused'
    if (Test-Path -LiteralPath $lease2) {
        Add-Pass 'AC4 lease survives a refused non-owner release'
    } else {
        Add-Fail 'AC4 lease must survive a refused non-owner release'
    }
    agents_release_lease $lease2 $OwnerA | Out-Null
    # Releasing a non-existent lease fails cleanly (false, no crash).
    Assert-False (agents_release_lease "$Work/nope/$script:AgentsLeaseDirname" $OwnerA) 'AC4 releasing a non-existent lease fails cleanly'
    # A path that is not a lease directory is refused outright (guarded removal).
    Assert-False (agents_release_lease "$Work/not-a-lease-dir" $OwnerA) 'AC4 non-lease path is refused (guarded removal)'

    Write-Host ""
    Write-Host "=== AC5: per-agent worktree add then remove leaves no orphan ==="
    $wtRepo = New-FixtureRepo 'wtrepo'
    $wtPath = "$Work/worktrees/agent1"
    # $script:AgentsLastError is only meaningful for the call that just failed
    # (it is never cleared on success), so it is read after the fact and
    # reported on the failure branch only -- mirroring bash's "${AGENTS_LAST_ERROR:-}"
    # appearing inside `bad`, not in the passing label.
    $addOk = agents_worktree_add $wtRepo $wtPath 'feat/agent1-work'
    if ($addOk -is [bool] -and $addOk) {
        Add-Pass 'AC5 worktree add succeeds'
    } else {
        Add-Fail 'AC5 worktree add should succeed' $script:AgentsLastError
    }
    if (Test-Path -LiteralPath $wtPath -PathType Container) {
        Add-Pass 'AC5 worktree directory exists after add'
    } else {
        Add-Fail 'AC5 worktree directory should exist after add'
    }
    $wtList = (& git -C $wtRepo worktree list | Out-String)
    Assert-Contains $wtPath $wtList 'AC5 git lists the added worktree'
    $removeOk = agents_worktree_remove $wtRepo $wtPath
    if ($removeOk -is [bool] -and $removeOk) {
        Add-Pass 'AC5 worktree remove succeeds'
    } else {
        Add-Fail 'AC5 worktree remove should succeed' $script:AgentsLastError
    }
    if (Test-Path -LiteralPath $wtPath) {
        Add-Fail 'AC5 worktree directory must be gone after remove'
    } else {
        Add-Pass 'AC5 worktree directory removed'
    }
    $wtListAfter = @(& git -C $wtRepo worktree list | Where-Object { $_ -like "*$wtPath*" })
    Assert-Equal 0 $wtListAfter.Count 'AC5 removed worktree is not orphaned in git worktree list'

    Write-Host ""
    Write-Host "=== AC6: state transitions READY -> AGENTS_RUNNING -> COMMITTED ==="
    $manifest = "$Work/manifest"
    workspace_manifest_write -Path $manifest -Key 'state' -Value 'READY' | Out-Null
    $resStart = run_agents -Manifest $manifest -Phase 'start' -OwnerId $OwnerA
    Assert-Contains '"state":"AGENTS_RUNNING"' (Get-DriverPayload $resStart) 'AC6 start phase emits AGENTS_RUNNING'
    Assert-Equal 0 (Get-DriverCode $resStart) 'AC6 start phase returns exit code 0'
    Assert-Equal 'AGENTS_RUNNING' (workspace_manifest_state -Path $manifest) 'AC6 manifest advances to AGENTS_RUNNING'
    Assert-Equal $OwnerA (workspace_manifest_read -Path $manifest -Key 'lease_owner') 'AC6 start records the lease owner'
    $resCommit = run_agents -Manifest $manifest -Phase 'commit'
    Assert-Contains '"state":"COMMITTED"' (Get-DriverPayload $resCommit) 'AC6 commit phase emits COMMITTED'
    Assert-Equal 'COMMITTED' (workspace_manifest_state -Path $manifest) 'AC6 manifest advances to COMMITTED'
    # Out-of-order transition is refused (fail-safe on strict ordering).
    $manifestBad = "$Work/manifest-bad"
    workspace_manifest_write -Path $manifestBad -Key 'state' -Value 'READY' | Out-Null
    $resBad = run_agents -Manifest $manifestBad -Phase 'commit'
    if ((Get-DriverCode $resBad) -ne 0) {
        Add-Pass 'AC6 out-of-order transition is refused'
    } else {
        Add-Fail 'AC6 commit from READY (skipping AGENTS_RUNNING) must be refused'
    }
    Assert-Contains '"state":"ERROR"' (Get-DriverPayload $resBad) 'AC6 refused transition emits an ERROR outcome'
    Assert-Equal 'READY' (workspace_manifest_state -Path $manifestBad) 'AC6 refused transition leaves state unchanged'

    Write-Host ""
    Write-Host "=== AC7: capability guard -- script performs no gh call and no remote push ==="
    # The agent must never perform a GitHub mutation. Assert the script contains no
    # remote push and no GitHub-CLI invocation. The gh check uses a word boundary so
    # ordinary words ending in 'gh' (e.g. 'through') never register as a false match.
    $agentsText = Get-Content -LiteralPath $Agents -Raw
    if ($agentsText.Contains('git push')) {
        Add-Fail "AC7 agents.ps1 must not contain 'git push'"
    } else {
        Add-Pass 'AC7 agents.ps1 performs no remote push'
    }
    if ($agentsText -match '(?m)(^|[^A-Za-z0-9_])gh ') {
        Add-Fail 'AC7 agents.ps1 must not invoke the GitHub CLI (gh)'
    } else {
        Add-Pass 'AC7 agents.ps1 performs no gh call'
    }
    if ($agentsText.Contains('GH_BIN')) {
        Add-Fail 'AC7 agents.ps1 must not wire a gh injection seam'
    } else {
        Add-Pass 'AC7 agents.ps1 has no gh injection seam'
    }

    Write-Host ""
    Write-Host "=== S2 (#847): the CLI entry point actually prints its phase JSON ==="
    # Before commit 38df2ec, `pwsh -File agents.ps1 ...` printed nothing:
    # run_agents returns @(<json>, <int>) on the success stream and `exit` cast
    # the whole array to int, throwing and taking the JSON with it.
    $manifestCli = "$Work/manifest-cli"
    workspace_manifest_write -Path $manifestCli -Key 'state' -Value 'READY' | Out-Null
    $outStart = (& pwsh -NoProfile -File $Agents --manifest $manifestCli --phase start --owner $OwnerA 2>&1 | Out-String).Trim()
    $codeStart = $LASTEXITCODE
    if (-not [string]::IsNullOrWhiteSpace($outStart)) {
        Add-Pass 'S2 CLI stdout is non-empty'
    } else {
        Add-Fail 'S2 CLI stdout is non-empty' 'the CLI printed nothing'
    }
    $s2Lines = @($outStart -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    Assert-Equal 1 $s2Lines.Count 'S2 CLI emits exactly one line (the exit code is not re-emitted as output)'
    Assert-Contains '"state":"AGENTS_RUNNING"' $outStart 'S2 CLI stdout carries the phase JSON'
    Assert-Equal 'AGENTS_RUNNING' ($outStart | ConvertFrom-Json).state 'S2 CLI stdout parses as JSON with a state field'
    Assert-Equal 0 $codeStart 'S2 CLI exits 0 on a successful phase'
    Assert-Equal 'AGENTS_RUNNING' (workspace_manifest_state -Path $manifestCli) 'S2 CLI actually advanced the manifest'

    # The refused-transition path must print its ERROR JSON too, not just exit 1.
    $outCommitBad = (& pwsh -NoProfile -File $Agents --manifest $manifestCli --phase commit 2>&1 | Out-String).Trim()
    $codeCommitBad = $LASTEXITCODE
    Assert-Equal 'COMMITTED' ($outCommitBad | ConvertFrom-Json).state 'S2 CLI commit phase emits COMMITTED JSON'
    Assert-Equal 0 $codeCommitBad 'S2 CLI commit phase exits 0'
    $outRefused = (& pwsh -NoProfile -File $Agents --manifest $manifestCli --phase start 2>&1 | Out-String).Trim()
    $codeRefused = $LASTEXITCODE
    Assert-Contains '"state":"ERROR"' $outRefused 'S2 CLI prints the ERROR JSON on a refused transition'
    Assert-Equal 1 $codeRefused 'S2 CLI exits 1 on a refused transition'

    # Split-AgentsCliResult in isolation, including the single-element edge case
    # the helper explicitly guards ($items[0..-1] would otherwise re-emit the
    # exit code as output). Each call gets its own capture buffer so the
    # "lone int emits nothing" assertion is exact.
    $origOut = [Console]::Out
    $swBoth = [System.IO.StringWriter]::new()
    $swOnly = [System.IO.StringWriter]::new()
    try {
        [Console]::SetOut($swBoth)
        $codeBoth = Split-AgentsCliResult '{"state":"AGENTS_RUNNING"}' 0
        [Console]::SetOut($swOnly)
        $codeOnly = Split-AgentsCliResult 2
    } finally {
        [Console]::SetOut($origOut)
    }
    Assert-Equal 0 $codeBoth 'S2 Split-AgentsCliResult returns the trailing int as the exit code'
    Assert-Equal 2 $codeOnly 'S2 Split-AgentsCliResult returns a lone int as the exit code'
    Assert-Contains '{"state":"AGENTS_RUNNING"}' $swBoth.ToString() 'S2 Split-AgentsCliResult writes the payload to the console'
    Assert-Equal '' $swOnly.ToString().Trim() 'S2 Split-AgentsCliResult never re-emits a lone exit code as output'

    Write-Host ""
    Write-Host "=== S1 (#847): native-command error action is pinned off ==="
    # agents.ps1 sets $ErrorActionPreference='Stop' at script scope. A host that
    # has enabled $PSNativeCommandUseErrorActionPreference would therefore promote
    # git's non-zero exit to a terminating NativeCommandExitException, destroying
    # the structured $false that agents.sh returns for a failed worktree
    # operation. agents_worktree_add/_remove invoke $script:GitBin directly rather
    # than through _agents_git, which is why the pin lives at script scope.
    #
    # The driver enables the preference BEFORE dot-sourcing, reproducing a real
    # consumer whose session had it on; the dot-sourced pin is what protects the
    # worktree calls that follow.
    $s1Driver = "$Work/s1-driver.ps1"
    $s1Body = @'
$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
. '__AGENTS__'
# worktree add into a directory that is not a git repository -> git exits non-zero.
$addResult = agents_worktree_add '__NOTAREPO__' '__WTPATH__' 'feat/should-fail'
[Console]::Out.WriteLine("ADD_RESULT=$addResult")
# worktree remove of a path that was never a worktree -> git exits non-zero.
$removeResult = agents_worktree_remove '__NOTAREPO__' '__WTPATH__'
[Console]::Out.WriteLine("REMOVE_RESULT=$removeResult")
[Console]::Out.WriteLine('REACHED_END=True')
exit 0
'@
    $notARepo = "$Work/not-a-repo"
    New-Item -ItemType Directory -Force -Path $notARepo | Out-Null
    $s1Body = $s1Body.Replace('__AGENTS__', $Agents).Replace('__NOTAREPO__', $notARepo).Replace('__WTPATH__', "$Work/worktrees/s1")
    Set-Content -LiteralPath $s1Driver -Value $s1Body

    $outS1 = (& pwsh -NoProfile -File $s1Driver 2>&1 | Out-String)
    $codeS1 = $LASTEXITCODE
    Assert-NotContains 'NativeCommandExitException' $outS1 'S1 a failing worktree op does not throw NativeCommandExitException'
    Assert-Contains 'ADD_RESULT=False' $outS1 'S1 a failing worktree add returns a structured $false'
    Assert-Contains 'REMOVE_RESULT=False' $outS1 'S1 a failing worktree remove returns a structured $false'
    Assert-Contains 'REACHED_END=True' $outS1 'S1 execution continues past the failing worktree ops'
    Assert-Equal 0 $codeS1 'S1 the consuming script completes normally'
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
