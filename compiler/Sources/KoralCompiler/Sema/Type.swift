import Foundation

// MARK: - Type Declaration Entities

/// Struct 类型的声明实体
/// 使用 struct + UUID 实现类型身份语义，避免循环引用问题
public struct StructDecl: Equatable, Hashable {
    /// 唯一标识符，用于类型身份比较
    public let id: UUID
    
    /// 类型名称（简单名）
    public let name: String

    /// 定义标识符（用于生成唯一的 C 标识符）
    public let defId: DefId
    
    /// 模块路径
    public var modulePath: [String]
    
    /// 源文件路径（用于 private 符号隔离）
    public var sourceFile: String
    
    /// 访问修饰符
    public var access: AccessModifier
    
    /// 字段列表（可变，用于解析递归类型）
    public var members: [(name: String, type: Type, mutable: Bool)]
    
    /// 是否为泛型实例化
    public var isGenericInstantiation: Bool
    
    /// 泛型类型参数（用于实例化类型的 qualifiedName）
    public var typeArguments: [Type]?
    
    public init(
      id: UUID = UUID(),
      name: String,
      defId: DefId,
      modulePath: [String],
      sourceFile: String,
      access: AccessModifier,
      members: [(name: String, type: Type, mutable: Bool)] = [],
      isGenericInstantiation: Bool = false,
      typeArguments: [Type]? = nil
    ) {
        self.id = id
        self.name = name
        self.defId = defId
        self.modulePath = modulePath
        self.sourceFile = sourceFile
        self.access = access
        self.members = members
        self.isGenericInstantiation = isGenericInstantiation
        self.typeArguments = typeArguments
    }
    
    // 类型相等性基于 UUID
    public static func == (lhs: StructDecl, rhs: StructDecl) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Union 类型的声明实体
/// 使用 struct + UUID 实现类型身份语义，避免循环引用问题
public struct UnionDecl: Equatable, Hashable {
    /// 唯一标识符，用于类型身份比较
    public let id: UUID
    
    /// 类型名称（简单名）
    public let name: String

    /// 定义标识符（用于生成唯一的 C 标识符）
    public let defId: DefId
    
    /// 模块路径
    public var modulePath: [String]
    
    /// 源文件路径（用于 private 符号隔离）
    public var sourceFile: String
    
    /// 访问修饰符
    public var access: AccessModifier
    
    /// Union cases（可变，用于解析递归类型）
    public var cases: [UnionCase]
    
    /// 是否为泛型实例化
    public var isGenericInstantiation: Bool
    
    /// 泛型类型参数
    public var typeArguments: [Type]?
    
    public init(
      id: UUID = UUID(),
      name: String,
      defId: DefId,
      modulePath: [String],
      sourceFile: String,
      access: AccessModifier,
      cases: [UnionCase] = [],
      isGenericInstantiation: Bool = false,
      typeArguments: [Type]? = nil
    ) {
        self.id = id
        self.name = name
        self.defId = defId
        self.modulePath = modulePath
        self.sourceFile = sourceFile
        self.access = access
        self.cases = cases
        self.isGenericInstantiation = isGenericInstantiation
        self.typeArguments = typeArguments
    }
    
    // 类型相等性基于 UUID
    public static func == (lhs: UnionDecl, rhs: UnionDecl) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Union Case

public struct UnionCase {
  public let name: String
  public let parameters: [(name: String, type: Type)]
  
  public init(name: String, parameters: [(name: String, type: Type)]) {
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
  case structure(decl: StructDecl)
  case reference(inner: Type)
  case pointer(element: Type)
  case genericParameter(name: String)
  case union(decl: UnionDecl)
  case genericStruct(template: String, args: [Type])
  case genericUnion(template: String, args: [Type])
  case module(info: ModuleSymbolInfo)
  case typeVariable(TypeVariable)
  
  // MARK: - Convenience Accessors
  
  /// 获取类型名称（用于显示）
  public var typeName: String? {
    switch self {
    case .structure(let decl): return decl.name
    case .union(let decl): return decl.name
    default: return nil
    }
  }
  
  /// 获取字段列表（struct）
  public var structMembers: [(name: String, type: Type, mutable: Bool)]? {
    if case .structure(let decl) = self {
      return decl.members
    }
    return nil
  }
  
  /// 获取 cases（union）
  public var unionCases: [UnionCase]? {
    if case .union(let decl) = self {
      return decl.cases
    }
    return nil
  }
  
  /// 是否为泛型实例化
  public var isGenericInstantiation: Bool {
    switch self {
    case .structure(let decl): return decl.isGenericInstantiation
    case .union(let decl): return decl.isGenericInstantiation
    default: return false
    }
  }
  
  // MARK: - Legacy Pattern Matching Support
  
  /// 解构 struct 类型（用于迁移期间的模式匹配）
  /// 返回 (name, members, isGenericInstantiation) 或 nil
  public var structureComponents: (name: String, members: [(name: String, type: Type, mutable: Bool)], isGenericInstantiation: Bool)? {
    if case .structure(let decl) = self {
      return (decl.name, decl.members, decl.isGenericInstantiation)
    }
    return nil
  }
  
  /// 解构 union 类型（用于迁移期间的模式匹配）
  /// 返回 (name, cases, isGenericInstantiation) 或 nil
  public var unionComponents: (name: String, cases: [UnionCase], isGenericInstantiation: Bool)? {
    if case .union(let decl) = self {
      return (decl.name, decl.cases, decl.isGenericInstantiation)
    }
    return nil
  }
  
  /// 获取 struct 的声明实体
  public var structDecl: StructDecl? {
    if case .structure(let decl) = self {
      return decl
    }
    return nil
  }
  
  /// 获取 union 的声明实体
  public var unionDecl: UnionDecl? {
    if case .union(let decl) = self {
      return decl
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
    case .structure(let decl):
      return decl.name
    case .union(let decl):
      return decl.name
    case .reference(let inner):
      return "\(inner.description) ref"
    case .pointer(let element):
      return "\(element.description) ptr"
    case .genericParameter(let name):
      return name
    case .genericStruct(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(template)"
    case .genericUnion(let template, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(template)"
    case .module(let info):
      return "module(\(info.modulePath.joined(separator: ".")))"
    case .typeVariable(let tv):
      return tv.description
    }
  }

  public var layoutKey: String {
    switch self {
    case .int: return "I"
    case .int8: return "I8"
    case .int16: return "I16"
    case .int32: return "I32"
    case .int64: return "I64"
    case .uint: return "U"
    case .uint8: return "U8"
    case .uint16: return "U16"
    case .uint32: return "U32"
    case .uint64: return "U64"
    case .float32: return "F32"
    case .float64: return "F64"
    case .bool: return "B"
    case .void: return "V"
    case .never: return "N"
    case .function: return "Fn"
    case .reference(let inner): return "R_\(inner.layoutKey)"
    case .pointer(let element): return "P_\(element.layoutKey)"
    case .structure(let decl):
      // 使用模块路径、文件标识（如果是 private）和名称来确保唯一性
      var parts: [String] = []
      if !decl.modulePath.isEmpty {
        parts.append(decl.modulePath.joined(separator: "_"))
      }
      if decl.access == .private {
        // 使用文件路径的哈希值生成短标识符
        var hash: UInt32 = 0
        for char in decl.sourceFile.utf8 {
          hash = hash &* 31 &+ UInt32(char)
        }
        parts.append("f\(hash % 10000)")
      }
      parts.append(decl.name)
      if let typeArgs = decl.typeArguments, !typeArgs.isEmpty {
        let argsStr = typeArgs.map { $0.layoutKey }.joined(separator: "_")
        parts.append(argsStr)
      }
      return parts.joined(separator: "_")
    case .union(let decl):
      // 使用模块路径、文件标识（如果是 private）和名称来确保唯一性
      var parts: [String] = []
      if !decl.modulePath.isEmpty {
        parts.append(decl.modulePath.joined(separator: "_"))
      }
      if decl.access == .private {
        // 使用文件路径的哈希值生成短标识符
        var hash: UInt32 = 0
        for char in decl.sourceFile.utf8 {
          hash = hash &* 31 &+ UInt32(char)
        }
        parts.append("f\(hash % 10000)")
      }
      parts.append(decl.name)
      if let typeArgs = decl.typeArguments, !typeArgs.isEmpty {
        let argsStr = typeArgs.map { $0.layoutKey }.joined(separator: "_")
        parts.append(argsStr)
      }
      return parts.joined(separator: "_")
    case .genericParameter(let name):
      return "Param_\(name)"
    case .genericStruct(let template, let args):
      let argsKeys = args.map { $0.layoutKey }.joined(separator: "_")
      return "\(template)_\(argsKeys)"
    case .genericUnion(let template, let args):
      let argsKeys = args.map { $0.layoutKey }.joined(separator: "_")
      return "\(template)_\(argsKeys)"
    case .module(let info):
      return "M_\(info.modulePath.joined(separator: "_"))"
    case .typeVariable(let tv):
      return "TV_\(tv.id)"
    }
  }
  
  /// 生成可读的调试名称（用于生成的代码中的注释）
  ///
  /// 与 layoutKey 不同，debugName 使用完整的类型名称而不是缩写，
  /// 便于在生成的 C 代码中进行调试。
  ///
  /// ## 示例
  /// - `List[Int]` 而不是 `List_I`
  /// - `Map[String, Int]` 而不是 `Map_std_String_I`
  public var debugName: String {
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
      let paramStr = params.map { $0.type.debugName }.joined(separator: ", ")
      return "(\(paramStr)) -> \(returns.debugName)"
    case .reference(let inner): return "ref \(inner.debugName)"
    case .pointer(let element): return "Pointer[\(element.debugName)]"
    case .structure(let decl):
      var name = decl.name
      if let typeArgs = decl.typeArguments, !typeArgs.isEmpty {
        let argsStr = typeArgs.map { $0.debugName }.joined(separator: ", ")
        name += "[\(argsStr)]"
      }
      return name
    case .union(let decl):
      var name = decl.name
      if let typeArgs = decl.typeArguments, !typeArgs.isEmpty {
        let argsStr = typeArgs.map { $0.debugName }.joined(separator: ", ")
        name += "[\(argsStr)]"
      }
      return name
    case .genericParameter(let name):
      return name
    case .genericStruct(let template, let args):
      let argsStr = args.map { $0.debugName }.joined(separator: ", ")
      return "\(template)[\(argsStr)]"
    case .genericUnion(let template, let args):
      let argsStr = args.map { $0.debugName }.joined(separator: ", ")
      return "\(template)[\(argsStr)]"
    case .module(let info):
      return "module \(info.modulePath.joined(separator: "."))"
    case .typeVariable(let tv):
      return "?\(tv.id)"
    }
  }

  public var containsGenericParameter: Bool {
    switch self {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64, .bool, .void, .never:
      return false
    case .function(let params, let returns):
      return returns.containsGenericParameter || params.contains { $0.type.containsGenericParameter }
    case .structure(let decl):
      return decl.members.contains { $0.type.containsGenericParameter }
    case .union(let decl):
      return decl.cases.contains { c in c.parameters.contains { $0.type.containsGenericParameter } }
    case .reference(let inner):
      return inner.containsGenericParameter
    case .pointer(let element):
       return element.containsGenericParameter
    case .genericParameter:
      return true
    case .genericStruct(_, let args):
      return args.contains { $0.containsGenericParameter }
    case .genericUnion(_, let args):
      return args.contains { $0.containsGenericParameter }
    case .module:
      return false
    case .typeVariable:
      return true  // 类型变量类似于泛型参数，需要被解析
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
    case .structure(let decl):
      if decl.isGenericInstantiation {
        let newMembers = decl.members.map { ($0.name, $0.type.canonical, $0.mutable) }
        let newDecl = StructDecl(
          name: decl.name,
          defId: decl.defId,
          modulePath: decl.modulePath,
          sourceFile: decl.sourceFile,
          access: decl.access,
          members: newMembers,
          isGenericInstantiation: true,
          typeArguments: decl.typeArguments
        )
        return .structure(decl: newDecl)
      } else {
        return self
      }
    case .union(let decl):
      if decl.isGenericInstantiation {
        let newCases = decl.cases.map { UnionCase(name: $0.name, parameters: $0.parameters.map { p in (name: p.name, type: p.type.canonical) }) }
        let newDecl = UnionDecl(
          name: decl.name,
          defId: decl.defId,
          modulePath: decl.modulePath,
          sourceFile: decl.sourceFile,
          access: decl.access,
          cases: newCases,
          isGenericInstantiation: true,
          typeArguments: decl.typeArguments
        )
        return .union(decl: newDecl)
      } else {
        return self
      }
    case .function: return self
    case .genericParameter: return self
    case .genericStruct(let template, let args):
      return .genericStruct(template: template, args: args.map { $0.canonical })
    case .genericUnion(let template, let args):
      return .genericUnion(template: template, args: args.map { $0.canonical })
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

    // struct/union 相等性基于声明实体的 UUID
    case (.structure(let lDecl), .structure(let rDecl)):
      return lDecl == rDecl  // 基于 UUID 比较
      
    case (.union(let lDecl), .union(let rDecl)):
      return lDecl == rDecl  // 基于 UUID 比较
      
    case (.reference(let l), .reference(let r)):
      return l == r
    case (.pointer(let l), .pointer(let r)):
       return l == r
    case (.genericParameter(let l), .genericParameter(let r)):
      return l == r
    case (.genericStruct(let lTemplate, let lArgs), .genericStruct(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
    case (.genericUnion(let lTemplate, let lArgs), .genericUnion(let rTemplate, let rArgs)):
      return lTemplate == rTemplate && lArgs == rArgs
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
