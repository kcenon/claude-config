## Epic closure audit update

The first registered child-issue wave for #776 has been implemented and merged to `develop`, but the final closure audit found two remaining follow-up gaps that now have dedicated issues.

### Child issue status

| Scope | Issues | Status |
|-------|--------|--------|
| P0 input minimization | #777, #778, #779, #780 | Closed and merged |
| P1 cross-platform and enforcement parity | #781, #782 | Closed and merged |
| P2 maintenance and documentation | #783 | Closed and merged |
| #783 split work | #790, #791, #792, #793, #794, #795 | Closed and merged through #796 |
| Final audit follow-ups | #797, #798 | Open |

### Final cross-check

The final audit found three concrete gaps after the implementation work had landed:

1. Git identity auto-seeding was implemented, but README, QUICKSTART, and installer next-step messages still described manual `git-identity.md` editing as required.
2. #778 lacks executable non-tty bootstrap coverage for the advertised `curl ... | INSTALL_TYPE=3 bash` path; tracked by #797.
3. #779 deployed bootstrap hooks but still ignores broad hook-copy failures after writing `settings.json`; tracked by #798.

This PR closes the first gap and two small parity defects discovered during the audit:

- fresh installs auto-fill `~/.claude/git-identity.md` from `git config --global user.name` and `git config --global user.email` when both values exist;
- docs now ask users to verify the installed values instead of editing by default;
- bootstrap and install scripts warn only when `YOUR NAME` / `YOUR EMAIL` placeholders remain.
- PowerShell reinstall keeps the prior `.language` and `.env.CLAUDE_CONTENT_LANGUAGE` settings just like Bash;
- `push-target-guard` now resolves bare `git push` through `@{upstream}` before falling back to the current branch.

### Verification

- `bash -n bootstrap.sh scripts/install.sh`
- PowerShell parser check for `bootstrap.ps1` and `scripts/install.ps1`
- `bash scripts/diff-readme.sh`
- `bash tests/scripts/test-diff-readme.sh`
- `pwsh -NoProfile -File tests/scripts/test-install-prompts-ps1.ps1`
- `pwsh -NoProfile -File tests/hooks/test-push-target-guard.ps1`
- `bash tests/hooks/test-push-target-guard.sh` with a temporary local `jq` wrapper because WSL exposes `jq.exe`, while CI installs native `jq`
- `git diff --check`

### Closure decision

#776 should remain open until #797 and #798 are complete. The rejected proposals in the epic body remain intentional non-goals:

- do not infer the language default from `$LANG`;
- do not unify the bootstrap install-type default with `scripts/install.sh`;
- do not merge the Bash PreToolUse hooks into one dispatcher.
