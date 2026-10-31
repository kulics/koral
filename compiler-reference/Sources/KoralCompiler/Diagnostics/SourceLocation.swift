// SourceLocation.swift
// Represents a precise location in source code.

/// A precise location in source code, containing line and column numbers.
/// Both line and column are 1-based (first line is 1, first column is 1).
public struct SourceLocation: Equatable, Hashable, Sendable {
    /// The line number (1-based)
    public let line: Int
    
    /// The column number (1-based)
    public let column: Int

    /// The file this location points INTO. Rides along from lexing so a span
    /// always knows its own file -- the checker's ambient file names the file
    /// being processed, which is not where a deferred or instantiated check's
    /// span lives. `nil` for synthesized locations (fall back to ambient).
    public let fileName: String?
    
    /// Creates a new source location.
    /// - Parameters:
    ///   - line: The line number (1-based)
    ///   - column: The column number (1-based)
    ///   - fileName: the file the location points into
    public init(line: Int, column: Int, fileName: String? = nil) {
        self.line = line
        self.column = column
        self.fileName = fileName
    }

    /// Equality and hashing are position-only: the file rides along for
    /// attribution and must not change span identity (dedup and comparison
    /// traffic treats the same position as the same span).
    public static func == (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        lhs.line == rhs.line && lhs.column == rhs.column
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(line)
        hasher.combine(column)
    }
    
    /// A sentinel value representing an unknown location.
    /// Used when location information is not available.
    public static let unknown = SourceLocation(line: 0, column: 0)
    
    /// Whether this location is known (not the unknown sentinel).
    public var isKnown: Bool {
        line > 0 && column > 0
    }
}

extension SourceLocation: CustomStringConvertible {
    public var description: String {
        if isKnown {
            return "\(line):\(column)"
        }
        return "<unknown>"
    }
}

extension SourceLocation: Comparable {
    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }
}
