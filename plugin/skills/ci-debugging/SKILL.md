---
name: ci-debugging
description: Provides systematic CI/CD failure diagnosis and resolution. Use when CI builds fail, GitHub Actions errors occur, TLS/auth issues block pipelines, or platform-specific failures need debugging.
allowed-tools: Bash, Read, Grep, Glob, WebFetch
---

# CI/CD Debugging Skill

## When to Use

- CI build failures
- GitHub Actions workflow errors
- TLS certificate or authentication issues
- Platform-specific compilation failures
- Dependency resolution problems

## Diagnostic Flow

### Step 1: Categorize Failure Type

Determine which category the failure falls into:

| Category | Indicators | Priority |
|----------|------------|----------|
| **Environment/Auth** | TLS errors, token expired, permission denied | Check first |
| **Platform-Specific** | Works on Linux fails on Windows, vice versa | Check second |
| **Missing Dependencies** | Module not found, package missing | Check third |
| **Actual Code Bug** | Test assertions, logic errors | Check last |

### Step 2: Environment/Auth Issues

Check for sandboxed environment limitations:

```bash
# Test GitHub API connectivity
curl -s --connect-timeout 5 https://api.github.com/zen

# Check GitHub CLI auth status
gh auth status

# Verify GITHUB_TOKEN
echo "Token present: ${GITHUB_TOKEN:+yes}"
```

**Common Issues:**
- TLS certificate errors -> Try diagnosis with connectivity check first
- Token expired -> Re-authenticate with `gh auth login`
- Sandbox blocked -> Use local git operations as fallback

### Step 3: Platform-Specific Issues

Look for platform-specific patterns:

```bash
# Search for Unix-specific code
grep -rn "MSG_DONTWAIT\|/dev/null\|fork()" src/

# Check for Windows path issues
grep -rn '"/tmp\|"/var' src/
```

**Fallback**: Add conditional compilation or use cross-platform alternatives.

### Step 4: Dependency Issues

```bash
# Check for missing packages (Node.js)
npm ls 2>&1 | grep "MISSING" || echo "No missing npm packages"

# For Python
pip check 2>&1 || echo "No pip issues"

# For CMake/C++
cmake --build build/ 2>&1 | grep -i "error\|not found" || echo "Build OK"
```

### Step 5: Code Bug Analysis

If none of the above:
1. Read the failing test output carefully
2. Identify the assertion that failed
3. Trace back to the implementation
4. Fix the actual bug

## Fallback Strategies

### GitHub API Blocked

```
Priority order:
1. Use gh CLI (preferred)
2. Direct curl with GITHUB_TOKEN
3. Local git operations only
4. Manual intervention required
```

### TLS/Certificate Issues

```
Priority order:
1. Check system certificates
2. Verify proxy settings
3. Use alternative connectivity check
4. Report as environment issue
```

## Quick Commands

| Issue | Command |
|-------|---------|
| Check CI logs | `gh run view --log-failed` |
| Re-run failed | `gh run rerun --failed` |
| View workflow | `gh run view` |
| Check auth | `gh auth status` |
| List failed runs | `gh run list --status failure` |

## Reference Documents (Import Syntax)
@./reference/common-failures.md
