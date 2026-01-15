---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.c"
  - "**/*.h"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.kt"
  - "**/*.java"
---

# Coding Standards

## Naming Conventions

- Use descriptive, meaningful names that reveal intent
- Variables: camelCase (JS/TS), snake_case (Python/Rust), PascalCase (Go exported)
- Functions: camelCase (JS/TS), snake_case (Python/Rust/C++), PascalCase (Go exported)
- Classes/Types: PascalCase (all languages)
- Constants: SCREAMING_SNAKE_CASE
- Private members: prefix with underscore (_) where appropriate

## Code Structure

- Keep functions small and focused (single responsibility)
- Maximum function length: ~50 lines (guideline, not strict rule)
- Maximum file length: ~500 lines (consider splitting if larger)
- Group related functionality together
- Order: imports, constants, types, main logic, helpers

## Comments

- Write self-documenting code first
- Add comments for "why", not "what"
- Document public APIs with clear descriptions
- Use TODO/FIXME with context and owner

## Error Handling

- Handle errors explicitly, never silently ignore
- Use language-appropriate error patterns
- Provide context in error messages
- Log errors with sufficient information for debugging

## Immutability

- Prefer immutable data structures
- Use const/final/readonly where possible
- Avoid mutating function parameters
- Return new objects instead of modifying existing ones
