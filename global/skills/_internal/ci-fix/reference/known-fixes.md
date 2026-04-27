# ci-fix — Known Fix Patterns

Catalogue of the three recurring CI failure patterns this skill handles. Each entry includes
a deterministic classifier, a before/after diff template, and a verification step.

## Classifier

Run against the last 200 lines of `gh run view <id> --log-failed`. First match wins.

| Priority | Pattern id | Signal (regex, case-insensitive) |
|----------|-----------|----------------------------------|
| 1 | `msvc-c4996` | `error C4996` or `warning C4996` accompanied by `/WX` or `treated as an error` under an MSVC toolchain |
| 2 | `cmake-fetchcontent` | `FetchContent` + (`fatal: could not read Username` OR `object .* not found` OR `could not fetch`) |
| 3 | `cpp-lib-format` | (`<format>` or `std::format`) AND (`__cpp_lib_format` or `cannot open source file` or `unresolved external symbol.*format`) |

If none match, fall through to escalation (see `SKILL.md` § Escalation).

---

## Pattern 1: `msvc-c4996` — Deprecated API under warnings-as-errors

**Root cause**: MSVC flags a deprecated API call (`strcpy`, `sprintf`, `fopen`, `std::iterator`,
etc.) and the project enables `/WX` (warnings as errors). Common trigger: `<iterator>` and
`<codecvt>` deprecations, or C runtime functions used in examples/adapters that were added after
the project-wide deprecation policy was set.

**Before (fails)**
```cpp
// example/legacy.cpp
#include <cstdio>
void write_log(const char* msg) {
    FILE* f = fopen("log.txt", "a");    // C4996: 'fopen': This function or variable may be unsafe
    fprintf(f, "%s\n", msg);
    fclose(f);
}
```

**After (passes)**
```cpp
// example/legacy.cpp
#include <cstdio>
#include <fstream>
void write_log(const char* msg) {
    std::ofstream f("log.txt", std::ios::app);
    f << msg << '\n';
}
```

Alternative when `fopen` is strictly required (e.g. third-party signature):
```cpp
FILE* f = nullptr;
#ifdef _MSC_VER
    fopen_s(&f, "log.txt", "a");
#else
    f = std::fopen("log.txt", "a");
#endif
```

**Do not** apply `#pragma warning(disable: 4996)` or add `_CRT_SECURE_NO_WARNINGS` project-wide
to silence the message — that hides the next deprecation too. Fix the call site.

**Verify**: build the affected target locally with `cmake --build build --target <target>` on a
Windows runner, or push and monitor the matrix leg only.

See also `msvc-c4996.md` for the full migration table.

---

## Pattern 2: `cmake-fetchcontent` — Shallow clone with a commit hash

**Root cause**: `FetchContent_Declare` is given `GIT_SHALLOW ON` together with `GIT_TAG <sha>`.
Shallow clones only resolve branch tips and tags; an arbitrary commit hash is not advertised by
the server and the fetch fails with `fatal: reference is not a tree`. The failure is
amplified when the `GIT_TAG` value arrives via macro expansion — quoting becomes non-obvious.

**Before (fails)**
```cmake
FetchContent_Declare(
    fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG        9a2138a8ec4ecef4e8c2ef3d1c8c1f3c4c0f2f3e   # commit sha
    GIT_SHALLOW    ON
)
```

**After (passes)** — pick one:

1. **Drop shallow clone** for commit-hash pins (preferred when determinism matters):
   ```cmake
   FetchContent_Declare(
       fmt
       GIT_REPOSITORY https://github.com/fmtlib/fmt.git
       GIT_TAG        9a2138a8ec4ecef4e8c2ef3d1c8c1f3c4c0f2f3e
       # GIT_SHALLOW removed; a full fetch is required to resolve a non-tip commit
   )
   ```

2. **Pin to a tag or branch** and keep `GIT_SHALLOW ON`:
   ```cmake
   FetchContent_Declare(
       fmt
       GIT_REPOSITORY https://github.com/fmtlib/fmt.git
       GIT_TAG        10.2.1
       GIT_SHALLOW    ON
   )
   ```

**Macro expansion caveat** — when `GIT_TAG` flows through a helper macro, quote the value at
the macro boundary:
```cmake
# fetch_dep expects: fetch_dep(<name> <repo> <tag>)
macro(fetch_dep name repo tag)
    FetchContent_Declare(${name}
        GIT_REPOSITORY ${repo}
        GIT_TAG        ${tag}            # unquoted OK only when tag is a single token
    )
endmacro()
```
Passing a tag with characters that require escaping (rare, but possible with Git refs) demands
`"${tag}"`. See `cmake-fetchcontent.md` for the full analysis.

**Verify**: `cmake -S . -B build -G <generator>` on a clean checkout. The configure step is
where `FetchContent_MakeAvailable` resolves the fetch.

---

## Pattern 3: `cpp-lib-format` — `__cpp_lib_format` probe vs link-time availability

**Root cause**: `<format>` is partially implemented across toolchains. `__cpp_lib_format` tells
the compiler the header parses; it does **not** guarantee the linker can resolve `std::format`
symbols. Projects that gate `<format>` purely on the feature macro hit link errors on Clang +
libstdc++ 14 and on older Apple Clang.

**Before (fails at link time on mixed toolchains)**
```cpp
// format_adapter.hpp
#include <version>
#if __cpp_lib_format >= 201907L
  #include <format>
  inline std::string render(int n) { return std::format("{}", n); }
#else
  #include <sstream>
  inline std::string render(int n) { std::ostringstream os; os << n; return os.str(); }
#endif
```

**After (passes)** — add a CMake-level probe that compiles *and* links:

```cmake
# cmake/checks.cmake
include(CheckCXXSourceCompiles)
check_cxx_source_compiles("
    #include <format>
    int main() { return std::format(\"{}\", 42).size(); }
" CLAUDE_HAS_STD_FORMAT)

if(CLAUDE_HAS_STD_FORMAT)
    target_compile_definitions(adapter PRIVATE CLAUDE_HAS_STD_FORMAT=1)
endif()
```

```cpp
// format_adapter.hpp
#if defined(CLAUDE_HAS_STD_FORMAT)
  #include <format>
  inline std::string render(int n) { return std::format("{}", n); }
#else
  #include <sstream>
  inline std::string render(int n) { std::ostringstream os; os << n; return os.str(); }
#endif
```

The project-controlled `CLAUDE_HAS_STD_FORMAT` replaces a hopeful `__cpp_lib_format` check and
is driven by a probe that actually links.

**Do not** rely on `__has_include(<format>)` either — the header may exist while `std::format`
remains unlinked (libc++ before 17, libstdc++ before 13).

**Verify**: the CMake configure log must show
`Performing Test CLAUDE_HAS_STD_FORMAT - Success` on supported matrices.

---

## Extending the Catalogue

To add a new pattern:

1. Append a row to the Classifier table with a precise regex.
2. Add a section following the same structure: Root cause → Before → After → Verify.
3. If the pattern needs more than ~200 lines of exposition, promote it to its own file under
   `reference/` and link it from this catalogue (as done for `msvc-c4996` and
   `cmake-fetchcontent`).
4. Cover the new pattern with a reproduction in `tests/` if the project has a skill-test harness.
