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
06:07 UTC and on demand (`workflow_dispatch`). It re-fetches
`https://claude.ai/install.sh`, computes its sha256, and compares against
the pinned value extracted from `bootstrap.sh`. On mismatch the workflow
exits non-zero with both hashes printed to the job log, surfacing an alert
that a maintainer can investigate.

Failure paths the workflow surfaces:

- Anthropic published a legitimate update (release notes, blog post, or
  similar). Action: maintainer reviews the new installer content, computes
  the new sha256, and rotates the pin via PR.
- Origin or CDN serving unexpected content. Action: maintainer holds the
  pin, raises with Anthropic security, and notifies users via release
  notes if this drags on.
- Network blip during the workflow. Action: re-run the workflow manually.

## Rotating the pin

A pin rotation MUST be a human-authored PR with explicit rationale.

```bash
# 1. Verify the upstream change is legitimate.
#    Check Anthropic announcements, release notes, or contact Anthropic
#    security if the change is unexplained.

# 2. Compute the new sha256.
NEW_HASH=$(curl -fsSL https://claude.ai/install.sh | sha256sum | awk '{print $1}')
echo "$NEW_HASH"

# 3. Open a branch and update the pin in bootstrap.sh.
#    Edit ANTHROPIC_INSTALLER_SHA256 and the `# pinned YYYY-MM-DD` comment.

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
- [ ] Pin date comment in `bootstrap.sh` is updated.
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

## Related

- Issue: #565 (M1.2b)
- Parent EPIC: #562 (supply-chain hardening rollup)
- Sibling: #564 / PR #571 (M1.2a — pin `claude-config` source by tag)
- Workflow: `.github/workflows/check-anthropic-installer.yml`
