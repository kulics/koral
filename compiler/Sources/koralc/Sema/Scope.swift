public class Scope {
    private var symbols: [String: (Type, Bool)]  // (type, mutability)
    private let parent: Scope?
    
    public init(parent: Scope? = nil) {
        self.symbols = [:]
        self.parent = parent
    }
    
    public func define(_ name: String, _ type: Type, mutable: Bool = false) {
        symbols[name] = (type, mutable)
    }
    
    public func lookup(_ name: String) -> Type? {
        if let (type, _) = symbols[name] {
            return type
        }
        return parent?.lookup(name)
    }
    
    public func isMutable(_ name: String) -> Bool {
        if let (_, mutable) = symbols[name] {
            return mutable
        }
        return parent?.isMutable(name) ?? false
    }
    
    public func createChild() -> Scope {
        return Scope(parent: self)
    }
}