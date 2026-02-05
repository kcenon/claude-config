---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.c", "**/*.rs", "**/*.go"]
---

# Cross-Platform Compatibility Guidelines

> **Purpose**: Prevent Windows CI failures caused by Unix-specific code patterns
> **Impact**: Ensures code compiles and runs on both Windows and Unix systems

## Core Principle

Always consider cross-platform compatibility when writing system-level code. Unix-specific APIs and patterns will cause build failures on Windows CI.

## Platform Detection

### C/C++ Platform Macros

```cpp
#if defined(_WIN32) || defined(_WIN64)
    #define PLATFORM_WINDOWS
#elif defined(__linux__)
    #define PLATFORM_LINUX
#elif defined(__APPLE__)
    #define PLATFORM_MACOS
#elif defined(__unix__)
    #define PLATFORM_UNIX
#endif
```

### Rust Platform Detection

```rust
#[cfg(target_os = "windows")]
fn platform_specific() { /* Windows */ }

#[cfg(target_os = "linux")]
fn platform_specific() { /* Linux */ }

#[cfg(unix)]
fn platform_specific() { /* Any Unix */ }
```

### Go Platform Detection

```go
// Use build tags
// +build windows

// Or runtime check
import "runtime"
if runtime.GOOS == "windows" { /* Windows */ }
```

## Socket and Network Code

### MSG_DONTWAIT (Unix-only)

```cpp
// Unix-only - Will fail on Windows
int flags = MSG_DONTWAIT;
recv(sock, buf, len, MSG_DONTWAIT);
```

```cpp
// Cross-platform solution
#ifdef _WIN32
    // Windows: Use non-blocking socket mode
    u_long mode = 1;
    ioctlsocket(sock, FIONBIO, &mode);
    recv(sock, buf, len, 0);
#else
    // Unix: Use MSG_DONTWAIT
    recv(sock, buf, len, MSG_DONTWAIT);
#endif
```

### Socket Initialization

```cpp
// Windows requires WSAStartup
#ifdef _WIN32
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        // Handle error
    }
    // ... socket operations ...
    WSACleanup();
#endif
```

### Socket Close

```cpp
#ifdef _WIN32
    closesocket(sock);
#else
    close(sock);
#endif
```

## File System Operations

### Null Device

```cpp
// Unix-only
FILE* null = fopen("/dev/null", "w");

// Cross-platform
#ifdef _WIN32
    FILE* null = fopen("NUL", "w");
#else
    FILE* null = fopen("/dev/null", "w");
#endif
```

### Path Separators

```cpp
#ifdef _WIN32
    const char PATH_SEP = '\\';
    const char* PATH_SEP_STR = "\\";
#else
    const char PATH_SEP = '/';
    const char* PATH_SEP_STR = "/";
#endif
```

### Temporary Directory

```cpp
#ifdef _WIN32
    const char* temp = getenv("TEMP");
    if (!temp) temp = getenv("TMP");
#else
    const char* temp = getenv("TMPDIR");
    if (!temp) temp = "/tmp";
#endif
```

## Process Management

### fork() (Unix-only)

```cpp
// Unix-only - No equivalent on Windows
pid_t pid = fork();
if (pid == 0) {
    // Child process
}

// Cross-platform: Use portable process creation
#ifdef _WIN32
    // Use CreateProcess or _spawnl
    STARTUPINFO si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    CreateProcess(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
#else
    pid_t pid = fork();
    if (pid == 0) {
        execv(path, argv);
    }
#endif
```

### Signal Handling

```cpp
// Unix signals not available on Windows
#ifndef _WIN32
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, handler);
#endif
```

## Threading

### Thread-Local Storage

```cpp
// C11 standard (preferred)
_Thread_local int value;

// Or compiler-specific
#ifdef _WIN32
    __declspec(thread) int value;
#else
    __thread int value;
#endif
```

### Sleep Functions

```cpp
#ifdef _WIN32
    #include <windows.h>
    Sleep(1000);  // milliseconds
#else
    #include <unistd.h>
    sleep(1);     // seconds
    usleep(1000); // microseconds
#endif

// Cross-platform C++11
#include <chrono>
#include <thread>
std::this_thread::sleep_for(std::chrono::milliseconds(1000));
```

## Common Unix-Only Patterns to Avoid

| Unix Pattern | Windows Alternative | Notes |
|--------------|---------------------|-------|
| `MSG_DONTWAIT` | `ioctlsocket(FIONBIO)` | Non-blocking I/O |
| `fork()` | `CreateProcess()` | Process creation |
| `/dev/null` | `NUL` | Null device |
| `SIGPIPE` | N/A | Handle in code |
| `dlopen()` | `LoadLibrary()` | Dynamic loading |
| `pthread_*` | `CreateThread()` | Or use C++11 threads |
| `mmap()` | `CreateFileMapping()` | Memory mapping |
| `pipe()` | `CreatePipe()` | IPC pipes |

## Validation Commands

Before committing, check for Unix-only patterns:

```bash
# Search for common Unix-only APIs
grep -rn "MSG_DONTWAIT\|/dev/null\|fork()\|SIGPIPE" --include="*.cpp" --include="*.c" --include="*.h"

# Check for missing Windows guards
grep -rn "fork\|dlopen\|mmap" --include="*.cpp" | grep -v "_WIN32"
```

## CI Configuration

Ensure multi-platform CI testing:

```yaml
# GitHub Actions example
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
```

## Portable Libraries

Prefer portable libraries over platform-specific APIs:

| Category | Portable Library |
|----------|------------------|
| Networking | Boost.Asio, libuv |
| Threading | C++11 std::thread, pthreads-win32 |
| File System | C++17 std::filesystem, Boost.Filesystem |
| Process | Boost.Process |
| Dynamic Loading | C++20 modules, or wrapper libraries |

## Rust Cross-Platform

Rust handles most cross-platform concerns automatically:

```rust
// std::fs works on all platforms
use std::fs;
fs::write("/tmp/test.txt", "data")?;  // Path handled automatically

// For platform-specific code
#[cfg(windows)]
fn windows_only() { }

#[cfg(unix)]
fn unix_only() { }
```

## Go Cross-Platform

Go's standard library is mostly cross-platform:

```go
// os package handles platform differences
import "os"
tmpDir := os.TempDir()  // Returns appropriate temp directory

// For platform-specific code
// +build windows
// +build !windows
```

## Checklist Before Commit

- [ ] No Unix-only socket flags (MSG_DONTWAIT, MSG_NOSIGNAL)
- [ ] No hardcoded Unix paths (/dev/null, /tmp, /proc)
- [ ] No Unix-only process APIs (fork, exec without guards)
- [ ] No Unix-only signals (SIGPIPE, SIGHUP without guards)
- [ ] Platform-specific code wrapped in #ifdef blocks
- [ ] CI configured for multi-platform testing
