#Requires -Version 7.0
# Test suite for global/skills/_internal/issue-work/scripts/pre-pr-gate.ps1
# Run: pwsh -NoProfile -File tests/issue-work/test-pre-pr-gate.ps1
#
# PowerShell parity suite for tests/issue-work/test-pre-pr-gate.sh. Drives the
# pre-PR readiness gate (git-state half) against REAL local bare git repositories
# -- no fake git shim is needed for the mechanics, because the gate never calls
# gh and driving real git exercises the actual fetch / fast-forward / rebase /
# merge codepaths instead of a stand-in. The classifier unit test points the
# dot-sourced helper at a throwaway repo via the PREPR_REPO_DIR seam.
#
# AC -> test mapping (identical to the bash suite; see
# reference/pre-pr-readiness.md):
#   AC1  clean-worktree precondition -> dirty tree -> blocked/dirty_worktree
#   AC2  develop refresh (advance)   -> behind -> local base ff'd -> ready;
#                                       current -> ready with no reset
#   AC3  develop refresh (guard)     -> ahead -> blocked/base_ahead (not reset);
#                                       diverged -> blocked/base_diverged (not reset)
#   AC4  integration                 -> clean rebase replays feature commits ->
#                                       ready; merge mode also integrates -> ready
#   AC5  conflict                    -> any conflict aborts -> blocked/conflict,
#                                       feature HEAD unchanged, worktree clean
#   AC6  base-movement retry         -> repeated movement -> blocked/base_unstable
#                                       after --max-base-moves attempts, reported
#   UNIT classify_base_relationship  -> equal/behind/ahead/diverged/unknown
#
# PowerShell-only regression cases (issue #847, commit 38df2ec):
#   S1   $PSNativeCommandUseErrorActionPreference is pinned $false at script
#        scope, so a host that enabled it still gets a structured outcome from
#        the `merge-base --is-ancestor` mismatch path instead of a
#        NativeCommandExitException.
#   S2   Split-PrePrGateCliResult puts the outcome JSON on stdout for
#        `pwsh -File pre-pr-gate.ps1 ...`; before the fix the CLI printed nothing
#        at all because `exit @(<json>, <int>)` threw on the array cast. Every
#        AC1-AC6 scenario below runs through that CLI, so the whole suite is a
#        regression test for it; the explicit S2 block pins the contract down.
#
# Injection seams exercised: PREPR_REPO_DIR (classifier unit test + S1 child),
# PRE_PR_ON_FETCH (AC6 base movement).

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Gate = Join-Path $RootDir 'global/skills/_internal/issue-work/scripts/pre-pr-gate.ps1'

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("iw-pre-pr-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
$Work = (Resolve-Path -LiteralPath $Work).Path

$Pass = 0
$Fail = 0
$Errors = @()
$LastGateExit = 0

$SavedEnv = @{}
foreach ($name in @('GIT_BIN', 'PREPR_REPO_DIR', 'PRE_PR_ON_FETCH')) {
    $SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
}

# ── Assertion helpers ─────────────────────────────────────────────────

function Write-Pass {
    param([string]$Label)
    $script:Pass++
    Write-Host "  PASS: $Label"
}

function Write-Fail {
    param([string]$Label, [string]$Detail = '')
    $script:Fail++
    $script:Errors += "FAIL: $Label$(if ($Detail) { " -- $Detail" })"
    Write-Host "  FAIL: $Label$(if ($Detail) { " ($Detail)" })"
}

function Assert-Equal {
    param([AllowEmptyString()][string]$Expected, [AllowEmptyString()][string]$Actual, [string]$Label)
    if ($Expected -eq $Actual) { Write-Pass $Label } else { Write-Fail $Label "expected '$Expected', got '$Actual'" }
}

function Assert-True {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) { Write-Pass $Label } else { Write-Fail $Label $Detail }
}

function Assert-Contains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) { Write-Pass $Label } else { Write-Fail $Label "'$Needle' not in output: $Haystack" }
}

function Assert-NotContains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) { Write-Fail $Label "'$Needle' unexpectedly present" } else { Write-Pass $Label }
}

# ── git / gate helpers ────────────────────────────────────────────────

function Invoke-GitOrDie {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    & git @GitArgs 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE)" }
}

function Get-GitLine {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    return ((& git @GitArgs 2>$null | Out-String).Trim())
}

# The bash suite's jfield: read one field out of the gate's single JSON line.
function Get-JField {
    param([AllowEmptyString()][string]$Json, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    $obj = $null
    try { $obj = $Json | ConvertFrom-Json } catch { return '' }
    if ($null -eq $obj) { return '' }
    $prop = $obj.PSObject.Properties[$Field]
    if ($null -eq $prop -or $null -eq $prop.Value) { return '' }
    return [string]$prop.Value
}

# Run the gate CLI from inside <RepoDir> so PREPR_REPO_DIR defaults to that
# checkout (the real workflow's shape), mirroring the bash run_gate. Returns the
# JSON stdout line; the process exit code lands in $script:LastGateExit.
function Invoke-Gate {
    param([string]$RepoDir, [Parameter(Mandatory)][string[]]$GateArgs)
    Push-Location -LiteralPath $RepoDir
    try {
        $out = & pwsh -NoProfile -File $Gate @GateArgs 2>$null
        $script:LastGateExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    return (($out | Out-String).Trim())
}

# A dot-sourced run_pre_pr_gate returns @(<json>, <exit code>) on one stream:
# PowerShell puts both the Write-Output payload and the `return` value on the
# success stream. Split them the way Split-PrePrGateCliResult does for the CLI.
function Get-EmittedText {
    param([AllowEmptyCollection()][object[]]$Result)
    $items = @($Result)
    if ($items.Count -gt 0 -and $items[-1] -is [int]) {
        if ($items.Count -gt 1) { $items = $items[0..($items.Count - 2)] } else { $items = @() }
    }
    return (($items | ForEach-Object { [string]$_ }) -join "`n")
}

function Get-ResultCode {
    param([AllowEmptyCollection()][object[]]$Result)
    $items = @($Result)
    if ($items.Count -gt 0 -and $items[-1] -is [int]) { return [int]$items[-1] }
    return 0
}

# ── Fixture builders (mirror the bash make_remote / make_feature_clone) ──

# Builds a bare "remote" under $Work/remote seeded with one commit on develop,
# plus a "seed" working clone used to advance the remote during a scenario.
# Returns a two-element array: @(<remote path>, <seed path>).
function New-Remote {
    param([string]$Name)
    $remote = Join-Path $Work "remote/$Name.git"
    $seed = Join-Path $Work "seed-$Name"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $remote) | Out-Null
    Invoke-GitOrDie @('init', '--bare', '-q', $remote)
    Invoke-GitOrDie @('init', '-q', '-b', 'develop', $seed)
    Invoke-GitOrDie @('-C', $seed, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $seed, 'config', 'user.name', 'test')
    [System.IO.File]::WriteAllText((Join-Path $seed 'file.txt'), "base`n")
    Invoke-GitOrDie @('-C', $seed, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $seed, 'commit', '-q', '-m', 'seed commit')
    Invoke-GitOrDie @('-C', $seed, 'remote', 'add', 'origin', $remote)
    Invoke-GitOrDie @('-C', $seed, 'push', '-q', 'origin', 'develop')
    return , @($remote, $seed)
}

# Clones <Remote>'s develop into <Dest>, sets a test identity, and creates a
# feature branch <Branch> carrying one commit on <FeatFile>. Returns <Dest>.
function New-FeatureClone {
    param([string]$Remote, [string]$Dest, [string]$Branch, [string]$FeatFile)
    Invoke-GitOrDie @('clone', '-q', '--branch', 'develop', '--single-branch', $Remote, $Dest)
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.name', 'test')
    Invoke-GitOrDie @('-C', $Dest, 'checkout', '-q', '-b', $Branch)
    [System.IO.File]::WriteAllText((Join-Path $Dest $FeatFile), "feature work`n")
    Invoke-GitOrDie @('-C', $Dest, 'add', $FeatFile)
    Invoke-GitOrDie @('-C', $Dest, 'commit', '-q', '-m', 'feature commit')
    return $Dest
}

function New-PlainClone {
    param([string]$Remote, [string]$Dest)
    Invoke-GitOrDie @('clone', '-q', '--branch', 'develop', '--single-branch', $Remote, $Dest)
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.name', 'test')
    return $Dest
}

# Advance the remote develop by one non-conflicting commit via the seed clone.
# Returns the new remote develop sha.
function Update-Remote {
    param([string]$Seed, [string]$File, [string]$Content)
    Invoke-GitOrDie @('-C', $Seed, 'checkout', '-q', 'develop')
    $target = Join-Path $Seed $File
    $existing = ''
    if (Test-Path -LiteralPath $target) { $existing = [System.IO.File]::ReadAllText($target) }
    [System.IO.File]::WriteAllText($target, ($existing + $Content + "`n"))
    Invoke-GitOrDie @('-C', $Seed, 'add', $File)
    Invoke-GitOrDie @('-C', $Seed, 'commit', '-q', '-m', 'remote advance')
    Invoke-GitOrDie @('-C', $Seed, 'push', '-q', 'origin', 'develop')
    return (Get-GitLine @('-C', $Seed, 'rev-parse', 'develop'))
}

$env:GIT_BIN = $null
$env:PREPR_REPO_DIR = $null
$env:PRE_PR_ON_FETCH = $null

try {
    Write-Host "=== pre-pr-gate.ps1 UNIT: classify_base_relationship ==="
    . $Gate

    $clsRepo = Join-Path $Work 'classify-repo'
    Invoke-GitOrDie @('init', '-q', '-b', 'main', $clsRepo)
    Invoke-GitOrDie @('-C', $clsRepo, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $clsRepo, 'config', 'user.name', 'test')
    [System.IO.File]::WriteAllText((Join-Path $clsRepo 'f.txt'), "a`n")
    Invoke-GitOrDie @('-C', $clsRepo, 'add', 'f.txt')
    Invoke-GitOrDie @('-C', $clsRepo, 'commit', '-q', '-m', 'A')
    $shaA = Get-GitLine @('-C', $clsRepo, 'rev-parse', 'HEAD')
    [System.IO.File]::WriteAllText((Join-Path $clsRepo 'f.txt'), "a`nb`n")
    Invoke-GitOrDie @('-C', $clsRepo, 'add', 'f.txt')
    Invoke-GitOrDie @('-C', $clsRepo, 'commit', '-q', '-m', 'B')
    $shaB = Get-GitLine @('-C', $clsRepo, 'rev-parse', 'HEAD')
    Invoke-GitOrDie @('-C', $clsRepo, 'checkout', '-q', '-b', 'fork', $shaA)
    [System.IO.File]::WriteAllText((Join-Path $clsRepo 'g.txt'), "c`n")
    Invoke-GitOrDie @('-C', $clsRepo, 'add', 'g.txt')
    Invoke-GitOrDie @('-C', $clsRepo, 'commit', '-q', '-m', 'C')
    $shaC = Get-GitLine @('-C', $clsRepo, 'rev-parse', 'HEAD')

    # PREPR_REPO_DIR is read fresh on every git call, so a dot-sourced helper can
    # be aimed at a throwaway repo without touching the working directory.
    $env:PREPR_REPO_DIR = $clsRepo
    Assert-Equal 'equal' (classify_base_relationship $shaA $shaA) 'UNIT identical shas -> equal'
    Assert-Equal 'behind' (classify_base_relationship $shaA $shaB) 'UNIT local ancestor of remote -> behind'
    Assert-Equal 'ahead' (classify_base_relationship $shaB $shaA) 'UNIT remote ancestor of local -> ahead'
    Assert-Equal 'diverged' (classify_base_relationship $shaB $shaC) 'UNIT forked histories -> diverged'
    Assert-Equal 'unknown' (classify_base_relationship '' $shaA) 'UNIT empty argument -> unknown'
    # Shape guard: the classifier must yield exactly one string. A stray value on
    # the success stream would make the driver's switch see an array and fall
    # through to the diverged branch for every relationship.
    $clsShape = @(classify_base_relationship $shaA $shaB)
    Assert-Equal '1' ([string]$clsShape.Count) 'UNIT the classifier emits exactly one value (no stray output)'

    # The CLI scenarios below rely on PREPR_REPO_DIR being unset so the gate
    # defaults to the current directory; leaving it set would aim every run at
    # the classifier repo.
    $env:PREPR_REPO_DIR = $null

    Write-Host ""
    Write-Host "=== AC1: dirty worktree is refused before any fetch ==="
    $r1 = New-Remote 'ac1'
    $repo1 = New-FeatureClone $r1[0] (Join-Path $Work 'repo1') 'feat/x' 'feature.txt'
    $dev1Before = Get-GitLine @('-C', $repo1, 'rev-parse', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $repo1 'file.txt'), "base`nuncommitted`n")   # tracked, uncommitted -> dirty
    $out1 = Invoke-Gate $repo1 @('--repo', 'o/ac1', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'blocked' (Get-JField $out1 'outcome') 'AC1 outcome=blocked on a dirty worktree'
    Assert-Equal 'dirty_worktree' (Get-JField $out1 'reason') 'AC1 reason=dirty_worktree'
    Assert-Equal '0' (Get-JField $out1 'attempts') 'AC1 no integration attempted (attempts=0)'
    Assert-Equal $dev1Before (Get-GitLine @('-C', $repo1, 'rev-parse', 'develop')) 'AC1 local base untouched by a refused run'
    Assert-Equal '1' ([string]$LastGateExit) 'AC1 a blocked run exits 1'

    Write-Host ""
    Write-Host "=== AC2: behind base -> local base fast-forwarded -> ready ==="
    $r2 = New-Remote 'ac2'
    $repo2 = New-FeatureClone $r2[0] (Join-Path $Work 'repo2') 'feat/x' 'feature.txt'
    $dev2Before = Get-GitLine @('-C', $repo2, 'rev-parse', 'develop')
    $remote2Sha = Update-Remote $r2[1] 'churn.txt' 'one'   # remote develop moves ahead
    $out2 = Invoke-Gate $repo2 @('--repo', 'o/ac2', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'ready' (Get-JField $out2 'outcome') 'AC2 outcome=ready when strictly behind'
    Assert-Equal $remote2Sha (Get-JField $out2 'remote_base_sha') 'AC2 remote_base_sha is the fetched remote head'
    Assert-Equal $dev2Before (Get-JField $out2 'local_base_sha_before') 'AC2 local_base_sha_before is the pre-refresh sha'
    Assert-Equal $remote2Sha (Get-JField $out2 'local_base_sha_after') 'AC2 local base fast-forwarded to the remote head'
    Assert-Equal $remote2Sha (Get-GitLine @('-C', $repo2, 'rev-parse', 'develop')) 'AC2 the on-disk local base branch was fast-forwarded'
    Assert-Equal '0' ([string]$LastGateExit) 'AC2 a ready run exits 0'
    # The feature commits are replayed onto the refreshed base.
    Assert-True (Test-Path -LiteralPath (Join-Path $repo2 'feature.txt')) 'AC2 feature file survives the rebase'
    Assert-True (Test-Path -LiteralPath (Join-Path $repo2 'churn.txt')) 'AC2 refreshed base content is present after the rebase'

    Write-Host ""
    Write-Host "=== AC2: base already current -> ready with no reset ==="
    $r2b = New-Remote 'ac2b'
    $repo2b = New-FeatureClone $r2b[0] (Join-Path $Work 'repo2b') 'feat/x' 'feature.txt'
    $dev2bBefore = Get-GitLine @('-C', $repo2b, 'rev-parse', 'develop')
    $out2b = Invoke-Gate $repo2b @('--repo', 'o/ac2b', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'ready' (Get-JField $out2b 'outcome') 'AC2 outcome=ready when base is already current'
    Assert-Equal $dev2bBefore (Get-JField $out2b 'local_base_sha_before') 'AC2 current-base before sha recorded'
    Assert-Equal $dev2bBefore (Get-JField $out2b 'local_base_sha_after') 'AC2 current base is not moved'

    Write-Host ""
    Write-Host "=== AC3: local base AHEAD -> blocked/base_ahead, base not reset ==="
    $r3 = New-Remote 'ac3'
    $repo3 = New-PlainClone $r3[0] (Join-Path $Work 'repo3')
    # Put an unshared commit on the LOCAL develop, then branch the feature from it.
    Invoke-GitOrDie @('-C', $repo3, 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $repo3 'file.txt'), "base`nlocal-only`n")
    Invoke-GitOrDie @('-C', $repo3, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $repo3, 'commit', '-q', '-m', 'local ahead')
    $dev3Before = Get-GitLine @('-C', $repo3, 'rev-parse', 'develop')
    Invoke-GitOrDie @('-C', $repo3, 'checkout', '-q', '-b', 'feat/x')
    $out3 = Invoke-Gate $repo3 @('--repo', 'o/ac3', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'blocked' (Get-JField $out3 'outcome') 'AC3 outcome=blocked when local base is ahead'
    Assert-Equal 'base_ahead' (Get-JField $out3 'reason') 'AC3 reason=base_ahead'
    Assert-Equal $dev3Before (Get-JField $out3 'local_base_sha_after') 'AC3 local_base_sha_after unchanged (not reset)'
    Assert-Equal $dev3Before (Get-GitLine @('-C', $repo3, 'rev-parse', 'develop')) 'AC3 the on-disk local base was not rewound'

    Write-Host ""
    Write-Host "=== AC3: local base DIVERGED -> blocked/base_diverged, base not reset ==="
    $r4 = New-Remote 'ac4'
    $repo4 = New-PlainClone $r4[0] (Join-Path $Work 'repo4')
    Invoke-GitOrDie @('-C', $repo4, 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $repo4 'local.txt'), "local-side`n")
    Invoke-GitOrDie @('-C', $repo4, 'add', 'local.txt')
    Invoke-GitOrDie @('-C', $repo4, 'commit', '-q', '-m', 'local diverge')
    $dev4Before = Get-GitLine @('-C', $repo4, 'rev-parse', 'develop')
    Invoke-GitOrDie @('-C', $repo4, 'checkout', '-q', '-b', 'feat/x')
    Update-Remote $r4[1] 'remote.txt' 'other' | Out-Null   # remote diverges independently
    $out4 = Invoke-Gate $repo4 @('--repo', 'o/ac4', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'blocked' (Get-JField $out4 'outcome') 'AC3 outcome=blocked when histories diverge'
    Assert-Equal 'base_diverged' (Get-JField $out4 'reason') 'AC3 reason=base_diverged'
    Assert-Equal $dev4Before (Get-JField $out4 'local_base_sha_after') 'AC3 diverged local base not reset'
    Assert-Equal $dev4Before (Get-GitLine @('-C', $repo4, 'rev-parse', 'develop')) 'AC3 the on-disk diverged base was not rewound'

    Write-Host ""
    Write-Host "=== AC4: clean rebase replays feature commits onto refreshed base ==="
    # Same mechanics as AC2 ready, asserted from the integration angle: the
    # feature commit sha changes (replayed) while its content and the new base
    # coexist.
    $r5 = New-Remote 'ac5'
    $repo5 = New-FeatureClone $r5[0] (Join-Path $Work 'repo5') 'feat/x' 'feature.txt'
    $feat5Before = Get-GitLine @('-C', $repo5, 'rev-parse', 'HEAD')
    Update-Remote $r5[1] 'churn.txt' 'two' | Out-Null
    $out5 = Invoke-Gate $repo5 @('--repo', 'o/ac5', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'ready' (Get-JField $out5 'outcome') 'AC4 clean integration -> ready'
    $feat5After = Get-GitLine @('-C', $repo5, 'rev-parse', 'HEAD')
    Assert-True ($feat5Before -ne $feat5After) 'AC4 feature commit was replayed (HEAD sha changed)'
    & git -C $repo5 merge-base --is-ancestor develop HEAD 2>$null | Out-Null
    Assert-Equal '0' ([string]$LASTEXITCODE) 'AC4 refreshed base is an ancestor of the feature HEAD'

    Write-Host ""
    Write-Host "=== AC4: merge mode integrates the base -> ready ==="
    $r6 = New-Remote 'ac6'
    $repo6 = New-FeatureClone $r6[0] (Join-Path $Work 'repo6') 'feat/x' 'feature.txt'
    Update-Remote $r6[1] 'churn.txt' 'three' | Out-Null
    $out6 = Invoke-Gate $repo6 @('--repo', 'o/ac6', '--base', 'develop', '--branch', 'feat/x', '--integrate', 'merge')
    Assert-Equal 'ready' (Get-JField $out6 'outcome') 'AC4 merge-mode integration -> ready'
    Assert-Equal '1' ([string](@(& git -C $repo6 rev-list --merges -1 HEAD 2>$null)).Count) 'AC4 merge mode created a merge commit'

    Write-Host ""
    Write-Host "=== AC5: integration conflict -> abort -> blocked/conflict, feature untouched ==="
    $r7 = New-Remote 'ac7'
    $repo7 = New-PlainClone $r7[0] (Join-Path $Work 'repo7')
    Invoke-GitOrDie @('-C', $repo7, 'checkout', '-q', '-b', 'feat/x')
    [System.IO.File]::WriteAllText((Join-Path $repo7 'file.txt'), "OURS`n")
    Invoke-GitOrDie @('-C', $repo7, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $repo7, 'commit', '-q', '-m', 'feature edits shared file')
    $feat7Before = Get-GitLine @('-C', $repo7, 'rev-parse', 'HEAD')
    # Remote edits the same line differently -> rebase will conflict.
    Invoke-GitOrDie @('-C', $r7[1], 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $r7[1] 'file.txt'), "THEIRS`n")
    Invoke-GitOrDie @('-C', $r7[1], 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $r7[1], 'commit', '-q', '-m', 'remote edits shared file')
    Invoke-GitOrDie @('-C', $r7[1], 'push', '-q', 'origin', 'develop')
    $out7 = Invoke-Gate $repo7 @('--repo', 'o/ac7', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'blocked' (Get-JField $out7 'outcome') 'AC5 outcome=blocked on an integration conflict'
    Assert-Equal 'conflict' (Get-JField $out7 'reason') 'AC5 reason=conflict'
    Assert-Equal $feat7Before (Get-GitLine @('-C', $repo7, 'rev-parse', 'HEAD')) 'AC5 feature branch HEAD is unchanged (rebase aborted)'
    Assert-Equal '' (Get-GitLine @('-C', $repo7, 'status', '--porcelain')) 'AC5 worktree is clean after the abort (no conflict markers left)'
    Assert-Equal 'feat/x' (Get-GitLine @('-C', $repo7, 'rev-parse', '--abbrev-ref', 'HEAD')) 'AC5 still on the feature branch after the abort'

    Write-Host ""
    Write-Host "=== AC6: repeated base movement -> blocked/base_unstable after N attempts ==="
    $r8 = New-Remote 'ac8'
    $repo8 = New-FeatureClone $r8[0] (Join-Path $Work 'repo8') 'feat/x' 'feature.txt'
    $counter = Join-Path $Work 'ac8-counter'
    [System.IO.File]::WriteAllText($counter, "0`n")
    # After every fetch, push a fresh non-conflicting commit so the base never
    # stabilizes. The hook body lives in its own script (the seam is evaluated
    # with Invoke-Expression, so `& '<path>'` is all the command string needs to
    # be) and reads its paths from the environment, which keeps the seam free of
    # nested quoting.
    $hookScript = Join-Path $Work 'ac8-hook.ps1'
    Set-Content -LiteralPath $hookScript -Value @'
$count = [int]((Get-Content -LiteralPath $env:IW_COUNTER -Raw).Trim()) + 1
[System.IO.File]::WriteAllText($env:IW_COUNTER, "$count`n")
[System.IO.File]::AppendAllText((Join-Path $env:IW_SEED 'churn.txt'), "churn$count`n")
git -C $env:IW_SEED add -A
git -C $env:IW_SEED commit -q -m "churn$count"
git -C $env:IW_SEED push -q origin develop
'@
    $env:IW_COUNTER = $counter
    $env:IW_SEED = $r8[1]
    $env:PRE_PR_ON_FETCH = "& '$hookScript'"
    $out8 = Invoke-Gate $repo8 @('--repo', 'o/ac8', '--base', 'develop', '--branch', 'feat/x')
    Assert-Equal 'blocked' (Get-JField $out8 'outcome') 'AC6 outcome=blocked when the base never stabilizes'
    Assert-Equal 'base_unstable' (Get-JField $out8 'reason') 'AC6 reason=base_unstable'
    Assert-Equal '3' (Get-JField $out8 'attempts') 'AC6 attempts caps at the default --max-base-moves (3)'
    Assert-True ([int]((Get-Content -LiteralPath $counter -Raw).Trim()) -gt 0) 'AC6 the PRE_PR_ON_FETCH seam actually ran'

    # A smaller cap is honored and reported.
    [System.IO.File]::WriteAllText($counter, "0`n")
    $out8b = Invoke-Gate $repo8 @('--repo', 'o/ac8', '--base', 'develop', '--branch', 'feat/x', '--max-base-moves', '2')
    Assert-Equal 'base_unstable' (Get-JField $out8b 'reason') 'AC6 reason=base_unstable with a smaller cap'
    Assert-Equal '2' (Get-JField $out8b 'attempts') 'AC6 attempts honors an explicit --max-base-moves 2'
    $env:PRE_PR_ON_FETCH = $null

    Write-Host ""
    Write-Host "=== Missing required args -> blocked/missing_args, returns 2 ==="
    # The JSON contract for a missing argument lives in the driver, exercised via
    # the function dot-sourced above (the CLI wrapper writes a usage hint to
    # stderr and returns 2 without JSON, mirroring workspace.ps1). The
    # missing-arg check returns before any git call, so PREPR_REPO_DIR is
    # irrelevant here.
    $result9 = run_pre_pr_gate 'o/n' 'develop' ''   # empty branch
    $out9 = Get-EmittedText $result9
    Assert-Equal 'blocked' (Get-JField $out9 'outcome') 'missing branch -> blocked'
    Assert-Equal 'missing_args' (Get-JField $out9 'reason') 'missing branch -> reason=missing_args'
    Assert-Equal '2' ([string](Get-ResultCode $result9)) 'missing required arg returns 2'

    Write-Host ""
    Write-Host "=== S2 (#847): the CLI puts its outcome JSON on stdout ==="
    # Before commit 38df2ec the driver's @(<json>, <int>) result was passed
    # straight to `exit`, which threw on the array cast and took the JSON with
    # it: `pwsh -File pre-pr-gate.ps1 ...` printed nothing at all. Every scenario
    # above already depends on this; these assertions pin the shape down.
    $rS2 = New-Remote 's2'
    $repoS2 = New-FeatureClone $rS2[0] (Join-Path $Work 'repo-s2') 'feat/x' 'feature.txt'
    $outS2 = Invoke-Gate $repoS2 @('--repo', 'o/s2', '--base', 'develop', '--branch', 'feat/x')
    Assert-True (-not [string]::IsNullOrWhiteSpace($outS2)) 'S2 the CLI writes a non-empty line to stdout'
    Assert-Equal '1' ([string](@($outS2 -split "`n")).Count) 'S2 CLI stdout is exactly one line (exit code not re-emitted)'
    Assert-Contains '"outcome":"ready"' $outS2 'S2 the stdout line is the gate outcome JSON'
    Assert-Equal 'ready' (Get-JField $outS2 'outcome') 'S2 the stdout line parses as JSON'
    Assert-Equal '0' ([string]$LastGateExit) 'S2 the exit code still rides alongside the JSON'
    # attempts must stay an unquoted number in the emitted JSON (schema parity
    # with pre-pr-gate.sh), which the -f format string is responsible for.
    Assert-Contains '"attempts":1' $outS2 'S2 attempts is emitted as an unquoted number'

    Write-Host ""
    Write-Host "=== S1 (#847): a non-zero git exit stays data under a host that enabled the native EAP ==="
    # $PSNativeCommandUseErrorActionPreference is set BEFORE the script loads,
    # which is how a host with the setting enabled reaches it. The script pins it
    # $false at script scope; the PIN assertion below fails outright if that line
    # is removed, and the classifier/driver assertions prove the
    # `merge-base --is-ancestor` mismatch path still yields a structured result.
    $rS1 = New-Remote 's1'
    $repoS1 = New-PlainClone $rS1[0] (Join-Path $Work 'repo-s1')
    Invoke-GitOrDie @('-C', $repoS1, 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $repoS1 'local.txt'), "local-side`n")
    Invoke-GitOrDie @('-C', $repoS1, 'add', 'local.txt')
    Invoke-GitOrDie @('-C', $repoS1, 'commit', '-q', '-m', 'local diverge')
    Invoke-GitOrDie @('-C', $repoS1, 'checkout', '-q', '-b', 'feat/x')
    Update-Remote $rS1[1] 'remote.txt' 'other' | Out-Null

    $s1Child = Join-Path $Work 'child-native-eap.ps1'
    Set-Content -LiteralPath $s1Child -Value @'
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. $env:IW_GATE_SCRIPT
[Console]::Out.WriteLine("PIN=$PSNativeCommandUseErrorActionPreference")
# Both `merge-base --is-ancestor` probes exit non-zero for forked histories.
$env:PREPR_REPO_DIR = $env:IW_CLS_REPO
[Console]::Out.WriteLine("CLASSIFY=" + (classify_base_relationship $env:IW_SHA_B $env:IW_SHA_C))
# The full driver over a diverged base: the same non-zero exits, reached through
# the gate rather than the helper.
$env:PREPR_REPO_DIR = $env:IW_S1_REPO
$result = run_pre_pr_gate 'o/s1' 'develop' 'feat/x'
foreach ($item in @($result)) {
    if ($item -isnot [int]) { [Console]::Out.WriteLine("JSON=" + [string]$item) } else { [Console]::Out.WriteLine("RC=$item") }
}
[Console]::Out.WriteLine('DONE')
exit 0
'@
    $s1ErrFile = Join-Path $Work 's1-stderr.txt'
    $savedPrepr = $env:PREPR_REPO_DIR
    $env:IW_GATE_SCRIPT = $Gate
    $env:IW_CLS_REPO = $clsRepo
    $env:IW_SHA_B = $shaB
    $env:IW_SHA_C = $shaC
    $env:IW_S1_REPO = $repoS1
    try {
        $s1Out = (& pwsh -NoProfile -File $s1Child 2>$s1ErrFile | Out-String).Trim()
        $s1Code = $LASTEXITCODE
    } finally {
        $env:PREPR_REPO_DIR = $savedPrepr
    }
    $s1Err = ''
    if (Test-Path -LiteralPath $s1ErrFile) { $s1Err = (Get-Content -LiteralPath $s1ErrFile -Raw -ErrorAction SilentlyContinue) }
    if ($null -eq $s1Err) { $s1Err = '' }
    Assert-Equal '0' ([string]$s1Code) 'S1 the run completes instead of dying on a non-zero git exit'
    Assert-Contains 'PIN=False' $s1Out 'S1 the script pins $PSNativeCommandUseErrorActionPreference back to $false'
    Assert-Contains 'CLASSIFY=diverged' $s1Out 'S1 a not-an-ancestor probe still classifies, it does not throw'
    Assert-Contains '"reason":"base_diverged"' $s1Out 'S1 the driver still emits a structured blocked outcome'
    Assert-Contains 'RC=1' $s1Out 'S1 the driver still returns its exit code'
    Assert-Contains 'DONE' $s1Out 'S1 every path ran to completion'
    Assert-NotContains 'NativeCommandExitException' $s1Err 'S1 no NativeCommandExitException reaches stderr'
}
finally {
    foreach ($name in $SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $SavedEnv[$name]) }
    foreach ($name in @('IW_COUNTER', 'IW_SEED', 'IW_GATE_SCRIPT', 'IW_CLS_REPO', 'IW_SHA_B', 'IW_SHA_C', 'IW_S1_REPO')) {
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  $Pass passed, $Fail failed"
if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:"
    foreach ($err in $Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
