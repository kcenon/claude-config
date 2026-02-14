---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.c", "**/*.rs", "**/*.go", "**/CMakeLists.txt", "**/*.cmake"]
alwaysApply: false
---

# C++ Build & Cross-Platform

> Merged from: `cross-platform.md` + `cmake-guidelines.md`

## Cross-Platform Compatibility

> Always consider cross-platform compatibility. Unix-specific APIs cause Windows CI failures.

### Platform Detection (C/C++)

```cpp
#if defined(_WIN32) || defined(_WIN64)
    #define PLATFORM_WINDOWS
#elif defined(__linux__)
    #define PLATFORM_LINUX
#elif defined(__APPLE__)
    #define PLATFORM_MACOS
#endif
```

### Common Unix-Only Patterns to Avoid

| Unix Pattern | Windows Alternative | Notes |
|--------------|---------------------|-------|
| `MSG_DONTWAIT` | `ioctlsocket(FIONBIO)` | Non-blocking I/O |
| `fork()` | `CreateProcess()` | Process creation |
| `/dev/null` | `NUL` | Null device |
| `SIGPIPE` | N/A | Handle in code |
| `dlopen()` | `LoadLibrary()` | Dynamic loading |
| `pthread_*` | `CreateThread()` | Or use C++11 threads |
| `mmap()` | `CreateFileMapping()` | Memory mapping |

### Socket Code

```cpp
// Cross-platform non-blocking I/O
#ifdef _WIN32
    u_long mode = 1;
    ioctlsocket(sock, FIONBIO, &mode);
    recv(sock, buf, len, 0);
#else
    recv(sock, buf, len, MSG_DONTWAIT);
#endif

// Socket close
#ifdef _WIN32
    closesocket(sock);
#else
    close(sock);
#endif
```

### File System

```cpp
// Null device
#ifdef _WIN32
    FILE* null = fopen("NUL", "w");
#else
    FILE* null = fopen("/dev/null", "w");
#endif

// Temporary directory
#ifdef _WIN32
    const char* temp = getenv("TEMP");
#else
    const char* temp = getenv("TMPDIR");
    if (!temp) temp = "/tmp";
#endif
```

### Portable Libraries

| Category | Portable Library |
|----------|------------------|
| Networking | Boost.Asio, libuv |
| Threading | C++11 std::thread |
| File System | C++17 std::filesystem |
| Process | Boost.Process |

### Rust/Go Cross-Platform

Rust and Go handle most cross-platform concerns automatically through their standard libraries. Use `#[cfg(target_os)]` (Rust) or build tags (Go) for platform-specific code.

---

## CMake Guidelines

> Always use unique, project-prefixed target names to avoid conflicts.

### Reserved Target Names (Never Use)

| Reserved | Reason | Use Instead |
|----------|--------|-------------|
| `test` | CTest | `${PROJECT_NAME}_test` |
| `install` | CMake | `${PROJECT_NAME}_install` |
| `clean` | CMake | N/A |
| `all` | CMake | N/A |
| `package` | CPack | `${PROJECT_NAME}_package` |

### Naming Conventions

```cmake
# Libraries: project-prefixed
add_library(${PROJECT_NAME}_core STATIC src/core.cpp)
add_library(${PROJECT_NAME}_utils STATIC src/utils.cpp)

# Executables
add_executable(${PROJECT_NAME} src/main.cpp)

# Tests: project-prefixed, registered with CTest
add_executable(${PROJECT_NAME}_test_unit tests/unit_tests.cpp)
add_test(NAME ${PROJECT_NAME}_unit_tests COMMAND ${PROJECT_NAME}_test_unit)

# Aliases: namespaced for external consumption
add_library(MyProject::core ALIAS ${PROJECT_NAME}_core)
```

### Conflict Prevention

```cmake
# Check if target exists before creating
if(NOT TARGET ${PROJECT_NAME}_mylib)
    add_library(${PROJECT_NAME}_mylib STATIC src/mylib.cpp)
endif()
```

### Debugging

```bash
# List all targets
cmake --build build --target help

# Search for target definitions
grep -rn "add_library\|add_executable" --include="CMakeLists.txt" .
```

### Checklist

- [ ] All targets use `${PROJECT_NAME}_` prefix
- [ ] No reserved names used
- [ ] No Unix-only patterns without platform guards
- [ ] CI configured for multi-platform testing
