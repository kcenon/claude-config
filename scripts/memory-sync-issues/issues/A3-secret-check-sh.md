---
title: "feat(memory): implement secret-check.sh PII/token scanner"
labels:
  - type/feature
  - priority/high
  - area/memory
  - size/S
  - phase/A-validation
milestone: memory-sync-v1-validation
blocked_by: [A1]
blocks: [A5]
parent_epic: EPIC
---

## What

Implement `scripts/secret-check.sh` per the spec from #A1. Detects non-owner emails, GitHub/AWS/OpenAI tokens, private IPs, foreign user home paths, SSH key fingerprints, and PEM blocks in memory files. **Blocks** on any finding (exit 1).

### Scope (in)

- Single bash script, executable, no compilation step
- Single-file mode and `--all <dir>` batch mode
- Owner identity allowlist via env vars (`OWNER_EMAILS`, `OWNER_GITHUB_HANDLE`, `OWNER_HOME_USER`)
- Default allowlist matches @kcenon's identity but is fully overridable
- Blocking exit code on any finding

### Scope (out)

- Frontmatter validation (#A2)
- Injection-pattern detection (#A4)
- Auto-redacting findings — caller decides response
- Removing files containing secrets — quarantine policy at #B4

## Why

Memory files are committed to a git repository and replicated across machines. A single accidental paste of a token or non-owner email leaks the secret to every clone and to GitHub history forever. **Pre-commit detection is non-optional** — once a secret reaches the remote, it cannot be unsent (rewriting history is detectable but the token must still be rotated).

### Concrete attack surface

1. User pastes terminal output containing a GitHub token into a "what I learned" memory
2. Claude auto-saves a memory while debugging, includes a co-worker's email from a stack trace
3. User describes a sensitive incident, includes `/Users/coworker/...` path
4. Memory describes a key rotation, accidentally includes `-----BEGIN OPENSSH PRIVATE KEY-----` block

### What this unblocks

- #A5 — integration tests need this tool
- #C3 — pre-commit hook calls secret-check.sh on staged files (last line of defense before push)
- #C5 — GitHub Actions runs secret-check.sh as second-line defense
- #D1 — sync engine refuses to push if any pending memory contains a secret
- #D2 — write-guard hook calls secret-check.sh during Edit/Write to memory paths

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high — secrets reaching the remote repo cannot be unsent
- **Estimate**: ½ day
- **Target close**: within 1 week of #A1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree** (final): `kcenon/claude-memory/scripts/secret-check.sh` after #C1
- **Work tree** (interim): `kcenon/claude-config/scripts/memory/secret-check.sh`; moved in #C1
- **Reference implementation**: `/tmp/claude/memory-validation/scripts/secret-check.sh` (105 lines, drafted 2026-05-01)

## How

### Approach

Promote the prototype draft. Draft already handles GitHub no-reply pattern (#A1 fix) and `BASH_REMATCH` save-then-use guard. This issue formalizes, documents owner-allowlist override mechanism, adds fixture tests with synthetic positive cases.

### Detailed Design

**Script signature**:
```
secret-check.sh <path/to/memory.md>          # single-file mode
secret-check.sh --all <dir>                  # batch mode
secret-check.sh --help                       # usage
```

**Environment variables** (all optional, defaults provided):
- `OWNER_EMAILS` — space-separated list, default: `kcenon@gmail.com`
- `OWNER_GITHUB_HANDLE` — single string, default: `kcenon`
- `OWNER_HOME_USER` — single string, default: `raphaelshin`

**Exit codes** (per #A1 spec):
- `0` — clean
- `1` — at least one finding (block)
- `64` — usage error

**Internal flow** (per file):
1. Skip if filename is `MEMORY.md`
2. For each line, scan for email pattern; for each email, call `is_owner_email()` — if not owner, record finding
3. grep for token signatures (GitHub/AWS/OpenAI/PEM)
4. grep for IPv4 patterns; if matches private range, record finding
5. grep for `/Users/<not-owner>/` and `/home/<not-owner>/` paths
6. grep for SSH key fingerprints `SHA256:[A-Za-z0-9+/=]{43}`
7. Print findings with line numbers; return exit 1 if any

**Owner-email recognition function**:
```
is_owner_email(email):
  if email in OWNER_EMAILS: return true
  if email matches /^[0-9]+\+<HANDLE>@users\.noreply\.github\.com$/: return true
  if email == "<HANDLE>@users.noreply.github.com": return true
  return false
```

**Data structures**: `hits[]` array of finding strings.

**State and side effects**:
- Read-only on inputs
- Stdout: per-file verdict and findings
- No temp files, no network

**External dependencies**: bash 3.2+, `grep`. Pattern matching uses bash regex `=~` operator.

### Inputs and Outputs

**Input** (clean — current baseline):
```
$ ./secret-check.sh /tmp/claude/memory-validation/sample-memories/user_github.md
```

**Output**:
```
user_github.md                                     CLEAN
```
Exit code: `0`

**Input** (with secret — synthetic):
```
$ cat /tmp/poison.md
---
name: test
description: test memory
type: project
---
The token I used was ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345678 and the AWS key
was AKIAIOSFODNN7EXAMPLE. I logged in from coworker@enemy.example.com via
192.168.1.50 and saw /Users/intruder/secrets/.

$ ./secret-check.sh /tmp/poison.md
```

**Output**:
```
poison.md                                          SECRET-DETECTED
    [!] non-owner email: coworker@enemy.example.com
    [!] token pattern at line 6: The token I used was ghp_aBcDeFgHiJkLmNoPqRsTuV
    [!] token pattern at line 7: was AKIAIOSFODNN7EXAMPLE. I logged in from cowo
    [!] private IP at line 8: 192.168.1.50
    [!] foreign /Users/ path at line 8: /Users/intruder/
```
Exit code: `1`

**Input** (override owner allowlist):
```
$ OWNER_EMAILS="alice@example.com" OWNER_GITHUB_HANDLE="alice" \
    ./secret-check.sh memory.md
```

**Input** (batch):
```
$ ./secret-check.sh --all /tmp/claude/memory-validation/sample-memories/
```

**Output** (last lines):
```
...
user_github.md                                     CLEAN

Summary: 18 clean, 0 with findings
```
Exit code: `0`

### Edge Cases

- **Email split across lines** (e.g., `kcenon@\ngmail.com`) → regex requires single line; this case missed by design (acceptable: rarely occurs in markdown)
- **Email inside markdown link** `[text](mailto:foo@bar.com)` → still detected (regex matches `foo@bar.com`)
- **Token-shaped string in code-fence describing a leak the user is documenting** → detected; recommended workaround: `<redacted>ghp_xxxxxxxxxxxxxxxxxxxxxxxx</redacted>` per #A1 spec section 4.x
- **IPv6 private addresses (fc00::/7)** → not in v1; documented as future enhancement
- **`OWNER_EMAILS` env var with multiple values** → space-separated parsing
- **Owner email with subdomain** (e.g., `kcenon@gmail.googlemail.com`) → not in default allowlist; user adds via env var
- **GitHub no-reply with mixed case** (`KCenon@users.noreply.github.com`) → spec says case-sensitive; user must match canonical case
- **`MEMORY.md`** → skipped (auto-generated, no user content expected)
- **File with no readable content** (binary, unreadable) → bash read fails; tool prints error to stderr, returns 1

### Acceptance Criteria

- [ ] Exit codes match #A1 spec: 0=clean, 1=finding, 64=usage
- [ ] **Owner email allowlist**
  - [ ] `OWNER_EMAILS` env override works (default: `kcenon@gmail.com`)
  - [ ] GitHub no-reply pattern: `<id>+<handle>@users.noreply.github.com` recognized
  - [ ] GitHub no-reply alt: `<handle>@users.noreply.github.com` recognized
- [ ] **Token patterns detected**
  - [ ] GitHub: `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`
  - [ ] OpenAI: `sk-[A-Za-z0-9]{20,}`
  - [ ] AWS: `AKIA[0-9A-Z]{16}`
  - [ ] PEM blocks: `-----BEGIN [A-Z ]+-----`
- [ ] **Private IP ranges**: `10.*`, `192.168.*`, `172.16-31.*`
- [ ] **Foreign home paths**: `/Users/<not-OWNER_HOME_USER>/`, `/home/<not-OWNER_HOME_USER>/`
- [ ] **SSH key fingerprints**: `SHA256:[A-Za-z0-9+/=]{43}`
- [ ] Bash 3.2 compatible (`BASH_REMATCH` saved before reuse via `email="${BASH_REMATCH[1]}"`)
- [ ] Findings include line numbers (except whole-file email scan)
- [ ] `--all <dir>` produces summary: `Summary: N clean, N with findings`
- [ ] **Against the 18 baseline files** (17 memories + MEMORY.md): 18 CLEAN per REPORT
- [ ] **Against 5 synthetic positive fixtures** (one per category): all 5 detected
- [ ] **Owner override test**: with `OWNER_EMAILS="alice@example.com"`, `kcenon@gmail.com` becomes a finding (proves override works)
- [ ] Help text on `--help` or `-h`
- [ ] Script `+x`, shebang `#!/bin/bash`

### Test Plan

- 17 baseline + MEMORY.md → 18 CLEAN
- 5 synthetic positive fixtures (each isolating one category) → all detected with correct line numbers
- Owner allowlist override (env var test)
- macOS bash 3.2 + Linux bash 5.x both pass
- Re-run twice → byte-identical output
- False-positive rate against baseline: must remain 0

### Implementation Notes

- `BASH_REMATCH[1]` overwritten on next regex match within a loop → save first: `local email="${BASH_REMATCH[1]}"; line="${line//"$email"/}"`
- Removing matched email from `line` variable enables finding multiple emails per line in single pass
- IPv4 regex matches things like `1.2.3.4` even when they're part of version strings ("v10.0.5.2") → false positive risk; mitigation: only flag if IP is in private ranges (the alternation in regex), so version strings rarely match
- `grep -E` is required (POSIX `grep` doesn't support `+` quantifier)
- Default values for env vars use `${VAR:-default}` not `${VAR:=default}` (don't pollute caller's environment)
- Owner-email helper is a function so #C3 / #D1 / #D2 can source the script and reuse the function
- Avoid `awk` write-redirection patterns (would trigger bash-write-guard) — use grep + bash regex only

### Deliverable

- `scripts/secret-check.sh` (executable, ~120 lines after fixture-test additions)
- Help text via `--help`
- PR linked to this issue

### Breaking Changes

None — net-new tool.

### Rollback Plan

Revert PR.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #A1
- Blocks: #A5
- Related: #C3 (consumer), #C5 (consumer), #D1 (consumer), #D2 (consumer)

**Docs**:
- Spec: `docs/MEMORY_VALIDATION_SPEC.md` (created in #A1)
- Baseline report: `/tmp/claude/memory-validation/baseline/REPORT.md`

**Commits/PRs**: (filled at PR time)

**Reference implementation**: `/tmp/claude/memory-validation/scripts/secret-check.sh`
