#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

# bash-sensitive-read-guard.ps1
# Blocks reading sensitive files via the Bash tool channel on Windows.
# PowerShell parity for bash-sensitive-read-guard.sh.
#
# This script is a regex-driven approximation of the bash tokenizer-based
# sibling. The full sub-command splitter from lib/tokenize-shell.sh is
# intentionally not ported because (a) the Bash tool on Windows always
# arrives with a string command identical to its POSIX form, and (b) the
# sensitive-path patterns are themselves anchored enough that a
# whitespace-aware scan catches the documented attack classes.

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

# Sensitive-path regex set. Mirrors the deny patterns in
# bash-sensitive-read-guard.sh (case-insensitive where applicable).
$sensitivePatterns = @(
    '(^|[\s/\\])\.env([\s.''"]|$)',
    '(^|[\s/\\])\.env\.[A-Za-z0-9_-]+',
    '(^|[\s/\\])\.ssh[/\\](id_[A-Za-z0-9_-]+|[A-Za-z0-9_-]+_(?:rsa|dsa|ecdsa|ed25519))',
    '(^|[\s/\\])\.aws[/\\](credentials|config)',
    '(^|[\s/\\])\.gnupg([/\\]|$)',
    '(^|[\s/\\])\.netrc(\s|$)',
    '(^|[\s/\\])\.npmrc(\s|$)',
    '(^|[\s/\\])\.pypirc(\s|$)',
    '(^|[\s/\\])\.dockerconfigjson(\s|$)',
    '(^|[\s/\\])\.docker[/\\]config\.json',
    '(^|[\s/\\])\.kube[/\\]config(\s|$)',
    '\.(?:pem|key|p12|pfx|crt|cer)([\s''"]|$)',
    '[/\\]secrets[/\\]',
    '[/\\]credentials[/\\]',
    '[/\\]passwords[/\\]',
    '\bpassword\b',
    '/etc/(shadow|sudoers)\b',
    '/etc/ssh/ssh_host_[A-Za-z0-9_]+_key\b'
)

# Read-tool prefix the regex below requires before the sensitive token.
# This keeps `echo "this references .env"` as allow while denying `cat .env`.
$readToolPrefix = '\b(cat|head|tail|less|more|bat|view|grep|egrep|fgrep|rg|find|tar|xxd|od|strings|hexdump|cp|mv|rsync|scp|install|sudo\s+cat|sudo\s+head|sudo\s+tail)\b'

# Env-file templates (.env.example, .env.example.*, .env.sample, .env.template)
# are committed on purpose and never carry real secrets; sensitive-file-guard.ps1
# allows the same four names on the file channel, so denying them here was a
# cross-channel divergence (issue #866).
#
# This guard matches patterns against the whole command string rather than
# against extracted paths, so a plain "allow and exit" would also let
# `cat .env.example && cat .env` through. Mask the template mentions out of a
# scanning copy instead: the template token stops matching while every other
# sensitive token in the same command still does. The placeholder is
# deliberately dot-free and slash-free so it cannot match any pattern above.
$envTemplateMention = '(?i)(^|[\s/\\])\.env\.(?:example(?:\.[^\s''";|&]*)?|sample|template)(?=[\s''";|&]|$)'
$scanCmd = [regex]::Replace($cmd, $envTemplateMention, '${1}env_template_placeholder')

foreach ($pattern in $sensitivePatterns) {
    $combined = "$readToolPrefix.*$pattern"
    if ($scanCmd -match $combined) {
        $reason = "Bash read of sensitive file blocked: matched pattern $pattern"
        New-HookDenyResponse -Reason $reason
        exit 0
    }
}

New-HookAllowResponse
exit 0
