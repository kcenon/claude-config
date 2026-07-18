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

---

# Subagent spawn + single-writer lease (#839)

Picks up where `READY` leaves off. The reference implementation is
`scripts/agents.sh` (sibling directory), ported 1:1 to `scripts/agents.ps1`.
It reuses the #838 manifest primitive (`workspace_manifest_write` / `_read` /
`_state`) by sourcing `workspace.sh`, and advances the manifest through
`READY -> AGENTS_RUNNING -> COMMITTED`. Code and doc must stay in sync — when
one changes, change the other in the same PR (same rule as the #838 sections
above).

This stage delivers three things and nothing more:

1. A **spawn-prompt contract** that guarantees every subagent is fully
   specified before it is launched.
2. A **single-writer lease** so only one writer mutates a shared checkout at a
   time.
3. The `READY -> AGENTS_RUNNING -> COMMITTED` manifest transitions, built on the
   #838 atomic primitive.

Per-agent worktrees are the escape hatch used **only** when concurrent writes
are genuinely required; the default is the single-writer lease on the shared
checkout.

## Agent prompt contract

`agents_build_prompt <repo_path> <issue> <branch> <baseline> <write_scope>`
emits a prompt that ALWAYS contains every field below, so a coordinator can
never spawn an under-specified agent:

| Field | Source | Why it is mandatory |
|-------|--------|---------------------|
| Normalized absolute repo path | `agents_normalize_path` of `<repo_path>` | An agent must never guess its working directory; a relative path is resolved to an absolute, symlink-resolved path. |
| Active issue | `<issue>` | Anchors the work and every artifact reference to one issue. |
| Target branch | `<branch>` | The branch the coordinator will commit and push; the agent writes toward it but never pushes. |
| Baseline commit | `<baseline>` | The exact `develop` HEAD the workspace was cloned at (#838 `baseline`). |
| Explicit write scope | `<write_scope>` | The only paths the agent may create or edit. Everything else is read-only to it. |
| Ownership / prohibition clause | fixed prose | States that the coordinator owns all git/GitHub mutations and forbids the agent from pushing to the remote, invoking the GitHub CLI, opening/updating/merging a pull request, or cleaning up the workspace. |

The prohibition clause is worded to convey each ban without embedding a literal
push or GitHub-CLI command token, so the capability-guard test can assert
`agents.sh` itself performs no such command (see below).

## Coordinator vs. agent capability split

The whole point of the spawn contract is a hard capability boundary. This is
the authority for who may do what:

| Capability | Coordinator | Subagent |
|------------|:-----------:|:--------:|
| Read/write files within the agent's write scope | Yes | Yes |
| Write files outside the write scope | Yes | No |
| `git` commit / branch (local) | Yes | No |
| `git push` to a remote | Yes | No |
| `gh` / GitHub API mutations | Yes | No |
| Open / update / merge a pull request | Yes | No |
| `git worktree` add/remove | Yes | No (coordinator-managed) |
| Workspace cleanup / teardown (#840) | Yes | No |

`agents.sh` enforces its own half of this contract structurally: it contains
**no** `gh` invocation and **no** remote push. The only git verb it ever runs
is `git worktree` (add/remove). A test greps the script to keep it that way.

## Lease protocol

Only one writer may modify a shared checkout at a time. The lease is a
directory whose creation is the atomic primitive:

- **Acquire** (`agents_acquire_lease <lease_path> <owner_id>`): creates the
  lease directory with `mkdir` (atomic on POSIX — exactly one caller can create
  it) and records `<owner_id>` in an `owner` marker file inside it. If the
  directory already exists, acquisition **fails** (non-zero) rather than
  admitting a second writer.
- **Release** (`agents_release_lease <lease_path> <owner_id>`): succeeds only
  when the caller is the recorded owner. Removal is **guarded** — the path's
  final component must equal the lease basename (`.iw-writer.lease`) and the
  directory must exist; release then deletes the known `owner` marker and
  `rmdir`s the now-empty directory. It never performs a recursive delete on a
  caller-supplied path.
- **Fail-safe**: when in doubt, refuse. A non-owner release, a release of a
  missing lease, and a release of a path that is not a lease directory all
  return non-zero and change nothing. A held lease is never silently stolen.
- **Mutual exclusion guarantee**: because acquisition is a single atomic
  directory create, two concurrent callers can never both observe success; the
  loser is refused and must wait or fall back to a worktree.

## Worktree rule

The single-writer lease on the shared checkout is the **default** concurrency
control. Per-agent worktrees (`agents_worktree_add` /
`agents_worktree_remove`, thin wrappers over `git worktree`) are used **only**
when agents must write concurrently and serializing them behind one lease is
unacceptable. When worktrees are used:

- Each worktree is created on its own branch under the run root.
- Each worktree **must** be removed once its agent finishes. An orphaned
  worktree keeps a lock in the parent repository and will block the #840
  cleanup stage, so removal is not optional.

## Manifest keys and transitions added by this stage

This stage advances `state` and adds one key, using the same atomic
`workspace_manifest_write` primitive (which redacts every value before it
touches disk):

| Key | Meaning |
|-----|---------|
| `state` | Advanced `READY -> AGENTS_RUNNING` (start phase) and `AGENTS_RUNNING -> COMMITTED` (post-commit phase). |
| `lease_owner` | The owner id recorded when the AGENTS_RUNNING transition is taken with an owner (the single writer holding the checkout). |

Transitions are strictly ordered. `agents_mark_running` refuses unless the
current state is exactly `READY`; `agents_mark_committed` refuses unless it is
exactly `AGENTS_RUNNING`. An out-of-order request (e.g. `COMMITTED` straight
from `READY`) is rejected and leaves the manifest unchanged, so a crash or a
mis-sequenced caller can never fabricate a state the work never actually passed
through. The `PUSHED` / `PR_OPEN` states listed in the full lifecycle table
remain the coordinator's / #840's responsibility — this stage stops at
`COMMITTED`.
