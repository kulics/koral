// MARK: - Memory Management and Scope Cleanup Extension

// This file documents the memory management and scope cleanup methods in CodeGen.
// The actual implementations are in CodeGen.swift as they are tightly coupled
// with the core code generation state.

// Memory Management Methods (in CodeGen.swift):
// - pushScope(): Creates a new lifetime scope for tracking variables
// - popScope(): Ends a scope and generates cleanup code for all variables in that scope
// - popScopeWithoutCleanup(): Ends a scope without generating cleanup code
// - emitCleanup(fromScopeIndex:): Generates cleanup code for all scopes from the given index
// - emitCleanupForScope(at:): Generates cleanup code for a specific scope
// - registerVariable(_:_:): Registers a variable in the current scope for lifetime tracking

// The memory management system handles:
// - Struct types: Calls __koral_<TypeName>_drop for cleanup
// - Union types: Calls __koral_<TypeName>_drop for cleanup
// - Reference types: Calls __koral_release for reference counting

// Scope Stack:
// - lifetimeScopeStack: Stack of scopes, each containing (name, type) pairs
// - Each scope tracks variables that need cleanup when the scope ends

// Loop Context:
// - loopStack: Stack of loop contexts for break/continue handling
// - Each context contains startLabel, endLabel, and scopeIndex for proper cleanup
