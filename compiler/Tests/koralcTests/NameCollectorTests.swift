import Testing

@testable import KoralCompiler

/// NameCollector 单元测试
///
/// 测试 NameCollector (Pass 1) 的核心功能：
/// - 收集类型定义（struct、union、trait）
/// - 收集函数声明
/// - 分配 DefId
/// - 注册模块名称
///
/// **Validates: Requirements 2.1, 2.2**
@Suite("NameCollector Tests")
struct NameCollectorTests {
    
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
    
    // MARK: - Basic Initialization Tests
    
    @Test("NameCollector initialization")
    func testNameCollectorInit() {
        let collector = NameCollector()
        #expect(collector.name == "NameCollector")
    }
    
    @Test("NameCollector with coreGlobalCount")
    func testNameCollectorWithCoreGlobalCount() {
        let collector = NameCollector(coreGlobalCount: 10)
        #expect(collector.name == "NameCollector")
    }
    
    // MARK: - Struct Collection Tests
    
    @Test("NameCollector collects non-generic struct")
    func testCollectNonGenericStruct() throws {
        let collector = NameCollector()
        
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
            modulePath: ["mymodule"],
            node: structNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        // 验证 DefId 被分配
        let defId = output.defIdMap.lookup(modulePath: ["mymodule"], name: "Point")
        #expect(defId != nil)
        #expect(defId?.name == "Point")
        #expect(defId?.kind == .type(.structure))
        #expect(defId?.modulePath == ["mymodule"])
        
        // 验证名称表
        let nameTableDefId = output.nameTable.lookup(name: "mymodule.Point")
        #expect(nameTableDefId != nil)
    }
    
    @Test("NameCollector collects generic struct template")
    func testCollectGenericStructTemplate() throws {
        let collector = NameCollector()
        
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Box",
            typeParameters: [
                TypeParameterDecl(name: "T", constraints: [])
            ],
            parameters: [
                (name: "value", type: .identifier("T"), mutable: false, access: .default)
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "box.koral",
            modulePath: [],
            node: structNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        // 验证 DefId 被分配为泛型模板
        let defId = output.defIdMap.lookup(modulePath: [], name: "Box")
        #expect(defId != nil)
        #expect(defId?.name == "Box")
        #expect(defId?.kind == .genericTemplate(.structure))
    }
    
    // MARK: - Union Collection Tests
    
    @Test("NameCollector collects non-generic union")
    func testCollectNonGenericUnion() throws {
        let collector = NameCollector()
        
        let unionNode = GlobalNode.globalUnionDeclaration(
            name: "Result",
            typeParameters: [],
            cases: [
                UnionCaseDeclaration(name: "Ok", parameters: []),
                UnionCaseDeclaration(name: "Err", parameters: [])
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "result.koral",
            modulePath: ["types"],
            node: unionNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [unionNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: ["types"], name: "Result")
        #expect(defId != nil)
        #expect(defId?.name == "Result")
        #expect(defId?.kind == .type(.union))
    }
    
    @Test("NameCollector collects generic union template")
    func testCollectGenericUnionTemplate() throws {
        let collector = NameCollector()
        
        let unionNode = GlobalNode.globalUnionDeclaration(
            name: "Option",
            typeParameters: [
                TypeParameterDecl(name: "T", constraints: [])
            ],
            cases: [
                UnionCaseDeclaration(name: "Some", parameters: [
                    (name: "value", type: .identifier("T"))
                ]),
                UnionCaseDeclaration(name: "None", parameters: [])
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "option.koral",
            modulePath: [],
            node: unionNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [unionNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: [], name: "Option")
        #expect(defId != nil)
        #expect(defId?.kind == .genericTemplate(.union))
    }
    
    // MARK: - Trait Collection Tests
    
    @Test("NameCollector collects trait")
    func testCollectTrait() throws {
        let collector = NameCollector()
        
        let traitNode = GlobalNode.traitDeclaration(
            name: "Printable",
            typeParameters: [],
            superTraits: [],
            methods: [
                TraitMethodSignature(
                    name: "print",
                    typeParameters: [],
                    parameters: [
                        (name: "self", mutable: false, type: .reference(.identifier("Self")))
                    ],
                    returnType: .identifier("Void"),
                    access: .default
                )
            ],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "printable.koral",
            modulePath: [],
            node: traitNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [traitNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: [], name: "Printable")
        #expect(defId != nil)
        #expect(defId?.kind == .type(.trait))
        
        // 验证 trait 信息被收集
        #expect(collector.traits["Printable"] != nil)
        #expect(collector.traits["Printable"]?.methods.count == 1)
    }
    
    // MARK: - Function Collection Tests
    
    @Test("NameCollector collects non-generic function")
    func testCollectNonGenericFunction() throws {
        let collector = NameCollector()
        
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "add",
            typeParameters: [],
            parameters: [
                (name: "a", mutable: false, type: .identifier("Int")),
                (name: "b", mutable: false, type: .identifier("Int"))
            ],
            returnType: .identifier("Int"),
            body: .integerLiteral("0", nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "math.koral",
            modulePath: ["math"],
            node: funcNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [funcNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: ["math"], name: "add")
        #expect(defId != nil)
        #expect(defId?.kind == .function)
    }
    
    @Test("NameCollector collects generic function template")
    func testCollectGenericFunctionTemplate() throws {
        let collector = NameCollector()
        
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "identity",
            typeParameters: [
                TypeParameterDecl(name: "T", constraints: [])
            ],
            parameters: [
                (name: "value", mutable: false, type: .identifier("T"))
            ],
            returnType: .identifier("T"),
            body: .identifier("value"),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "utils.koral",
            modulePath: [],
            node: funcNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [funcNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: [], name: "identity")
        #expect(defId != nil)
        #expect(defId?.kind == .genericTemplate(.function))
    }
    
    // MARK: - Variable Collection Tests
    
    @Test("NameCollector collects global variable")
    func testCollectGlobalVariable() throws {
        let collector = NameCollector()
        
        let varNode = GlobalNode.globalVariableDeclaration(
            name: "PI",
            type: .identifier("Float64"),
            value: .floatLiteral("3.14159", nil),
            mutable: false,
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo = createSourceInfo(
            sourceFile: "constants.koral",
            modulePath: ["math"],
            node: varNode
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [varNode],
                nodeSourceInfoList: [sourceInfo]
            )
        )
        
        let output = try collector.run(input: input)
        
        let defId = output.defIdMap.lookup(modulePath: ["math"], name: "PI")
        #expect(defId != nil)
        #expect(defId?.kind == .variable)
    }
    
    // MARK: - Module Registration Tests (Pass 1.5 merged)
    
    @Test("NameCollector registers module names")
    func testRegisterModuleNames() throws {
        let collector = NameCollector()
        
        let structNode1 = GlobalNode.globalStructDeclaration(
            name: "Frontend",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let structNode2 = GlobalNode.globalStructDeclaration(
            name: "Backend",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(
            sourceFile: "frontend.koral",
            modulePath: ["app", "frontend"],
            node: structNode1
        )
        
        let sourceInfo2 = createSourceInfo(
            sourceFile: "backend.koral",
            modulePath: ["app", "backend"],
            node: structNode2
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode1, structNode2],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2]
            )
        )
        
        let output = try collector.run(input: input)
        
        // 验证模块被注册
        #expect(collector.modules["app.frontend"] != nil)
        #expect(collector.modules["app.backend"] != nil)
        
        // 验证模块 DefId
        let frontendModuleDefId = output.nameTable.lookup(name: "app.frontend")
        #expect(frontendModuleDefId != nil)
        #expect(frontendModuleDefId?.kind == .module)
    }
    
    // MARK: - Duplicate Definition Tests
    
    @Test("NameCollector throws on duplicate struct definition")
    func testDuplicateStructDefinition() throws {
        let collector = NameCollector()
        
        let structNode1 = GlobalNode.globalStructDeclaration(
            name: "Point",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let structNode2 = GlobalNode.globalStructDeclaration(
            name: "Point",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 5, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(
            sourceFile: "point1.koral",
            modulePath: [],
            node: structNode1
        )
        
        let sourceInfo2 = createSourceInfo(
            sourceFile: "point2.koral",
            modulePath: [],
            node: structNode2
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode1, structNode2],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2]
            )
        )
        
        #expect(throws: SemanticError.self) {
            _ = try collector.run(input: input)
        }
    }
    
    @Test("NameCollector allows same name in different modules")
    func testSameNameDifferentModules() throws {
        let collector = NameCollector()
        
        let structNode1 = GlobalNode.globalStructDeclaration(
            name: "Config",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let structNode2 = GlobalNode.globalStructDeclaration(
            name: "Config",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(
            sourceFile: "config1.koral",
            modulePath: ["module1"],
            node: structNode1
        )
        
        let sourceInfo2 = createSourceInfo(
            sourceFile: "config2.koral",
            modulePath: ["module2"],
            node: structNode2
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode1, structNode2],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2]
            )
        )
        
        let output = try collector.run(input: input)
        
        // 两个不同模块中的同名类型应该都被收集
        let defId1 = output.defIdMap.lookup(modulePath: ["module1"], name: "Config")
        let defId2 = output.defIdMap.lookup(modulePath: ["module2"], name: "Config")
        
        #expect(defId1 != nil)
        #expect(defId2 != nil)
        #expect(defId1?.id != defId2?.id)
    }
    
    @Test("NameCollector allows private types with same name in different files")
    func testPrivateTypesSameNameDifferentFiles() throws {
        let collector = NameCollector()
        
        let structNode1 = GlobalNode.globalStructDeclaration(
            name: "Helper",
            typeParameters: [],
            parameters: [],
            access: .private,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let structNode2 = GlobalNode.globalStructDeclaration(
            name: "Helper",
            typeParameters: [],
            parameters: [],
            access: .private,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(
            sourceFile: "file1.koral",
            modulePath: ["module"],
            node: structNode1
        )
        
        let sourceInfo2 = createSourceInfo(
            sourceFile: "file2.koral",
            modulePath: ["module"],
            node: structNode2
        )
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode1, structNode2],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2]
            )
        )
        
        // 私有类型在不同文件中可以同名
        let output = try collector.run(input: input)
        #expect(output.defIdMap.count >= 2)
    }
    
    // MARK: - Multiple Definitions Tests
    
    @Test("NameCollector collects multiple definitions")
    func testCollectMultipleDefinitions() throws {
        let collector = NameCollector()
        
        let structNode = GlobalNode.globalStructDeclaration(
            name: "Point",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 1, column: 1))
        )
        
        let unionNode = GlobalNode.globalUnionDeclaration(
            name: "Shape",
            typeParameters: [],
            cases: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 5, column: 1))
        )
        
        let funcNode = GlobalNode.globalFunctionDeclaration(
            name: "draw",
            typeParameters: [],
            parameters: [],
            returnType: .identifier("Void"),
            body: .blockExpression(statements: [], finalExpression: nil),
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 10, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(sourceFile: "shapes.koral", modulePath: [], node: structNode)
        let sourceInfo2 = createSourceInfo(sourceFile: "shapes.koral", modulePath: [], node: unionNode)
        let sourceInfo3 = createSourceInfo(sourceFile: "shapes.koral", modulePath: [], node: funcNode)
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [structNode, unionNode, funcNode],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2, sourceInfo3]
            )
        )
        
        let output = try collector.run(input: input)
        
        #expect(output.defIdMap.lookup(modulePath: [], name: "Point") != nil)
        #expect(output.defIdMap.lookup(modulePath: [], name: "Shape") != nil)
        #expect(output.defIdMap.lookup(modulePath: [], name: "draw") != nil)
        #expect(output.defIdMap.count == 3)
    }
    
    // MARK: - Using Declaration Tests
    
    @Test("NameCollector skips using declarations")
    func testSkipUsingDeclarations() throws {
        let collector = NameCollector()
        
        let usingNode = GlobalNode.usingDeclaration(
            UsingDeclaration(
                pathKind: .external,
                pathSegments: ["other", "module"],
                span: SourceSpan(location: SourceLocation(line: 1, column: 1))
            )
        )
        
        let structNode = GlobalNode.globalStructDeclaration(
            name: "MyType",
            typeParameters: [],
            parameters: [],
            access: .default,
            span: SourceSpan(location: SourceLocation(line: 3, column: 1))
        )
        
        let sourceInfo1 = createSourceInfo(sourceFile: "test.koral", modulePath: [], node: usingNode)
        let sourceInfo2 = createSourceInfo(sourceFile: "test.koral", modulePath: [], node: structNode)
        
        let input = NameCollectorInput(
            moduleResolverOutput: createModuleResolverOutput(
                astNodes: [usingNode, structNode],
                nodeSourceInfoList: [sourceInfo1, sourceInfo2]
            )
        )
        
        let output = try collector.run(input: input)
        
        // using 声明不应该创建 DefId
        #expect(output.defIdMap.count == 1)
        #expect(output.defIdMap.lookup(modulePath: [], name: "MyType") != nil)
    }
    
    // MARK: - Output Preservation Tests
    
    @Test("NameCollector preserves ModuleResolverOutput in output")
    func testPreservesModuleResolverOutput() throws {
        let collector = NameCollector()
        
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
        
        let input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
        let output = try collector.run(input: input)
        
        // 验证 ModuleResolverOutput 被保留
        #expect(output.moduleResolverOutput.astNodes.count == 1)
        #expect(output.moduleResolverOutput.nodeSourceInfoList.count == 1)
    }
}
