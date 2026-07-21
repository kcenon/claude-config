#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for bash-sensitive-read-guard.ps1
# Run: pwsh tests/hooks/test-bash-sensitive-read-guard.ps1
#
# Port of tests/hooks/test-bash-sensitive-read-guard.sh (60 assertions). The
# .ps1 guard is a whole-command regex approximation of the tokenizer-based .sh
# guard, so a handful of bash cases legitimately diverge. Every ported case was
# probed against the actual .ps1 guard first; matches are asserted plainly,
# divergences are asserted at the ACTUAL .ps1 decision with a comment explaining
# why (never forced into agreement). See the divergence section at the bottom
# and the inline approximation-artifact notes.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'bash-sensitive-read-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

# Build the hook JSON payload with ConvertTo-Json so commands containing quotes
# and backslashes (echo "do not commit .env", find / -name .env -exec cat {} \;)
# are escaped correctly instead of being hand-concatenated.
function New-BashPayload {
    param([string]$Command)
    return (@{ tool_name = 'Bash'; tool_input = @{ command = $Command } } | ConvertTo-Json -Compress -Depth 5)
}

function Assert-Deny {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"deny"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected deny, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Allow {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"allow"' -or [string]::IsNullOrEmpty($result)) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected allow, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== bash-sensitive-read-guard.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-open on missing input]'
Assert-Allow -InputJson (New-BashPayload '') -Label 'Empty command -> allow (fail-open; dangerous-command-guard owns parse-failure)'

Write-Host ''
Write-Host '[deny - direct read of sensitive paths]'
# `cat secrets/db.yml` lives in the divergence section below: the relative
# sensitive-directory arm is not yet ported to the .ps1 guard (#878).
Assert-Deny -InputJson (New-BashPayload 'cat .env') -Label 'cat .env'
Assert-Deny -InputJson (New-BashPayload 'cat ./config/.env.production') -Label 'nested .env.production'
Assert-Deny -InputJson (New-BashPayload 'head -n 5 .env') -Label 'head .env'
Assert-Deny -InputJson (New-BashPayload 'tail -f .env.local') -Label 'tail .env.local'
Assert-Deny -InputJson (New-BashPayload 'grep AWS_SECRET .env') -Label 'grep .env'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.ssh/id_rsa') -Label 'cat ~/.ssh/id_rsa'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.ssh/my_key_ed25519') -Label 'ssh ed25519 key'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.aws/credentials') -Label 'AWS credentials file'
Assert-Deny -InputJson (New-BashPayload 'cat /etc/shadow') -Label '/etc/shadow'
# `config/credentials/` supplies the leading slash the .ps1 arm requires, so this
# absolute-form directory case denies on both channels.
Assert-Deny -InputJson (New-BashPayload 'cat config/credentials/aws.json') -Label 'credentials/ directory'
Assert-Deny -InputJson (New-BashPayload 'cat certs/server.pem') -Label '*.pem extension'
Assert-Deny -InputJson (New-BashPayload 'cat keys/private.key') -Label '*.key extension'

Write-Host ''
Write-Host '[deny - case-insensitive variants (macOS/Windows bypass guard)]'
Assert-Deny -InputJson (New-BashPayload 'cat .ENV') -Label 'uppercase .ENV'
Assert-Deny -InputJson (New-BashPayload 'cat ./config/.Env.Production') -Label 'mixed-case .Env.Production'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.NETRC') -Label 'uppercase .NETRC'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.AWS/credentials') -Label 'uppercase .AWS directory'
Assert-Deny -InputJson (New-BashPayload 'cat ~/.SSH/ID_RSA') -Label 'uppercase .SSH/ID_RSA'

Write-Host ''
Write-Host '[deny - wrapper bypasses]'
Assert-Deny -InputJson (New-BashPayload 'sudo cat /etc/shadow') -Label 'sudo wrapper'
Assert-Deny -InputJson (New-BashPayload 'env DEBUG=1 cat .env') -Label 'env wrapper'
Assert-Deny -InputJson (New-BashPayload 'nice cat .env') -Label 'nice wrapper'

Write-Host ''
Write-Host '[deny - chained commands]'
Assert-Deny -InputJson (New-BashPayload 'echo start && cat .env') -Label '&& chain'
Assert-Deny -InputJson (New-BashPayload 'cat README.md; cat .env') -Label '; chain'
Assert-Deny -InputJson (New-BashPayload 'true | cat .env') -Label 'pipe receiver'

Write-Host ''
Write-Host '[deny - find -exec cat]'
# `find . -name id_rsa` is in the divergence section: bare credential filenames
# without a `.ssh/` prefix are not caught by the .ps1 regex (#878).
Assert-Deny -InputJson (New-BashPayload 'find / -name .env -exec cat {} \;') -Label 'find -exec cat sensitive'

Write-Host ''
Write-Host '[allow - non-sensitive reads]'
Assert-Allow -InputJson (New-BashPayload 'cat README.md') -Label 'README.md'
Assert-Allow -InputJson (New-BashPayload 'cat src/main.py') -Label 'src/main.py'
Assert-Allow -InputJson (New-BashPayload 'cat package.json') -Label 'package.json'
Assert-Allow -InputJson (New-BashPayload 'head -n 10 docs/guide.md') -Label 'docs/guide.md'
Assert-Allow -InputJson (New-BashPayload 'grep TODO src/') -Label 'grep TODO in src/'
Assert-Allow -InputJson (New-BashPayload 'find . -name "*.md"') -Label 'find non-sensitive'

Write-Host ''
Write-Host '[allow - sensitive token inside non-read context]'
Assert-Allow -InputJson (New-BashPayload 'echo "do not commit .env"') -Label 'echo about .env (not a read)'
# APPROXIMATION ARTIFACT: bash allows `echo cat .env` (echo, not a read), but the
# .ps1 read-tool-prefix regex `\b(cat|head|...)\b` matches the `cat` token mid-
# string and denies. Over-denial of a whole-command regex; fail-safe, not a
# security gap. Asserted at the actual .ps1 decision.
Assert-Deny -InputJson (New-BashPayload 'echo cat .env') -Label 'echo cat .env (echo, not cat) [approximation artifact -> deny]'
Assert-Allow -InputJson (New-BashPayload 'git status') -Label 'git status'
Assert-Allow -InputJson (New-BashPayload 'ls -la') -Label 'ls -la'

Write-Host ''
Write-Host '[allow - env file templates (issue #866, file-channel parity)]'
Assert-Allow -InputJson (New-BashPayload 'cat .env.example') -Label 'cat .env.example'
Assert-Allow -InputJson (New-BashPayload 'cat /app/.env.sample') -Label 'cat /app/.env.sample (path-prefixed form)'
Assert-Allow -InputJson (New-BashPayload 'cat .env.template') -Label 'cat .env.template'
Assert-Allow -InputJson (New-BashPayload 'cat .env.example.local') -Label 'cat .env.example.local (suffixed example)'
Assert-Allow -InputJson (New-BashPayload 'grep API_URL .env.example') -Label 'grep in .env.example'

Write-Host ''
Write-Host '[deny - template allow-list must not widen the bypass surface (#866)]'
Assert-Deny -InputJson (New-BashPayload 'cat .env.*') -Label 'glob .env.* (not an allow-list entry)'
Assert-Deny -InputJson (New-BashPayload 'cat .env.example*') -Label 'glob .env.example* (no dot before wildcard)'
Assert-Deny -InputJson (New-BashPayload 'cat .env.examplexyz') -Label '.env.examplexyz (not .env.example)'
Assert-Deny -InputJson (New-BashPayload 'cat .env.sample.local') -Label '.env.sample.local (no suffix arm for sample)'
# DIVERGENCE (#878 relative-dir arm gap, same root cause as `cat secrets/db.yml`
# below): bash denies because the template arm falls through to the directory
# check, which catches relative `secrets/`. The .ps1 directory arm requires a
# leading slash, so after masking the template this reads `cat secrets/<ph>`
# with no `/secrets/` boundary and is allowed. Asserted at the actual decision;
# flips to deny when #878 lands.
Assert-Allow -InputJson (New-BashPayload 'cat secrets/.env.example') -Label 'template under relative secrets/ [#878 gap -> allow]'
Assert-Deny -InputJson (New-BashPayload 'cat .env.example && cat .env') -Label 'template does not launder a chained .env read'

Write-Host ''
Write-Host '[deny - unexpanded glob bracketing the env token (issue #867)]'
Assert-Deny -InputJson (New-BashPayload 'cat *.env*') -Label 'double-wildcard env glob (the reported bypass)'
Assert-Deny -InputJson (New-BashPayload 'cat .env*') -Label 'trailing glob after .env'
Assert-Deny -InputJson (New-BashPayload 'cat *.env') -Label 'leading glob before .env'
Assert-Deny -InputJson (New-BashPayload 'cat .env?') -Label 'single-char glob after .env'
Assert-Deny -InputJson (New-BashPayload 'grep SECRET *.env*') -Label 'grep double-wildcard env glob'
Assert-Deny -InputJson (New-BashPayload 'head config/*.env*') -Label 'path-prefixed double-wildcard env glob'

Write-Host ''
Write-Host '[allow - env-mentioning globs that cannot expand to a .env file (#867 precision)]'
Assert-Allow -InputJson (New-BashPayload 'cat env*') -Label 'env* -- no leading dot, not the .env class'
Assert-Allow -InputJson (New-BashPayload 'cat *.md') -Label 'wildcard over markdown'
Assert-Allow -InputJson (New-BashPayload 'cat environment.txt') -Label 'environment.txt -- env substring, no wildcard, no .env'

Write-Host ''
Write-Host '[skipped - symlink to sensitive (Red Team Vector F): no .ps1 analogue]'
# The bash suite plants a real `.env`, symlinks `safe.txt` -> it, and expects
# `cat safe.txt` to deny because the .sh guard's resolve_path follows the link
# through realpath. The .ps1 read guard is a whole-command regex scanner with no
# filesystem resolution: it only sees the literal token `safe.txt`, which
# carries no sensitive pattern, so it cannot reproduce this case. Skipped rather
# than asserted at a misleading allow. Filesystem-resolving symlink coverage is
# a read-guard capability gap, not exercisable by this regex guard.

Write-Host ''
Write-Host '[edge - cp source side]'
Assert-Deny -InputJson (New-BashPayload 'cp .env /tmp/exfil') -Label 'cp .env (source side denied)'
Assert-Allow -InputJson (New-BashPayload 'cp README.md /tmp/copy.md') -Label 'cp README.md (non-sensitive source)'

Write-Host ''
Write-Host '[divergence - .ps1 arm gaps pinned as-is, see #878]'
# Read twin of the write-guard gaps. The .ps1 sensitive-directory arm
# (`[/\\]secrets[/\\]` etc.) requires a path separator BEFORE the directory
# name, so relative forms with no leading slash are not caught; and bare
# credential filenames need a `.ssh/` prefix in the regex. The .sh guard
# resolves paths and matches these; the .ps1 guard does not yet. Pinned at
# today's ALLOW so a future flip to deny (when #878 ports the arms) trips this
# suite and forces the update. The first three reproduce the verified table;
# the credentials/passwords twins are added for full sensitive-directory
# coverage (the bash read suite only exercises the secrets/ relative form).
Assert-Allow -InputJson (New-BashPayload 'cat secrets/db.yml') -Label 'relative secrets/ [#878 gap -> allow]'
Assert-Allow -InputJson (New-BashPayload 'cat credentials/aws.json') -Label 'relative credentials/ [#878 gap -> allow]'
Assert-Allow -InputJson (New-BashPayload 'cat passwords/list.txt') -Label 'relative passwords/ [#878 gap -> allow]'
Assert-Allow -InputJson (New-BashPayload 'find . -name id_rsa') -Label 'find -name id_rsa (bare credential filename) [#878 gap -> allow]'

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
