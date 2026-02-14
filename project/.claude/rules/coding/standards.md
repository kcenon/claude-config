---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.py", "**/*.js", "**/*.ts", "**/*.tsx", "**/*.jsx", "**/*.java", "**/*.kt", "**/*.go", "**/*.rs", "**/*.c"]
---

# Coding Standards

> Merged from: `general.md` + `quality.md`
> For language-specific conventions, refer to official style guides (C++ Core Guidelines, PEP 8, etc.)

## Naming Conventions

### Descriptive Names

- **Classes**: Nouns describing the entity (`UserAccount`, `DatabaseConnection`)
- **Functions**: Verbs describing the action (`calculateTotal`, `fetchUserData`)
- **Variables**: Meaningful names indicating purpose (`connectionTimeout`, `userEmail`)
- **Constants**: Names explaining the value's purpose (`MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT_MS`)

### Consistent Casing

- **C++**: `snake_case` for variables/functions, `PascalCase` for classes
- **Kotlin/Java**: `camelCase` for variables/functions, `PascalCase` for classes
- **Python**: `snake_case` for variables/functions, `PascalCase` for classes
- **TypeScript**: `camelCase` for variables/functions, `PascalCase` for classes/interfaces

## File Organization

Organize file contents in this order:

1. **Dependencies/Imports**: External and internal dependencies
2. **Constants/Type Definitions**: Global constants, type aliases, enums
3. **Main Implementation**: Primary classes, functions, or logic
4. **Auxiliary Code**: Helper functions, utilities, internal support code

## Single Responsibility

- **One purpose per unit**: Each class or function should have one well-defined responsibility
- **Naming test**: If you struggle to name a function without using "and", it might do too much
- **Length guideline**: Functions should typically be 20-50 lines; longer functions often need splitting
- **Split large features**: Break complex functionality into smaller, focused components

## Complexity Management

### Reduce Nesting

```cpp
// Bad: Deep nesting
if (user.isAuthenticated()) {
    if (user.hasPermission()) {
        if (data.isValid()) {
            // Process...
        }
    }
}

// Good: Early returns
if (!user.isAuthenticated()) return;
if (!user.hasPermission()) return;
if (!data.isValid()) return;
// Process...
```

### Extract Helper Functions

```cpp
bool canProcessRequest(const User& user, const Data& data) {
    return user.isAuthenticated()
        && user.hasPermission()
        && data.isValid();
}
```

## Avoid Magic Numbers

```cpp
// Bad
if (retryCount > 3) return;
sleep(5000);

// Good
const int MAX_RETRY_COUNT = 3;
const int RETRY_DELAY_MS = 5000;
if (retryCount > MAX_RETRY_COUNT) return;
sleep(RETRY_DELAY_MS);
```

## Error Logging

Include sufficient context when catching exceptions:

```cpp
catch (const Exception& e) {
    log("Failed to process user request",
        "user_id", user.id,
        "request_type", req.type,
        "error", e.what(),
        "retry_count", retryCount);
}
```

## Prefer Immutability

Use immutable data where practical to minimize side effects:

- **C++**: `const auto result = processData(input);`
- **Kotlin**: `val result = processData(input)` (val over var)
- **Python**: `RESULT: Final = process_data(input)`

## Comments and Documentation

### Public API Documentation

Document all public classes and functions with:
- **Purpose**: What the code does
- **Parameters**: What inputs it expects
- **Return value**: What it returns
- **Exceptions**: What errors it might throw

### Comment Guidelines

- **Explain why, not what**: Code should be self-explanatory; comments explain reasoning
- **Keep updated**: Update comments when code changes
- **Avoid obvious comments**: Don't comment what's already clear from code

## Code Style

- **Readability first**: Optimize for humans reading the code
- **Consistency**: Follow the project's established patterns
- **Formatting**: Use language-appropriate formatters (`clang-format`, `black`, `prettier`)
