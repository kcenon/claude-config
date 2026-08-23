# Install Behavior

`bootstrap.sh`, `bootstrap.ps1`, `scripts/install.sh`, and
`scripts/install.ps1` preserve local customizations across re-installs by
recording SHA-256 manifests for managed install trees.

## Manifest

Locations:

- Global install tree: `~/.claude/.install-manifest.json`
- Project install tree: `<project>/.claude/.install-manifest.json`
- Enterprise install tree: `<enterprise-dir>/.install-manifest.json`, where
  `<enterprise-dir>` is `C:\Program Files\ClaudeCode` on Windows,
  `/Library/Application Support/ClaudeCode` on macOS, and `/etc/claude-code`
  elsewhere. Reachable only through `scripts/install.ps1` or
  `scripts/install.sh` with install type 4 or 5; neither `bootstrap.sh` nor
  `bootstrap.ps1` deploys it.

  On POSIX the enterprise root is usually not writable by the installing user,
  so `install_enterprise` sets `MANIFEST_ELEVATE=sudo` and the manifest helper
  routes its copies, its `mkdir`, and the placement of the manifest through
  that prefix. `MANIFEST_ELEVATE` is empty everywhere else, and an empty value
  makes the helper collapse to running the command directly, so the global and
  project layers are unaffected. The merged manifest document is always built
  unprivileged in a temp file and only its final placement is elevated: reading
  the existing manifest needs no privilege, and keeping the JSON step out of
  `sudo` avoids the environment stripping its inline variables depend on. The
  deployed manifest is left mode 644 so a drift audit can hash it without
  elevation.

Format:

```json
{
  "schema": 1,
  "files": {
    "CLAUDE.md": "sha256-hex",
    "commit-settings.md": "sha256-hex",
    "conversation-language.md": "sha256-hex",
    "git-identity.md": "sha256-hex",
    "token-management.md": "sha256-hex",
    "hooks/sensitive-file-guard.sh": "sha256-hex",
    "skills/_internal/issue-work/SKILL.md": "sha256-hex"
  }
}
```

The manifest is written on successful managed copies and updated whenever
the installer replaces a file. It is created on first install and survives
across re-runs. Project manifests use paths relative to the project root
(`CLAUDE.md`, `.claude/rules/...`, `.claude/skills/...`), while global
manifests use paths relative to `~/.claude`. The enterprise manifest follows
the same rule, with keys relative to the enterprise dir (`CLAUDE.md`,
`rules/security.md`, `rules/compliance.md`).

Each root needs its own manifest file, not merely its own key prefix: the
global and enterprise trees both deploy a file whose key is `CLAUDE.md`, so a
shared manifest would have them overwrite each other's stored hash and every
later guarded copy would compare against the wrong baseline.

## Copy Decision

On each run, the installer compares three hashes per tracked file:

- `src_hash` — the hash of the incoming managed file or rendered output
- `dest_hash` — the hash of the current deployed file
- `stored_hash` — the hash recorded in `.install-manifest.json`

| Condition | Outcome |
|-----------|---------|
| destination missing | copy and record `src_hash` |
| `src_hash == dest_hash` | no-op (record `src_hash` if manifest is empty) |
| `dest_hash == stored_hash` and `src_hash != dest_hash` | silent upgrade; record `src_hash` |
| destination diverges from both | prompt user (keep / overwrite) |

The "diverges from both" case means the user has locally edited the
file after the last install. In interactive mode the installer prints
the diff (first 40 lines) and prompts:

```
  [k]eep local / [o]verwrite (default: keep):
```

Pressing `Enter` keeps the local file unchanged. The manifest is not
updated in this case, so subsequent re-installs will prompt again until
the user either overwrites or aligns their local file with an upstream
version.

## Prune Decision

After the current managed set is copied, installers compare the manifest
against the current managed keys for that root.

| Condition | Outcome |
|-----------|---------|
| key is still in the current managed set | keep |
| key is absent, deployed file is missing | remove the stale manifest entry |
| key is absent, `dest_hash == stored_hash` | delete the removed managed file and remove the manifest entry |
| key is absent, `dest_hash != stored_hash` | preserve the local file and report it as locally edited |
| key points outside the install root | preserve and report as unsafe |

This is the deletion counterpart to guarded copy: repository removals are
propagated only when the deployed file still matches the last managed hash.
The installers also carry a small retired-file ownership table for legacy
command files removed before directory manifests existed. Those files are
seeded into the manifest only when their current bytes match a known
upstream hash; edited copies are preserved.

## Non-Interactive Override

For CI or unattended installs, the bootstrap entrypoints accept the same
prompt overrides as the clone installers. Use env vars when you want a
specific answer, or force every prompt's documented default:

```bash
# Pick the install type and accept every other default.
INSTALL_TYPE=3 bash bootstrap.sh

# Force bootstrap defaults. The bootstrap default install type is 1.
bash bootstrap.sh --yes
```

```powershell
# Pick the install type and accept every other default.
$env:INSTALL_TYPE = '3'; pwsh -File bootstrap.ps1

# Force bootstrap defaults. The bootstrap default install type is 1.
$env:FORCE_MODE = '1'; pwsh -File bootstrap.ps1
```

Recognized prompt overrides: `INSTALL_TYPE`, `PROJECT_DIR`,
`INSTALL_NPM`, `OVERWRITE`, `AGENT_LANGUAGE`, and `CONTENT_LANGUAGE`.
PowerShell also accepts `FORCE_MODE=1`, which is the `bootstrap.ps1`
equivalent of Bash `--yes`.

Manifest conflict resolution has a separate override:

```bash
BOOTSTRAP_FORCE=1 bash bootstrap.sh
```

```powershell
$env:BOOTSTRAP_FORCE = '1'; pwsh -File bootstrap.ps1
```

With `BOOTSTRAP_FORCE=1`, divergent manifest-tracked files are
overwritten and the manifest is refreshed. This flag does not select
answers for unrelated installer prompts.

## Toolchain Fallback

The POSIX path uses `python3` (or `python`) for JSON manipulation and
`shasum -a 256` or `sha256sum` for hashing. If none of these are
available on the system, the installer falls back to the previous
unconditional copy behavior for backwards compatibility.

PowerShell uses the built-in `Get-FileHash` and `ConvertTo-Json` /
`ConvertFrom-Json` cmdlets, so no additional dependencies are required
on Windows.

## Template Files

Some tracked files are rendered dynamically before the manifest copy
logic runs. Currently:

| Template | Output | Placeholders |
|----------|--------|--------------|
| `conversation-language.md.tmpl` | `conversation-language.md` | `{{AGENT_LANGUAGE_POLICY}}` → `English` / `Korean` |

Render pipeline (`guarded_template_copy` in
`scripts/install-manifest.sh` and `Invoke-GuardedTemplateCopy` in
`scripts/install-manifest.ps1`):

1. Detect `.tmpl` source.
2. Substitute placeholders into a temp file (sed for POSIX,
   `-replace` for PowerShell).
3. Pass the temp file through the standard manifest copy decision
   (see "Copy Decision" above).
4. `src_hash` is computed from the **rendered output**, not the raw
   template, so the manifest reflects the user's policy choice.

Selecting a different policy on re-install produces a different
`src_hash`, which triggers a silent upgrade if the user has not
locally edited the file, or a "diverges from both" prompt otherwise.

On re-install, the language prompt seeds its defaults from the existing
`settings.json`: `.language` seeds `AGENT_LANGUAGE`, and
`.env.CLAUDE_CONTENT_LANGUAGE` seeds `CONTENT_LANGUAGE`. Explicit env
overrides still win, and the two values are seeded independently.

`settings.json` follows a different rule: it bypasses the manifest
entirely so policy attributes (`.language`,
`.env.CLAUDE_CONTENT_LANGUAGE`) are enforced on every install.
`update_claude_settings_json` / `Update-ClaudeSettingsJson` injects
the values and removes them when the policy returns to the default
("english"), keeping the file idempotent.

Bootstrap and clone installers publish `settings.json` together with the
runtime hooks it references. `bootstrap.sh` and `scripts/install.sh` stage
`global/settings.json`; `bootstrap.ps1` and `scripts/install.ps1` stage
`global/settings.windows.json`. Each path applies the language policy to
the staged file, deploys the required hook scripts and hook libraries, and
only then replaces `~/.claude/settings.json`. If hook deployment or
required runtime-library validation fails, the staged settings file is
removed and the existing `settings.json` is left unchanged.

The platform settings profiles are parity-gated in CI. Bash installers stage
`global/settings.json`; PowerShell installers stage `global/settings.windows.json`.
`tests/scripts/test-windows-settings-parity.sh` fails if top-level keys,
shared `env` values, `permissions.deny`, or the Bash `permissions.allow`
surface drift unexpectedly. The only documented exceptions are POSIX CA-bundle
environment variables and the Windows-only PowerShell read-only allowlist.

## Tracked Files

The global manifest tracks guarded files under `~/.claude`, including:

- Core markdown files: `CLAUDE.md`, `commit-settings.md`,
  `conversation-language.md`, `git-identity.md`, `token-management.md`
- Runtime trees: `hooks/`, `hooks/lib/`, `scripts/`
- Catalog trees: `skills/`, `commands/`
- `.claudeignore`, deployed by all four full-install entry points. It is part
  of the `~/.claude/` subtree that `CLAUDE_DOCKER_CONTRACT.md` guarantees, so
  it is not optional; before #914 only `install.sh` deployed it and the
  verifiers reported a permanent `MISS` everywhere else.
- Optional in-tree artifacts when present, such as `policies/`

The project manifest tracks files relative to the project root, including
`CLAUDE.md`, `.claude/settings.json`, `.claude/rules/`,
`.claude/reference/`, `.claude/skills/`, `.claude/commands/`,
`.claude/agents/`, and `.claudeignore`.

The enterprise manifest tracks `CLAUDE.md` and `rules/` relative to the
enterprise dir. Two differences from the other two roots:

- **Prune does not run for this root.** Tracking exists so drift becomes
  visible; deleting files out of a managed-policy directory is a separate
  decision. A retired enterprise rule therefore stays on disk after it is
  removed from `enterprise/rules/`, as it did before tracking existed.
- **`BOOTSTRAP_FORCE=1` reaches this root too.** Since the tree is now
  manifest-tracked, a divergent enterprise policy file is overwritten without
  the keep/overwrite prompt under that variable, exactly as for the global and
  project trees.

Artifacts deployed outside those roots, such as `~/.tmux.conf` and
`~/.config/ccstatusline/settings.json`, remain outside manifest pruning.

## Regression Test

`tests/scripts/test-install-preserves-customization.sh` covers keep,
overwrite, force, prune, and retired-file seeding paths for the Bash
helper. `tests/scripts/test-install-manifest-helpers.sh` and
`tests/scripts/test-install-manifest-helpers.ps1` cover template copies,
tree copies, tracked prune, and settings mutation helpers.

Run the focused Bash tests from the repository root:

```bash
bash tests/scripts/test-install-preserves-customization.sh
bash tests/scripts/test-install-manifest-helpers.sh
```

Run the PowerShell helper test where `pwsh` is available:

```powershell
pwsh -NoProfile -File tests/scripts/test-install-manifest-helpers.ps1
```

The Bash manifest tests are skipped on systems without `python3`/`python`;
on such systems the POSIX installer itself also falls back to unconditional
copy.
