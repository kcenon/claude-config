---
title: "chore(memory): enforce SSH commit signing across machines"
labels:
  - type/chore
  - priority/medium
  - area/memory
  - size/S
  - phase/C-bootstrap
milestone: memory-sync-v1-bootstrap
blocked_by: [C1]
blocks: [G1]
parent_epic: EPIC
---

## What

Enable required-signed-commit branch protection on `kcenon/claude-memory` main branch. Document the per-machine SSH signing key setup procedure. Provide `setup-ssh-signing.sh` helper that configures git to sign with SSH keys and registers the key with GitHub.

### Scope (in)

- GitHub branch protection rule on `main` requiring signed commits
- Per-machine setup script `scripts/setup-ssh-signing.sh`
- Documentation of key registration with GitHub
- Documentation of rotation procedure (key compromise / rotation)

### Scope (out)

- GPG-based signing (rejected: heavier setup, less common in this user's workflow)
- Org-wide signing policies (out of scope; single user)
- Cross-repo signing — only claude-memory matters here

## Why

Required-signed commits ensure that history can't be silently forged or rewritten. For a memory store that influences automatic behavior across all machines, **provenance matters as much as content**. A bad actor with write access (or a future me with a bad day) cannot inject memories without a verifiable signature.

SSH signing is preferred over GPG because the user already has SSH keys configured for git push, and the `gpg.format=ssh` setting makes the same key serve both purposes — no new keys to manage.

### What this unblocks

- #G1 — onboarding new machine documents key registration
- General confidence: any commit pulled during sync has a verified author

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium — required before second machine joins (#G1)
- **Estimate**: ½ day
- **Target close**: within 3 days of #C1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**:
  - GitHub branch protection: `kcenon/claude-memory` settings
  - Helper script: `kcenon/claude-config/scripts/memory/setup-ssh-signing.sh`
- **Per-machine config**: `~/.gitconfig` (or `~/.gitconfig.d/memory.conf`)

## How

### Approach

Branch protection set via `gh api`. Setup script automates the per-machine git config and provides instructions to register the key on GitHub. Document rotation procedure separately. Setup is one-shot per machine.

### Detailed Design

**Branch protection enable command**:
```
gh api repos/kcenon/claude-memory/branches/main/protection \
  --method PUT \
  -f required_signatures.enabled=true \
  -f required_pull_request_reviews=null \
  -f restrictions=null \
  -f enforce_admins=true
```

**`setup-ssh-signing.sh` flow** (per machine):
1. Check git ≥ 2.34 (SSH signing requires this)
2. Detect existing SSH key:
   - Look at `~/.ssh/id_ed25519.pub`, `~/.ssh/id_rsa.pub`, `~/.ssh/id_ecdsa.pub` in order
   - If none, prompt user to create one with `ssh-keygen -t ed25519`
3. Configure git:
   ```
   git config --global gpg.format ssh
   git config --global user.signingkey <path-to-pubkey>
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   ```
4. Set up `~/.config/git/allowed_signers` for local verification:
   ```
   <user-email> <key-type> <key-content>
   ```
5. Configure `gpg.ssh.allowedSignersFile`:
   ```
   git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
   ```
6. Print next steps:
   - Register the public key as a **signing** key (not auth key) at https://github.com/settings/keys
   - Test: `git commit -S --allow-empty -m "test signed"`
   - Verify: `git log --show-signature -1`

**Rotation procedure** (documented):
1. On affected machine, generate new key: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing_v2`
2. Update `user.signingkey` to new path
3. Add new public key as signing key on GitHub
4. Test signed commit
5. (Optional) Remove old key from GitHub after grace period
6. Document the rotation in `kcenon/claude-config/docs/MEMORY_SYNC.md`

**Compromise procedure** (documented separately):
1. Immediately remove compromised key from GitHub
2. Audit recent commits in `claude-memory` for unauthorized changes
3. Generate new key, update config, register
4. Notify any other machines (in single-user setup, just self-notify)

**State and side effects**:
- `setup-ssh-signing.sh`: modifies `~/.gitconfig` and creates `~/.config/git/allowed_signers`
- Branch protection: GitHub repo state
- No memory file modifications

**External dependencies**: git ≥ 2.34, ssh-keygen, gh CLI.

### Inputs and Outputs

**Input** (setup, fresh machine):
```
$ ./setup-ssh-signing.sh
```

**Output**:
```
[OK] git version: 2.42.1
[OK] found SSH key: ~/.ssh/id_ed25519.pub
[OK] configured git to sign with this key
[OK] wrote ~/.config/git/allowed_signers

Next steps:
  1. Visit https://github.com/settings/ssh/new
  2. Paste the public key, set Type=Signing key
  3. Run: git commit -S --allow-empty -m "test signed" -C <claude-memory-clone>
  4. Verify: git log --show-signature -1
```
Exit: `0`

**Input** (setup, no SSH key found):
```
$ ./setup-ssh-signing.sh
```

**Output**:
```
[ERROR] no SSH key found in ~/.ssh/
        Generate one with:
          ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
        Then re-run this script.
```
Exit: `1`

**Input** (verify after setup):
```
$ cd ~/.claude/memory-shared
$ git commit -S --allow-empty -m "test"
$ git log --show-signature -1
```

**Output**:
```
commit 3a4b5c6 ...
Signature made ... using SSH key SHA256:...
Good "ssh" signature for kcenon@gmail.com with ED25519 key SHA256:...
```

### Edge Cases

- **Existing `gpg.format=openpgp` config** (user previously used GPG) → script asks before overriding; backup current config to `~/.gitconfig.bak.<stamp>`
- **Multiple SSH keys** → script uses first found; user can re-run with `--key <path>` to override
- **Key file permissions wrong** (>600) → ssh-keygen normally rejects; document this if encountered
- **GitHub does not yet recognize SSH signing keys** (predates 2022) → fail loud; require git ≥ 2.34 and current GitHub
- **Allowed-signers file with multiple entries** (multiple machines, same user) → format supports multiple lines; one per machine; documented
- **Branch protection conflicts with admin override** → `enforce_admins=true` blocks even admin direct push
- **SSH agent not running** → signing fails per commit; documented; user starts agent
- **Different signing key per machine** → expected and supported; each machine independently registers
- **Lost key without rotation** → user can't sign on that machine; commits from that machine refused at server; rotation procedure restores

### Acceptance Criteria

- [ ] Branch protection on `kcenon/claude-memory` main: signed commits required
- [ ] `enforce_admins=true` (admin cannot bypass)
- [ ] `setup-ssh-signing.sh` configures git correctly when run on fresh machine
- [ ] Script detects git version, refuses on < 2.34
- [ ] Script detects existing SSH key in standard locations; prompts to create if missing
- [ ] Script writes `gpg.format=ssh`, `user.signingkey`, `commit.gpgsign=true`, `tag.gpgsign=true`
- [ ] Script creates `~/.config/git/allowed_signers` with the user's email + key
- [ ] Script prints clear "next steps" with the GitHub key registration URL
- [ ] **Rotation procedure documented** in `docs/MEMORY_SYNC.md` (created in #G3)
- [ ] **Compromise procedure documented** in `docs/MEMORY_SYNC.md`
- [ ] Test signed commit works after setup on at least one machine
- [ ] Branch protection prevents force-push, deletion, and unsigned-commit push

### Test Plan

- Fresh machine: run setup, register key, push signed commit → succeeds
- Try to push unsigned commit (`git -c commit.gpgsign=false commit ...`) → server rejects
- Try to force-push (`git push --force`) → server rejects
- Try to delete branch via `gh api --method DELETE` → server rejects
- macOS bash 3.2 + Linux bash 5.x both pass for the script

### Implementation Notes

- Both `commit.gpgsign` and `tag.gpgsign` set to true — tags also signed
- `allowed_signers` file format: `<email> [namespaces=...] <key-type> <key>` (man `ssh-keygen` § ALLOWED SIGNERS)
- Setting `enforce_admins=true` is critical; without it, repo owner can bypass and the protection is theatre
- Key paths: prefer `~/.ssh/id_ed25519` (modern); `id_rsa` fallback warned
- Branch protection settings can also be done via repo Settings UI; document both paths in case user prefers UI
- Verify post-setup with `git verify-commit HEAD` and `git log --show-signature -1`

### Deliverable

- `scripts/setup-ssh-signing.sh` in claude-config
- Branch protection enabled on claude-memory main
- Documentation snippet in `docs/MEMORY_SYNC.md` (cross-issue with #G3)
- PR linked to this issue

### Breaking Changes

After this issue lands, **commits to claude-memory main without signature are rejected**. Any in-flight unsigned PRs must be re-signed before merge.

### Rollback Plan

- Disable branch protection: `gh api ... -f required_signatures.enabled=false`
- Revert `setup-ssh-signing.sh` PR
- Existing signed commits remain signed (no harm)

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C1
- Blocks: #G1
- Related: #G3 (rotation/compromise docs)

**Docs**:
- `docs/MEMORY_SYNC.md` (#G3) — rotation & compromise procedures

**Commits/PRs**: (filled at PR time)

**External**:
- Git SSH signing: https://git-scm.com/docs/git-config#Documentation/git-config.txt-gpgssh
