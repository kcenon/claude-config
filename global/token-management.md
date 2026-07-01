# Token Management

Personal notes on the access tokens and credential helpers Claude Code relies
on. This file is deployed to `~/.claude/token-management.md` with `600`
permissions and is intended for your own reference.

Never paste real tokens, passwords, or secrets into this file. Record only
*where* a credential lives and *how* to rotate it — not the value itself.

## GitHub

- Credential helper: <e.g. osxkeychain, gh auth, manager-core>
- Required scopes: `repo`, `workflow`, `read:org`
- Rotation policy: <cadence / expiry reminder>

## Other services

- <service>: <how the token is stored / where to rotate it>
