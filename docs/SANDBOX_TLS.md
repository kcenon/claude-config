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

TLS is not the only blocker. `gh` keeps its token in the macOS keyring by
default, and a sandboxed `gh auth status` reports `The token in keyring is
invalid` because the sandbox cannot read the keyring either. A fix that
restores TLS alone (`enableWeakerNetworkIsolation`, a CGO-free build) still
leaves `gh` unauthenticated inside the sandbox.

Options for `gh` commands specifically:

1. **Exclude `gh` from the sandbox (shipped default, issue #952)**:
   `global/settings.json` lists `gh *` in `sandbox.excludedCommands`, the
   remediation Claude Code's sandboxing guide gives for Go-based CLIs on macOS.
   A matching call runs outside the sandbox from the start, with the keyring
   token, and goes through the regular permission flow, where the
   `Bash(gh ...:*)` rules in `permissions.allow` approve it without a prompt.
   Two rules decide whether a call matches:

   - **The whole call must match.** `gh pr checks 1 | head` stays sandboxed
     because `head` matches no entry, fails TLS, and the unsandboxed retry
     then prompts. A redirect to a file, a `cd`, or a `$(...)` substitution
     also keeps the call sandboxed. Keep one `gh` command per Bash call: shape
     output with `--jq`, pass `--repo owner/name` literally (no `R=...;`
     prefix), and wait with `gh pr checks --watch` or `gh run watch` instead
     of a polling loop. `global/CLAUDE.md` carries this as an always-on
     invariant.
   - **End each entry with ` *`.** Entries use `Bash(...)` rule syntax, where
     a pattern without a wildcard is an exact match: `docker` matches only the
     bare word, never `docker ps`. The `docker` and `watchman` entries were
     bare words until #952.

   A `gh` command a helper script runs is not matched, because matching reads
   the text of the call. Such a script still needs an unsandboxed retry.

2. **Bash allowlist alone (before #952)**: the `Bash(gh ...:*)` rules in
   `permissions.allow` approve an unsandboxed retry of a single `gh` command,
   but not a compound call. In a review of six days of sessions, 80 of 83
   prompted `gh` calls were compound, and a `PreToolUse` hook returning
   `allow` did not reliably approve the retry either. Without the
   `excludedCommands` entry, most `gh` work prompts.

3. **Rebuild gh without CGO**: `CGO_ENABLED=0 go install github.com/cli/cli/v2/cmd/gh@latest`
   produces a pure-Go binary that respects `SSL_CERT_FILE`. It does not fix
   the keyring token, and it forfeits the Homebrew update pipeline.

## Other Sandbox Collisions

The same review found two more sources of unsandboxed retries:

- **`npm` cache**: the sandbox can write only `~/.npm/_logs`, so `npm view`,
  `npm ci`, and `npx` fail on the cache (`EPERM`, "sudo chown -R ... ~/.npm").
  `global/settings.json` adds `~/.npm` to `sandbox.filesystem.allowWrite`.
- **Read denies that match source code**: the `Read(...)` deny rules in
  `permissions.deny` become sandbox read denies, so `**/secrets` blocks a
  source directory such as `src/security/secrets`, and `**/*password*` blocks
  files such as `password_callback.hpp` or a test fixture. `git status`,
  builds, and test runners in those repositories then fail or report the
  files as deleted. Re-open the specific paths with
  `sandbox.filesystem.allowRead`; a literal path re-opens a region that a
  `**/` glob denies (verified on macOS, 2026-10-23). Keep these entries out
  of `global/settings.json`, because the paths are per machine and the
  installer replaces the user-level `sandbox` key. Put them in the
  `.claude/settings.local.json` of the directory sessions start from:

  ```json
  {
    "sandbox": {
      "filesystem": {
        "allowRead": ["~/Sources/example/src/security/secrets"]
      }
    }
  }
  ```

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
For gh, use the excludedCommands remediation (option 1 under "gh Caveat").
```

The script reports `gh` as a FAIL on macOS even after this fix. That is the
documented behavior, not a regression. `git` and `curl` passing is the goal
of this change.
