# Git Identity

Personal git identity Claude Code uses when authoring commits, issues, and PRs.

The installer auto-seeds the two fields below from your `git config --global`
(`user.name` / `user.email`) when both are set, so a fresh install usually
needs no manual editing. If either git-config value is missing, replace the
`YOUR NAME` / `YOUR EMAIL` placeholders by hand.

name: YOUR NAME
email: YOUR EMAIL

## Notes

- This file is deployed to `~/.claude/git-identity.md` and holds personal
  information; it is not meant to be committed back to any repository.
- To change your identity later, edit the two lines above and rerun nothing —
  Claude Code reads this file directly.
