import Foundation

private struct StableTypeHasher {
  private(set) var state: UInt64 = 0xcbf29ce484222325

  mutating func combine(_ value: UInt64) {
    state ^= value &+ 0x9e3779b97f4a7c15
    state &*= 0x100000001b3
  }

  mutating func combine(_ value: Int) {
    combine(UInt64(bitPattern: Int64(value)))
  }

  mutating func combine(_ value: Bool) {
    combine(value ? 1 : 0)
  }

  mutating func combine(_ value: String) {
    combine(UInt64(value.utf8.count))
    for byte in value.utf8 {
      combine(UInt64(byte))
    }
    combine(0xff)
  }
}

// MARK: - Type Declaration Entities

/// Struct 类型的声明实体
/// 仅保留 DefId 与结构体成员信息，其余元数据由 DefIdMap 提供
public struct StructDecl: Equatable, Hashable {
  /// 定义标识符
  public let defId: DefId
    
  /// 字段列表（可变，用于解析递归类型）
  public var members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)]
    
  /// 是否为泛型实例化
  public var isGenericInstantiation: Bool
    
  /// 泛型类型参数
  public var typeArguments: [Type]?
    
  public init(
    defId: DefId,
    members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)] = [],
    isGenericInstantiation: Bool = false,
    typeArguments: [Type]? = nil
  ) {
    self.defId = defId
    self.members = members
    self.isGenericInstantiation = isGenericInstantiation
    self.typeArguments = typeArguments
  }
    
  // 类型相等性基于 DefId
  public static func == (lhs: StructDecl, rhs: StructDecl) -> Bool {
    return lhs.defId == rhs.defId
  }
    
  public func hash(into hasher: inout Hasher) {
    hasher.combine(defId)
  }
    
  // MARK: - DefIdMap Accessors
    
  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }
    
  public func modulePath(in map: DefIdMap) -> [String]? {
    return map.getModulePath(defId)
  }
    
  public func sourceFile(in map: DefIdMap) -> String? {
    return map.getSourceFile(defId)
  }
    
  public func access(in map: DefIdMap) -> AccessModifier? {
    return map.getAccess(defId)
  }
}

/// Enum 类型的声明实体
/// 仅保留 DefId 与 enum case 信息，其余元数据由 DefIdMap 提供
public struct EnumDecl: Equatable, Hashable {
  /// 定义标识符
  public let defId: DefId
    
  /// Enum cases（可变，用于解析递归类型）
  public var cases: [EnumCase]
    
  /// 是否为泛型实例化
  public var isGenericInstantiation: Bool
    
  /// 泛型类型参数
  public var typeArguments: [Type]?
    
  public init(
    defId: DefId,
    cases: [EnumCase] = [],
    isGenericInstantiation: Bool = false,
    typeArguments: [Type]? = nil
  ) {
    self.defId = defId
    self.cases = cases
    self.isGenericInstantiation = isGenericInstantiation
    self.typeArguments = typeArguments
  }
    
  // 类型相等性基于 DefId
  public static func == (lhs: EnumDecl, rhs: EnumDecl) -> Bool {
    return lhs.defId == rhs.defId
  }
    
  public func hash(into hasher: inout Hasher) {
    hasher.combine(defId)
  }
    
  // MARK: - DefIdMap Accessors
    
  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }
    
  public func modulePath(in map: DefIdMap) -> [String]? {
    return map.getModulePath(defId)
  }
    
  public func sourceFile(in map: DefIdMap) -> String? {
    return map.getSourceFile(defId)
  }
    
  public func access(in map: DefIdMap) -> AccessModifier? {
    return map.getAccess(defId)
  }
}

// MARK: - Enum Case

public struct EnumCase {
  public let name: String
  public let parameters: [(name: String, type: Type, access: AccessModifier, named: Bool)]
  
  public init(name: String, parameters: [(name: String, type: Type, access: AccessModifier, named: Bool)]) {
    self.name = name
    self.parameters = parameters
  }
}

// MARK: - Type Enum

public indirect enum Type: CustomStringConvertible {
  case int
  case int8
  case int16
  case int32
  case int64
  case uint
  case uint8
  case uint16
  case uint32
  case uint64
  case float32
  case float64
  case bool
  case void
  case never
  case function(parameters: [Parameter], returns: Type)
  case structure(defId: DefId)
  case reference(inner: Type)
  case mutableReference(inner: Type)
  case borrowedReference(inner: Type, lifetime: String)
  case mutableBorrowedReference(inner: Type, lifetime: String)
  case pointer(element: Type)
  case mutablePointer(element: Type)
  case weakReference(inner: Type)
  case mutableWeakReference(inner: Type)
  case genericParameter(name: String)
  case `enum`(defId: DefId)
  case genericStruct(template: String, args: [Type])
  case genericEnum(template: String, args: [Type])
  case opaque(defId: DefId)
  case module(info: ModuleSymbolInfo)
  case typeVariable(TypeVariable)
  case traitObject(traitName: String, typeArgs: [Type])
  
  // MARK: - Context-Aware Accessors

  /// 获取类型名称（用于显示）
  public func typeName(in context: CompilerContext) -> String? {
    switch self {
    case .structure(let defId): return context.getName(defId)
    case .`enum`(let defId): return context.getName(defId)
    case .opaque(let defId): return context.getName(defId)
    default: return nil
    }
  }

  /// 获取字段列表（struct）
  public func structMembers(in context: CompilerContext) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)]? {
    if case .structure(let defId) = self {
      return context.getStructMembers(defId)
    }
    return nil
  }

  /// 获取 cases（enum）
  public func enumCases(in context: CompilerContext) -> [EnumCase]? {
    if case .`enum`(let defId) = self {
      return context.getEnumCases(defId)
    }
    return nil
  }

  /// 是否为泛型实例化
  public func isGenericInstantiation(in context: CompilerContext) -> Bool {
    switch self {
    case .structure(let defId): return context.isGenericInstantiation(defId) ?? false
    case .`enum`(let defId): return context.isGenericInstantiation(defId) ?? false
    default: return false
    }
  }

  /// 解构 struct 类型（用于迁移期间的模式匹配）
  /// 返回 (name, members, isGenericInstantiation) 或 nil
  public func structureComponents(in context: CompilerContext) -> (name: String, members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)], isGenericInstantiation: Bool)? {
    if case .structure(let defId) = self {
      guard let name = context.getName(defId),
            let members = context.getStructMembers(defId) else {
        return nil
      }
      let isGeneric = context.isGenericInstantiation(defId) ?? false
      return (name, members, isGeneric)
    }
    return nil
  }

  /// 解构 enum 类型（用于迁移期间的模式匹配）
  /// 返回 (name, cases, isGenericInstantiation) 或 nil
  public func enumComponents(in context: CompilerContext) -> (name: String, cases: [EnumCase], isGenericInstantiation: Bool)? {
    if case .`enum`(let defId) = self {
      guard let name = context.getName(defId),
            let cases = context.getEnumCases(defId) else {
        return nil
      }
      let isGeneric = context.isGenericInstantiation(defId) ?? false
      return (name, cases, isGeneric)
    }
    return nil
  }

  /// 获取 struct 的声明实体
  public func structDecl(in context: CompilerContext) -> StructDecl? {
    if case .structure(let defId) = self {
      let members = context.getStructMembers(defId) ?? []
      let isGeneric = context.isGenericInstantiation(defId) ?? false
      let typeArguments = context.getTypeArguments(defId)
      return StructDecl(
        defId: defId,
        members: members,
        isGenericInstantiation: isGeneric,
        typeArguments: typeArguments
      )
    }
    return nil
  }

  /// 获取 enum 的声明实体
  public func enumDecl(in context: CompilerContext) -> EnumDecl? {
    if case .`enum`(let defId) = self {
      let cases = context.getEnumCases(defId) ?? []
      let isGeneric = context.isGenericInstantiation(defId) ?? false
      let typeArguments = context.getTypeArguments(defId)
      return EnumDecl(
        defId: defId,
        cases: cases,
        isGenericInstantiation: isGeneric,
        typeArguments: typeArguments
      )
    }
    return nil
  }

  public var description: String {
    switch self {
    case .int: return "Int"
    case .int8: return "Int8"
    case .int16: return "Int16"
    case .int32: return "Int32"
    case .int64: return "Int64"
    case .uint: return "UInt"
    case .uint8: return "UInt8"
    case .uint16: return "UInt16"
    case .uint32: return "UInt32"
    case .uint64: return "UInt64"
    case .float32: return "Float32"
    case .float64: return "Float64"
    case .bool: return "Bool"
    case .void: return "Void"
    case .never: return "Never"
    case .function(let params, let returns):
      let paramTypes = params.map { $0.type.description }.joined(separator: ", ")
      return "(\(paramTypes)) -> \(returns)"
    case .structure(let defId):
      if let context = SemanticErrorContext.currentCompilerContext {
        return context.getDebugName(self)
      }
      return "struct(\(defId.id))"
    case .`enum`(let defId):
      if let context = SemanticErrorContext.currentCompilerContext {
        return context.getDebugName(self)
      }
      return "enum(\(defId.id))"
    case .reference(let inner):
      return "ref \(inner.description)"
    case .mutableReference(let inner):
      return "ref mut \(inner.description)"
    case .borrowedReference(let inner, let lifetime):
      return "ref \(lifetime) \(inner.description)"
    case .mutableBorrowedReference(let inner, let lifetime):
      return "ref \(lifetime) mut \(inner.description)"
    case .pointer(let element):
      return "ptr \(element.description)"
    case .mutablePointer(let element):
      return "ptr mut \(element.description)"
    case .weakReference(let inner):
      return "weakref \(inner.description)"
    case .mutableWeakReference(let inner):
      return "weakref mut \(inner.description)"
    case .genericParameter(let name):
      return name
    case .genericStruct(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "\(template)[\(argsStr)]"
    case .genericEnum(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "\(template)[\(argsStr)]"
    case .opaque(let defId):
      if let context = SemanticErrorContext.currentCompilerContext {
        return context.getDebugName(self)
      }
      return "opaque(\(defId.id))"
    case .module(let info):
      return "module(\(info.modulePath.joined(separator: ".")))"
    case .typeVariable(let tv):
      return tv.description
    case .traitObject(let traitName, let typeArgs):
      if typeArgs.isEmpty {
        return traitName
      }
      let argsStr = typeArgs.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(traitName)"
    }
  }

  public func layoutKey(in context: CompilerContext) -> String {
    return context.getLayoutKey(self)
  }
  
  /// 生成可读的调试名称（用于生成的代码中的注释）
  ///
  /// 与 layoutKey 不同，debugName 使用完整的类型名称而不是缩写，
  /// 便于在生成的 C 代码中进行调试。
  ///
  /// ## 示例
  /// - `List[Int]` 而不是 `List_I`
  /// - `Map[String, Int]` 而不是 `Map_std_String_I`
  public func debugName(in context: CompilerContext) -> String {
    return context.getDebugName(self)
  }

  public func containsGenericParameter(in context: CompilerContext) -> Bool {
    return context.containsGenericParameter(self)
  }

  public var stableHashKey: UInt64 {
    var hasher = StableTypeHasher()
    switch self {
    case .int:
      hasher.combine(1)
    case .int8:
      hasher.combine(2)
    case .int16:
      hasher.combine(3)
    case .int32:
      hasher.combine(4)
    case .int64:
      hasher.combine(5)
    case .uint:
      hasher.combine(6)
    case .uint8:
      hasher.combine(7)
    case .uint16:
      hasher.combine(8)
    case .uint32:
      hasher.combine(9)
    case .uint64:
      hasher.combine(10)
    case .float32:
      hasher.combine(11)
    case .float64:
      hasher.combine(12)
    case .bool:
      hasher.combine(13)
    case .void:
      hasher.combine(14)
    case .never:
      hasher.combine(15)
    case .function(let params, let returns):
      hasher.combine(16)
      hasher.combine(params.count)
      for param in params {
        hasher.combine(param.stableHashKey)
      }
      hasher.combine(returns.stableHashKey)
    case .structure(let defId):
      hasher.combine(17)
      hasher.combine(defId.id)
    case .reference(let inner):
      hasher.combine(18)
      hasher.combine(inner.stableHashKey)
    case .mutableReference(let inner):
      hasher.combine(19)
      hasher.combine(inner.stableHashKey)
    case .borrowedReference(let inner, let lifetime):
      hasher.combine(32)
      hasher.combine(inner.stableHashKey)
      hasher.combine(lifetime)
    case .mutableBorrowedReference(let inner, let lifetime):
      hasher.combine(33)
      hasher.combine(inner.stableHashKey)
      hasher.combine(lifetime)
    case .pointer(let element):
      hasher.combine(20)
      hasher.combine(element.stableHashKey)
    case .mutablePointer(let element):
      hasher.combine(21)
      hasher.combine(element.stableHashKey)
    case .weakReference(let inner):
      hasher.combine(22)
      hasher.combine(inner.stableHashKey)
    case .mutableWeakReference(let inner):
      hasher.combine(23)
      hasher.combine(inner.stableHashKey)
    case .genericParameter(let name):
      hasher.combine(24)
      hasher.combine(name)
    case .`enum`(let defId):
      hasher.combine(25)
      hasher.combine(defId.id)
    case .genericStruct(let template, let args):
      hasher.combine(26)
      hasher.combine(template)
      hasher.combine(args.count)
      for arg in args {
        hasher.combine(arg.stableHashKey)
      }
    case .genericEnum(let template, let args):
      hasher.combine(27)
      hasher.combine(template)
      hasher.combine(args.count)
      for arg in args {
        hasher.combine(arg.stableHashKey)
      }
    case .opaque(let defId):
      hasher.combine(28)
      hasher.combine(defId.id)
    case .module(let info):
      hasher.combine(29)
      hasher.combine(info.modulePath.count)
      for part in info.modulePath {
        hasher.combine(part)
      }
    case .typeVariable(let tv):
      hasher.combine(30)
      hasher.combine(tv.id)
    case .traitObject(let traitName, let typeArgs):
      hasher.combine(31)
      hasher.combine(traitName)
      hasher.combine(typeArgs.count)
      for arg in typeArgs {
        hasher.combine(arg.stableHashKey)
      }
    }
    return hasher.state
  }

  /// Stable key for hashing/deduplication without global context.
  public var stableKey: String {
    switch self {
    case .int: return "Int"
    case .int8: return "Int8"
    case .int16: return "Int16"
    case .int32: return "Int32"
    case .int64: return "Int64"
    case .uint: return "UInt"
    case .uint8: return "UInt8"
    case .uint16: return "UInt16"
    case .uint32: return "UInt32"
    case .uint64: return "UInt64"
    case .float32: return "Float32"
    case .float64: return "Float64"
    case .bool: return "Bool"
    case .void: return "Void"
    case .never: return "Never"
    case .function(let params, let returns):
      let paramStr = params.map { $0.type.stableKey }.joined(separator: ",")
      return "Fn(\(paramStr))->\(returns.stableKey)"
    case .structure(let defId):
      return "S#\(defId.id)"
    case .`enum`(let defId):
      return "E#\(defId.id)"
    case .reference(let inner):
      return "Ref(\(inner.stableKey))"
    case .mutableReference(let inner):
      return "MutRef(\(inner.stableKey))"
    case .borrowedReference(let inner, let lifetime):
      return "BorrowRef(\(lifetime))(\(inner.stableKey))"
    case .mutableBorrowedReference(let inner, let lifetime):
      return "BorrowMutRef(\(lifetime))(\(inner.stableKey))"
    case .pointer(let element):
      return "Ptr(\(element.stableKey))"
    case .mutablePointer(let element):
      return "MutPtr(\(element.stableKey))"
    case .weakReference(let inner):
      return "WeakRef(\(inner.stableKey))"
    case .mutableWeakReference(let inner):
      return "MutWeakRef(\(inner.stableKey))"
    case .genericParameter(let name):
      return "Param(\(name))"
    case .genericStruct(let template, let args):
      let argsKey = args.map { $0.stableKey }.joined(separator: ",")
      return "GS(\(template))[\(argsKey)]"
    case .genericEnum(let template, let args):
      let argsKey = args.map { $0.stableKey }.joined(separator: ",")
      return "GE(\(template))[\(argsKey)]"
    case .opaque(let defId):
      return "Opaque#\(defId.id)"
    case .module(let info):
      return "M(\(info.modulePath.joined(separator: ".")))"
    case .typeVariable(let tv):
      return "TV#\(tv.id)"
    case .traitObject(let traitName, let typeArgs):
      if typeArgs.isEmpty {
        return "TO(\(traitName))"
      }
      let argsKey = typeArgs.map { $0.stableKey }.joined(separator: ",")
      return "TO(\(traitName))[\(argsKey)]"
    }
  }
  
  /// Returns true if this type is an integer type (signed or unsigned)
  public var isIntegerType: Bool {
    switch self {
    case .int, .int8, .int16, .int32, .int64,
         .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }
  
  public var functionParameters: [Parameter]? {
      if case .function(let params, _) = self { return params }
      return nil
  }

  public var canonical: Type {
    switch self {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64, .bool, .void, .never: return self
    case .reference(_), .mutableReference(_): return .reference(inner: .void)
    case .borrowedReference(_, let lifetime): return .borrowedReference(inner: .void, lifetime: lifetime)
    case .mutableBorrowedReference(_, let lifetime): return .borrowedReference(inner: .void, lifetime: lifetime)
    case .pointer(let element): return .pointer(element: element.canonical)
    case .mutablePointer(let element): return .pointer(element: element.canonical)
    case .weakReference(let inner): return .weakReference(inner: inner.canonical)
    case .mutableWeakReference(let inner): return .weakReference(inner: inner.canonical)
    case .structure:
      return self
    case .`enum`:
      return self
    case .function: return self
    case .genericParameter: return self
    case .genericStruct(let template, let args):
      return .genericStruct(template: template, args: args.map { $0.canonical })
    case .genericEnum(let template, let args):
      return .genericEnum(template: template, args: args.map { $0.canonical })
    case .opaque:
      return self
    case .module:
      return self
    case .typeVariable:
      return self  // 类型变量保持不变
    case .traitObject:
      return self
    }
  }
}

public struct Parameter: Equatable, Hashable {
  public let type: Type
  public let kind: PassKind
  
  public init(type: Type, kind: PassKind) {
    self.type = type
    self.kind = kind
  }

  fileprivate var stableHashKey: UInt64 {
    var hasher = StableTypeHasher()
    hasher.combine(1)
    hasher.combine(type.stableHashKey)
    hasher.combine(kind.stableHashKey)
    return hasher.state
  }
}

public enum PassKind: Equatable, Hashable {
  case byVal
  case byRef
  case byMutRef

  fileprivate var stableHashKey: UInt64 {
    switch self {
    case .byVal:
      return 1
    case .byRef:
      return 2
    case .byMutRef:
      return 3
    }
  }
}

public func passKindForParameterType(_ type: Type) -> PassKind {
  switch type {
  case .reference:
    return .byRef
  case .mutableReference:
    return .byMutRef
  case .borrowedReference:
    return .byRef
  case .mutableBorrowedReference:
    return .byMutRef
  default:
    return .byVal
  }
}

public func fromSymbolKindToPassKind(_ kind: SymbolKind) -> PassKind {
  switch kind {
  case .variable(let varKind):
    switch varKind {
    case .Value:
      return .byVal
    case .MutableValue:
      return .byVal
    case .Reference:
      return .byRef
    case .MutableReference:
      return .byMutRef
    }
  case .function, .type, .module:
    fatalError("Cannot convert function, type, or module symbol kind to pass kind")
  }
}

public extension Type {
  var containsBorrowedReference: Bool {
    switch self {
    case .borrowedReference, .mutableBorrowedReference:
      return true
    case .function(let parameters, let returns):
      return parameters.contains { $0.type.containsBorrowedReference } || returns.containsBorrowedReference
    case .reference(let inner),
         .mutableReference(let inner),
         .pointer(let inner),
         .mutablePointer(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return inner.containsBorrowedReference
    case .genericStruct(_, let args), .genericEnum(_, let args), .traitObject(_, let args):
      return args.contains(where: \.containsBorrowedReference)
    default:
      return false
    }
  }
}

extension Type: Equatable, Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(stableHashKey)
  }

  public static func == (lhs: Type, rhs: Type) -> Bool {
    switch (lhs, rhs) {
    case (.int, .int),
      (.int8, .int8), (.int16, .int16), (.int32, .int32), (.int64, .int64),
      (.uint, .uint), (.uint8, .uint8), (.uint16, .uint16), (.uint32, .uint32), (.uint64, .uint64),
      (.float32, .float32), (.float64, .float64),
      (.bool, .bool),
      (.void, .void),
      (.never, .never):
      return true

    case (.function(let lParams, let lReturns), .function(let rParams, let rReturns)):
      return lParams == rParams && lReturns == rReturns

    // struct/enum 相等性基于 DefId
    case (.structure(let lDefId), .structure(let rDefId)):
      return lDefId == rDefId
      
    case (.`enum`(let lDefId), .`enum`(let rDefId)):
      return lDefId == rDefId
      
    case (.reference(let l), .reference(let r)):
      return l == r
    case (.mutableReference(let l), .mutableReference(let r)):
      return l == r
    case (.borrowedReference(let lInner, let lLifetime), .borrowedReference(let rInner, let rLifetime)):
      return lInner == rInner && lLifetime == rLifetime
    case (.mutableBorrowedReference(let lInner, let lLifetime), .mutableBorrowedReference(let rInner, let rLifetime)):
      return lInner == rInner && lLifetime == rLifetime
    case (.pointer(let l), .pointer(let r)):
       return l == r
    case (.mutablePointer(let l), .mutablePointer(let r)):
       return l == r
    case (.weakReference(let l), .weakReference(let r)):
      return l == r
    case (.mutableWeakReference(let l), .mutableWeakReference(let r)):
      return l == r
    case (.genericParameter(let l), .genericParameter(let r)):
      return l == r
    case (.genericStruct(let lTemplate, let lArgs), .genericStruct(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
    case (.genericEnum(let lTemplate, let lArgs), .genericEnum(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
    case (.opaque(let lDefId), .opaque(let rDefId)):
      return lDefId == rDefId
    case (.module(let lInfo), .module(let rInfo)):
      return lInfo.modulePath == rInfo.modulePath
    
    case (.typeVariable(let lTV), .typeVariable(let rTV)):
      return lTV == rTV
    case (.traitObject(let lName, let lArgs), .traitObject(let rName, let rArgs)):
      return lName == rName && lArgs == rArgs

    default:
      return false
    }
  }

  public static func != (lhs: Type, rhs: Type) -> Bool {
    return !(lhs == rhs)
  }
}
