// SourceSpan.swift
// Represents a range in source code from start to end location.

/// A range in source code, defined by start and end locations.
/// Used to mark the extent of tokens, expressions, and error locations.
public struct SourceSpan: Equatable, Hashable, Sendable {
    /// The starting location of the span (inclusive)
    public let start: SourceLocation
    
    /// The ending location of the span (inclusive)
    public let end: SourceLocation
    
    /// Creates a new source span from start to end locations.
    /// - Parameters:
    ///   - start: The starting location
    ///   - end: The ending location
    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
    
    /// Creates a single-point span at the given location.
    /// - Parameter location: The location for both start and end
    public init(location: SourceLocation) {
        self.start = location
        self.end = location
    }
    
    /// Creates a span from line and column values.
    /// - Parameters:
    ///   - startLine: Starting line number (1-based)
    ///   - startColumn: Starting column number (1-based)
    ///   - endLine: Ending line number (1-based)
    ///   - endColumn: Ending column number (1-based)
    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.start = SourceLocation(line: startLine, column: startColumn)
        self.end = SourceLocation(line: endLine, column: endColumn)
    }
    
    /// A sentinel value representing an unknown span.
    /// Used when location information is not available.
    public static let unknown = SourceSpan(
        start: .unknown,
        end: .unknown
    )
    
    /// Whether this span has known location information.
    public var isKnown: Bool {
        start.isKnown && end.isKnown
    }
    
    /// The line number of the start location (for convenience).
    public var line: Int {
        start.line
    }
    
    /// The column number of the start location (for convenience).
    public var column: Int {
        start.column
    }
    
    /// Merges this span with another to create a span covering both.
    /// - Parameter other: The other span to merge with
    /// - Returns: A new span that covers both input spans
    public func merged(with other: SourceSpan) -> SourceSpan {
        let newStart = start < other.start ? start : other.start
        let newEnd = end > other.end ? end : other.end
        return SourceSpan(start: newStart, end: newEnd)
    }
    
    /// Creates a span that extends from this span's start to the given end location.
    /// - Parameter endLocation: The new end location
    /// - Returns: A new span with the same start but different end
    public func extended(to endLocation: SourceLocation) -> SourceSpan {
        return SourceSpan(start: start, end: endLocation)
    }
    
    /// Creates a span that extends from this span's start to the end of another span.
    /// - Parameter other: The span whose end location to use
    /// - Returns: A new span from this start to other's end
    public func extended(to other: SourceSpan) -> SourceSpan {
        return SourceSpan(start: start, end: other.end)
    }
}

extension SourceSpan: CustomStringConvertible {
    public var description: String {
        if !isKnown {
            return "<unknown>"
        }
        if start == end {
            return "\(start)"
        }
        if start.line == end.line {
            return "\(start.line):\(start.column)-\(end.column)"
        }
        return "\(start)-\(end)"
    }
}
