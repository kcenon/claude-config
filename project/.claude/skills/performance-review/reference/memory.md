---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.c", "**/*.rs", "**/*.java", "**/*.kt", "**/*.go", "**/*.py"]
alwaysApply: false
---

# Memory & Concurrency Safety

> Merged from: `memory.md` + `concurrency.md`

## Memory Management

### Smart Pointers (C++)

Always prefer smart pointers over raw pointers for ownership:

```cpp
// Unique ownership
std::unique_ptr<Resource> resource = std::make_unique<Resource>();

// Shared ownership
std::shared_ptr<Resource> shared = std::make_shared<Resource>();

// Weak reference (doesn't prevent deletion)
std::weak_ptr<Resource> weak = shared;
```

### RAII Prevents Leaks

```cpp
// Bad: Early returns or exceptions leak memory
void processData() {
    Resource* res = new Resource();
    if (someCondition) return;  // LEAK!
    delete res;
}

// Good: RAII handles cleanup automatically
void processData() {
    auto res = std::make_unique<Resource>();
    if (someCondition) return;  // OK! unique_ptr cleans up
}
```

### Ownership Semantics

Make ownership explicit:

```cpp
class ResourceOwner {
    std::unique_ptr<Resource> ownedResource_;

public:
    // Transfer ownership to caller
    std::unique_ptr<Resource> releaseResource() {
        return std::move(ownedResource_);
    }

    // Borrow resource (no ownership transfer)
    Resource* borrowResource() {
        return ownedResource_.get();
    }
};
```

### Lifetime Guidelines

1. Prefer stack allocation over heap when possible
2. Use smart pointers instead of raw pointers for ownership
3. Document lifetime in comments when non-obvious
4. Avoid dangling references by ensuring objects outlive references

### Memory Safety Tools

```bash
# Address Sanitizer (leaks, use-after-free, buffer overflows)
g++ -fsanitize=address -g program.cpp

# Memory Sanitizer (uninitialized reads)
clang++ -fsanitize=memory -g program.cpp

# Valgrind (comprehensive)
valgrind --leak-check=full --track-origins=yes ./program
```

---

## Concurrency

### Avoiding Data Races

Data races occur when multiple threads access the same memory, at least one writes, and there's no synchronization.

**Mutexes (C++)**:
```cpp
class ThreadSafeCounter {
    mutable std::mutex mutex_;
    int count_ = 0;

public:
    void increment() {
        std::lock_guard<std::mutex> lock(mutex_);
        ++count_;
    }

    int get() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return count_;
    }
};
```

**Atomic Operations (C++)**:
```cpp
class ThreadSafeCounter {
    std::atomic<int> count_{0};

public:
    void increment() { count_.fetch_add(1, std::memory_order_relaxed); }
    int get() const { return count_.load(std::memory_order_relaxed); }
};
```

### Choosing Concurrency Model

| Model | Use When | Languages |
|-------|----------|-----------|
| **Threading** | CPU-bound parallel work, shared memory | C++, Java, Kotlin |
| **Coroutines** | I/O-bound, lightweight concurrency | Kotlin, Python |
| **Async/Await** | I/O-bound, responsive UIs | TypeScript, Python |
| **Process-based** | True CPU parallelism, isolation | Python (GIL bypass) |

### Common Patterns

**Producer-Consumer (C++)**:
```cpp
template<typename T>
class ThreadSafeQueue {
    std::queue<T> queue_;
    mutable std::mutex mutex_;
    std::condition_variable cond_;

public:
    void push(T value) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            queue_.push(std::move(value));
        }
        cond_.notify_one();
    }

    T pop() {
        std::unique_lock<std::mutex> lock(mutex_);
        cond_.wait(lock, [this] { return !queue_.empty(); });
        T value = std::move(queue_.front());
        queue_.pop();
        return value;
    }
};
```

**Read-Write Lock (C++)**:
```cpp
class SharedResource {
    mutable std::shared_mutex mutex_;
    std::string data_;

public:
    std::string read() const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        return data_;
    }

    void write(std::string newData) {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        data_ = std::move(newData);
    }
};
```

### Deadlock Prevention

1. **Lock Ordering**: Always acquire locks in the same order
2. **Timeout**: Use timed locks and retry on timeout
3. **Try-Lock**: Use non-blocking lock attempts
4. **Lock Hierarchy**: Assign levels and only acquire higher levels

### Testing Concurrent Code

- **Stress testing**: Run many threads doing concurrent operations, verify final state
- **ThreadSanitizer**: `g++ -fsanitize=thread` detects race conditions at runtime
- **Deterministic testing**: Use controlled scheduling where possible
