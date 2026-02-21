/// NameCollector.swift - Pass 1: 收集所有类型和函数名称
///
/// NameCollector 是编译器的第一个 Pass，负责：
/// - 收集所有类型定义（struct、union、trait）
/// - 收集所有函数声明
/// - 分配 DefId
/// - 注册模块名称（合并了原 Pass 1.5 的功能）
///
/// ## 设计参考
/// - Rust 编译器 (rustc): DefId 系统
/// - 原 TypeCheckerPasses.swift 中的 collectTypeDefinition 和 registerModuleNames 方法
///
/// ## 依赖关系
/// - 输入：ModuleResolverOutput（包含 AST 节点和模块信息）
/// - 输出：NameCollectorOutput（包含 DefIdMap）
///
/// **Validates: Requirements 2.1, 2.2**

import Foundation

// MARK: - NameCollector

/// NameCollector - Pass 1: 收集所有类型和函数名称
///
/// 负责：
/// - 收集所有类型定义（struct、union、trait）
/// - 收集所有函数声明
/// - 分配 DefId
/// - 注册模块名称
public class NameCollector: CompilerPass {
    public typealias Input = NameCollectorInput
    public typealias Output = NameCollectorOutput
    
    public var name: String { "NameCollector" }
    
    // MARK: - 私有属性
    
    /// DefId 映射表
    private var defIdMap: DefIdMap
    
    
    /// 当前处理的源文件
    private var currentSourceFile: String = ""
    
    /// 当前处理的模块路径
    private var currentModulePath: [String] = []
    
    /// 标准库类型集合
    private var stdLibTypes: Set<String> = []
    
    /// 标准库全局节点数量
    private var coreGlobalCount: Int = 0
    
    /// 收集到的 trait 定义
    private var collectedTraits: [String: CollectedTraitInfo] = [:]
    
    /// 收集到的类型定义（用于后续 Pass）
    private var collectedTypes: [String: CollectedTypeInfo] = [:]
    
    /// 收集到的泛型模板
    private var collectedGenericTemplates: [String: CollectedGenericTemplateInfo] = [:]
    
    /// 收集到的函数声明
    private var collectedFunctions: [String: CollectedFunctionInfo] = [:]
    
    /// 收集到的模块信息
    private var collectedModules: [String: CollectedModuleInfo] = [:]

    /// 关联的 TypeChecker（用于 Pass 1 状态注入）
    private var checker: TypeChecker?
    
    // MARK: - 初始化
    
    /// 创建一个新的 NameCollector
    ///
    /// - Parameter coreGlobalCount: 标准库全局节点数量（用于判断是否是标准库定义）
    public init(coreGlobalCount: Int = 0, checker: TypeChecker? = nil) {
        self.defIdMap = DefIdMap()
        self.coreGlobalCount = coreGlobalCount
        self.checker = checker
    }
    
    // MARK: - CompilerPass 实现
    
    /// 执行 Pass 1
    ///
    /// - Parameter input: NameCollector 的输入
    /// - Returns: NameCollector 的输出
    /// - Throws: 如果遇到语义错误
    public func run(input: Input) throws -> Output {
        let moduleResolverOutput = input.moduleResolverOutput
        let astNodes = moduleResolverOutput.astNodes
        let nodeSourceInfoList = moduleResolverOutput.nodeSourceInfoList
        
        // 重置状态
        defIdMap = DefIdMap()
        collectedTraits = [:]
        collectedTypes = [:]
        collectedGenericTemplates = [:]
        collectedFunctions = [:]
        collectedModules = [:]

        if let checker {
            checker.defIdMap = defIdMap
        }

        // 第一步：收集所有类型定义
        for (index, node) in astNodes.enumerated() {
            let isStdLib = index < coreGlobalCount
            
            // 获取源信息
            let sourceInfo = index < nodeSourceInfoList.count ? nodeSourceInfoList[index] : nil
            currentSourceFile = sourceInfo?.sourceFile ?? ""
            currentModulePath = sourceInfo?.modulePath ?? []
            
            try collectDefinition(node, isStdLib: isStdLib)

            if let checker {
                checker.isCurrentDeclStdLib = isStdLib
                checker.currentFileName = currentSourceFile
                checker.currentSourceFile = currentSourceFile
                checker.currentModulePath = currentModulePath
                checker.currentSpan = node.span
                try checker.collectTypeDefinition(node, isStdLib: isStdLib)
            }
        }
        
        // 第二步：注册模块名称（合并原 Pass 1.5 的功能）
        try registerModuleNames(from: nodeSourceInfoList)

        if let checker {
            try checker.registerModuleNames(from: astNodes)
        }
        
        return NameCollectorOutput(
            defIdMap: defIdMap,
            moduleResolverOutput: moduleResolverOutput
        )
    }
    
    // MARK: - 类型定义收集
    
    /// 收集单个定义
    ///
    /// - Parameters:
    ///   - node: 全局节点
    ///   - isStdLib: 是否是标准库定义
    private func collectDefinition(_ node: GlobalNode, isStdLib: Bool) throws {
        switch node {
        case .usingDeclaration:
            // Using 声明在 ModuleResolver 中处理，这里跳过
            return
        case .foreignUsingDeclaration:
            // Foreign using is handled in CodeGen, skip here
            return
            
        case .traitDeclaration(let name, let typeParameters, let superTraits, let methods, let access, let span):
            try collectTraitDefinition(
                name: name,
                typeParameters: typeParameters,
                superTraits: superTraits,
                methods: methods,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .globalStructDeclaration(let name, let typeParameters, let parameters, let access, let span):
            try collectStructDefinition(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let span):
            try collectUnionDefinition(
                name: name,
                typeParameters: typeParameters,
                cases: cases,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, let access, let span):
            try collectFunctionDeclaration(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
        case .foreignFunctionDeclaration(let name, let parameters, let returnType, let access, let span):
            try collectFunctionDeclaration(
                name: name,
                typeParameters: [],
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .globalVariableDeclaration(let name, _, _, _, let access, let span):
            try collectVariableDeclaration(
                name: name,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .givenDeclaration(let typeParams, let typeNode, _, let span):
            try collectGivenDeclaration(
                typeParams: typeParams,
                typeNode: typeNode,
                span: span,
                isStdLib: isStdLib
            )
            
        case .intrinsicTypeDeclaration(let name, let typeParameters, _, let span):
            try collectIntrinsicTypeDeclaration(
                name: name,
                typeParameters: typeParameters,
                span: span,
                isStdLib: isStdLib
            )
        case .foreignTypeDeclaration(let name, _, let fields, let access, let span):
            try collectForeignTypeDefinition(
                name: name,
                fields: fields,
                access: access,
                span: span,
                isStdLib: isStdLib
            )

        case .foreignLetDeclaration(let name, _, _, let access, let span):
            try collectVariableDeclaration(
                name: name,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
            
        case .intrinsicFunctionDeclaration(let name, let typeParameters, _, _, _, let span):
            try collectIntrinsicFunctionDeclaration(
                name: name,
                typeParameters: typeParameters,
                span: span,
                isStdLib: isStdLib
            )
            
        case .intrinsicGivenDeclaration(_, _, _, let span):
            // Intrinsic given 在 Pass 2 中处理
            if !isStdLib {
                throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
            }

        case .typeAliasDeclaration(let name, _, let access, let span):
            try collectTypeAliasDeclaration(
                name: name,
                access: access,
                span: span,
                isStdLib: isStdLib
            )
        }
    }
    
    // MARK: - Trait 定义收集
    
    private func collectTraitDefinition(
        name: String,
        typeParameters: [TypeParameterDecl],
        superTraits: [TypeNode],
        methods: [TraitMethodSignature],
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        // 检查重复定义
        if collectedTraits[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 检查方法级类型参数冲突
        try checkMethodTypeParameterConflicts(
            methods: methods,
            outerTypeParams: typeParameters,
            contextName: "trait '\(name)'"
        )
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .type(.trait),
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        // 收集 trait 信息
        collectedTraits[qualifiedName] = CollectedTraitInfo(
            defId: defId,
            name: name,
            typeParameters: typeParameters,
            superTraits: superTraits,
            methods: methods,
            access: access
        )
        
        // 标记标准库类型
        if isStdLib {
            stdLibTypes.insert(name)
        }
    }
    
    // MARK: - Struct 定义收集
    
    private func collectStructDefinition(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)],
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        let isPrivate = (access == .private)
        
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        // 检查重复定义（非私有类型，在同一模块中）
        if !isPrivate && collectedTypes[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 检查泛型模板重复
        if !isPrivate && collectedGenericTemplates[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.structure)
        } else {
            defKind = .type(.structure)
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        // 收集类型信息
        if !typeParameters.isEmpty {
            // 泛型结构体模板
            collectedGenericTemplates[qualifiedName] = CollectedGenericTemplateInfo(
                defId: defId,
                name: name,
                kind: .structure,
                typeParameters: typeParameters,
                access: access
            )
        } else {
            // 非泛型结构体
            let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName
            collectedTypes[key] = CollectedTypeInfo(
                defId: defId,
                name: name,
                kind: .structure,
                access: access,
                isPrivate: isPrivate,
                sourceFile: currentSourceFile,
                modulePath: currentModulePath
            )
        }
        
        // 标记标准库类型
        if isStdLib {
            stdLibTypes.insert(name)
        }
    }
    
    // MARK: - Union 定义收集
    
    private func collectUnionDefinition(
        name: String,
        typeParameters: [TypeParameterDecl],
        cases: [UnionCaseDeclaration],
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        let isPrivate = (access == .private)
        
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        
        // 检查重复定义（非私有类型，在同一模块中）
        if !isPrivate && collectedTypes[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 检查泛型模板重复
        if !isPrivate && collectedGenericTemplates[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.union)
        } else {
            defKind = .type(.union)
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        // 收集类型信息
        if !typeParameters.isEmpty {
            // 泛型联合类型模板
            collectedGenericTemplates[qualifiedName] = CollectedGenericTemplateInfo(
                defId: defId,
                name: name,
                kind: .union,
                typeParameters: typeParameters,
                access: access
            )
        } else {
            // 非泛型联合类型
            let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName
            collectedTypes[key] = CollectedTypeInfo(
                defId: defId,
                name: name,
                kind: .union,
                access: access,
                isPrivate: isPrivate,
                sourceFile: currentSourceFile,
                modulePath: currentModulePath
            )
        }
        
        // 标记标准库类型
        if isStdLib {
            stdLibTypes.insert(name)
        }
    }
    
    // MARK: - 函数声明收集
    
    private func collectFunctionDeclaration(
        name: String,
        typeParameters: [TypeParameterDecl],
        parameters: [(name: String, mutable: Bool, type: TypeNode)],
        returnType: TypeNode,
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.function)
        } else {
            defKind = .function
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        // 收集函数信息
        let isPrivate = (access == .private)
        let key = isPrivate ? "\(name)@\(currentSourceFile)" : name
        collectedFunctions[key] = CollectedFunctionInfo(
            defId: defId,
            name: name,
            isGeneric: !typeParameters.isEmpty,
            access: access,
            isPrivate: isPrivate,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }
    
    // MARK: - 变量声明收集
    
    private func collectVariableDeclaration(
        name: String,
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 分配 DefId
        _ = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .variable,
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )
    }
    
    // MARK: - Given 声明收集
    
    private func collectGivenDeclaration(
        typeParams: [TypeParameterDecl],
        typeNode: TypeNode,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // Given 声明不需要分配 DefId，它们扩展现有类型
        // 在 Pass 2 中处理方法签名
        
        if !typeParams.isEmpty {
            // 泛型 given - 验证基类型存在
            if case .generic(let baseName, _) = typeNode {
                // 基类型应该已经在前面注册
                // 这里只是记录，实际验证在 Pass 2 中进行
                _ = baseName
            }
        }
    }
    
    // MARK: - Intrinsic 类型声明收集
    
    private func collectIntrinsicTypeDeclaration(
        name: String,
        typeParameters: [TypeParameterDecl],
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 检查是否在标准库中
        if !isStdLib {
            throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
        }
        
        // 检查重复定义
        if collectedTypes[name] != nil || collectedGenericTemplates[name] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }
        
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.structure)
        } else {
            defKind = .type(.structure)
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: .protected,
            span: span
        )

        // 收集类型信息
        if !typeParameters.isEmpty {
            collectedGenericTemplates[name] = CollectedGenericTemplateInfo(
                defId: defId,
                name: name,
                kind: .structure,
                typeParameters: typeParameters,
                access: .protected
            )
        } else {
            collectedTypes[name] = CollectedTypeInfo(
                defId: defId,
                name: name,
                kind: .structure,
                access: .protected,
                isPrivate: false,
                sourceFile: currentSourceFile,
                modulePath: currentModulePath
            )
        }
        
        // 标记标准库类型
        stdLibTypes.insert(name)
    }

    // MARK: - Foreign 类型声明收集

    private func collectForeignTypeDefinition(
        name: String,
        fields: [(name: String, type: TypeNode)]?,
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        let isPrivate = (access == .private)
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        if !isPrivate && collectedTypes[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }

        let kind: TypeDefKind = fields == nil ? .opaque : .structure
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .type(kind),
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName
        let collectedKind: CollectedTypeKind = fields == nil ? .opaque : .structure
        collectedTypes[key] = CollectedTypeInfo(
            defId: defId,
            name: name,
            kind: collectedKind,
            access: access,
            isPrivate: isPrivate,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )

        if isStdLib {
            stdLibTypes.insert(name)
        }
    }
    
    // MARK: - Type Alias 声明收集

    private func collectTypeAliasDeclaration(
        name: String,
        access: AccessModifier,
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        let isPrivate = (access == .private)

        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义（非私有类型，在同一模块中）
        if !isPrivate && (collectedTypes[qualifiedName] != nil || collectedGenericTemplates[qualifiedName] != nil) {
            throw SemanticError.duplicateDefinition(name, line: span.line)
        }

        // 分配 DefId（别名最终解析为目标类型，使用 .type(.structure)）
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .type(.structure),
            sourceFile: currentSourceFile,
            access: access,
            span: span
        )

        // 注册到类型信息表
        let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName
        collectedTypes[key] = CollectedTypeInfo(
            defId: defId,
            name: name,
            kind: .structure,
            access: access,
            isPrivate: isPrivate,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )

        // 标记标准库类型
        if isStdLib {
            stdLibTypes.insert(name)
        }
    }

    // MARK: - Intrinsic 函数声明收集
    
    private func collectIntrinsicFunctionDeclaration(
        name: String,
        typeParameters: [TypeParameterDecl],
        span: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 检查是否在标准库中
        if !isStdLib {
            throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
        }
        
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.function)
        } else {
            defKind = .function
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: .protected,
            span: span
        )

        // 收集函数信息
        collectedFunctions[name] = CollectedFunctionInfo(
            defId: defId,
            name: name,
            isGeneric: !typeParameters.isEmpty,
            access: .protected,
            isPrivate: false,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
    }
    
    // MARK: - 模块名称注册（合并原 Pass 1.5）
    
    /// 注册模块名称
    ///
    /// 这个方法合并了原 Pass 1.5 的功能，在 Pass 1 中一起完成。
    /// 注册模块名称使得模块限定类型（如 `backend.Evaluator`）可以在 Pass 2 中解析。
    private func registerModuleNames(from nodeSourceInfoList: [GlobalNodeSourceInfo]) throws {
        // 收集所有唯一的模块路径
        var allModulePaths: Set<String> = []
        
        for sourceInfo in nodeSourceInfoList {
            let modulePath = sourceInfo.modulePath
            
            // 跳过根模块（空路径）- 我们只关心子模块
            if modulePath.isEmpty { continue }
            
            let moduleKey = modulePath.joined(separator: ".")
            allModulePaths.insert(moduleKey)
        }
        
        // 为每个模块分配 DefId 并注册
        for moduleKey in allModulePaths {
            let parts = moduleKey.split(separator: ".").map(String.init)
            
            // 分配模块 DefId
            let defId = defIdMap.allocate(
                modulePath: Array(parts.dropLast()),
                name: parts.last ?? "",
                kind: .module,
                sourceFile: "",
                access: .protected,
                span: .unknown
            )
            
            // 添加到名称表
            
            // 收集模块信息
            collectedModules[moduleKey] = CollectedModuleInfo(
                defId: defId,
                modulePath: parts
            )
        }
    }
    
    // MARK: - 辅助方法
    
    /// 检查方法级类型参数与外部类型参数的冲突
    private func checkMethodTypeParameterConflicts(
        methods: [TraitMethodSignature],
        outerTypeParams: [TypeParameterDecl],
        contextName: String
    ) throws {
        let outerNames = Set(outerTypeParams.map { $0.name })
        for method in methods {
            for param in method.typeParameters {
                if outerNames.contains(param.name) {
                    throw SemanticError(.generic(
                        "Method '\(method.name)' type parameter '\(param.name)' conflicts with \(contextName) type parameter"
                    ), line: 0)
                }
            }
        }
    }
    
    // MARK: - 公共访问器
    
    /// 获取收集到的 trait 信息
    public var traits: [String: CollectedTraitInfo] {
        return collectedTraits
    }
    
    /// 获取收集到的类型信息
    public var types: [String: CollectedTypeInfo] {
        return collectedTypes
    }
    
    /// 获取收集到的泛型模板信息
    public var genericTemplates: [String: CollectedGenericTemplateInfo] {
        return collectedGenericTemplates
    }
    
    /// 获取收集到的函数信息
    public var functions: [String: CollectedFunctionInfo] {
        return collectedFunctions
    }
    
    /// 获取收集到的模块信息
    public var modules: [String: CollectedModuleInfo] {
        return collectedModules
    }
    
    /// 获取标准库类型集合
    public var standardLibraryTypes: Set<String> {
        return stdLibTypes
    }
}

// MARK: - 收集的信息结构体

/// 收集到的 Trait 信息
public struct CollectedTraitInfo {
    public let defId: DefId
    public let name: String
    public let typeParameters: [TypeParameterDecl]
    public let superTraits: [TypeNode]
    public let methods: [TraitMethodSignature]
    public let access: AccessModifier
}

/// 收集到的类型信息
public struct CollectedTypeInfo {
    public let defId: DefId
    public let name: String
    public let kind: CollectedTypeKind
    public let access: AccessModifier
    public let isPrivate: Bool
    public let sourceFile: String
    public let modulePath: [String]
}

/// 收集到的类型种类
public enum CollectedTypeKind {
    case structure
    case union
    case opaque
}

/// 收集到的泛型模板信息
public struct CollectedGenericTemplateInfo {
    public let defId: DefId
    public let name: String
    public let kind: CollectedGenericKind
    public let typeParameters: [TypeParameterDecl]
    public let access: AccessModifier
}

/// 收集到的泛型种类
public enum CollectedGenericKind {
    case structure
    case union
    case function
}

/// 收集到的函数信息
public struct CollectedFunctionInfo {
    public let defId: DefId
    public let name: String
    public let isGeneric: Bool
    public let access: AccessModifier
    public let isPrivate: Bool
    public let sourceFile: String
    public let modulePath: [String]
}

/// 收集到的模块信息
public struct CollectedModuleInfo {
    public let defId: DefId
    public let modulePath: [String]
}
