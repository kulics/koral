import Testing

@testable import KoralCompiler

/// Pass 架构测试
///
/// 测试编译器多 Pass 架构的核心功能：
/// - Pass 顺序依赖（Property 2）
/// - Pass 之间的数据传递
/// - NameCollector -> TypeResolver -> BodyChecker 的数据流
///
/// **Property 2: Pass 顺序依赖**
/// - Pass 2 (TypeResolver) 执行前，Pass 1 (NameCollector) 必须完成所有 DefId 分配
/// - Pass 3 (BodyChecker) 执行前，Pass 2 必须完成所有类型解析
///
/// **Validates: Requirements 2.2, 2.5**
@Suite("Pass Architecture Tests")
struct PassArchitectureTests {
    
    // MARK: - Helper Functions
    
    /// 创建一个简单的 ModuleResolverOutput 用于测试
    private func createModuleResolverOutput(
        astNodes: [GlobalNode],
        nodeSourceInfoList: [GlobalNodeSourceInfo]
    ) -> ModuleResolverOutput {
        let moduleTree = ModuleTree(
            rootModule: ModuleInfo(
                path: [],
                entryFile: "test.koral"
            ),
            loadedModules: [:]
        )
        
        return ModuleResolverOutput(
            moduleTree: moduleTree,
            importGraph: ImportGraph(),
            astNodes: astNodes,
            nodeSourceInfoList: nodeSourceInfoList
        )
    }
    
    /// 创建源信息
    private func createSourceInfo(
        sourceFile: String,
        modulePath: [String],
        node: GlobalNode
    ) -> GlobalNodeSourceInfo {
        return GlobalNodeSourceInfo(
            sourceFile: sourceFile,
            modulePath: modulePath,
            node: node
        )
    }

    /// 基于 ModuleResolverOutput 创建 TypeChecker（用于 Pass 3）
    private func createTypeChecker(for moduleResolverOutput: ModuleResolverOutput) -> TypeChecker {
        return TypeChecker(
            ast: .program(globalNodes: moduleResolverOutput.astNodes),
            nodeSourceInfoList: moduleResolverOutput.nodeSourceInfoList
        )
    }
    
    // MARK: - Pass 1 -> Pass 2 数据传递测试
    
    @Test("Pass 2 can access Pass 1 output: DefIdMap")
    func testPass2AccessesDefIdMap() throws {
        // 创建 Pass 1 输入
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Point",
            typeParameters: [],
            parameters: [
                (name: "x", type: .identifier("Int"), mutable: false, access: .default),
                (name: "y", type: .identifier("Int"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "point.koral",
            modulePath: ["geometry"],
            node: structNode
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        // 执行 Pass 1
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 验证 Pass 1 输出包含 DefIdMap
        #expect(pass1Output.defIdMap.count > 0)
        let pointDefId = pass1Output.defIdMap.lookup(modulePath: ["geometry"], name: "Point")
        #expect(pointDefId != nil)
        
        // 执行 Pass 2
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 可以访问 Pass 1 的 DefIdMap
        let defIdMapFromPass2 = pass2Output.nameCollectorOutput.defIdMap
        let pointDefIdFromPass2 = defIdMapFromPass2.lookup(modulePath: ["geometry"], name: "Point")
        #expect(pointDefIdFromPass2 != nil)
        #expect(pointDefIdFromPass2?.id == pointDefId?.id)
    }
    
    @Test("Pass 2 can access Pass 1 output: NameTable")
    func testPass2AccessesNameTable() throws {
        // 创建 Pass 1 输入
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "calculate",
            typeParameters: [],
            parameters: [],
            returnType: .identifier("Int"),
            body: .integerLiteral("42", nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "math.koral",
            modulePath: ["math"],
            node: funcNode
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [funcNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        // 执行 Pass 1
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 验证 Pass 1 输出包含 NameTable
        let funcDefId = pass1Output.nameTable.lookup(name: "math.calculate")
        #expect(funcDefId != nil)
        
        // 执行 Pass 2
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 可以访问 Pass 1 的 NameTable
        let nameTableFromPass2 = pass2Output.nameCollectorOutput.nameTable
        let funcDefIdFromPass2 = nameTableFromPass2.lookup(name: "math.calculate")
        #expect(funcDefIdFromPass2 != nil)
        #expect(funcDefIdFromPass2?.id == funcDefId?.id)
    }
    
    // MARK: - Pass 2 -> Pass 3 数据传递测试
    
    @Test("Pass 3 can access Pass 2 output: TypedDefMap")
    func testPass3AccessesTypedDefMap() throws {
        // 创建测试节点
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Config",
            typeParameters: [],
            parameters: [
                (name: "value", type: .identifier("Int"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "config.koral",
            modulePath: [],
            node: structNode
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        // 执行 Pass 1
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 执行 Pass 2
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 输出包含 TypedDefMap
        let configDefId = pass1Output.defIdMap.lookup(modulePath: [], name: "Config")
        #expect(configDefId != nil)
        
        // 执行 Pass 3
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Input = BodyCheckerInput(typeResolverOutput: pass2Output)
        let pass3Output = try bodyChecker.run(input: pass3Input)
        
        // 验证 Pass 3 可以访问 Pass 2 的 TypedDefMap
        let typedDefMapFromPass3 = pass3Output.typeResolverOutput.typedDefMap
        #expect(typedDefMapFromPass3.lookupType(defId: configDefId!) != nil)
    }
    
    @Test("Pass 3 can access Pass 2 output: SymbolTable")
    func testPass3AccessesSymbolTable() throws {
        // 创建测试节点
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "process",
            typeParameters: [],
            parameters: [
                (name: "input", mutable: false, type: .identifier("Int"))
            ],
            returnType: .identifier("Int"),
            body: .identifier("input"),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "processor.koral",
            modulePath: ["utils"],
            node: funcNode
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [funcNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        // 执行 Pass 1
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 执行 Pass 2
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 执行 Pass 3
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Input = BodyCheckerInput(typeResolverOutput: pass2Output)
        let pass3Output = try bodyChecker.run(input: pass3Input)
        
        // 验证 Pass 3 可以访问 Pass 2 的 SymbolTable
        let symbolTableFromPass3 = pass3Output.typeResolverOutput.symbolTable
        let processDefId = pass1Output.defIdMap.lookup(modulePath: ["utils"], name: "process")
        #expect(processDefId != nil)
        
        let symbolEntry = symbolTableFromPass3.lookup(defId: processDefId!)
        #expect(symbolEntry != nil)
        #expect(symbolEntry?.name == "process")
    }
    
    // MARK: - Pass 顺序依赖测试 (Property 2)
    
    @Test("Property 2: Pass 1 completes all DefId allocation before Pass 2")
    func testPass1CompletesBeforePass2() throws {
        // 创建多个定义
        let structNode = GlobalNode.globalStructDeclaration(
            name: "User",
            typeParameters: [],
            parameters: [
                (name: "name", type: .identifier("Int"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "createUser",
            typeParameters: [],
            parameters: [],
            returnType: .identifier("User"),
            body: .blockExpression(statements: [], finalExpression: nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 5, column: 1))
        )
        
        let unionNode = GlobalNode.globalUnionDeclaration(
            name: "Status",
            typeParameters: [],
            cases: [
                UnionCaseDeclaration(name: "Active", parameters: []),
                UnionCaseDeclaration(name: "Inactive", parameters: [])
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 10, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(sourceFile: "user.koral", modulePath: [], node: structNode)
        let sourceInfo2 = createSourceInfo(sourceFile: "user.koral", modulePath: [], node: funcNode)
        let sourceInfo3 = createSourceInfo(sourceFile: "user.koral", modulePath: [], node: unionNode)
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode, funcNode, unionNode],
            nodeSourceInfoList: [sourceInfo1, sourceInfo2, sourceInfo3]
        )
        
        // 执行 Pass 1
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 验证所有 DefId 在 Pass 1 完成后都已分配
        #expect(pass1Output.defIdMap.lookup(modulePath: [], name: "User") != nil)
        #expect(pass1Output.defIdMap.lookup(modulePath: [], name: "createUser") != nil)
        #expect(pass1Output.defIdMap.lookup(modulePath: [], name: "Status") != nil)
        #expect(pass1Output.defIdMap.count == 3)
        
        // 执行 Pass 2 - 此时所有 DefId 应该已经可用
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 可以访问所有 DefId
        let defIdMap = pass2Output.nameCollectorOutput.defIdMap
        #expect(defIdMap.lookup(modulePath: [], name: "User") != nil)
        #expect(defIdMap.lookup(modulePath: [], name: "createUser") != nil)
        #expect(defIdMap.lookup(modulePath: [], name: "Status") != nil)
    }
    
    @Test("Property 2: Pass 2 completes type resolution before Pass 3")
    func testPass2CompletesBeforePass3() throws {
        // 创建类型定义
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Data",
            typeParameters: [],
            parameters: [
                (name: "value", type: .identifier("Int"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "data.koral",
            modulePath: ["storage"],
            node: structNode
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        let checker = createTypeChecker(for: moduleResolverOutput)

        // 执行 Pass 1
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 执行 Pass 2
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 完成后类型信息已解析
        let dataDefId = pass1Output.defIdMap.lookup(modulePath: ["storage"], name: "Data")
        #expect(dataDefId != nil)
        
        // TypedDefMap 应该包含类型信息
        let typeInfo = pass2Output.typedDefMap.lookupType(defId: dataDefId!)
        #expect(typeInfo != nil)
        
        // SymbolTable 应该包含符号信息
        let symbolEntry = pass2Output.symbolTable.lookup(defId: dataDefId!)
        #expect(symbolEntry != nil)
        // Verify symbol entry exists and has correct name
        #expect(symbolEntry?.name == "Data")
        
        // 执行 Pass 3 - 此时类型信息应该已经可用
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Input = BodyCheckerInput(typeResolverOutput: pass2Output)
        let pass3Output = try bodyChecker.run(input: pass3Input)
        
        // 验证 Pass 3 可以访问类型信息
        let typeInfoFromPass3 = pass3Output.typeResolverOutput.typedDefMap.lookupType(defId: dataDefId!)
        #expect(typeInfoFromPass3 != nil)
    }
    
    // MARK: - 完整数据流测试
    
    @Test("Complete data flow: NameCollector -> TypeResolver -> BodyChecker")
    func testCompleteDataFlow() throws {
        // 创建一个完整的程序
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Person",
            typeParameters: [],
            parameters: [
                (name: "name", type: .identifier("Int"), mutable: false, access: .default),
                (name: "age", type: .identifier("Int"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "greet",
            typeParameters: [],
            parameters: [
                (name: "person", mutable: false, type: .identifier("Person"))
            ],
            returnType: .identifier("Int"),
            body: .integerLiteral("0", nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 10, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(sourceFile: "person.koral", modulePath: ["app"], node: structNode)
        let sourceInfo2 = createSourceInfo(sourceFile: "person.koral", modulePath: ["app"], node: funcNode)
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode, funcNode],
            nodeSourceInfoList: [sourceInfo1, sourceInfo2]
        )
        
        // Pass 1: NameCollector
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let pass1Output = try nameCollector.run(input: pass1Input)
        
        // 验证 Pass 1 输出
        #expect(pass1Output.defIdMap.count >= 3) // Person, greet, app module (may include nested modules)
        #expect(pass1Output.nameTable.lookup(name: "app.Person") != nil)
        #expect(pass1Output.nameTable.lookup(name: "app.greet") != nil)
        
        // Pass 2: TypeResolver
        let typeResolver = TypeResolver(checker: checker)
        let pass2Input = TypeResolverInput(nameCollectorOutput: pass1Output)
        let pass2Output = try typeResolver.run(input: pass2Input)
        
        // 验证 Pass 2 输出
        let personDefId = pass1Output.defIdMap.lookup(modulePath: ["app"], name: "Person")
        let greetDefId = pass1Output.defIdMap.lookup(modulePath: ["app"], name: "greet")
        
        #expect(pass2Output.typedDefMap.lookupType(defId: personDefId!) != nil)
        #expect(pass2Output.typedDefMap.lookupSignature(defId: greetDefId!) != nil)
        #expect(pass2Output.symbolTable.lookup(defId: personDefId!) != nil)
        #expect(pass2Output.symbolTable.lookup(defId: greetDefId!) != nil)
        
        // Pass 3: BodyChecker
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Input = BodyCheckerInput(typeResolverOutput: pass2Output)
        let pass3Output = try bodyChecker.run(input: pass3Input)
        
        // 验证 Pass 3 可以访问所有之前 Pass 的输出
        // 访问 Pass 2 输出
        #expect(pass3Output.typeResolverOutput.typedDefMap.lookupType(defId: personDefId!) != nil)
        #expect(pass3Output.typeResolverOutput.symbolTable.lookup(defId: greetDefId!) != nil)
        
        // 访问 Pass 1 输出（通过 Pass 2 输出）
        #expect(pass3Output.typeResolverOutput.nameCollectorOutput.defIdMap.count >= 3)
        #expect(pass3Output.typeResolverOutput.nameCollectorOutput.nameTable.lookup(name: "app.Person") != nil)
        
        // 访问 ModuleResolverOutput（通过 Pass 1 输出）
        #expect(pass3Output.typeResolverOutput.nameCollectorOutput.moduleResolverOutput.astNodes.count == 2)
    }
    
    // MARK: - 多模块数据流测试
    
    @Test("Data flow with multiple modules")
    func testDataFlowWithMultipleModules() throws {
        // 创建多个模块的定义
        let frontendStruct = GlobalNode.globalStructDeclaration(
            name: "Parser",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let backendStruct = GlobalNode.globalStructDeclaration(
            name: "Evaluator",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(
            sourceFile: "frontend.koral",
            modulePath: ["app", "frontend"],
            node: frontendStruct
        )
        
        let sourceInfo2 = createSourceInfo(
            sourceFile: "backend.koral",
            modulePath: ["app", "backend"],
            node: backendStruct
        )
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [frontendStruct, backendStruct],
            nodeSourceInfoList: [sourceInfo1, sourceInfo2]
        )
        
        // 执行完整的 Pass 流程
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Output = try nameCollector.run(input: NameCollectorInput(moduleResolverOutput: moduleResolverOutput))
        
        let typeResolver = TypeResolver(checker: checker)
        let pass2Output = try typeResolver.run(input: TypeResolverInput(nameCollectorOutput: pass1Output))
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Output = try bodyChecker.run(input: BodyCheckerInput(typeResolverOutput: pass2Output))
        
        // 验证多模块的 DefId 分配
        let parserDefId = pass1Output.defIdMap.lookup(modulePath: ["app", "frontend"], name: "Parser")
        let evaluatorDefId = pass1Output.defIdMap.lookup(modulePath: ["app", "backend"], name: "Evaluator")
        
        #expect(parserDefId != nil)
        #expect(evaluatorDefId != nil)
        #expect(parserDefId?.id != evaluatorDefId?.id)
        
        // 验证模块路径正确
        #expect(parserDefId?.modulePath == ["app", "frontend"])
        #expect(evaluatorDefId?.modulePath == ["app", "backend"])
        
        // 验证 Pass 3 可以访问所有模块的信息
        #expect(pass3Output.typeResolverOutput.typedDefMap.lookupType(defId: parserDefId!) != nil)
        #expect(pass3Output.typeResolverOutput.typedDefMap.lookupType(defId: evaluatorDefId!) != nil)
    }
    
    // MARK: - 泛型类型数据流测试
    
    @Test("Data flow with generic types")
    func testDataFlowWithGenericTypes() throws {
        // 创建泛型类型
        let genericStruct = GlobalNode.globalStructDeclaration(
            name: "Container",
            typeParameters: [
                TypeParameterDecl(name: "T", constraints: [])
            ],
            parameters: [
                (name: "value", type: .identifier("T"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let genericFunc = GlobalNode.globalFunctionDeclaration(
            name: "wrap",
            typeParameters: [
                TypeParameterDecl(name: "U", constraints: [])
            ],
            parameters: [
                (name: "item", mutable: false, type: .identifier("U"))
            ],
            returnType: .generic(base: "Container", args: [.identifier("U")]),
            body: .blockExpression(statements: [], finalExpression: nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 10, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(sourceFile: "container.koral", modulePath: [], node: genericStruct)
        let sourceInfo2 = createSourceInfo(sourceFile: "container.koral", modulePath: [], node: genericFunc)
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [genericStruct, genericFunc],
            nodeSourceInfoList: [sourceInfo1, sourceInfo2]
        )
        
        // 执行完整的 Pass 流程
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Output = try nameCollector.run(input: NameCollectorInput(moduleResolverOutput: moduleResolverOutput))
        
        // 验证泛型模板的 DefId 分配
        let containerDefId = pass1Output.defIdMap.lookup(modulePath: [], name: "Container")
        let wrapDefId = pass1Output.defIdMap.lookup(modulePath: [], name: "wrap")
        
        #expect(containerDefId != nil)
        #expect(containerDefId?.kind == .genericTemplate(.structure))
        
        #expect(wrapDefId != nil)
        #expect(wrapDefId?.kind == .genericTemplate(.function))
        
        // 继续执行 Pass 2 和 Pass 3
        let typeResolver = TypeResolver(checker: checker)
        let pass2Output = try typeResolver.run(input: TypeResolverInput(nameCollectorOutput: pass1Output))
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Output = try bodyChecker.run(input: BodyCheckerInput(typeResolverOutput: pass2Output))
        
        // 验证泛型信息在整个流程中保持
        let defIdMapFromPass3 = pass3Output.typeResolverOutput.nameCollectorOutput.defIdMap
        let containerFromPass3 = defIdMapFromPass3.lookup(modulePath: [], name: "Container")
        #expect(containerFromPass3?.kind == .genericTemplate(.structure))
    }
    
    // MARK: - ModuleResolverOutput 传递测试
    
    @Test("ModuleResolverOutput is preserved through all passes")
    func testModuleResolverOutputPreserved() throws {
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Test",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(sourceFile: "test.koral", modulePath: [], node: structNode)
        
        let moduleResolverOutput = createModuleResolverOutput(
            astNodes: [structNode],
            nodeSourceInfoList: [sourceInfo]
        )
        
        // 执行完整的 Pass 流程
        let checker = createTypeChecker(for: moduleResolverOutput)
        let nameCollector = NameCollector(checker: checker)
        let pass1Output = try nameCollector.run(input: NameCollectorInput(moduleResolverOutput: moduleResolverOutput))
        
        let typeResolver = TypeResolver(checker: checker)
        let pass2Output = try typeResolver.run(input: TypeResolverInput(nameCollectorOutput: pass1Output))
        let bodyChecker = BodyChecker(checker: checker)
        let pass3Output = try bodyChecker.run(input: BodyCheckerInput(typeResolverOutput: pass2Output))
        
        // 验证 ModuleResolverOutput 在所有 Pass 中都被保留
        let mrOutputFromPass1 = pass1Output.moduleResolverOutput
        let mrOutputFromPass2 = pass2Output.nameCollectorOutput.moduleResolverOutput
        let mrOutputFromPass3 = pass3Output.typeResolverOutput.nameCollectorOutput.moduleResolverOutput
        
        #expect(mrOutputFromPass1.astNodes.count == 1)
        #expect(mrOutputFromPass2.astNodes.count == 1)
        #expect(mrOutputFromPass3.astNodes.count == 1)
        
        #expect(mrOutputFromPass1.nodeSourceInfoList.count == 1)
        #expect(mrOutputFromPass2.nodeSourceInfoList.count == 1)
        #expect(mrOutputFromPass3.nodeSourceInfoList.count == 1)
    }
    
    // MARK: - Pass 名称测试
    
    @Test("Each pass has correct name")
    func testPassNames() {
        let checker = TypeChecker(ast: .program(globalNodes: []))
        let nameCollector = NameCollector(checker: checker)
        let typeResolver = TypeResolver(checker: checker)
        let bodyChecker = BodyChecker(checker: checker)
        
        #expect(nameCollector.name == "NameCollector")
        #expect(typeResolver.name == "TypeResolver")
        #expect(bodyChecker.name == "BodyChecker")
    }
}
