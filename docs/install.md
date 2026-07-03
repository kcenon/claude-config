# Install Behavior

`bootstrap.sh` (POSIX) and `bootstrap.ps1` (Windows) preserve local
customizations of global rule files across re-installs by recording a
SHA-256 manifest.

## Manifest

Location: `~/.claude/.install-manifest.json`

Format:

```json
{
  "schema": 1,
  "files": {
    "CLAUDE.md": "sha256-hex",
    "commit-settings.md": "sha256-hex",
    "conversation-language.md": "sha256-hex",
    "git-identity.md": "sha256-hex",
    "token-management.md": "sha256-hex"
  }
}
```

The manifest is written on successful copy and updated whenever the
installer replaces a file. It is created on first install and survives
across re-runs.

## Copy Decision

On each run, the installer compares three hashes per tracked file:

- `src_hash` — the hash of the incoming file under `$INSTALL_DIR/global/<file>` (if a `.tmpl` exists, this is the hash of the dynamically rendered output, e.g. for `conversation-language.md`)
- `dest_hash` — the hash of the current `~/.claude/<file>`
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

Bootstrap publishes `settings.json` together with the runtime hooks it
references. `bootstrap.sh` stages `global/settings.json` in a temp file
and `bootstrap.ps1` stages `global/settings.windows.json`; both apply the
language policy to the staged file, deploy the required hook scripts and
hook libraries, and only then replace `~/.claude/settings.json`. If hook
deployment or required runtime-library validation fails, the staged
settings file is removed and the existing `settings.json` is left
unchanged.

## Tracked Files

The manifest currently tracks these entries (see `bootstrap.sh`
`install_global` and `bootstrap.ps1` `Install-GlobalSettings`):

- `CLAUDE.md`
- `commit-settings.md`
- `conversation-language.md` *(rendered from `.tmpl` — see Template Files above)*
- `git-identity.md`
- `token-management.md`

Other installed artifacts (`tmux.conf`, `ccstatusline/settings.json`,
plugin resources, project templates) remain unconditional copies — add
them to the manifest block in future issues if their customizations
need to be preserved.

## Regression Test

`tests/scripts/test-install-preserves-customization.sh` covers the
keep / overwrite / force-flag paths of the manifest helper directly.
Run it from the repository root:

```bash
bash tests/scripts/test-install-preserves-customization.sh
```

The test is skipped on systems without `python3`/`python` — on such
systems the installer itself also falls back to unconditional copy.
