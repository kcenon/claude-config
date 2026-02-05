# Common CI Failure Patterns

## Environment Failures

### TLS Certificate Errors

**Symptoms:**
```
tls: failed to verify certificate: x509: certificate signed by unknown authority
Post "https://api.github.com/graphql": x509: OSStatus -26276
```

**Causes:**
- Sandboxed environment without proper certificates
- Proxy intercepting HTTPS
- Outdated CA certificates

**Solutions:**
1. Check if running in sandbox environment
2. Update CA certificates: `update-ca-certificates`
3. Verify proxy settings: `echo $https_proxy`
4. Fallback to local operations when GitHub API is blocked

### GitHub Token Issues

**Symptoms:**
```
gh: authentication required
error: The requested URL returned error: 403
```

**Solutions:**
1. `gh auth status` - Check current auth
2. `gh auth refresh` - Refresh token
3. `gh auth login` - Re-authenticate

### Permission Denied

**Symptoms:**
```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
remote: Permission to org/repo.git denied to user.
```

**Solutions:**
1. Verify repository access permissions
2. Check SSH key configuration: `ssh -T git@github.com`
3. Use HTTPS with token: `git remote set-url origin https://TOKEN@github.com/org/repo.git`

## Platform-Specific Failures

### Windows Socket Errors

**Pattern:** `MSG_DONTWAIT` not available on Windows

**Solution:**
```cpp
#ifdef _WIN32
    u_long mode = 1;
    ioctlsocket(socket, FIONBIO, &mode);
#else
    fcntl(socket, F_SETFL, O_NONBLOCK);
#endif
```

### Path Separator Issues

**Pattern:** `/tmp/file` not found on Windows

**Solution:**
```python
import tempfile
temp_dir = tempfile.gettempdir()  # Cross-platform
```

```cpp
#include <filesystem>
auto temp = std::filesystem::temp_directory_path();  // Cross-platform
```

### Line Ending Issues

**Pattern:** `\r\n` vs `\n` causing test failures

**Solution:**
```bash
# Configure git to handle line endings
git config core.autocrlf input  # On Linux/macOS
git config core.autocrlf true   # On Windows
```

## Dependency Failures

### Node.js

```bash
# Clear cache and reinstall
rm -rf node_modules package-lock.json
npm install
```

### Python

```bash
# Reinstall in fresh venv
python -m venv .venv --clear
source .venv/bin/activate
pip install -r requirements.txt
```

### CMake/C++

```bash
# Clean rebuild
rm -rf build/
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build/
```

### Java/Gradle

```bash
# Check JAVA_HOME
echo $JAVA_HOME
# Clear Gradle cache
./gradlew clean --refresh-dependencies
```

## GitHub Actions Specific

### Runner Environment Issues

**Symptoms:**
```
Error: Process completed with exit code 1.
##[error]The operation was canceled.
```

**Diagnostic Steps:**
1. Check runner OS: `runs-on` in workflow YAML
2. Verify available tools: `which cmake`, `node --version`
3. Check disk space: `df -h`
4. Review timeout settings

### Cache Issues

**Symptoms:** Build succeeds locally but fails in CI after cache restore

**Solutions:**
1. Clear GitHub Actions cache
2. Verify cache key includes dependency lock file hash
3. Check cache size limits (10 GB per repository)

### Secret/Environment Variable Issues

**Symptoms:** API calls fail only in CI

**Solutions:**
1. Verify secrets are set in repository settings
2. Check secret name matches workflow reference
3. Ensure secrets are available for the trigger event (fork PRs have limited access)
