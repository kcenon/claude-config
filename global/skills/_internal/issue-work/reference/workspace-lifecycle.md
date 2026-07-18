# Workspace Lifecycle

Isolated-workspace stage for `issue-work`. Picks up exactly where the triage
state machine (`reference/triage-state-machine.md`) hands off — a `proceed`
outcome with a claimed `active` issue — and turns that claim into a private,
identity-verified clone before any code is written.

The reference implementation is `scripts/workspace.sh` (sibling directory),
ported 1:1 to `scripts/workspace.ps1`. This document is the contract: the
full lifecycle, the run-root layout, the marker format, the manifest schema,
the identity-verification rule, and the credential-redaction rule. Code and
doc must stay in sync — when one changes, change the other in the same PR.

## Handoff from triage

Triage (`run_triage`) ends at `PROCEED`: it selects and claims an issue but
performs no repository side effects. `run_workspace` is the next stage. It
takes the `active` issue number from triage's outcome JSON and turns it into
an isolated, verified clone — nothing more.

```
triage: run_triage --repo <owner/name> [--issue <n>]
          -> {"outcome":"proceed", "active":"<n>", ...}
                    |
                    v
workspace: run_workspace <owner/name> <base> <active>
          -> {"state":"READY", "run_root":..., "repo_dir":..., "baseline":..., ...}
```

## Full lifecycle

```
CLAIMED -> CLONING -> READY -> AGENTS_RUNNING -> COMMITTED -> PUSHED
        -> PR_OPEN -> CI_PENDING -> MERGED -> CLEANUP_PENDING -> CLEANED
```

| State | Meaning | Delivered by |
|-------|---------|---------------|
| `CLAIMED` | Run root and marker exist; the manifest records the claim. | **#838 (this issue)** |
| `CLONING` | The `develop` branch is being cloned into the run root. | **#838 (this issue)** |
| `READY` | Clone complete, origin identity verified against the expected `owner/name`. | **#838 (this issue)** |
| `AGENTS_RUNNING` | One or more implementation subagents are active in the workspace. | #839 |
| `COMMITTED` | Work is committed to a local branch. | #839 |
| `PUSHED` | The branch has been pushed to the remote. | #839 / #840 |
| `PR_OPEN` | A pull request exists for the branch. | #839 / #840 |
| `CI_PENDING` | CI is running against the PR. | #840 |
| `MERGED` | The PR merged. | #840 |
| `CLEANUP_PENDING` | The run root is scheduled for removal. | #840 |
| `CLEANED` | The run root has been removed. | #840 |

**This issue (#838) implements only `CLAIMED -> CLONING -> READY` and the
manifest primitive** (`workspace_manifest_write` / `_read` / `_state`) that
every later state transition reuses to record its own progress. It does not
spawn subagents, create branches, or open PRs — see "Scope boundary" below.

A `REJECTED` outcome is not part of the state list above: it is a terminal
side-exit specific to this stage, reached only when the post-clone origin
identity check fails or the clone itself fails. It never advances to
`READY`, and no later stage should ever observe it as a valid predecessor
state — a `REJECTED` run root is abandoned, not resumed.

## Run-root layout

```
<base>/iw-<issue>-<suffix>/        # run root
├── .iw-run-marker                 # marker file, see below
├── manifest                       # key=value state file, see below
└── repo/                          # the clone (created during CLONING)
```

- `<base>` is caller-supplied (a temp directory). The scripts never invent
  their own base.
- `<suffix>` makes the run root unique per invocation. It comes from the
  `WORKSPACE_RUN_SUFFIX` injection seam when the caller/test sets it
  (deterministic); otherwise it is a timestamp+pid combination so concurrent
  real runs do not collide.
- The `iw-<issue>-<suffix>` naming keeps the path short, which matters on
  systems with path-length limits and keeps run roots visually distinct
  from unrelated temp directories.
- `repo/` does not exist until the clone step creates it — `git clone`
  requires its destination to be absent or empty.

## Marker format

`.iw-run-marker` is written into the run root as soon as it is created,
before any manifest state is written. It is a small `key=value` block (the
same line format as the manifest, kept intentionally minimal):

```
issue=838
created=2026-07-18T12:16:48Z
```

Its purpose is narrow: a resumed session (or the cleanup stage, #840) can
confirm a candidate run root actually belongs to a specific issue — and was
created by this stage, not some unrelated temp directory — before reusing or
deleting it. The marker is not a substitute for the manifest; it never
carries lifecycle state.

## Manifest schema

The manifest is a portable, line-based `key=value` file — no `jq` (or any
JSON library) dependency, so both `workspace.sh` and `workspace.ps1` can read
and write it with only string operations. One key per line, `key=value`,
no quoting.

Keys written by this stage (#838):

| Key | Meaning |
|-----|---------|
| `issue` | The issue number this workspace was claimed for. |
| `repo` | The expected `owner/name` identity. |
| `run_root` | Absolute path to the run root (redundant with the manifest's own location, kept for convenience). |
| `marker` | Absolute path to `.iw-run-marker`. |
| `state` | Current lifecycle state — the single field every stage after this one reads first. |
| `repo_dir` | Absolute path to the clone (`<run_root>/repo`). Written once the clone succeeds. |
| `baseline` | The `HEAD` commit sha of the cloned `develop` branch at claim time. Written once verified. |

Later stages (#839, #840) append their own keys to the same manifest using
the same primitives; this document does not attempt to enumerate keys it
does not own.

### Atomicity rule

Every manifest write goes through `workspace_manifest_write <path> <key>
<value>`, which:

1. Redacts `<value>` through `workspace_redact_credentials` unconditionally
   (a no-op on non-URL-shaped values, so this is always safe to do).
2. Rewrites the manifest to a sibling temp file (`<path>.tmp.$$`), replacing
   any prior line for `<key>` and preserving every other key.
3. `mv`s the temp file over the real manifest path.

A reader (`workspace_manifest_read` / `workspace_manifest_state`) therefore
never observes a partially-written manifest: the file it opens is either the
version before the update or the version after, never a half-written mix.

## Identity-verification rule

Before a run root is allowed to reach `READY`, `workspace_verify_identity
<repo_dir> <expected owner/name>` must succeed:

1. Read `git -C <repo_dir> remote get-url origin`.
2. Redact it through `workspace_redact_credentials`.
3. Reduce it to its trailing `owner/name` path component — this step is
   host-agnostic by design (it strips a `<scheme>://<host>/` prefix or an
   SSH-shorthand `<user>@<host>:` prefix, then takes the final two
   `/`-separated segments), so it accepts both `https://github.com/owner/name`
   and `git@github.com:owner/name` (with or without a trailing `.git`) as
   specified, while also working unmodified against GitHub Enterprise hosts.
4. Compare the reduced value against the expected `owner/name` **exactly**.

A missing origin, an empty expected value, or any mismatch fails the check.
On failure the manifest is set to `REJECTED` (never `READY`) and the CLI
prints a `{"state":"REJECTED","reason":...}` JSON line and exits non-zero.
This is the single gate that keeps a workspace from ever being handed to a
subagent (#839) with the wrong repository checked out.

## Credential-redaction rule

No credential may ever reach stdout, stderr, or the manifest:

- `workspace_redact_credentials` strips any `<userinfo>@` segment
  immediately following a `<scheme>://` prefix — this covers
  `https://user:token@host/...` and the `x-access-token:<token>@` form used
  by gh/CI credential helpers — and matches anywhere in its input, not just
  at the start, so a credential embedded mid-sentence in a git error message
  is also caught.
- `workspace_manifest_write` runs every value through this redaction
  unconditionally before it ever touches disk.
- `_workspace_clone` never streams git's own stdout/stderr to the caller.
  On failure it captures git's combined output, redacts it, and only a
  redacted, single-line summary is ever placed in a `reason` field.
- The identity-verification path redacts the origin URL before reducing it
  to `owner/name`, so a credential embedded in the stored remote URL never
  survives into a comparison, a log line, or an error message.
- The clone step never adds `--recurse-submodules` (submodule URLs are a
  second, uncontrolled source of embedded credentials this stage does not
  attempt to sanitize) and supports `--depth` only through an explicit
  `WORKSPACE_CLONE_DEPTH` seam, never on by default.

## Scope boundary

This stage stops at `READY`. It:

- Creates the run root, the marker, and the manifest.
- Clones `develop` and verifies the clone's origin identity.
- Writes exactly one final JSON line (`READY` or `REJECTED`) to stdout.

It does **not**:

- Spawn any subagent (#839).
- Create a branch, commit, push, or open a PR (#839 / #840).
- Poll CI, merge, or clean up the run root (#840).

A `REJECTED` run root is left on disk for inspection rather than deleted by
this stage — cleanup ownership belongs entirely to #840, consistent with
triage leaving no side effects on its own non-`proceed` terminal outcomes.
