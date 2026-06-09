# SSH Commit Signing for claude-memory

> **Status**: Active
> **Audience**: Operators of any machine that pushes to `kcenon/claude-memory`
> **Tracker**: kcenon/claude-config#518
> **Related**: kcenon/claude-config#534 (rotation/compromise procedures in `docs/MEMORY_SYNC.md`)

Every machine that pushes commits to `kcenon/claude-memory` **must sign those
commits with an SSH key**. Branch protection on `main` enforces this; unsigned
commits are rejected at the server. This document is the per-machine setup
runbook.

## Why SSH signing (not GPG)

- The user already has SSH keys configured for `git push`. Setting `gpg.format=ssh`
  lets the same key authenticate the push **and** sign the commit. No new keys
  to manage.
- GPG keyrings, agent forwarding, and trust webs are out of proportion for a
  single-user memory store.
- GitHub natively recognizes SSH signing keys (since 2022) and renders the
  "Verified" badge on the web UI.

## Per-machine setup (one-shot)

There are two paths: the **automated helper** (recommended) or **manual steps**.

### Automated path

```bash
cd /path/to/kcenon/claude-config
./scripts/memory/setup-ssh-signing.sh
```

The script:

1. Verifies `git >= 2.34`
2. Locates an existing SSH public key in `~/.ssh/` (preferring `id_ed25519`)
3. Backs up `~/.gitconfig` to `~/.gitconfig.bak.<timestamp>`
4. Sets `gpg.format=ssh`, `user.signingkey`, `commit.gpgsign=true`,
   `tag.gpgsign=true`
5. Writes `~/.config/git/allowed_signers` and configures
   `gpg.ssh.allowedSignersFile`
6. Prints the next manual steps (key registration on GitHub, signed-commit test)

The script is **idempotent** (safe to re-run) and **non-destructive** (it does
not generate keys unless given `--generate-key`, and never uploads keys to
GitHub).

Useful flags:

| Flag | Effect |
|------|--------|
| `--key <path>` | Use a specific public key file instead of auto-detect |
| `--generate-key` | Generate `~/.ssh/id_ed25519` if no key exists |
| `--dry-run` | Print intended changes without writing |
| `--help` | Show usage |

### Manual path

If you prefer to run each step yourself:

```bash
# 1. Verify git version
git --version  # must be >= 2.34

# 2. Generate an SSH key if you do not have one
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# 3. Configure git
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# 4. Set up allowed_signers for local verification
mkdir -p ~/.config/git
EMAIL="$(git config --global user.email)"
KEY="$(awk '{print $1, $2}' ~/.ssh/id_ed25519.pub)"
echo "${EMAIL} ${KEY}" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

## Register the key on GitHub (manual)

The setup helper does **not** upload keys for you. After running it:

1. Open `https://github.com/settings/ssh/new`
2. Paste the contents of your public key
3. **Set Key type = Signing Key** (this is critical; auth keys are separate)
4. Save

Alternatively, with `gh` CLI (still requires your explicit consent):

```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$(hostname -s)"
```

## Verification

From any local clone of `claude-memory`:

```bash
git commit -S --allow-empty -m "test signed commit"
git log --show-signature -1
```

Expected output:

```
commit ...
Signature made ... using SSH key SHA256:...
Good "ssh" signature for you@example.com with ED25519 key SHA256:...
```

`git verify-commit HEAD` should also report `Good signature`.

If you see `Could not verify signature`, your `allowed_signers` file is missing
the email/key entry. Re-run `setup-ssh-signing.sh` or check the file by hand.

## Branch protection (repository owner only)

This is run **once per repository**, not per machine.

```bash
gh api repos/kcenon/claude-memory/branches/main/protection \
  --method PUT \
  -f required_signatures.enabled=true \
  -f required_pull_request_reviews=null \
  -f restrictions=null \
  -f enforce_admins=true
```

After this, the server enforces:

- Unsigned commits to `main` are rejected
- Force-push to `main` is rejected
- Branch deletion is rejected
- `enforce_admins=true` means even the owner cannot bypass the rule

The same can be configured via `Settings -> Branches -> Branch protection rules`
in the GitHub web UI; check **Require signed commits**, **Include administrators**,
and uncheck force-push and deletion.

To temporarily disable (e.g., for emergency rollback):

```bash
gh api repos/kcenon/claude-memory/branches/main/protection \
  --method PUT \
  -f required_signatures.enabled=false
```

## Multi-machine workflow

Each machine has its own SSH signing key. Do **not** copy private keys between
machines; the threat model treats key compromise as a per-machine event.

The shared `allowed_signers` file accumulates one line per (email, key) pair:

```
you@example.com ssh-ed25519 AAAA...machine1
you@example.com ssh-ed25519 AAAA...machine2
you@example.com ssh-ed25519 AAAA...machine3
```

If you sync this file across machines (via `claude-memory` itself or
`stow(1)`), every machine can locally verify commits made by any other.

`setup-ssh-signing.sh` appends a new line on each unique (email, key) pair and
skips duplicates.

## Rotation (planned key replacement)

Detailed steps live in `docs/MEMORY_SYNC.md` (kcenon/claude-config#534). Quick
summary:

1. On the affected machine: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_v2`
2. `git config --global user.signingkey ~/.ssh/id_ed25519_v2.pub`
3. Add the new public key on GitHub as a signing key
4. Append the new entry to `~/.config/git/allowed_signers`
5. Test a signed commit
6. After a grace period, remove the old key from GitHub

## Compromise (urgent)

If a private key may have leaked:

1. Immediately remove the compromised key from GitHub
   (`https://github.com/settings/keys`)
2. Audit recent commits on `claude-memory main` for unauthorized changes
3. Generate a new key, register it, update `allowed_signers`
4. Document the incident in your local notes (and in the next memory sync)

The detailed compromise procedure is tracked in
kcenon/claude-config#534.

## Edge cases

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gpg failed to sign the data` | SSH agent not running | `eval "$(ssh-agent -s)" && ssh-add` |
| `error: bad signature` after pull | Remote `allowed_signers` missing | Append the remote committer's key entry |
| Existing `gpg.format=openpgp` | Previously used GPG | Helper backs up `~/.gitconfig` before changing |
| Multiple SSH keys present | Helper picks first match | Pass `--key <path>` to override |
| `git --version` < 2.34 | Distro git too old | Install newer git (Homebrew, deb backports, etc.) |

## References

- Git SSH signing config: <https://git-scm.com/docs/git-config#Documentation/git-config.txt-gpgssh>
- GitHub signed commit verification: <https://docs.github.com/en/authentication/managing-commit-signature-verification>
- `ssh-keygen` ALLOWED SIGNERS format: `man ssh-keygen` (search `ALLOWED SIGNERS`)
