# Sandbox TLS: SSL_CERT_FILE Fix

Root-cause fix for the recurring TLS handshake failure that forced Claude Code
sessions to use `dangerouslyDisableSandbox: true` for `git`, `curl`, and most
HTTPS-based tooling. Tracked in issue #367.

## Symptom

Inside the Claude Code sandbox, Go-based TLS stacks and some system binaries
have failed with:

```
Post "https://api.github.com/graphql": tls: failed to verify certificate:
x509: OSStatus -26276
```

The workaround prior to this fix was to set `dangerouslyDisableSandbox: true`
on every affected Bash call, which in turn triggered an individual user
confirmation prompt per call.

## Root Cause

The Claude Code sandbox on macOS restricts access to the Keychain Services
API. Tools that read trust anchors from a local CA bundle file (LibreSSL,
OpenSSL, libcurl) succeed once the bundle path is discoverable via
`SSL_CERT_FILE`. Tools that mandate Keychain access return the Apple
`OSStatus -26276` error.

## Fix

Set two environment variables in `global/settings.json` so CA-bundle-aware
tools consult an on-disk file instead of the Keychain:

```json
{
  "env": {
    "SSL_CERT_FILE": "/etc/ssl/cert.pem",
    "SSL_CERT_DIR": "/etc/ssl/certs"
  }
}
```

After `scripts/sync.sh` propagates the change to `~/.claude/settings.json`,
new Claude Code sessions inherit the variables.

## Coverage Matrix

| Tool | TLS Stack | SSL_CERT_FILE Respected? | Works Inside Sandbox After Fix? |
|------|-----------|--------------------------|---------------------------------|
| `curl` | LibreSSL | Yes | Yes |
| `git` (HTTPS) | libcurl | Yes | Yes |
| `wget` | OpenSSL | Yes | Yes |
| `npm`, `pnpm`, `yarn` | Node OpenSSL | Yes | Yes |
| `pip` | urllib3 + OpenSSL | Yes | Yes |
| `go build`, `go mod` | Go crypto/tls | Yes (uses fallback roots) | Yes |
| `cargo` | rustls or OpenSSL | Yes | Yes |
| `gh` (GitHub CLI) | Go crypto/x509 on Darwin | **No** | **No** |
| Any Darwin-Go binary compiled against `Security.framework` | Go crypto/x509 on Darwin | **No** | **No** |

### gh Caveat

`gh` on macOS links against `crypto/x509/root_darwin.go`, which always calls
`Security.framework` for trust evaluation and ignores `SSL_CERT_FILE`. The
sandbox blocks Keychain access, so `gh` inherits the failure regardless of
env-var configuration. Neither `GODEBUG=x509roots=fallback` nor
`GODEBUG=x509usefallbackroots=1` changes this behavior on recent Go versions
because Darwin's `systemRoots` always succeeds-or-errors before the fallback
is consulted.

Two options for `gh` commands specifically:

1. **Bash allowlist (preferred for day-to-day use)**: add patterns to
   `global/settings.json` `permissions.allow` so the sandbox-bypass
   confirmation prompt does not re-appear for safe `gh` verbs:

   ```json
   "permissions": {
     "allow": [
       "Bash(gh issue *)",
       "Bash(gh pr view*)",
       "Bash(gh pr list*)",
       "Bash(gh pr checks*)",
       "Bash(gh run list*)",
       "Bash(gh repo view*)"
     ]
   }
   ```

2. **Rebuild gh without CGO**: `CGO_ENABLED=0 go install github.com/cli/cli/v2/cmd/gh@latest`
   produces a pure-Go binary that respects `SSL_CERT_FILE`. Not recommended
   for most users since it forfeits the Homebrew update pipeline.

## Platform Fallback Ladder

`scripts/verify-tls.sh` picks the first readable path when `SSL_CERT_FILE`
is not already set:

| Platform | Path | Notes |
|----------|------|-------|
| macOS (default) | `/etc/ssl/cert.pem` | Present on every supported macOS release |
| macOS (Homebrew) | `$(brew --prefix)/etc/openssl@3/cert.pem` | Fallback when the system path is unreadable |
| Debian / Ubuntu | `/etc/ssl/certs/ca-certificates.crt` | Installed by `ca-certificates` package |
| RHEL / Fedora | `/etc/pki/tls/certs/ca-bundle.crt` | Installed by `ca-certificates` package |
| Windows | N/A | `gh` on Windows uses Schannel and reads the Windows certificate store directly |

`SSL_CERT_DIR` points at a directory of hashed-link CA files. macOS keeps the
directory empty but some Linux distributions populate it; setting both is the
safest default.

## Verification

Run the included verification probe inside a sandboxed session:

```bash
./scripts/verify-tls.sh
```

Expected output (macOS, inside sandbox, after the fix):

```
SSL_CERT_FILE=/etc/ssl/cert.pem
SSL_CERT_DIR=/etc/ssl/certs

[FAIL] gh api user
       (expected — see "gh Caveat" above)
[OK] curl https://api.github.com
[OK] git ls-remote origin

2 / 4 probes passed. git and curl work without sandbox bypass.
For gh, use the Bash allowlist remediation documented above.
```

The script reports `gh` as a FAIL on macOS even after this fix. That is the
documented behavior, not a regression. `git` and `curl` passing is the goal
of this change.
