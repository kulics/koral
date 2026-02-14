import Foundation

// MARK: - Type Declaration Entities

/// Struct 类型的声明实体
/// 仅保留 DefId 与结构体成员信息，其余元数据由 DefIdMap 提供
public struct StructDecl: Equatable, Hashable {
  /// 定义标识符
  public let defId: DefId
    
  /// 字段列表（可变，用于解析递归类型）
  public var members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)]
    
  /// 是否为泛型实例化
  public var isGenericInstantiation: Bool
    
  /// 泛型类型参数
  public var typeArguments: [Type]?
    
  public init(
    defId: DefId,
    members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)] = [],
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

/// Union 类型的声明实体
/// 仅保留 DefId 与 union case 信息，其余元数据由 DefIdMap 提供
public struct UnionDecl: Equatable, Hashable {
  /// 定义标识符
  public let defId: DefId
    
  /// Union cases（可变，用于解析递归类型）
  public var cases: [UnionCase]
    
  /// 是否为泛型实例化
  public var isGenericInstantiation: Bool
    
  /// 泛型类型参数
  public var typeArguments: [Type]?
    
  public init(
    defId: DefId,
    cases: [UnionCase] = [],
    isGenericInstantiation: Bool = false,
    typeArguments: [Type]? = nil
  ) {
    self.defId = defId
    self.cases = cases
    self.isGenericInstantiation = isGenericInstantiation
    self.typeArguments = typeArguments
  }
    
  // 类型相等性基于 DefId
  public static func == (lhs: UnionDecl, rhs: UnionDecl) -> Bool {
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

// MARK: - Union Case

public struct UnionCase {
  public let name: String
  public let parameters: [(name: String, type: Type, access: AccessModifier)]
  
  public init(name: String, parameters: [(name: String, type: Type, access: AccessModifier)]) {
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
  case pointer(element: Type)
  case weakReference(inner: Type)
  case genericParameter(name: String)
  case union(defId: DefId)
  case genericStruct(template: String, args: [Type])
  case genericUnion(template: String, args: [Type])
  case opaque(defId: DefId)
  case module(info: ModuleSymbolInfo)
  case typeVariable(TypeVariable)
  
  // MARK: - Context-Aware Accessors

  /// 获取类型名称（用于显示）
  public func typeName(in context: CompilerContext) -> String? {
    switch self {
    case .structure(let defId): return context.getName(defId)
    case .union(let defId): return context.getName(defId)
    case .opaque(let defId): return context.getName(defId)
    default: return nil
    }
  }

  /// 获取字段列表（struct）
  public func structMembers(in context: CompilerContext) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier)]? {
    if case .structure(let defId) = self {
      return context.getStructMembers(defId)
    }
    return nil
  }

  /// 获取 cases（union）
  public func unionCases(in context: CompilerContext) -> [UnionCase]? {
    if case .union(let defId) = self {
      return context.getUnionCases(defId)
    }
    return nil
  }

  /// 是否为泛型实例化
  public func isGenericInstantiation(in context: CompilerContext) -> Bool {
    switch self {
    case .structure(let defId): return context.isGenericInstantiation(defId) ?? false
    case .union(let defId): return context.isGenericInstantiation(defId) ?? false
    default: return false
    }
  }

  /// 解构 struct 类型（用于迁移期间的模式匹配）
  /// 返回 (name, members, isGenericInstantiation) 或 nil
  public func structureComponents(in context: CompilerContext) -> (name: String, members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)], isGenericInstantiation: Bool)? {
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

  /// 解构 union 类型（用于迁移期间的模式匹配）
  /// 返回 (name, cases, isGenericInstantiation) 或 nil
  public func unionComponents(in context: CompilerContext) -> (name: String, cases: [UnionCase], isGenericInstantiation: Bool)? {
    if case .union(let defId) = self {
      guard let name = context.getName(defId),
            let cases = context.getUnionCases(defId) else {
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

  /// 获取 union 的声明实体
  public func unionDecl(in context: CompilerContext) -> UnionDecl? {
    if case .union(let defId) = self {
      let cases = context.getUnionCases(defId) ?? []
      let isGeneric = context.isGenericInstantiation(defId) ?? false
      let typeArguments = context.getTypeArguments(defId)
      return UnionDecl(
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
    case .union(let defId):
      if let context = SemanticErrorContext.currentCompilerContext {
        return context.getDebugName(self)
      }
      return "union(\(defId.id))"
    case .reference(let inner):
      return "\(inner.description) ref"
    case .pointer(let element):
      return "\(element.description) ptr"
    case .weakReference(let inner):
      return "\(inner.description) weakref"
    case .genericParameter(let name):
      return name
    case .genericStruct(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(template)"
    case .genericUnion(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(template)"
    case .opaque(let defId):
      if let context = SemanticErrorContext.currentCompilerContext {
        return context.getDebugName(self)
      }
      return "opaque(\(defId.id))"
    case .module(let info):
      return "module(\(info.modulePath.joined(separator: ".")))"
    case .typeVariable(let tv):
      return tv.description
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
    case .union(let defId):
      return "U#\(defId.id)"
    case .reference(let inner):
      return "Ref(\(inner.stableKey))"
    case .pointer(let element):
      return "Ptr(\(element.stableKey))"
    case .weakReference(let inner):
      return "WeakRef(\(inner.stableKey))"
    case .genericParameter(let name):
      return "Param(\(name))"
    case .genericStruct(let template, let args):
      let argsKey = args.map { $0.stableKey }.joined(separator: ",")
      return "GS(\(template))[\(argsKey)]"
    case .genericUnion(let template, let args):
      let argsKey = args.map { $0.stableKey }.joined(separator: ",")
      return "GU(\(template))[\(argsKey)]"
    case .opaque(let defId):
      return "Opaque#\(defId.id)"
    case .module(let info):
      return "M(\(info.modulePath.joined(separator: ".")))"
    case .typeVariable(let tv):
      return "TV#\(tv.id)"
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
    case .reference(_): return .reference(inner: .void)
    case .pointer(let element): return .pointer(element: element.canonical)
    case .weakReference(let inner): return .weakReference(inner: inner.canonical)
    case .structure:
      return self
    case .union:
      return self
    case .function: return self
    case .genericParameter: return self
    case .genericStruct(let template, let args):
      return .genericStruct(template: template, args: args.map { $0.canonical })
    case .genericUnion(let template, let args):
      return .genericUnion(template: template, args: args.map { $0.canonical })
    case .opaque:
      return self
    case .module:
      return self
    case .typeVariable:
      return self  // 类型变量保持不变
    }
  }
}

public struct Parameter: Equatable {
  public let type: Type
  public let kind: PassKind
  
  public init(type: Type, kind: PassKind) {
    self.type = type
    self.kind = kind
  }
}

public enum PassKind: Equatable {
  case byVal
  case byRef
  case byMutRef
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

extension Type: Equatable {
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

    // struct/union 相等性基于 DefId
    case (.structure(let lDefId), .structure(let rDefId)):
      return lDefId == rDefId
      
    case (.union(let lDefId), .union(let rDefId)):
      return lDefId == rDefId
      
    case (.reference(let l), .reference(let r)):
      return l == r
    case (.pointer(let l), .pointer(let r)):
       return l == r
    case (.weakReference(let l), .weakReference(let r)):
      return l == r
    case (.genericParameter(let l), .genericParameter(let r)):
      return l == r
    case (.genericStruct(let lTemplate, let lArgs), .genericStruct(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
    case (.genericUnion(let lTemplate, let lArgs), .genericUnion(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
    case (.opaque(let lDefId), .opaque(let rDefId)):
      return lDefId == rDefId
    case (.module(let lInfo), .module(let rInfo)):
      return lInfo.modulePath == rInfo.modulePath
    
    case (.typeVariable(let lTV), .typeVariable(let rTV)):
      return lTV == rTV

    default:
      return false
    }
  }

  public static func != (lhs: Type, rhs: Type) -> Bool {
    return !(lhs == rhs)
  }
}
