---
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.test.js"
  - "**/*.spec.ts"
  - "**/*.spec.js"
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/*_test.go"
  - "**/tests/**"
  - "**/test/**"
  - "**/__tests__/**"
---

# Testing Standards

## Test Structure

- Arrange-Act-Assert (AAA) pattern
- One assertion per test (when practical)
- Descriptive test names that explain the scenario
- Group related tests with describe/context blocks

## Test Naming

- Format: `should_expectedBehavior_when_condition`
- Or: `test_functionName_scenario_expectedResult`
- Be specific about what is being tested

## Test Coverage

- Aim for meaningful coverage, not 100%
- Cover critical paths and edge cases
- Test error handling scenarios
- Include boundary conditions

## Mocking

- Mock external dependencies only
- Use dependency injection for testability
- Avoid mocking implementation details
- Reset mocks between tests

## Test Data

- Use factories or builders for test data
- Avoid hardcoded magic values
- Keep test data close to tests
- Use meaningful, realistic values

## Test Independence

- Tests should not depend on each other
- Each test should set up its own state
- Clean up after tests when needed
- Avoid shared mutable state
