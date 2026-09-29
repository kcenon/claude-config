# Supply-Chain Integrity Policy

This document describes how `claude-config` defends its install path against
supply-chain tampering, and how maintainers rotate pinned artifacts when
upstream legitimately changes.

## Threat model in scope

`bootstrap.sh` performs network fetches that, if compromised in transit or at
the origin, would execute attacker-controlled code on the user's machine.
The two surfaces are:

1. The `claude-config` source itself, fetched from GitHub. See M1.2a (#564 /
   PR #571) — pinned to a release tag and cloned with `git clone --branch`,
   eliminating mutable-`main` exposure.
2. The chained Anthropic Claude Code installer (`https://claude.ai/install.sh`)
   that `bootstrap.sh` invokes to install the `claude` CLI. The original
   pattern was `curl -fsSL ... | bash` — the canonical supply-chain pipe.
   This document covers the M1.2b mitigation (issue #565).

## Anthropic installer pin (M1.2b)

We pin the sha256 of the Anthropic install script. The pinned value lives
in `bootstrap.sh` as `ANTHROPIC_INSTALLER_SHA256`. When `ensure_claude_cli`
runs, it:

1. Downloads the installer to a temp file (no piping to bash).
2. Computes the sha256 of the downloaded bytes.
3. Compares against `ANTHROPIC_INSTALLER_SHA256`.
4. Aborts on mismatch with a clear error; only on match does it `bash` the
   temp file.

The pin is enforced at install time and re-validated weekly by CI (see
"Drift detection" below).

### Why pinning, not TLS alone

TLS protects bytes in transit, but the install pattern still trusts whatever
content the origin returns. A pinned sha256 binds the install to a specific,
human-reviewed version of the upstream installer — defense in depth against:

- A compromised CDN or origin returning malicious content under a valid TLS
  certificate.
- An MITM with a stolen or forged certificate (rare in practice, but cheap
  to defend against).
- A regression or accidental breaking change in upstream that we have not
  vetted yet — rotation forces a human to ack the new content.

### Why we do not auto-update the pin

Auto-rotation defeats the purpose: an attacker who controls the upstream for
a brief window would have their hash silently accepted. The drift workflow
intentionally fails CI rather than committing a new pin — a maintainer must
review the upstream change and open a manual PR.

## Drift detection

`.github/workflows/check-anthropic-installer.yml` runs every Monday at
06:07 UTC and on demand (`workflow_dispatch`). It runs
`scripts/check-installer-pins.sh`, which makes three checks and runs all of
them even when one fails:

| Check | Compares | Network |
|-------|----------|---------|
| bash pin parity | the `ANTHROPIC_INSTALLER_SHA256` default in `bootstrap.sh` with its copy in `scripts/install.sh` | no |
| `install.sh` | the `bootstrap.sh` pin with the sha256 of `https://claude.ai/install.sh` | yes |
| `install.ps1` | the `$AnthropicInstallerSha256` default in `bootstrap.ps1` with the sha256 of `https://claude.ai/install.ps1` | yes |

On a failure the workflow exits non-zero, prints both hashes to the job log,
and lists every result in the job summary. Exit code 1 is drift (a mismatch,
or bash pins that differ), 2 a pin line the script could not read, 3 a failed
download. Pull requests run the parity half too:
`tests/scripts/test-check-installer-pins.sh` (in `validate-hooks.yml`) runs
the script with `--offline` against the repository, so a rotation that
updates only one of the two bash pins fails before merge.

Failure paths the workflow surfaces:

- Anthropic published a legitimate update (release notes, blog post, or
  similar). Action: maintainer reviews the new installer content, computes
  the new sha256, and rotates the pin via PR.
- Origin or CDN serving unexpected content. Action: maintainer holds the
  pin, raises with Anthropic security, and notifies users via release
  notes if this drags on.
- The two bash pins differ (exit 1, parity row). Action: set both to the
  reviewed value in one PR.
- A pin line changed shape (exit 2). Action: restore the shape or update the
  pattern in `scripts/check-installer-pins.sh`.
- Network blip during the workflow (exit 3). Action: re-run the workflow
  manually.

## Rotating the pin

A pin rotation MUST be a human-authored PR with explicit rationale.

```bash
# 1. Verify the upstream change is legitimate.
#    Check Anthropic announcements, release notes, or contact Anthropic
#    security if the change is unexplained.

# 2. Compute the new sha256.
NEW_HASH=$(curl -fsSL https://claude.ai/install.sh | sha256sum | awk '{print $1}')
echo "$NEW_HASH"

# 3. Open a branch and update the pin in bootstrap.sh and its copy in
#    scripts/install.sh (ensure_claude_cli). Edit ANTHROPIC_INSTALLER_SHA256
#    and the `# pinned YYYY-MM-DD` comment in bootstrap.sh;
#    scripts/check-installer-pins.sh fails when the two values differ.

# 4. Commit and PR.
git commit -am "security(bootstrap): rotate Anthropic installer pin to <date>"
gh pr create --base develop --title "security(bootstrap): rotate Anthropic installer pin"
# In the PR body: link the upstream change, explain what changed and why
# we trust it.
```

PR review checklist for a pin rotation:

- [ ] Upstream change is documented (Anthropic announcement, release notes,
      diff inspection).
- [ ] New sha256 was independently re-computed by the reviewer.
- [ ] Pin date comment in `bootstrap.sh` (or `bootstrap.ps1`) is updated.
- [ ] For the bash pin, `bootstrap.sh` and `scripts/install.sh` carry the
      same value: `bash scripts/check-installer-pins.sh --offline` exits 0.
- [ ] No other unrelated changes in the PR.

## Tamper test

A local sanity check that the verification path actually aborts on a
forced mismatch:

```bash
# Override the pin to an obviously-wrong value and run the installer arm
# of bootstrap.sh interactively. The script must fail with the
# "sha256 불일치 — 설치 중단." message and a non-zero exit.
ANTHROPIC_INSTALLER_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
    bash bootstrap.sh
```

Expected: install aborts with the mismatch banner before any code from
`https://claude.ai/install.sh` is executed.

## Multi-entry-point parity (#620)

The download → verify → run contract is shared across all three install
entry points:

| Entry point | Verifies via | Pinned hash variable |
|-------------|--------------|----------------------|
| `bootstrap.sh` (one-line `curl ... \| bash`) | `hooks/lib/installer-fetch.sh` | `ANTHROPIC_INSTALLER_SHA256` |
| `scripts/install.sh` (`ensure_claude_cli`) | `hooks/lib/installer-fetch.sh` | `ANTHROPIC_INSTALLER_SHA256` |
| `bootstrap.ps1` (one-line `irm \| iex`) | `hooks/lib/InstallerFetch.psm1` | `$AnthropicInstallerSha256` |

The bash and PowerShell libs share the same exit-code semantics
(`0=OK`, `10=DOWNLOAD`, `11=CHECKSUM`, `12=MISMATCH`, `13=RUN`,
`64=usage`). Regression coverage lives at
`tests/scripts/test-installer-fetch.sh`.

Because `bootstrap.sh` and `bootstrap.ps1` run before the repo is cloned,
both reorder their `main` to clone first, then source/import the lib from
the just-cloned tag. This makes the `GITHUB_REF` tag the integrity root for
every subsequent verification step in those entry points.

### PowerShell installer pin

`bootstrap.ps1` ships a parallel pin for `https://claude.ai/install.ps1`,
and the weekly drift check covers it as well (#936). The URL answers 302 to
`https://downloads.claude.ai/claude-code-releases/bootstrap.ps1`, which
`curl -L` follows. Compute it the same way:

```bash
curl -fsSL https://claude.ai/install.ps1 | sha256sum
```

Rotate via `$AnthropicInstallerSha256` in `bootstrap.ps1` together with the
`# pinned YYYY-MM-DD` comment. The same review checklist as the bash pin
applies; if the bash and PowerShell installers drift independently the
maintainer rotates each side separately rather than waiting for both.

## Related

- Issue: #565 (M1.2b — bash sha256 pin), #620 (parity sync to ps1 + install.sh),
  #936 (drift check covers `install.ps1` and bash pin parity)
- Parent EPIC: #562 (supply-chain hardening rollup)
- Sibling: #564 / PR #571 (M1.2a — pin `claude-config` source by tag)
- Workflow: `.github/workflows/check-anthropic-installer.yml`, which runs
  `scripts/check-installer-pins.sh`
