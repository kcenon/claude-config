# MSVC C4996 — Deprecated API Migration

Deep dive for the `msvc-c4996` pattern in `known-fixes.md`. Read this when the simple "swap
`fopen` for `ofstream`" recipe is not enough — typically when the deprecated symbol is a
standard-library type (`std::iterator`, `std::codecvt`) or a Win32 API that does not have an
obvious cross-platform replacement.

## Why MSVC flags C4996 as an error

The project's CI enables `/WX` (treat warnings as errors). C4996 is the warning MSVC emits for
any symbol marked with `[[deprecated]]` or `_CRT_DEPRECATE_TEXT`. The warning exists on every
toolchain; `/WX` is what makes it a CI blocker.

The fix belongs at the call site. Neither `#pragma warning(disable: 4996)` nor
`_CRT_SECURE_NO_WARNINGS` scales — they hide future deprecations and are symptomatic of not
having a migration plan.

## Migration table

| Deprecated symbol | Preferred replacement | Notes |
|-------------------|------------------------|-------|
| `strcpy`, `strcat`, `sprintf`, `vsprintf` | `snprintf` + bounds, or `std::format` / `std::string` | Bounds-checked. |
| `fopen`, `freopen` | `std::ofstream` / `std::ifstream` | RAII; no need for `fclose`. |
| `fopen_s` (non-portable) | Platform shim, see Pattern 1 snippet | Keep `fopen_s` inside `#ifdef _MSC_VER`. |
| `std::iterator` (deprecated in C++17) | Define the five typedefs inline | `using iterator_category = …` etc. |
| `std::codecvt_utf8` (deprecated in C++17) | `MultiByteToWideChar` + `WideCharToMultiByte` on Windows; `iconv` or ICU elsewhere | `<codecvt>` is slated for removal. |
| `std::bind` | Lambda | Lambdas inline better and avoid surprising binding semantics. |
| `std::random_shuffle` | `std::shuffle` with an RNG | Removed in C++17; C4996 warns on compatibility shims. |
| `std::auto_ptr` | `std::unique_ptr` | Removed in C++17. |
| `std::uncaught_exception()` | `std::uncaught_exceptions()` (plural) | Removed in C++20. |
| Win32 `GetVersionEx` | `VerifyVersionInfo` or version helpers in `<VersionHelpers.h>` | `GetVersionEx` returns lies on Win10+. |

## `std::iterator` migration

Before:
```cpp
class MyIter : public std::iterator<std::forward_iterator_tag, int> {
    // …
};
```

After:
```cpp
class MyIter {
public:
    using iterator_category = std::forward_iterator_tag;
    using value_type        = int;
    using difference_type   = std::ptrdiff_t;
    using pointer           = int*;
    using reference         = int&;
    // …
};
```

The base class was never load-bearing — iterator traits look up the typedefs directly on the
iterator type. Removing the base is a pure rename.

## `std::codecvt_utf8` migration on Windows

Before:
```cpp
#include <codecvt>
#include <locale>
std::wstring to_wide(const std::string& s) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> cv;
    return cv.from_bytes(s);
}
```

After (Windows):
```cpp
#include <Windows.h>
std::wstring to_wide(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring out(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), n);
    return out;
}
```

Cross-platform projects should gate on `_WIN32` and keep a `<codecvt>` implementation for other
platforms, pending a move to `{fmt}` or ICU for real i18n.

## When you cannot migrate — scoped suppression

If the call site is third-party code you cannot edit, scope the suppression tightly:

```cpp
#ifdef _MSC_VER
    #pragma warning(push)
    #pragma warning(disable: 4996)
#endif

    third_party_call_that_uses_deprecated_api();

#ifdef _MSC_VER
    #pragma warning(pop)
#endif
```

Do **not** scope the suppression wider than the offending statement. Any future C4996 in the
suppressed region becomes silent.

## Verification

Rebuild the Windows matrix leg only:

```bash
cmake --preset windows
cmake --build --preset windows --target <target> -- /verbosity:normal | \
    grep -E "(C4996|/WX)" || echo "No C4996 under /WX"
```

A successful fix prints `No C4996 under /WX` and produces a green CI leg on the next push.

## Cross-reference

- Pattern summary: `known-fixes.md` § Pattern 1
- MSVC C4996 docs: <https://learn.microsoft.com/cpp/error-messages/compiler-warnings/compiler-warning-level-3-c4996>
