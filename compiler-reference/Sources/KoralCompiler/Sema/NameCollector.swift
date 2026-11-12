/// NameCollector.swift - Pass 1: 收集所有类型和函数名称
///
/// NameCollector 是编译器的第一个 Pass，负责：
/// - 收集所有类型定义（struct、enum、trait）
/// - 收集所有函数声明
/// - 分配 DefId
/// - 注册模块名称（合并了原 Pass 1.5 的功能）
///
/// ## 设计参考
/// - Rust 编译器 (rustc): DefId 系统
/// - 原 TypeCheckerPasses.swift 中的 collectTypeDefinition 方法
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
/// - 收集所有类型定义（struct、enum、trait）
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

    /// 当前处理的 package identity
    private var currentPackageID: String = ""
    
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

    /// Symmetric top-level name registry (name-resolution.md \u{00A7}\u{540C}\u{540D}\u{9876}\u{5C42}\u{5B9A}\u{4E49}\u{7684}\u{51B2}\u{7A81}\u{89C4}\u{5219}, 2026-11-12).
    /// Bare name -> files holding a PRIVATE definition, plus the names with a
    /// module-level (non-private) definition. The per-kind maps key private
    /// entries by file and cannot answer the cross-kind, order-independent
    /// question on their own.
    private var privateTopLevelNames: [String: [String: SourceSpan]] = [:]
    private var moduleTopLevelNames: [String: SourceSpan] = [:]

    /// \u{540C}\u{540D}\u{9876}\u{5C42}\u{5B9A}\u{4E49}\u{7684}\u{51B2}\u{7A81}\u{89C4}\u{5219}: two same-named top-level definitions in
    /// one module conflict iff they share a file or either side is non-private
    /// -- a private symbol may not shadow its module-level peer. Symmetric and
    /// collection-order independent (the old checks consulted only the incoming
    /// declaration's access, so the answer flipped with file order).
    /// Source-order comparison for the conflict anchor: the LATER of the two
    /// declarations by (file, line, column) reports the duplicate, so the
    /// diagnostic is collection-order independent (the two compilers discover
    /// merged files in opposite orders).
    private func laterSpan(_ a: SourceSpan, _ b: SourceSpan) -> SourceSpan {
        // (file, line, column) -- the same ruler as koralc's span_is_later.
        // Synthesized locations carry no file name and compare as "".
        let af = a.start.fileName ?? ""
        let bf = b.start.fileName ?? ""
        if af != bf { return af > bf ? a : b }
        if a.start.line != b.start.line { return a.start.line > b.start.line ? a : b }
        return a.start.column > b.start.column ? a : b
    }

    private func checkTopLevelNameConflict(
        name: String, qualifiedName: String, isPrivate: Bool, span: SourceSpan
    ) throws {
        var anchor: SourceSpan? = nil
        if let existing = moduleTopLevelNames[qualifiedName] {
            anchor = laterSpan(existing, span)
        }
        if let entries = privateTopLevelNames[qualifiedName] {
            if !isPrivate || entries[currentSourceFile] != nil {
                for (_, entrySpan) in entries {
                    anchor = anchor.map { laterSpan($0, entrySpan) } ?? entrySpan
                }
                anchor = anchor.map { laterSpan($0, span) } ?? span
            }
        }
        if let conflictAnchor = anchor {
            throw SemanticError.duplicateDefinition(name, span: conflictAnchor)
        }
        if isPrivate {
            privateTopLevelNames[qualifiedName, default: [:]][currentSourceFile] = span
        } else {
            moduleTopLevelNames[qualifiedName] = span
        }
    }

    /// Foreign struct layout claims: one entry per struct-form `type foreign`
    /// (its C name, Koral name, source). Checked across declarations at the
    /// end of `run` -- see the report there.
    private var foreignStructClaims: [(cName: String, name: String, sourceFile: String, span: SourceSpan)] = []
    
    /// 收集到的模块信息

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
        foreignStructClaims = []

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
            currentPackageID = sourceInfo?.packageID ?? ""
            defIdMap.currentModulePath = currentModulePath

            // A diagnostic names its file from the AMBIENT name, so that has to
            // be this node's before the node is looked at. Setting it after
            // attributes everything `collectDefinition` reports to whatever
            // node came before -- for a user `intrinsic` that was a std file.
            if let checker {
                checker.isCurrentDeclStdLib = isStdLib
                checker.currentFileName = currentSourceFile
                checker.currentSourceFile = currentSourceFile
                checker.currentModulePath = currentModulePath
                checker.currentPackageID = currentPackageID
                checker.currentSpan = node.span
                checker.resetDeclarationBoundaryCaches()
            }

            // One declaration is one unit of recovery: a rejection is recorded
            // once, and the NEXT declaration is still collected. Walking away
            // at the first duplicate would hide every later one; recording
            // both halves of one rejection separately would say it twice --
            // these two calls are one declaration's collection, and the second
            // one only re-discovers what the first already refused.
            do {
                try collectDefinition(node, isStdLib: isStdLib)
                if let checker {
                    try checker.collectTypeDefinition(node, isStdLib: isStdLib)
                }
            } catch let error as SemanticError {
                if let checker {
                    try? checker.handleError(error)
                } else {
                    throw error
                }
            }
        }
        
        // Foreign struct layout claims (cffi-design.md §A.3 / §C): the C tag
        // is one type identity, so two `type foreign` STRUCT declarations whose
        // C names coincide are two layout claims for one C type -- C itself
        // calls that a redefinition, and the drift between the two field lists
        // is silent. The opaque form claims nothing and may repeat (two views
        // of one C type -- the `let foreign` "same external symbol bound
        // twice" rule). Reported in source order after the first claim.
        let sortedClaims = foreignStructClaims.sorted { a, b in
            if a.sourceFile != b.sourceFile {
                return Array(a.sourceFile.utf8).lexicographicallyPrecedes(Array(b.sourceFile.utf8))
            }
            if a.span.start.line != b.span.start.line {
                return a.span.start.line < b.span.start.line
            }
            return a.span.start.column < b.span.start.column
        }
        var firstClaimByCName: [String: (name: String, sourceFile: String, span: SourceSpan)] = [:]
        for claim in sortedClaims {
            if let first = firstClaimByCName[claim.cName] {
                let message = "foreign types '\(first.name)' and '\(claim.name)' both define the C type '\(claim.cName)'; a C type gets one definition"
                let error = SemanticError(.generic(message), fileName: claim.sourceFile, span: claim.span)
                if let checker {
                    try? checker.handleError(error)
                } else {
                    throw error
                }
            } else {
                firstClaimByCName[claim.cName] = (name: claim.name, sourceFile: claim.sourceFile, span: claim.span)
            }
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
            
        case .traitDeclaration(let name, let isSendable, let typeParameters, let superTraits, let methods, let access, let span, let nameSpan):
            try collectTraitDefinition(
                name: name,
                isSendable: isSendable,
                typeParameters: typeParameters,
                superTraits: superTraits,
                methods: methods,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
            
        case .globalStructDeclaration(let name, let typeParameters, let parameters, let isMutableType, let sendability, let access, let span, let nameSpan):
            try collectStructDefinition(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib,
                isMutableType: isMutableType,
                sendability: sendability
            )

        case .globalEnumDeclaration(let name, let typeParameters, let cases, let sendability, let access, let span, let nameSpan):
            try collectEnumDefinition(
                name: name,
                typeParameters: typeParameters,
                cases: cases,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib,
                sendability: sendability
            )
            
        case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, let access, let span, let nameSpan):
            try collectFunctionDeclaration(
                name: name,
                typeParameters: typeParameters,
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
        case .foreignFunctionDeclaration(let name, let parameters, let returnType, _, let cname, let access, let span, let nameSpan):
            try collectFunctionDeclaration(
                name: name,
                typeParameters: [],
                parameters: parameters,
                returnType: returnType,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib,
                cname: cname
            )
            
        case .globalVariableDeclaration(let name, _, _, _, let access, let span, let nameSpan):
            try collectVariableDeclaration(
                name: name,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
            
        case .givenDeclaration(let typeParams, let typeNode, _, let span):
            try collectGivenDeclaration(
                typeParams: typeParams,
                typeNode: typeNode,
                span: span,
                nameSpan: span,
                isStdLib: isStdLib
            )

        case .givenTraitDeclaration(let typeParams, let typeNode, _, _, let span):
            try collectGivenDeclaration(
                typeParams: typeParams,
                typeNode: typeNode,
                span: span,
                nameSpan: span,
                isStdLib: isStdLib
            )
        case .intrinsicTypeDeclaration(let name, let typeParameters, _, let span, let nameSpan):
            try collectIntrinsicTypeDeclaration(
                name: name,
                typeParameters: typeParameters,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
        case .foreignTypeDeclaration(let name, let fields, let cname, let sendability, let access, let span, let nameSpan):
            try collectForeignTypeDefinition(
                name: name,
                fields: fields,
                cname: cname,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib,
                sendability: sendability
            )

        case .foreignLetDeclaration(let name, _, _, _, let cname, let access, let span, let nameSpan):
            try collectVariableDeclaration(
                name: name,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib,
                cname: cname
            )
            
        case .intrinsicFunctionDeclaration(let name, let typeParameters, _, _, let access, let span, let nameSpan):
            try collectIntrinsicFunctionDeclaration(
                name: name,
                typeParameters: typeParameters,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
            
        case .intrinsicGivenDeclaration(_, _, _, let span):
            // Intrinsic given 在 Pass 2 中处理
            if !isStdLib {
                throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
            }

        case .typeAliasDeclaration(let name, let typeParams, let targetType, let access, let span, let nameSpan):
            try collectTypeAliasDeclaration(
                name: name,
                typeParams: typeParams,
                targetType: targetType,
                access: access,
                span: span,
                nameSpan: nameSpan,
                isStdLib: isStdLib
            )
        }
    }
    
    // MARK: - Trait 定义收集
    
    private func collectTraitDefinition(
        name: String,
        isSendable: Bool,
        typeParameters: [TypeParameterDecl],
        superTraits: [TypeNode],
        methods: [TraitMethodSignature],
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义（对称规则，与收集顺序无关）
        try checkTopLevelNameConflict(
            name: name, qualifiedName: qualifiedName, isPrivate: access == .private,
            span: nameSpan)

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
            packageID: currentPackageID,
            span: span
        )

        // `trait sendable` (concurrency-design.md): the trait's objects are
        // always sendable, so the declaration registers the same sendability
        // slot a nominal type would.
        if isSendable {
            defIdMap.setTypeSendability(defId, .sendable)
        }

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
        parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)],
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool,
        isMutableType: Bool = false,
        sendability: TypeSendability = .unmarked
    ) throws {
        let isPrivate = (access == .private)
        
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义（对称规则，与收集顺序无关）
        try checkTopLevelNameConflict(
            name: name, qualifiedName: qualifiedName, isPrivate: isPrivate, span: nameSpan)
        
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
            packageID: currentPackageID,
            span: span
        )

        // `type mutable` travels with the DECLARATION, not with the finished
        // definition: a field's own `?Node` is resolved before `Node` is
        // complete, and asking about mutability then must already have the
        // answer (§ self-referential weak fields).
        if isMutableType {
            defIdMap.markStructMutable(defId)
        }
        // Nominal sendability (`sendable` / `unsafe sendable`) travels with the
        // declaration for the same reason (concurrency-design.md).
        defIdMap.setTypeSendability(defId, sendability)

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
    
    // MARK: - Enum 定义收集
    
    private func collectEnumDefinition(
        name: String,
        typeParameters: [TypeParameterDecl],
        cases: [EnumCaseDeclaration],
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool,
        sendability: TypeSendability = .unmarked
    ) throws {
        let isPrivate = (access == .private)
        
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义（对称规则，与收集顺序无关）
        try checkTopLevelNameConflict(
            name: name, qualifiedName: qualifiedName, isPrivate: isPrivate, span: nameSpan)
        
        // 确定定义类型
        let defKind: DefKind
        if !typeParameters.isEmpty {
            defKind = .genericTemplate(.`enum`)
        } else {
            defKind = .type(.`enum`)
        }
        
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: defKind,
            sourceFile: currentSourceFile,
            access: access,
            packageID: currentPackageID,
            span: span
        )
        // Nominal sendability (`sendable` / `unsafe sendable`) travels with the
        // declaration (concurrency-design.md).
        defIdMap.setTypeSendability(defId, sendability)

        // 收集类型信息
        if !typeParameters.isEmpty {
            // 泛型枚举类型模板
            collectedGenericTemplates[qualifiedName] = CollectedGenericTemplateInfo(
                defId: defId,
                name: name,
                kind: .`enum`,
                typeParameters: typeParameters,
                access: access
            )
        } else {
            // 非泛型枚举类型
            let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName
            collectedTypes[key] = CollectedTypeInfo(
                defId: defId,
                name: name,
                kind: .`enum`,
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
        parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)],
        returnType: TypeNode,
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool,
        cname: String? = nil
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
            packageID: currentPackageID,
            span: span
        )
        if let cname {
            defIdMap.setDeclaredCname(defId, cname)
        }

        // 收集函数信息
        let isPrivate = (access == .private)
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        let key = isPrivate ? "\(name)@\(currentSourceFile)" : qualifiedName

        // 检查重复定义（同名自由函数不允许重载；对称规则，与收集顺序无关）
        try checkTopLevelNameConflict(
            name: name, qualifiedName: qualifiedName, isPrivate: isPrivate, span: nameSpan)

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
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool,
        cname: String? = nil
    ) throws {
        // 分配 DefId
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .variable,
            sourceFile: currentSourceFile,
            access: access,
            packageID: currentPackageID,
            span: span
        )
        if let cname {
            defIdMap.setDeclaredCname(defId, cname)
        }
    }
    
    // MARK: - Given 声明收集
    
    private func collectGivenDeclaration(
        typeParams: [TypeParameterDecl],
        typeNode: TypeNode,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool
    ) throws {
        // Given 声明不需要分配 DefId，它们扩展现有类型
        // 在 Pass 2 中处理方法签名
        
        if !typeParams.isEmpty {
            // 泛型 given - 验证基类型存在
            if case .generic(let baseName, _, _) = typeNode {
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
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 检查是否在标准库中
        if !isStdLib {
            throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
        }
        
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义
        if collectedTypes[qualifiedName] != nil || collectedGenericTemplates[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, span: nameSpan)
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
            access: .internal,
            packageID: currentPackageID,
            span: span
        )

        // 收集类型信息
        if !typeParameters.isEmpty {
            collectedGenericTemplates[qualifiedName] = CollectedGenericTemplateInfo(
                defId: defId,
                name: name,
                kind: .structure,
                typeParameters: typeParameters,
                access: .internal
            )
        } else {
            collectedTypes[qualifiedName] = CollectedTypeInfo(
                defId: defId,
                name: name,
                kind: .structure,
                access: .internal,
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
        cname: String? = nil,
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool,
        sendability: TypeSendability = .unmarked
    ) throws {
        let isPrivate = (access == .private)
        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        if !isPrivate && collectedTypes[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, span: nameSpan)
        }

        let kind: TypeDefKind = fields == nil ? .opaque : .structure
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .type(kind),
            sourceFile: currentSourceFile,
            access: access,
            packageID: currentPackageID,
            span: span
        )
        if let cname {
            // The C-name slot: this type's name in the C world -- a struct tag
            // for the struct form, the C type's own spelling for the opaque one.
            defIdMap.setDeclaredCname(defId, cname)
        }
        // Nominal sendability (`sendable` / `unsafe sendable`) travels with the
        // declaration (concurrency-design.md). Both forms register.
        defIdMap.setTypeSendability(defId, sendability)
        if fields != nil {
            foreignStructClaims.append((cName: cname ?? name, name: name, sourceFile: currentSourceFile, span: span))
        }

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
        typeParams: [TypeParameterDecl],
        targetType: TypeNode,
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool
    ) throws {
        let isPrivate = (access == .private)

        // 生成完整限定名用于重复检查
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"

        // 检查重复定义（非私有类型，在同一模块+文件中）
        if !isPrivate && (collectedTypes[qualifiedName] != nil || collectedGenericTemplates[qualifiedName] != nil) {
            throw SemanticError.duplicateDefinition(name, span: nameSpan)
        }

        // 分配 DefId（别名最终解析为目标类型，使用 .type(.structure)）
        let defId = defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .type(.structure),
            sourceFile: currentSourceFile,
            access: access,
            packageID: currentPackageID,
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

        // A generic alias registers its template here so every later resolution
        // sees it regardless of declaration order -- the same reason struct
        // templates are collected before anything resolves against them.
        if !typeParams.isEmpty {
            defIdMap.registerGenericAliasTemplate(
                name: name,
                defId: defId,
                info: DefIdMap.GenericAliasTemplateInfo(
                    name: name,
                    typeParameters: typeParams,
                    targetType: targetType
                )
            )
        }

        // 标记标准库类型
        if isStdLib {
            stdLibTypes.insert(name)
        }
    }

    // MARK: - Intrinsic 函数声明收集
    
    private func collectIntrinsicFunctionDeclaration(
        name: String,
        typeParameters: [TypeParameterDecl],
        access: AccessModifier,
        span: SourceSpan, nameSpan: SourceSpan,
        isStdLib: Bool
    ) throws {
        // 检查是否在标准库中
        if !isStdLib {
            throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
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
            access: access,
            packageID: currentPackageID,
            span: span
        )

        // 收集函数信息
        let qualifiedName = currentModulePath.isEmpty ? name : "\(currentModulePath.joined(separator: ".")).\(name)"
        if collectedFunctions[qualifiedName] != nil {
            throw SemanticError.duplicateDefinition(name, span: nameSpan)
        }
        collectedFunctions[qualifiedName] = CollectedFunctionInfo(
            defId: defId,
            name: name,
            isGeneric: !typeParameters.isEmpty,
            access: .internal,
            isPrivate: false,
            sourceFile: currentSourceFile,
            modulePath: currentModulePath
        )
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
                    ), span: .unknown)
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
    case `enum`
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
    case `enum`
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
