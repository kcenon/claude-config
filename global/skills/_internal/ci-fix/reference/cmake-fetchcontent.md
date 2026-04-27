# CMake FetchContent — Shallow Clone and Macro Expansion

Deep dive for the `cmake-fetchcontent` pattern in `known-fixes.md`. Read this when the
before/after diff is not enough — typically when a helper macro sits between the caller and
`FetchContent_Declare`.

## Why `GIT_SHALLOW ON` + commit hash fails

`git clone --depth 1` instructs the server to advertise only the tip of each branch. Tags are
negotiated separately with `--branch <tag>`. A bare commit hash is not advertised under either
path, so the resolver returns:

```
fatal: reference is not a tree: <sha>
```

or, on some servers, a less specific `upload-pack` error. CMake surfaces these as:

```
CMake Error at FetchContent_Declare: failed to clone https://.../fmt.git
```

This is not a CMake bug — it is a direct consequence of the Git transfer protocol when asked to
materialize a commit the server is not advertising.

## Resolution matrix

| Pin type | `GIT_SHALLOW` safe? | Notes |
|----------|---------------------|-------|
| Tag (`v10.2.1`) | Yes | Most common choice for releases. |
| Branch (`main`, `release/1.0`) | Yes | Non-deterministic; avoid for reproducible builds. |
| Short SHA (`abcd123`) | No | Shallow fetch cannot resolve. |
| Full SHA (`abcd123...`) | No | Same. Drop shallow or use a submodule. |
| Tag + SHA (belt-and-braces) | Yes | Use tag for fetch, verify SHA post-fetch. |

## Macro expansion mechanics

CMake macros expand argument tokens textually before the surrounding command is parsed. This
matters for `GIT_TAG` values containing characters CMake treats specially: `;`, `$`, `"`, and
whitespace.

### Failure mode A — list expansion

`${list}` expands to a semicolon-joined string. If a macro receives what it thinks is a single
tag but was actually passed a list, `FetchContent_Declare` sees multiple `GIT_TAG` values:

```cmake
set(TAG_LIST "v10.2.1" "v10.2.2")    # a CMake list
fetch_dep(fmt "https://.../fmt.git" ${TAG_LIST})
# Expands to:
#   fetch_dep(fmt "https://.../fmt.git" v10.2.1;v10.2.2)
# FetchContent then parses the tag as "v10.2.1;v10.2.2" and fails.
```

**Fix**: quote in the macro body:

```cmake
macro(fetch_dep name repo tag)
    FetchContent_Declare(${name}
        GIT_REPOSITORY ${repo}
        GIT_TAG        "${tag}"
    )
endmacro()
```

### Failure mode B — nested variable references

If the caller passes `${VAR_NAME}` and `VAR_NAME` itself holds another variable reference,
expansion can produce an empty string:

```cmake
set(FMT_VERSION "")
set(DEP_TAG "${FMT_VERSION}")        # intentionally empty sentinel
fetch_dep(fmt "https://.../fmt.git" ${DEP_TAG})
# GIT_TAG expands to an empty token; FetchContent defaults to the default branch
# and the build is non-deterministic.
```

**Fix**: validate at the caller:

```cmake
if(NOT FMT_VERSION)
    message(FATAL_ERROR "FMT_VERSION must be set before calling fetch_dep")
endif()
```

## Submodule alternative

When a project must pin to a commit hash that no tag points at (e.g. a patch not yet released),
prefer `git submodule` over `FetchContent`:

```bash
git submodule add -b main https://github.com/fmtlib/fmt.git external/fmt
git -C external/fmt checkout <sha>
git add external/fmt
git commit -m "deps: pin fmt to <sha> via submodule"
```

Drawback: consumers of the repo must run `git submodule update --init --recursive`. Benefit: no
shallow-clone negotiation involved — the commit is materialized by the submodule checkout.

## Verification

```bash
rm -rf build
cmake -S . -B build -G Ninja
```

Look for:

```
-- FetchContent: populating fmt
-- FetchContent: fmt populated
```

If you see `fatal: reference is not a tree` or `git fetch failed`, the fix was not applied
correctly — re-check `GIT_SHALLOW` and quoting.

## Cross-reference

- Pattern summary: `known-fixes.md` § Pattern 2
- CMake docs: <https://cmake.org/cmake/help/latest/module/FetchContent.html>
