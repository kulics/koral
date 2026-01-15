// SemanticErrorContext.swift
// Centralized source context for semantic diagnostics.

public enum SemanticErrorContext {
  // These are intentionally global state: the compiler is currently single-threaded.
  public nonisolated(unsafe) static var currentFileName: String = "<input>"
  public nonisolated(unsafe) static var currentLine: Int = 1
}
