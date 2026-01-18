// SourceLocation.swift
// Represents a precise location in source code.

/// A precise location in source code, containing line and column numbers.
/// Both line and column are 1-based (first line is 1, first column is 1).
public struct SourceLocation: Equatable, Hashable, Sendable {
    /// The line number (1-based)
    public let line: Int
    
    /// The column number (1-based)
    public let column: Int
    
    /// Creates a new source location.
    /// - Parameters:
    ///   - line: The line number (1-based)
    ///   - column: The column number (1-based)
    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
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
