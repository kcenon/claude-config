---
paths: ["**/CMakeLists.txt", "**/*.cmake"]
---

# CMake Guidelines

> **Purpose**: Prevent CMake target name conflicts and build system issues
> **Impact**: Eliminates build failures caused by duplicate or reserved target names

## Core Principle

Always use unique, project-prefixed target names to avoid conflicts with CMake reserved names, dependency targets, and targets in other subdirectories.

## Reserved Target Names

Never use these names as CMake targets - they are reserved by CMake or common conventions:

| Reserved Name | Reason | Alternative |
|---------------|--------|-------------|
| `test` | Reserved by CTest | `${PROJECT_NAME}_test` |
| `install` | Reserved by CMake | `${PROJECT_NAME}_install` |
| `clean` | Reserved by CMake | N/A (don't create) |
| `all` | Reserved by CMake | N/A (don't create) |
| `package` | Reserved by CPack | `${PROJECT_NAME}_package` |
| `rebuild_cache` | Reserved by CMake | N/A |
| `edit_cache` | Reserved by CMake | N/A |
| `uninstall` | Common convention | `${PROJECT_NAME}_uninstall` |

## Naming Conventions

### Library Targets

```cmake
# Use project name as prefix
add_library(${PROJECT_NAME}_core STATIC
    src/core.cpp
)

add_library(${PROJECT_NAME}_utils STATIC
    src/utils.cpp
)

# For header-only libraries
add_library(${PROJECT_NAME}_headers INTERFACE)
```

### Executable Targets

```cmake
# Main executable - can use project name directly
add_executable(${PROJECT_NAME}
    src/main.cpp
)

# Additional executables with descriptive suffixes
add_executable(${PROJECT_NAME}_cli
    src/cli_main.cpp
)

add_executable(${PROJECT_NAME}_server
    src/server_main.cpp
)
```

### Test Targets

```cmake
# Individual test executables
add_executable(${PROJECT_NAME}_test_unit
    tests/unit_tests.cpp
)

add_executable(${PROJECT_NAME}_test_integration
    tests/integration_tests.cpp
)

# Register with CTest
add_test(NAME ${PROJECT_NAME}_unit_tests
    COMMAND ${PROJECT_NAME}_test_unit
)
```

### Alias Targets

```cmake
# Create namespaced aliases for external consumption
add_library(MyProject::core ALIAS ${PROJECT_NAME}_core)
add_library(MyProject::utils ALIAS ${PROJECT_NAME}_utils)
```

## Pre-Creation Verification

Before adding a new target, verify it doesn't conflict:

### 1. Check Existing Targets

```bash
# List all targets in the build directory
cmake --build build --target help 2>/dev/null | grep -v "^\.\.\." | sort

# Or using CMake directly
cd build && cmake --graphviz=targets.dot .. && cat targets.dot
```

### 2. Search for Potential Conflicts

```bash
# Search for target definitions in all CMakeLists.txt
grep -rn "add_library\|add_executable" --include="CMakeLists.txt" .

# Check imported targets from dependencies
grep -rn "IMPORTED" --include="*.cmake" .
```

### 3. Verify Against Dependencies

```cmake
# In CMakeLists.txt, check if target exists before creating
if(NOT TARGET ${PROJECT_NAME}_mylib)
    add_library(${PROJECT_NAME}_mylib STATIC src/mylib.cpp)
endif()
```

## Common Conflict Scenarios

### Scenario 1: Duplicate Target in Subdirectory

```
CMake Error: add_library cannot create target "utils" because another
target with the same name already exists.
```

**Solution**: Use project-prefixed names

```cmake
# Bad
add_library(utils ...)  # Conflicts with parent/sibling directory

# Good
add_library(${PROJECT_NAME}_utils ...)
```

### Scenario 2: Conflict with Dependency Target

```
CMake Error: add_library cannot create target "core" because an imported
target with the same name already exists.
```

**Solution**: Check imported targets and use unique names

```cmake
# Check if target already exists (from find_package)
if(TARGET core)
    message(WARNING "Target 'core' already exists, using prefixed name")
endif()

add_library(${PROJECT_NAME}_core ...)
```

### Scenario 3: Reserved Name Collision

```
CMake Error: The target name "test" is reserved or not valid for certain
CMake features.
```

**Solution**: Never use reserved names

```cmake
# Bad
add_executable(test tests/main.cpp)

# Good
add_executable(${PROJECT_NAME}_tests tests/main.cpp)
```

## Debugging Commands

### List All Targets

```bash
# Using cmake --build
cmake --build build --target help

# Using make (if using Makefiles)
make -C build help

# Using ninja (if using Ninja)
ninja -C build -t targets all
```

### Visualize Target Dependencies

```bash
# Generate Graphviz dot file
cmake --graphviz=build/targets.dot -B build

# Convert to PNG (requires graphviz)
dot -Tpng build/targets.dot -o build/targets.png
```

### Find Target Definition

```bash
# Search for where a target is defined
grep -rn "add_library(mylib\|add_executable(mylib" --include="CMakeLists.txt" .

# Search in cmake modules
grep -rn "add_library(mylib\|IMPORTED" --include="*.cmake" /usr/share/cmake
```

## Best Practices

### Project Structure

```cmake
# Top-level CMakeLists.txt
cmake_minimum_required(VERSION 3.16)
project(MyProject VERSION 1.0.0)

# Set project-wide naming prefix
set(TARGET_PREFIX ${PROJECT_NAME})

# Add subdirectories
add_subdirectory(src)
add_subdirectory(tests)
```

### Subdirectory Pattern

```cmake
# src/CMakeLists.txt
add_library(${TARGET_PREFIX}_core
    core/core.cpp
    core/utils.cpp
)

target_include_directories(${TARGET_PREFIX}_core
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)
```

### Export Configuration

```cmake
# For install and package export
install(TARGETS ${PROJECT_NAME}_core ${PROJECT_NAME}_utils
    EXPORT ${PROJECT_NAME}Targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(EXPORT ${PROJECT_NAME}Targets
    FILE ${PROJECT_NAME}Targets.cmake
    NAMESPACE ${PROJECT_NAME}::
    DESTINATION lib/cmake/${PROJECT_NAME}
)
```

## Checklist Before Commit

- [ ] All targets use `${PROJECT_NAME}_` prefix
- [ ] No reserved names used (test, install, clean, all, package)
- [ ] Alias targets use namespace pattern (`MyProject::target`)
- [ ] Test targets registered with CTest using unique names
- [ ] No conflicts with imported dependency targets
- [ ] `cmake --build build --target help` shows no duplicates
