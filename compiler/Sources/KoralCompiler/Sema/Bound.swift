// Bound.swift
// A generic parameter's bound, expressed as a semantic kind rather than raw
// type syntax.
//
// Bounds used to be stored as `TypeNode`, which forced every consumer to
// recover meaning by string-matching the bound's name (`== "Any"`,
// `== "mutable"`, ...). Making the kind explicit is what lets those special
// cases disappear.
//
// The source spellings `Any` and `mutable` are read by name exactly once, in
// `boundFromTypeNode` below -- the syntax writes `mutable` as a keyword and `Any`
// as the vacuous constraint (a type parameter must have a constraint, and `Any`
// is how "no constraint" is spelled). Everywhere after that boundary sees only
// the kind.

/// Represents a generic parameter's bound as an algebraic kind.
///
/// - `.trait`: a real trait bound, e.g. `T Hash` or `T Add[Int]`.
/// - `.mutable`: `T mutable` -- the subject must have been declared
///   `type mutable`. A shape requirement on the type itself, so it is not a
///   trait.
///
/// `defId` is the DECLARATION identity of the required trait and is what every
/// comparison must use. `name` exists only so diagnostics can print it; it is
/// `.invalid` until sema resolves the spelling to a declaration. Comparing
/// names instead of identities is what let two same-named traits from different
/// modules collapse into one.
///
/// `args` is the written type-argument list. An empty list is not a distinct
/// shape: `Foo` and `Foo[]` are the same bound.
public enum Bound: CustomStringConvertible {
    case trait(defId: DefId, name: String, args: [TypeNode])
    case mutable

    /// The declaration identity of the required trait, or nil for shape bounds
    /// (which have no declaration).
    public var defId: DefId? {
        switch self {
        case .trait(let defId, _, _): return defId
        case .mutable: return nil
        }
    }

    /// The bare trait name (e.g. "Iterator" for `[T]Iterator`).
    /// `mutable` renders as `"mutable"` so legacy trait-ref lookups that only
    /// need a name keep working; generic-bound consumers should dispatch on the
    /// kind instead of matching this string.
    public var baseName: String {
        switch self {
        case .trait(_, let name, _): return name
        case .mutable: return "mutable"
        }
    }

    /// The trait this bound requires, if it is a trait bound. `mutable` requires
    /// no trait declaration and returns nil.
    public var traitName: String? {
        switch self {
        case .trait(_, let name, _): return name
        case .mutable: return nil
        }
    }

    /// The trait arguments of a trait bound (`T Add[Int]` -> `[Int]`), empty for
    /// shape bounds.
    public var traitArgs: [TypeNode] {
        switch self {
        case .trait(_, _, let args): return args
        case .mutable: return []
        }
    }

    /// A copy of this bound with the trait's declaration identity filled in.
    /// Sema resolves the spelling once, at the boundary where names become
    /// declarations; every later comparison uses the identity.
    public func resolved(to defId: DefId) -> Bound {
        switch self {
        case .trait(_, let name, let args): return .trait(defId: defId, name: name, args: args)
        case .mutable: return .mutable
        }
    }

    /// The one place allowed to turn a bound back into text. Must reproduce the
    /// diagnostics exactly: bare names for simple traits, a PREFIXED bracket for
    /// parameterised ones (`[Int]Iterator`, not `Iterator[Int]`), and the
    /// keyword spelling for the type kind.
    public var description: String {
        switch self {
        case .trait(_, let name, let args):
            if args.isEmpty {
                return name
            }
            let argsStr = args.map { $0.description }.joined(separator: ", ")
            return "[\(argsStr)]\(name)"
        case .mutable:
            return "mutable"
        }
    }
}

// MARK: - Free functions (mirroring the bootstrap helper surface)

/// Recognise a bound from its source spelling. `Any` produces no bound at all --
/// it is the vacuous constraint (a type parameter must have a constraint, and
/// `Any` is how "no constraint" is spelled).
///
/// Returns nil for `Any` (and `Any[...]`). Throws for shapes that cannot be
/// bounds (references, pointers, ...), preserving the historical
/// `invalid trait bound` error.
///
/// This is the ONLY place allowed to recognise the `Any` / `mutable` spellings
/// as bound kinds.
public func boundFromTypeNode(_ node: TypeNode) throws -> Bound? {
    switch node {
    case .identifier(let name, _):
        if name == "Any" {
            return nil
        } else if name == "mutable" {
            return .mutable
        } else {
            return .trait(defId: .invalid, name: name, args: [])
        }
    case .generic(let base, let args, _):
        if base == "Any" {
            return nil
        }
        return .trait(defId: .invalid, name: base, args: args)
    default:
        throw SemanticError.invalidOperation(
            op: "invalid trait bound",
            type1: String(describing: node),
            type2: ""
        )
    }
}

/// The trait this bound requires, if it is a trait bound. `mutable` requires no
/// trait declaration and returns nil.
public func boundTraitName(_ b: Bound) -> String? {
    return b.traitName
}

/// The trait arguments of a trait bound (`T Add[Int]` -> `[Int]`), empty for
/// shape bounds.
public func boundTraitArgs(_ b: Bound) -> [TypeNode] {
    return b.traitArgs
}

/// The bare trait name, for messages that print it without type arguments.
public func boundBaseName(_ b: Bound) -> String {
    return b.baseName
}

/// Render a bound for diagnostics. Mirrors `Bound.description`.
public func boundDisplay(_ b: Bound) -> String {
    return b.description
}

// MARK: - Legacy alias
//
// `TraitConstraint` was the historical name for a bound before it gained the
// explicit `mutable` kind. Kept as a thin alias so trait-reference code
// (supertraits, canonical trait refs, casts) continues to compile unchanged.
public typealias TraitConstraint = Bound
