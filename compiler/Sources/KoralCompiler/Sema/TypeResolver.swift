/// TypeResolver.swift - Pass 2: 解析类型成员和函数签名
///
/// TypeResolver 是编译器的第二个 Pass，负责：
/// - 解析类型成员和函数签名
/// - 构建完整的类型信息
/// - 注册 given 方法签名（允许方法间相互调用）
/// - 构建模块符号表（合并了原 Pass 2.5 的功能）
///
/// ## 设计参考
/// - Rust 编译器 (rustc): 类型解析阶段
/// - 原 TypeCheckerPasses.swift 中的 collectGivenSignatures 和 buildModuleSymbols 方法
///
/// ## 依赖关系
/// - 输入：NameCollectorOutput（包含 DefIdMap 和 ModuleResolverOutput）
/// - 输出：TypeResolverOutput（包含 NameCollectorOutput）
///
/// **Validates: Requirements 2.1, 2.2**

import Foundation

// MARK: - TypeResolver

/// TypeResolver - Pass 2: 解析类型成员和函数签名
///
/// 负责：
/// - 解析类型成员和函数签名
/// - 构建完整的类型信息
/// - 注册 given 方法签名
/// - 构建模块符号表
public class TypeResolver: CompilerPass {
    public typealias Input = TypeResolverInput
    public typealias Output = TypeResolverOutput
    
    public var name: String { "TypeResolver" }
    
    // MARK: - 私有属性
    
    /// 统一查询上下文
    private var context: CompilerContext
    
    
    /// 当前处理的源文件
    private var currentSourceFile: String = ""
    
    /// 当前处理的模块路径
    private var currentModulePath: [String] = []
    
    /// 标准库全局节点数量
    private var coreGlobalCount: Int = 0
    
    /// 收集到的类型签名信息
    private var collectedTypeSignatures: [String: ResolvedTypeSignature] = [:]
    
    /// 收集到的函数签名信息
    private var collectedFunctionSignatures: [String: ResolvedFunctionSignature] = [:]
    
    /// 收集到的 given 方法签名
    private var collectedGivenSignatures: [String: [ResolvedGivenMethodSignature]] = [:]
    
    /// 模块符号信息
    private var moduleSymbolInfos: [String: ResolvedModuleSymbolInfo] = [:]

    /// 关联的 TypeChecker（用于 Pass 2 状态注入）
    private var checker: TypeChecker?
    
    // MARK: - 初始化
    
    /// 创建一个新的 TypeResolver
    ///
    /// - Parameter coreGlobalCount: 标准库全局节点数量（用于判断是否是标准库定义）
    public init(coreGlobalCount: Int = 0, checker: TypeChecker? = nil, context: CompilerContext? = nil) {
        self.coreGlobalCount = coreGlobalCount
        self.checker = checker
        self.context = context ?? CompilerContext()
    }
    
    // MARK: - CompilerPass 实现
    
    /// 执行 Pass 2
    ///
    /// - Parameter input: TypeResolver 的输入
    /// - Returns: TypeResolver 的输出
    /// - Throws: 如果遇到语义错误
    public func run(input: Input) throws -> Output {
        let nameCollectorOutput = input.nameCollectorOutput
        let moduleResolverOutput = nameCollectorOutput.moduleResolverOutput
        let astNodes = moduleResolverOutput.astNodes
        let nodeSourceInfoList = moduleResolverOutput.nodeSourceInfoList
        let defIdMap = nameCollectorOutput.defIdMap
        context.setDefIdMap(defIdMap)
        
        // 重置状态
        defIdMap.clearTypeInfo()
        collectedTypeSignatures = [:]
        collectedFunctionSignatures = [:]
        collectedGivenSignatures = [:]
        moduleSymbolInfos = [:]
        
        // 第一步：解析类型成员和函数签名
        // 这对应原来的 collectGivenSignatures 逻辑
        for (index, node) in astNodes.enumerated() {
            // 获取源信息
            let sourceInfo = index < nodeSourceInfoList.count ? nodeSourceInfoList[index] : nil
            currentSourceFile = sourceInfo?.sourceFile ?? ""
            currentModulePath = sourceInfo?.modulePath ?? []
            
            try resolveSignatures(node, defIdMap: defIdMap, index: index)
        }

        // Pass 2: 注册 given 方法签名到 TypeChecker（用于后续体检查）
        if let checker {
            let declarations = astNodes.filter { node in
                if case .usingDeclaration = node { return false }
                if case .foreignUsingDeclaration = node { return false }
                return true
            }
            for (index, node) in declarations.enumerated() {
                let isStdLib = index < coreGlobalCount
                checker.isCurrentDeclStdLib = isStdLib
                let sourceInfo = index < nodeSourceInfoList.count ? nodeSourceInfoList[index] : nil
                checker.currentFileName = sourceInfo?.sourceFile ?? ""
                checker.currentSourceFile = sourceInfo?.sourceFile ?? ""
                checker.currentModulePath = sourceInfo?.modulePath ?? []
                checker.currentSpan = node.span
                try checker.collectGivenSignatures(node)
            }
        }
        
        // 第二步：构建模块符号表（合并原 Pass 2.5 的功能）
        try buildModuleSymbols(from: astNodes, nodeSourceInfoList: nodeSourceInfoList, defIdMap: defIdMap)

        if let checker {
            // Use full node list to keep nodeSourceInfoMap indices aligned
            try checker.buildModuleSymbols(from: astNodes)
        }
        
        // 第三步：将收集的信息添加到 DefIdMap
        try populateOutputMaps(defIdMap: defIdMap)
        
        return TypeResolverOutput(nameCollectorOutput: nameCollectorOutput)
    }
    
    // MARK: - 签名解析
    
    /// 解析单个节点的签名
    ///
    /// - Parameters:
    ///   - node: 全局节点
    ///   - defIdMap: DefId 映射表
    ///   - index: 节点索引
    private func resolveSignatures(_ node: GlobalNode, defIdMap: DefIdMap, index: Int) throws {
        switch node {
        case .usingDeclaration:
            // Using 声明在 ModuleResolver 中处理，这里跳过
            return
        case .foreignUsingDeclaration:
            // Foreign using doesn't affect type signatures
            return
            
        case .givenDeclaration(let typeParams, let typeNode, let methods, let span):
            try resolveGivenSignatures(
                typeParams: typeParams,
                typeNode: typeNode,
                methods: methods,
                span: span,
                defIdMap: defIdMap
            )
            
        case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let span):
            try resolveIntrinsicGivenSignatures(
                typeParams: typeParams,
                typeNode: typeNode,
                methods: methods,
                span: span,
                defIdMap: defIdMap
            )
            
        case .globalStructDeclaration(let name, let typeParameters, let parameters, let access, let span):
            try resolveStructSignature(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                access: access,
                span: span,
                defIdMap: defIdMap
            )
            
        case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let span):
            try resolveUnionSignature(
                name: name,
                typeParameters: typeParameters,
                cases: cases,
                access: access,
                span: span,
                defIdMap: defIdMap
            )
            
        case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, let access, let span):
            try resolveFunctionSignature(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                defIdMap: defIdMap
            )
            
        case .intrinsicFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, let span):
            try resolveIntrinsicFunctionSignature(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                returnType: returnType,
                span: span,
                defIdMap: defIdMap
            )
        case .foreignFunctionDeclaration(let name, let parameters, let returnType, let access, let span):
            try resolveFunctionSignature(
                name: name,
                typeParameters: [],
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                defIdMap: defIdMap
            )
        case .foreignTypeDeclaration(let name, let access, let span):
            try resolveOpaqueTypeSignature(
                name: name,
                access: access,
                span: span,
                defIdMap: defIdMap
            )
            
        case .traitDeclaration, .globalVariableDeclaration, .intrinsicTypeDeclaration:
            // 这些在 Pass 1 中已处理，或在 Pass 3 中处理
            break
        }
    }
    
    // MARK: - Given 签名解析
    
    /// 解析 given 声明的方法签名
    ///
    /// - Parameters:
    ///   - typeParams: 类型参数
    ///   - typeNode: 类型节点
    ///   - methods: 方法声明列表
    ///   - span: 源代码位置
    ///   - defIdMap: DefId 映射表
    private func resolveGivenSignatures(
        typeParams: [TypeParameterDecl],
        typeNode: TypeNode,
        methods: [MethodDeclaration],
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 获取基类型名称
        let baseName: String
        if !typeParams.isEmpty {
            // 泛型 given
            switch typeNode {
            case .generic(let name, _):
                baseName = name
            case .pointer:
                baseName = "Ptr"
            default:
                // 非泛型类型上的泛型 given 将在后续处理
                return
            }
        } else {
            // 非泛型 given
            baseName = extractTypeName(from: typeNode)
        }
        
        // 初始化方法签名列表
        if collectedGivenSignatures[baseName] == nil {
            collectedGivenSignatures[baseName] = []
        }
        
        // 收集每个方法的签名
        for method in methods {
            let signature = ResolvedGivenMethodSignature(
                methodName: method.name,
                typeParameters: typeParams,
                methodTypeParameters: method.typeParameters,
                parameters: method.parameters.map { param in
                    ResolvedParameter(
                        name: param.name,
                        typeNode: param.type,
                        isMutable: param.mutable
                    )
                },
                returnTypeNode: method.returnType,
                isGeneric: !typeParams.isEmpty,
                baseName: baseName,
                sourceFile: currentSourceFile,
                modulePath: currentModulePath
            )
            collectedGivenSignatures[baseName]!.append(signature)
        }
    }
    
    /// 解析 intrinsic given 声明的方法签名
    ///
    /// - Parameters:
    ///   - typeParams: 类型参数
    ///   - typeNode: 类型节点
    ///   - methods: 方法声明列表
    ///   - span: 源代码位置
    ///   - defIdMap: DefId 映射表
    private func resolveIntrinsicGivenSignatures(
        typeParams: [TypeParameterDecl],
        typeNode: TypeNode,
        methods: [IntrinsicMethodDeclaration],
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 获取基类型名称
        let baseName: String
        if !typeParams.isEmpty {
            switch typeNode {
            case .generic(let name, _):
                baseName = name
            case .pointer:
                baseName = "Ptr"
            default:
                return
            }
        } else {
            baseName = extractTypeName(from: typeNode)
        }
        
        // 初始化方法签名列表
        if collectedGivenSignatures[baseName] == nil {
            collectedGivenSignatures[baseName] = []
        }
        
        // 收集每个方法的签名
        for method in methods {
            let signature = ResolvedGivenMethodSignature(
                methodName: method.name,
                typeParameters: typeParams,
                methodTypeParameters: [],
                parameters: method.parameters.map { param in
                    ResolvedParameter(
                        name: param.name,
                        typeNode: param.type,
                        isMutable: param.mutable
                    )
                },
                returnTypeNode: method.returnType,
                isGeneric: !typeParams.isEmpty,
                baseName: baseName,
                sourceFile: currentSourceFile,
                modulePath: currentModulePath,
                isIntrinsic: true
            )
            collectedGivenSignatures[baseName]!.append(signature)
        }
    }
    
    // MARK: - 类型签名解析
    
    /// 解析 struct 签名
    private func resolveStructSignature(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)],
        access: AccessModifier,
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 生成完整限定名
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        // 收集成员签名
        let members = parameters.map { param in
            ResolvedMember(
                name: param.name,
                typeNode: param.type,
                isMutable: param.mutable,
                access: param.access
            )
        }
        
        collectedTypeSignatures[qualifiedName] = ResolvedTypeSignature(
            name: name,
            kind: .structure,
            typeParameters: typeParameters,
            members: members,
            access: access,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }
    
    /// 解析 union 签名
    private func resolveUnionSignature(
        name: String,
        typeParameters: [TypeParameterDecl],
        cases: [UnionCaseDeclaration],
        access: AccessModifier,
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 生成完整限定名
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        // 收集 case 签名
        let resolvedCases = cases.map { caseDecl in
            ResolvedUnionCase(
                name: caseDecl.name,
                parameters: caseDecl.parameters.map { param in
                    ResolvedParameter(
                        name: param.name,
                        typeNode: param.type,
                        isMutable: false
                    )
                }
            )
        }
        
        collectedTypeSignatures[qualifiedName] = ResolvedTypeSignature(
            name: name,
            kind: .union(cases: resolvedCases),
            typeParameters: typeParameters,
            members: [],
            access: access,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }

    /// 解析 opaque（foreign type）签名
    private func resolveOpaqueTypeSignature(
        name: String,
        access: AccessModifier,
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        collectedTypeSignatures[qualifiedName] = ResolvedTypeSignature(
            name: name,
            kind: .opaque,
            typeParameters: [],
            members: [],
            access: access,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }
    
    // MARK: - 函数签名解析
    
    /// 解析函数签名
    private func resolveFunctionSignature(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [(name: String, mutable: Bool, type: TypeNode)],
        returnType: TypeNode,
        access: AccessModifier,
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 生成完整限定名
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        collectedFunctionSignatures[qualifiedName] = ResolvedFunctionSignature(
            name: name,
            typeParameters: typeParameters,
            parameters: parameters.map { param in
                ResolvedParameter(
                    name: param.name,
                    typeNode: param.type,
                    isMutable: param.mutable
                )
            },
            returnTypeNode: returnType,
            access: access,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }
    
    /// 解析 intrinsic 函数签名
    private func resolveIntrinsicFunctionSignature(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [(name: String, mutable: Bool, type: TypeNode)],
        returnType: TypeNode,
        span: SourceSpan,
        defIdMap: DefIdMap
    ) throws {
        // 生成完整限定名
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        collectedFunctionSignatures[qualifiedName] = ResolvedFunctionSignature(
            name: name,
            typeParameters: typeParameters,
            parameters: parameters.map { param in
                ResolvedParameter(
                    name: param.name,
                    typeNode: param.type,
                    isMutable: param.mutable
                )
            },
            returnTypeNode: returnType,
            access: .default,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath,
            isIntrinsic: true
        )
    }
    
    // MARK: - 模块符号构建（合并原 Pass 2.5）
    
    /// 构建模块符号表
    ///
    /// 这个方法合并了原 Pass 2.5 的功能，在 Pass 2 中一起完成。
    /// 构建模块符号表使得 `using self.child` 后可以通过 `child.xxx` 访问子模块符号。
    private func buildModuleSymbols(
        from astNodes: [GlobalNode],
        nodeSourceInfoList: [GlobalNodeSourceInfo],
        defIdMap: DefIdMap
    ) throws {
        // 第一步：收集所有唯一的模块路径
        var allModulePaths: Set<String> = []
        
        for sourceInfo in nodeSourceInfoList {
            let modulePath = sourceInfo.modulePath
            
            // 跳过根模块（空路径）- 我们只关心子模块
            if modulePath.isEmpty { continue }
            
            let moduleKey = modulePath.joined(separator: ".")
            allModulePaths.insert(moduleKey)
        }
        
        // 第二步：收集每个模块的符号
        var symbolsByModule: [String: [ResolvedModuleSymbol]] = [:]
        
        for (index, node) in astNodes.enumerated() {
            guard index < nodeSourceInfoList.count else { continue }
            let sourceInfo = nodeSourceInfoList[index]
            let modulePath = sourceInfo.modulePath
            
            // 跳过根模块
            if modulePath.isEmpty { continue }
            
            let moduleKey = modulePath.joined(separator: ".")
            
            // 提取符号信息
            if let symbolInfo = extractModuleSymbol(from: node, sourceInfo: sourceInfo, defIdMap: defIdMap) {
                if symbolsByModule[moduleKey] == nil {
                    symbolsByModule[moduleKey] = []
                }
                symbolsByModule[moduleKey]!.append(symbolInfo)
            }
        }
        
        // 第三步：为每个模块构建 ModuleSymbolInfo
        for moduleKey in allModulePaths {
            var publicSymbols: [String: ResolvedModuleSymbol] = [:]
            
            if let symbols = symbolsByModule[moduleKey] {
                for symbol in symbols {
                    // 只包含公开符号
                    if symbol.access != .private {
                        publicSymbols[symbol.name] = symbol
                    }
                }
            }
            
            let modulePath = moduleKey.split(separator: ".").map(String.init)
            moduleSymbolInfos[moduleKey] = ResolvedModuleSymbolInfo(
                modulePath: modulePath,
                publicSymbols: publicSymbols
            )
        }
    }
    
    /// 从全局声明中提取模块符号信息
    private func extractModuleSymbol(
        from node: GlobalNode,
        sourceInfo: GlobalNodeSourceInfo,
        defIdMap: DefIdMap
    ) -> ResolvedModuleSymbol? {
        switch node {
        case .globalFunctionDeclaration(let name, let typeParameters, _, _, _, let access, _):
            // 跳过泛型函数
            if !typeParameters.isEmpty { return nil }
            
            return ResolvedModuleSymbol(
                name: name,
                kind: .function,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
        case .foreignFunctionDeclaration(let name, _, _, let access, _):
            return ResolvedModuleSymbol(
                name: name,
                kind: .function,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
            
        case .globalStructDeclaration(let name, let typeParameters, _, let access, _):
            // 跳过泛型结构体
            if !typeParameters.isEmpty { return nil }
            
            return ResolvedModuleSymbol(
                name: name,
                kind: .type,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
            
        case .globalUnionDeclaration(let name, let typeParameters, _, let access, _):
            // 跳过泛型联合类型
            if !typeParameters.isEmpty { return nil }
            
            return ResolvedModuleSymbol(
                name: name,
                kind: .type,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
        case .foreignTypeDeclaration(let name, let access, _):
            return ResolvedModuleSymbol(
                name: name,
                kind: .type,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
            
        case .globalVariableDeclaration(let name, _, _, _, let access, _):
            return ResolvedModuleSymbol(
                name: name,
                kind: .variable,
                access: access,
                modulePath: sourceInfo.modulePath,
                sourceFile: sourceInfo.sourceFile
            )
            
        default:
            return nil
        }
    }
    
    // MARK: - 输出映射填充
    
    /// 将收集的信息填充到 DefIdMap
    private func populateOutputMaps(defIdMap: DefIdMap) throws {
        // 填充类型签名到 DefIdMap
        for (_, signature) in collectedTypeSignatures {
            if let defId = defIdMap.lookup(
                modulePath: signature.modulePath,
                name: signature.name,
                sourceFile: signature.access == .private ? signature.sourceFile : nil
            ) {
                // 创建占位类型（实际类型解析在 TypeChecker 中完成）
                let placeholderType: Type
                switch signature.kind {
                case .structure:
                    placeholderType = .structure(defId: defId)
                    if defIdMap.getStructMembers(defId) == nil {
                        defIdMap.addStructInfo(defId: defId, members: [], isGenericInstantiation: false, typeArguments: nil)
                    }
                case .union:
                    placeholderType = .union(defId: defId)
                    if defIdMap.getUnionCases(defId) == nil {
                        defIdMap.addUnionInfo(defId: defId, cases: [], isGenericInstantiation: false, typeArguments: nil)
                    }
                case .opaque:
                    placeholderType = .opaque(defId: defId)
                }
                
                defIdMap.addType(defId: defId, type: placeholderType)
                
            }
        }
        
        // 填充函数签名到 DefIdMap
        for (_, signature) in collectedFunctionSignatures {
            if let defId = defIdMap.lookup(
                modulePath: signature.modulePath,
                name: signature.name,
                sourceFile: signature.access == .private ? signature.sourceFile : nil
            ) {
                // 创建函数签名
                let funcSignature = FunctionSignature(
                    parameters: signature.parameters.map { param in
                        FunctionParameter(
                            name: param.name,
                            type: .void, // 占位，实际类型在 TypeChecker 中解析
                            isMutable: param.isMutable,
                            passKind: param.isMutable ? .byMutRef : .byVal
                        )
                    },
                    returnType: .void, // 占位，实际类型在 TypeChecker 中解析
                    typeParameters: signature.typeParameters.map { $0.name }
                )
                
                defIdMap.addSignature(defId: defId, signature: funcSignature)
                
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 从 TypeNode 中提取类型名称
    private func extractTypeName(from typeNode: TypeNode) -> String {
        switch typeNode {
        case .identifier(let name):
            return name
        case .generic(let name, _):
            return name
        case .moduleQualified(_, let name):
            return name
        case .moduleQualifiedGeneric(_, let base, _):
            return base
        case .reference(let inner):
            return extractTypeName(from: inner)
        case .pointer(let inner):
            return extractTypeName(from: inner)
        case .functionType, .inferredSelf:
            return ""
        }
    }
    
    // MARK: - 公共访问器
    
    /// 获取收集到的类型签名
    public var typeSignatures: [String: ResolvedTypeSignature] {
        return collectedTypeSignatures
    }
    
    /// 获取收集到的函数签名
    public var functionSignatures: [String: ResolvedFunctionSignature] {
        return collectedFunctionSignatures
    }
    
    /// 获取收集到的 given 方法签名
    public var givenSignatures: [String: [ResolvedGivenMethodSignature]] {
        return collectedGivenSignatures
    }
    
    /// 获取模块符号信息
    public var moduleSymbols: [String: ResolvedModuleSymbolInfo] {
        return moduleSymbolInfos
    }
}

// MARK: - 解析的信息结构体

/// 解析的类型签名
public struct ResolvedTypeSignature {
    public let name: String
    public let kind: ResolvedTypeKind
    public let typeParameters: [TypeParameterDecl]
    public let members: [ResolvedMember]
    public let access: AccessModifier
    public let sourceFile: String
    public let modulePath: [String]
}

/// 解析的类型种类
public enum ResolvedTypeKind {
    case structure
    case union(cases: [ResolvedUnionCase])
    case opaque
}

/// 解析的成员
public struct ResolvedMember {
    public let name: String
    public let typeNode: TypeNode
    public let isMutable: Bool
    public let access: AccessModifier
}

/// 解析的 union case
public struct ResolvedUnionCase {
    public let name: String
    public let parameters: [ResolvedParameter]
}

/// 解析的参数
public struct ResolvedParameter {
    public let name: String
    public let typeNode: TypeNode
    public let isMutable: Bool
}

/// 解析的函数签名
public struct ResolvedFunctionSignature {
    public let name: String
    public let typeParameters: [TypeParameterDecl]
    public let parameters: [ResolvedParameter]
    public let returnTypeNode: TypeNode
    public let access: AccessModifier
    public let sourceFile: String
    public let modulePath: [String]
    public let isIntrinsic: Bool
    
    public init(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [ResolvedParameter],
        returnTypeNode: TypeNode,
        access: AccessModifier,
        sourceFile: String,
        modulePath: [String],
        isIntrinsic: Bool = false
    ) {
        self.name = name
        self.typeParameters = typeParameters
        self.parameters = parameters
        self.returnTypeNode = returnTypeNode
        self.access = access
        self.sourceFile = sourceFile
        self.modulePath = modulePath
        self.isIntrinsic = isIntrinsic
    }
}

/// 解析的 given 方法签名
public struct ResolvedGivenMethodSignature {
    public let methodName: String
    public let typeParameters: [TypeParameterDecl]
    public let methodTypeParameters: [TypeParameterDecl]
    public let parameters: [ResolvedParameter]
    public let returnTypeNode: TypeNode
    public let isGeneric: Bool
    public let baseName: String
    public let sourceFile: String
    public let modulePath: [String]
    public let isIntrinsic: Bool
    
    public init(
        methodName: String,
        typeParameters: [TypeParameterDecl],
        methodTypeParameters: [TypeParameterDecl],
        parameters: [ResolvedParameter],
        returnTypeNode: TypeNode,
        isGeneric: Bool,
        baseName: String,
        sourceFile: String,
        modulePath: [String],
        isIntrinsic: Bool = false
    ) {
        self.methodName = methodName
        self.typeParameters = typeParameters
        self.methodTypeParameters = methodTypeParameters
        self.parameters = parameters
        self.returnTypeNode = returnTypeNode
        self.isGeneric = isGeneric
        self.baseName = baseName
        self.sourceFile = sourceFile
        self.modulePath = modulePath
        self.isIntrinsic = isIntrinsic
    }
}

/// 解析的模块符号
public struct ResolvedModuleSymbol {
    public let name: String
    public let kind: ResolvedModuleSymbolKind
    public let access: AccessModifier
    public let modulePath: [String]
    public let sourceFile: String
}

/// 解析的模块符号种类
public enum ResolvedModuleSymbolKind {
    case function
    case type
    case variable
}

/// 解析的模块符号信息
public struct ResolvedModuleSymbolInfo {
    public let modulePath: [String]
    public let publicSymbols: [String: ResolvedModuleSymbol]
}
