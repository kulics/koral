// MARK: - Temporary Variable Pool for Stack Slot Reuse
//
// Implements JVM-style typed temporary variable pooling for match/if-else expressions.
// In mutually exclusive branches (match cases, if/else), temporary variables of the
// same C type can be reused across branches, dramatically reducing stack frame size.
//
// This is especially important because Koral compiles to C, and C compilers at -O0
// do not perform stack slot coloring. Without pooling, a match with 30 branches
// each using 2 temporaries would allocate 60 stack slots; with pooling, only 2.

/// Typed temporary variable pool for reusing stack slots across mutually exclusive branches.
struct TempPool {
  /// Available (released) variable names, keyed by C type string.
  var available: [String: [String]] = [:]

  /// All variables declared by this pool, for emitting declarations at the pool's scope.
  var declared: [(cType: String, name: String)] = []

  /// Monotonic counter for generating unique pool variable names.
  var counter: Int = 0

  /// Unique prefix for this pool instance (avoids collisions with nested pools).
  let prefix: String

  init(prefix: String) {
    self.prefix = prefix
  }

  /// Acquire a temporary variable of the given C type.
  /// Reuses a previously released variable if available, otherwise creates a new one.
  mutating func acquire(cType: String) -> String {
    if var list = available[cType], !list.isEmpty {
      let name = list.removeLast()
      available[cType] = list
      return name
    }
    counter += 1
    let name = "_pool\(prefix)_\(counter)"
    declared.append((cType: cType, name: name))
    return name
  }

  /// Release a temporary variable back to the pool for reuse.
  mutating func release(name: String, cType: String) {
    available[cType, default: []].append(name)
  }

  /// Release all variables of a given set back to the pool.
  /// Used at the end of a branch to return all branch-local temps.
  mutating func releaseAll(_ vars: [(name: String, cType: String)]) {
    for (name, cType) in vars {
      release(name: name, cType: cType)
    }
  }
}
