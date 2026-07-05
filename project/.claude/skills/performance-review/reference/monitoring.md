---
paths:
  - "**/scripts/**"
  - "Makefile"
  - "**/CMakeLists.txt"
  - "**/monitoring/**"
  - "**/metrics/**"
  - "**/observability/**"
  - "**/*.prometheus.*"
  - "**/*.grafana.*"
alwaysApply: false
---

# Operations: Cleanup & Monitoring

> Merged from: `cleanup.md` + `monitoring.md`

## Cleanup and Finalization

### Temporary File Removal

Common temporary files to clean up:
- Build artifacts (`*.o`, `*.obj`, `*.exe`, `build/`, `dist/`)
- Test outputs (`htmlcov/`, `.coverage`, `coverage.xml`)
- Editor files (`*~`, `*.swp`, `.DS_Store`)
- Cache files (`__pycache__/`, `node_modules/`)

### .gitignore Essentials

Keep build outputs and secrets out of version control:

```gitignore
# Build
build/ dist/ out/ target/ *.o *.obj *.exe

# Language-specific
__pycache__/ *.py[cod] node_modules/ *.class .gradle/

# IDE
.vscode/ .idea/ *.swp *~ .DS_Store

# Test coverage
htmlcov/ .coverage coverage.xml

# Secrets
.env .env.local secrets.json *.pem *.key
```

### Code Formatting & Linting

| Language | Formatter | Linter |
|----------|-----------|--------|
| C++ | `clang-format` | `clang-tidy` |
| Python | `black` + `isort` | `flake8` + `mypy` |
| TypeScript | `prettier` | `eslint` |
| Kotlin | `ktlint` | `ktlint` |

### Pre-Commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
```

### Documentation Deviations

When deviating from guidelines, document the reason:

```cpp
// DEVIATION: Using raw pointer because legacy C library requires it.
// TODO: Wrap in RAII class after migrating to library v2.0
```

---

## Performance Monitoring

### Common Metrics and Targets

| Metric | Description | Typical Target |
|--------|-------------|----------------|
| Response Time | Time to complete request | < 200ms (p95) |
| Throughput | Requests per second | > 1000 req/s |
| Memory Usage | RAM consumed | < 512MB (steady state) |
| CPU Utilization | CPU usage | < 70% (average) |
| Error Rate | Failed requests | < 0.1% |
| Uptime | Service availability | > 99.9% |

### Response Time Tracking (C++)

```cpp
class PerformanceMonitor {
    std::vector<std::chrono::microseconds> responseTimes_;
    std::mutex mutex_;

public:
    void recordResponseTime(std::chrono::microseconds duration) {
        std::lock_guard<std::mutex> lock(mutex_);
        responseTimes_.push_back(duration);
        if (responseTimes_.size() > 10000) {
            responseTimes_.erase(responseTimes_.begin());
        }
    }

    // Returns p50, p95, p99, average in milliseconds
    Statistics getStatistics() const;
};
```

### Memory Monitoring

```cpp
static MemoryUsage getCurrentUsage() {
#ifdef __linux__
    std::ifstream statm("/proc/self/statm");
    // ... read RSS and virtual memory size
#elif __APPLE__
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    // ... read ru_maxrss
#endif
}
```

### Integration with Monitoring Tools

**Prometheus (C++)**:
```cpp
#include <prometheus/exposer.h>
#include <prometheus/registry.h>

// Define metrics
auto& histogram = prometheus::BuildHistogram()
    .Name("http_request_duration_seconds")
    .Help("HTTP request latency")
    .Register(*registry);

// Expose on /metrics endpoint
prometheus::Exposer exposer{"127.0.0.1:9090"};
exposer.RegisterCollectable(registry);
```

### Alerting on Regressions

Check metrics against targets and alert when thresholds are exceeded:
- Response time p95 above target
- CPU utilization above threshold
- Memory usage above limit

Use tools: Prometheus + Alertmanager, Grafana, PagerDuty, or Slack integrations.
